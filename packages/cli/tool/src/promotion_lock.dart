import 'dart:io';

import 'promotion_layout.dart';

/// Abre el archivo del lock; las pruebas lo sustituyen para provocar fallos
/// que el sistema de archivos no permite reproducir.
typedef LockOpener = Future<RandomAccessFile> Function(File file);

Future<RandomAccessFile> _openForLock(File file) =>
    file.open(mode: FileMode.append);

/// Corre [body] con el lock de [layout] tomado.
///
/// El lock es exclusivo y no bloqueante: una segunda promoción falla en vez
/// de esperar. El archivo queda vacío y en su lugar para que todas las
/// ejecuciones sincronicen sobre el mismo inode. Es un lock de proceso: cerrar
/// cualquier descriptor de este archivo dentro del mismo proceso lo libera,
/// así que nada más lo abre mientras dura.
Future<T> withPromotionLock<T>(
  PromotionLayout layout,
  Future<T> Function() body, {
  LockOpener open = _openForLock,
}) async {
  final lock = await _acquire(layout, open);
  try {
    return await body();
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<RandomAccessFile> _acquire(
  PromotionLayout layout,
  LockOpener open,
) async {
  final RandomAccessFile lock;
  try {
    lock = await open(layout.lock);
  } on FileSystemException catch (error) {
    throw PromotionException(
      'no se pudo abrir ${layout.lock.path}: ${error.osError ?? error.message}.',
    );
  }
  try {
    await lock.lock(FileLock.exclusive);
  } on FileSystemException {
    await lock.close();
    throw PromotionException(
      'otra promoción tiene el lock de ${layout.bin.path}; no se modificó nada.',
    );
  }
  return lock;
}
