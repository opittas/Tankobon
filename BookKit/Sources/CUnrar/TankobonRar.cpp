// Ponte entre o Swift e o UnRAR. Veja include/CUnrar.h.
//
// UnRAR source code may be used in any software to handle RAR archives
// without limitations free of charge, but cannot be used to develop RAR
// (WinRAR) compatible archiver and to re-create RAR compression algorithm,
// which is proprietary. Distribution of modified UnRAR source code in
// separate form or as a part of other software is permitted, provided that
// full text of this paragraph, starting from "UnRAR source code" words,
// is included in license, or in documentation if license is not available,
// and in source code comments of resulting package.

#include "rar.hpp"
#include "include/CUnrar.h"

struct TankobonRar {
  HANDLE handle;
  TankobonRarWriteCallback callback;
  void *context;
  bool needsNextVolume;
  bool stopped;
};

static int CALLBACK TankobonRarCallback(UINT msg, LPARAM userData, LPARAM p1, LPARAM p2) {
  TankobonRar *rar = (TankobonRar *)userData;
  switch (msg) {
    case UCM_PROCESSDATA:
      if (rar->callback == NULL) return 1;
      if (rar->callback(rar->context, (const unsigned char *)p1, (long)p2) == 0) {
        rar->stopped = true;
        return -1;
      }
      return 1;
    case UCM_CHANGEVOLUME:
    case UCM_CHANGEVOLUMEW:
      // RAR dividido em partes: ainda não suportado.
      rar->needsNextVolume = true;
      return -1;
    case UCM_NEEDPASSWORD:
    case UCM_NEEDPASSWORDW:
      // Sem senha: o UnRAR devolve ERAR_MISSING_PASSWORD.
      return -1;
    default:
      return 0;
  }
}

static int TankobonRarResult(TankobonRar *rar, int code) {
  if (code != ERAR_SUCCESS && rar->needsNextVolume) return TANKOBON_RAR_NEXT_VOLUME;
  return code;
}

extern "C" TankobonRar *tankobon_rar_open(const char *path, int *result) {
  TankobonRar *rar = new (std::nothrow) TankobonRar();
  if (rar == NULL) { *result = ERAR_NO_MEMORY; return NULL; }

  RAROpenArchiveDataEx data;
  memset(&data, 0, sizeof(data));
  data.ArcName = (char *)path;
  data.OpenMode = RAR_OM_EXTRACT;
  data.Callback = TankobonRarCallback;
  data.UserData = (LPARAM)rar;

  rar->handle = RAROpenArchiveEx(&data);
  if (rar->handle == NULL || data.OpenResult != ERAR_SUCCESS) {
    *result = data.OpenResult != ERAR_SUCCESS ? (int)data.OpenResult : ERAR_UNKNOWN;
    if (rar->handle != NULL) RARCloseArchive(rar->handle);
    delete rar;
    return NULL;
  }
  *result = ERAR_SUCCESS;
  return rar;
}

extern "C" int tankobon_rar_next(TankobonRar *rar, char *name, int nameCapacity, int *isDirectory, int *isEncrypted) {
  RARHeaderDataEx header;
  memset(&header, 0, sizeof(header));
  int code = RARReadHeaderEx(rar->handle, &header);
  if (code != ERAR_SUCCESS) return TankobonRarResult(rar, code);
  WideToUtf(header.FileNameW, name, (size_t)nameCapacity);
  *isDirectory = (header.Flags & RHDF_DIRECTORY) != 0;
  *isEncrypted = (header.Flags & RHDF_ENCRYPTED) != 0;
  return ERAR_SUCCESS;
}

extern "C" int tankobon_rar_skip(TankobonRar *rar) {
  rar->callback = NULL;
  rar->context = NULL;
  return TankobonRarResult(rar, RARProcessFile(rar->handle, RAR_SKIP, NULL, NULL));
}

extern "C" int tankobon_rar_extract(TankobonRar *rar, TankobonRarWriteCallback callback, void *context) {
  rar->callback = callback;
  rar->context = context;
  rar->stopped = false;
  // RAR_TEST descompacta e confere o CRC sem gravar nada: os bytes chegam pelo callback.
  int code = RARProcessFile(rar->handle, RAR_TEST, NULL, NULL);
  rar->callback = NULL;
  rar->context = NULL;
  return TankobonRarResult(rar, code);
}

extern "C" void tankobon_rar_close(TankobonRar *rar) {
  if (rar == NULL) return;
  if (rar->handle != NULL) RARCloseArchive(rar->handle);
  delete rar;
}
