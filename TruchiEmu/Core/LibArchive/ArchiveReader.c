#include "ArchiveReader.h"
#include "archive.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>
#include <errno.h>

static char *str_dup(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char *d = (char *)malloc(len + 1);
    if (d) memcpy(d, s, len + 1);
    return d;
}

static int make_dirs(const char *path) {
    char tmp[4096];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (len > 0 && tmp[len - 1] == '/') tmp[len - 1] = '\0';
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    mkdir(tmp, 0755);
    return 0;
}

ArchiveFileList archive_list_files(const char *archivePath) {
    ArchiveFileList result = {NULL, 0, NULL};
    archive_t *a = archive_read_new();
    if (!a) return result;

    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);

    if (archive_read_open_filename(a, archivePath, 10240) != ARCHIVE_OK) {
        archive_read_free(a);
        return result;
    }

    int capacity = 64;
    result.entries = (char **)malloc(capacity * sizeof(char *));
    result.count = 0;

    archive_entry_t *entry;
    while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
        const char *name = archive_entry_pathname(entry);
        if (!name) {
            archive_read_data_skip(a);
            continue;
        }

        int type = archive_entry_filetype(entry);
        if ((type & AE_IFMT) == AE_IFDIR) {
            archive_read_data_skip(a);
            continue;
        }

        if (result.count >= capacity) {
            capacity *= 2;
            result.entries = (char **)realloc(result.entries, capacity * sizeof(char *));
        }
        result.entries[result.count++] = str_dup(name);
        archive_read_data_skip(a);
    }

    archive_read_free(a);
    return result;
}

static int copy_data(archive_t *ar, archive_t *aw) {
    char buf[16384];
    int r;
    for (;;) {
        r = archive_read_data(ar, buf, sizeof(buf));
        if (r < 0) return r;
        if (r == 0) break;
        int w = archive_write_data(aw, buf, r);
        if (w < 0) return w;
        if (w != r) return -1;
    }
    return ARCHIVE_OK;
}

ArchiveExtractResult archive_extract_to_dir(const char *archivePath, const char *destDir) {
    ArchiveExtractResult result = {0, 0, NULL};
    archive_t *a = archive_read_new();
    if (!a) {
        result.errorMessage = str_dup("Failed to create archive reader");
        return result;
    }

    archive_read_support_format_all(a);
    archive_read_support_filter_all(a);

    archive_t *ext = archive_write_disk_new();
    archive_write_disk_set_options(ext,
        ARCHIVE_EXTRACT_TIME |
        ARCHIVE_EXTRACT_PERM |
        ARCHIVE_EXTRACT_SECURE_SYMLINKS |
        ARCHIVE_EXTRACT_SECURE_NODOTDOT);
    archive_write_disk_set_skip_file(ext, 0, 0);

    int r = archive_read_open_filename(a, archivePath, 10240);
    if (r != ARCHIVE_OK) {
        const char *err = archive_error_string(a);
        result.errorMessage = str_dup(err ? err : "Failed to open archive");
        archive_write_free(ext);
        archive_read_free(a);
        return result;
    }

    make_dirs(destDir);

    archive_entry_t *entry;
    int fileCount = 0;
    while ((r = archive_read_next_header(a, &entry)) == ARCHIVE_OK || r == ARCHIVE_WARN) {
        const char *name = archive_entry_pathname(entry);
        if (!name) {
            archive_read_data_skip(a);
            continue;
        }

        int type = archive_entry_filetype(entry);
        if ((type & AE_IFMT) == AE_IFDIR) {
            char fullPath[4096];
            snprintf(fullPath, sizeof(fullPath), "%s/%s", destDir, name);
            make_dirs(fullPath);
            archive_read_data_skip(a);
            continue;
        }

        char fullPath[4096];
        snprintf(fullPath, sizeof(fullPath), "%s/%s", destDir, name);
        archive_entry_set_pathname(entry, fullPath);

        make_dirs(fullPath);

        r = archive_write_header(ext, entry);
        if (r == ARCHIVE_OK) {
            r = copy_data(a, ext);
            if (r < ARCHIVE_WARN) {
                break;
            }
            r = archive_write_finish_entry(ext);
            if (r < ARCHIVE_WARN) {
                break;
            }
            fileCount++;
        } else if (r == ARCHIVE_WARN) {
            archive_read_data_skip(a);
        } else {
            break;
        }
    }

    if (r == ARCHIVE_EOF) r = ARCHIVE_OK;

    if (r < ARCHIVE_WARN && r != ARCHIVE_EOF) {
        const char *err = archive_error_string(a);
        result.errorMessage = str_dup(err ? err : "Extraction error");
    } else {
        result.success = 1;
        result.fileCount = fileCount;
    }

    archive_write_free(ext);
    archive_read_free(a);
    return result;
}

void archive_file_list_free(ArchiveFileList *list) {
    if (!list) return;
    if (list->entries) {
        for (int i = 0; i < list->count; i++) {
            free(list->entries[i]);
        }
        free(list->entries);
        list->entries = NULL;
    }
    list->count = 0;
}
