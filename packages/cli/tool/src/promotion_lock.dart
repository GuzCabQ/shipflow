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
///
/// Liberar siempre intenta cerrar, aunque soltar el lock falle. Si [body]
/// falló, ese es el fallo que se propaga, con su tipo y su traza: el sistema
/// libera el lock al terminar el proceso, y un fallo al soltarlo no dice nada
/// nuevo sobre la instalación. Si [body] terminó, el fallo al liberar se
/// informa como uno controlado.
Future<T> withPromotionLock<T>(
  PromotionLayout layout,
  Future<T> Function() body, {
  LockOpener open = _openForLock,
}) async {
  final lock = await _acquire(layout, open);
  final T result;
  try {
    result = await body();
  } on Object catch (error, stack) {
    await _release(lock);
    Error.throwWithStackTrace(error, stack);
  }
  final failure = await _release(lock);
  if (failure != null) {
    throw PromotionException(
      'la promoción terminó, pero no se pudo liberar el lock de '
      '${layout.bin.path} (${failure.osError?.message ?? failure.message}); '
      'el sistema lo libera al terminar este proceso.',
    );
  }
  return result;
}

/// Suelta y cierra [lock]; devuelve el primer fallo de archivo, si hubo.
Future<FileSystemException?> _release(RandomAccessFile lock) async {
  FileSystemException? failure;
  try {
    await lock.unlock();
  } on FileSystemException catch (error) {
    failure = error;
  } finally {
    try {
      await lock.close();
    } on FileSystemException catch (error) {
      failure ??= error;
    }
  }
  return failure;
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
    try {
      await lock.close();
    } on FileSystemException {
      // El lock ocupado es el motivo; un cierre fallido no lo reemplaza.
    }
    throw PromotionException(
      'otra promoción tiene el lock de ${layout.bin.path}; no se modificó nada.',
    );
  }
  return lock;
}
