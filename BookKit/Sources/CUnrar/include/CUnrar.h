// Ponte em C entre o Swift e o UnRAR oficial (RARLAB).
//
// O UnRAR é escrito em C++ e tem uma API grande. Aqui ficam só as funções que
// o Tankobon usa para ler um RAR do começo ao fim e entregar cada arquivo.

#ifndef CUNRAR_H
#define CUNRAR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TankobonRar TankobonRar;

/// Recebe os pedaços descompactados de um arquivo. Retorne 1 para continuar
/// ou 0 para parar (por exemplo, se não deu para gravar no disco).
typedef int (*TankobonRarWriteCallback)(void *context, const unsigned char *bytes, long length);

// Códigos de resultado (iguais aos do UnRAR)
#define TANKOBON_RAR_OK               0
#define TANKOBON_RAR_END             10
#define TANKOBON_RAR_NO_MEMORY       11
#define TANKOBON_RAR_BAD_DATA        12
#define TANKOBON_RAR_BAD_ARCHIVE     13
#define TANKOBON_RAR_UNKNOWN_FORMAT  14
#define TANKOBON_RAR_EOPEN           15
#define TANKOBON_RAR_MISSING_PASSWORD 22
#define TANKOBON_RAR_BAD_PASSWORD    24
#define TANKOBON_RAR_NEXT_VOLUME    100  // o arquivo continua em outra parte (.part2.rar)

/// Abre o arquivo. Devolve NULL em caso de erro e preenche `result`.
TankobonRar *tankobon_rar_open(const char *path, int *result);

/// Avança para o próximo arquivo de dentro do RAR.
/// Preenche o nome (em UTF-8) e se é pasta ou se tem senha.
int tankobon_rar_next(TankobonRar *rar, char *name, int nameCapacity, int *isDirectory, int *isEncrypted);

/// Pula o arquivo atual sem extraí-lo.
int tankobon_rar_skip(TankobonRar *rar);

/// Descompacta o arquivo atual, entregando os bytes para `callback`.
int tankobon_rar_extract(TankobonRar *rar, TankobonRarWriteCallback callback, void *context);

/// Fecha o arquivo e libera a memória.
void tankobon_rar_close(TankobonRar *rar);

#ifdef __cplusplus
}
#endif

#endif
