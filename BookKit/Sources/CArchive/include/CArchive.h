// Ponte mínima para a libarchive que já vem no iOS e no macOS.
//
// O sistema traz a biblioteca (/usr/lib/libarchive.2.dylib), mas não o arquivo
// de cabeçalho "archive.h". Aqui declaramos só as funções que o Tankobon usa,
// copiadas da libarchive (licença BSD de 2 cláusulas, https://libarchive.org).

#ifndef CARCHIVE_H
#define CARCHIVE_H

#include <stdint.h>
#include <sys/types.h>

struct archive;
struct archive_entry;

// Códigos de retorno
#define ARCHIVE_EOF      1
#define ARCHIVE_OK       0
#define ARCHIVE_RETRY  (-10)
#define ARCHIVE_WARN   (-20)
#define ARCHIVE_FAILED (-25)
#define ARCHIVE_FATAL  (-30)

// Tipo de arquivo de uma entrada (igual ao S_IFREG do sistema)
#define CARCHIVE_AE_IFREG 0100000

struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_rar(struct archive *);
int archive_read_support_format_rar5(struct archive *);
int archive_read_support_format_7zip(struct archive *);
int archive_read_support_format_zip(struct archive *);
int archive_read_open_filename(struct archive *, const char *filename, size_t block_size);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *buffer, size_t size);
int archive_read_data_skip(struct archive *);
int archive_read_close(struct archive *);
int archive_read_free(struct archive *);
const char *archive_error_string(struct archive *);
int64_t archive_filter_bytes(struct archive *, int filter);

const char *archive_entry_pathname(struct archive_entry *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

#endif
