#ifndef ARCHIVE_READER_H
#define ARCHIVE_READER_H

#include <stddef.h>

typedef struct {
    char *data;
    int count;
    char **entries;
} ArchiveFileList;

typedef struct {
    int success;
    int fileCount;
    char *errorMessage;
} ArchiveExtractResult;

ArchiveFileList archive_list_files(const char *archivePath);

ArchiveExtractResult archive_extract_to_dir(const char *archivePath, const char *destDir);

void archive_file_list_free(ArchiveFileList *list);

#endif
