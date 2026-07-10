#include "RcheevosCDReader.h"
#include "rc_hash.h"

#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

// ---------------------------------------------------------------
// CD reader callbacks for .cdi files
//
// Reference: https://docs.retroachievements.org/developer-docs/game-identification.html
//
// Rather than parsing the complex CDI TOC (which varies across versions),
// we use a heuristic to find the disc data area:
// - For Dreamcast: scan for the "SEGA SEGAKATANA " magic at IP.BIN offset 0
// - Fall back to parsing the CDI footer to compute base_offset
//
// CDI hashing is inherently fragile — the format stores sectors at 2336-byte
// intervals, while ISO9660 uses 2048-byte logical blocks, and CDI creation tools
// often repack filesystem metadata into early sectors without updating LBA
// references. This means the rcheevos CD reader may fail to navigate the
// filesystem for .cdi files. When it does, the app falls back to name-based
// game identification (see RetroAchievementsService.syncROMWithRA), which works
// well enough for achievement loading.
// ---------------------------------------------------------------

typedef struct {
    FILE* fp;
    int64_t base_offset;       // file offset where sector 0 data starts
    uint32_t sector_size;      // bytes per sector (2336 for Mode 2)
    uint32_t track_first_lba;
} cdi_track_state_t;

// Scan the file for the SEGA Dreamcast IP.BIN signature.
// Returns the file offset where the signature is found, or -1.
static int64_t find_sega_magic(FILE* fp, long long fsize) {
    const unsigned char magic[] = "SEGA SEGAKATANA ";
    const int magic_len = 16;

    // Search up to the first 32 MB
    long long search_limit = fsize < 33554432 ? fsize : 33554432;
    unsigned char* buf = (unsigned char*)malloc((size_t)search_limit);
    if (!buf) return -1;

    fseeko(fp, 0, SEEK_SET);
    size_t nread = fread(buf, 1, (size_t)search_limit, fp);

    for (long long i = 0; i <= (long long)nread - magic_len; i++) {
        if (memcmp(buf + i, magic, magic_len) == 0) {
            free(buf);
            return i; // This is the start of the IP.BIN data area
        }
    }

    free(buf);
    return -1;
}

// Try to parse the CDI TOC footer to compute the base offset.
// Formula: base_offset = hdr_off - total_sector_data_size
// Returns 0 on failure.
static int compute_base_offset_from_toc(FILE* fp, long long fsize,
                                         int64_t* out_base_offset) {
    if (fsize < 8) return 0;

    uint32_t version, hdr_off_val;
    fseeko(fp, fsize - 8, SEEK_SET);
    if (fread(&version, 4, 1, fp) != 1) return 0;
    if (fread(&hdr_off_val, 4, 1, fp) != 1) return 0;

    long long hdr_off;
    if (version == 0x80000006)
        hdr_off = fsize - hdr_off_val;
    else
        hdr_off = hdr_off_val;

    if (hdr_off < 0 || hdr_off >= fsize - 8) return 0;

    // The TOC starts at hdr_off and goes to end of file.
    // The disc data occupies the space from base_offset to hdr_off.
    // For a rough estimate, assume the TOC overhead is about 8+12 bytes per entry
    // plus some fixed overhead. But actually, we can just try computing from
    // the footer data itself.

    // Simple heuristic: the file offset 0 is part of the disc data
    // (some CDI images have the data starting at offset 0 or near 0).
    // For CDI_V4, if the hdr_off is close to fsize (TOC is at end),
    // then base_offset is probably 0 and the disc data fills the file.

    // If TOC is very small (a few hundred bytes) at end of file,
    // then base_offset is approximately 0.
    if (fsize - hdr_off < 4096) {
        *out_base_offset = 0;
        return 1;
    }

    // Otherwise, assume the disc data doesn't start at 0.
    // We can't compute it from the TOC alone without parsing entries.
    return 0;
}

static void* cdi_open_track(const char* path, uint32_t track) {
    fprintf(stderr, "cdi_open_track: path=%s, track=%u\n", path ? path : "NULL", track);
    const char* dot = strrchr(path, '.');
    if (!dot || strcasecmp(dot, ".cdi") != 0) {
        fprintf(stderr, "cdi_open_track: not a .cdi file (ext=%s)\n", dot ? dot : "NULL");
        return NULL;
    }

    FILE* fp = fopen(path, "rb");
    if (!fp) return NULL;

    fseeko(fp, 0, SEEK_END);
    long long fsize = ftello(fp);

    int64_t base_offset = -1;
    uint32_t sector_size = 2336; // default for Mode 2 data

    // Try SEGA magic first (for Dreamcast)
    base_offset = find_sega_magic(fp, fsize);
    fprintf(stderr, "cdi_open_track: fsize=%lld, base_offset from SEGA=%lld\n", fsize, base_offset);
    if (base_offset < 0) {
        // Fall back to TOC heuristic
        compute_base_offset_from_toc(fp, fsize, &base_offset);
        fprintf(stderr, "cdi_open_track: base_offset from TOC=%lld\n", base_offset);
    }

    if (base_offset < 0) {
        fprintf(stderr, "cdi_open_track: could not find base offset\n");
        fclose(fp);
        return NULL;
    }

    cdi_track_state_t* state = (cdi_track_state_t*)calloc(1, sizeof(cdi_track_state_t));
    if (!state) { fclose(fp); return NULL; }

    state->fp = fp;
    state->base_offset = base_offset;
    state->sector_size = sector_size;
    state->track_first_lba = 0;

    return state;
}

static size_t cdi_read_sector(void* track_handle, uint32_t sector, void* buffer, size_t requested_bytes) {
    cdi_track_state_t* state = (cdi_track_state_t*)track_handle;
    if (!state || !state->fp) {
        fprintf(stderr, "cdi_read_sector: invalid handle\n");
        return 0;
    }

    int64_t sector_off = state->base_offset + (int64_t)sector * state->sector_size;
    fprintf(stderr, "cdi_read_sector: sector=%u, off=0x%llx, req=%zu\n", sector, sector_off, requested_bytes);

    if (fseeko(state->fp, sector_off, SEEK_SET) != 0) {
        fprintf(stderr, "cdi_read_sector: seek failed\n");
        return 0;
    }

    size_t nread = fread(buffer, 1, requested_bytes, state->fp);
    fprintf(stderr, "cdi_read_sector: read %zu bytes\n", nread);

    return nread;
}

static void cdi_close_track(void* track_handle) {
    cdi_track_state_t* state = (cdi_track_state_t*)track_handle;
    if (state) {
        if (state->fp) fclose(state->fp);
        free(state);
    }
}

static uint32_t cdi_first_track_sector(void* track_handle) {
    cdi_track_state_t* state = (cdi_track_state_t*)track_handle;
    if (!state) return 0;
    return state->track_first_lba;
}

// ---------------------------------------------------------------
// Public API
// ---------------------------------------------------------------

void rcheevos_cdreader_register(void) {
    rc_hash_cdreader_t reader;
    memset(&reader, 0, sizeof(reader));
    reader.open_track = cdi_open_track;
    reader.read_sector = cdi_read_sector;
    reader.close_track = cdi_close_track;
    reader.first_track_sector = cdi_first_track_sector;
    reader.open_track_iterator = NULL;

    rc_hash_init_custom_cdreader(&reader);
}
