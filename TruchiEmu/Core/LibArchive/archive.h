#ifndef ARCHIVE_FWD_H
#define ARCHIVE_FWD_H

#include <stdint.h>
#include <stddef.h>
#include <sys/_types/_mode_t.h>

struct archive;
struct archive_entry;

typedef struct archive archive_t;
typedef struct archive_entry archive_entry_t;

typedef int (*archive_open_callback)(archive_t *, void *);
typedef int (*archive_close_callback)(archive_t *, void *);
typedef int64_t (*archive_read_callback)(archive_t *, void *, const void **);
typedef int64_t (*archive_skip_callback)(archive_t *, void *, int64_t);
typedef int (*archive_switch_callback)(archive_t *, void *, void *);

#define ARCHIVE_EOF   1
#define ARCHIVE_OK    0
#define ARCHIVE_RETRY (-10)
#define ARCHIVE_WARN  (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL (-30)

#define ARCHIVE_EXTRACT_TIME        0x0001
#define ARCHIVE_EXTRACT_PERM        0x0002
#define ARCHIVE_EXTRACT_ACL         0x0004
#define ARCHIVE_EXTRACT_FFLAGS      0x0008
#define ARCHIVE_EXTRACT_XATTR       0x0010
#define ARCHIVE_EXTRACT_SECURE_SYMLINKS 0x0100
#define ARCHIVE_EXTRACT_SECURE_NODOTDOT 0x0200
#define ARCHIVE_EXTRACT_NO_OVERWRITE    0x0400
#define ARCHIVE_EXTRACT_UNLINK          0x0800
#define ARCHIVE_EXTRACT_NO_OVERWRITE_NEWER 0x1000

archive_t *archive_read_new(void);
int archive_read_support_format_all(archive_t *);
int archive_read_support_filter_all(archive_t *);
int archive_read_open_filename(archive_t *, const char *, size_t);
int archive_read_next_header(archive_t *, archive_entry_t **);
int archive_read_data(archive_t *, void *, size_t);
int archive_read_data_skip(archive_t *);
int archive_read_free(archive_t *);
const char *archive_error_string(archive_t *);
int archive_errno(archive_t *);

const char *archive_entry_pathname(archive_entry_t *);
void archive_entry_set_pathname(archive_entry_t *, const char *);
int64_t archive_entry_size(archive_entry_t *);
mode_t archive_entry_filetype(archive_entry_t *);
int archive_entry_size_is_set(archive_entry_t *);

archive_t *archive_write_disk_new(void);
int archive_write_disk_set_options(archive_t *, int);
int archive_write_header(archive_t *, archive_entry_t *);
int archive_write_data(archive_t *, const void *, size_t);
int archive_write_finish_entry(archive_t *);
int archive_write_free(archive_t *);
int archive_write_disk_set_skip_file(archive_t *, int64_t, int64_t);

#define AE_IFMT     0170000
#define AE_IFDIR    0040000
#define AE_IFREG    0100000

#endif
