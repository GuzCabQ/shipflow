import 'dart:math';

import 'package:crypto/crypto.dart';

import 'context_handles.dart';
import 'native/posix_api.dart';

/// El máximo que se lee de un destino para comparar su huella: más que
/// cualquier documento admitido, así que uno mayor nunca coincide.
const _maxFingerprintBytes = 16 * 1024 * 1024;
const _fileMode = 420;

/// Los bytes de la entrada regular [name] de [dirFd], hasta [max]; null si
/// no existe. Un enlace, FIFO, dispositivo o directorio no se abre para
/// leer su contenido.
List<int>? readRegular(NativePosix posix, int dirFd, String name, int max) {
  final entry = storeGuard(() => posix.lstatAt(dirFd, name));
  if (entry == null) return null;
  if (entry.type != NativeFileType.regular) {
    throw const ContextStoreFailure('unsafe_path');
  }
  final fd = storeGuard(() => posix.openRead(dirFd, name));
  try {
    final opened = storeGuard(() => posix.fstat(fd));
    if (opened.type != NativeFileType.regular ||
        opened.inode != entry.inode ||
        opened.device != entry.device) {
      throw const ContextStoreFailure('concurrent_change');
    }
    return storeGuard(() => posix.read(fd, max));
  } finally {
    posix.close(fd);
  }
}

/// La huella SHA-256 de los bytes completos de [name], o null si no existe.
String? fingerprintAt(NativePosix posix, int dirFd, String name) {
  final bytes = readRegular(posix, dirFd, name, _maxFingerprintBytes + 1);
  if (bytes == null) return null;
  if (bytes.length > _maxFingerprintBytes) {
    throw const ContextStoreFailure('concurrent_change');
  }
  return sha256.convert(bytes).toString();
}

/// Publica [bytes] como [name] de [dirFd] sólo si su versión actual tiene
/// la huella [expected] (null: ausente). Escribe un temporal propio en el
/// mismo directorio, con los permisos del destino que reemplaza, lo
/// confirma con fsync y lo renombra: nunca abre el destino para escribir,
/// así que un enlace o un hardlink colocados allí no reciben bytes. Si falla
/// después de crear el temporal, lo retira.
void publishAt(
  NativePosix posix,
  int dirFd,
  String name,
  List<int> bytes,
  String? expected,
) {
  if (fingerprintAt(posix, dirFd, name) != expected) {
    throw const ContextStoreFailure('concurrent_change');
  }
  final mode = expected == null
      ? _fileMode
      : storeGuard(() => posix.lstatAt(dirFd, name))?.permissions ?? _fileMode;
  final temporary = '.$name.${_nonce()}.tmp';
  final fd = storeGuard(() => posix.createExclusive(dirFd, temporary, mode));
  try {
    try {
      if (expected != null) storeGuard(() => posix.fchmod(fd, mode));
      storeGuard(() => posix.writeAll(fd, bytes));
      storeGuard(() => posix.fsync(fd));
    } finally {
      posix.close(fd);
    }
    storeGuard(() => posix.renameat(dirFd, temporary, dirFd, name));
  } on Object {
    _discard(posix, dirFd, temporary);
    rethrow;
  }
  storeGuard(() => posix.fsync(dirFd));
}

/// Retira [name] de [dirFd] sólo si su versión actual tiene [expected].
void removeAt(NativePosix posix, int dirFd, String name, String expected) {
  if (fingerprintAt(posix, dirFd, name) != expected) {
    throw const ContextStoreFailure('concurrent_change');
  }
  storeGuard(() => posix.unlinkat(dirFd, name));
  storeGuard(() => posix.fsync(dirFd));
}

/// El temporal de esta operación, si sigue ahí; nunca otro.
void _discard(NativePosix posix, int dirFd, String temporary) {
  try {
    posix.unlinkat(dirFd, temporary);
  } on PosixError {
    // Ya no está: no hay nada propio que retirar.
  }
}

String _nonce() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 8; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}
