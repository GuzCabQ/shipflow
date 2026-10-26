import 'dart:io';

import 'package:core/core.dart';

import 'context_handles.dart';
import 'context_publication.dart';
import 'native/posix_api.dart';

export 'context_handles.dart'
    show ContextLease, ContextResource, ContextStoreFailure;

/// El archivo de lock estable del contexto, relativo a la raíz.
const contextLockPath = 'shipflow/local/locks/context.lock';
const _directoryMode = 493;

/// Lecturas y publicaciones bajo una raíz, siempre desde el descriptor de
/// esa raíz y tramo a tramo sin seguir enlaces: una sustitución entre una
/// comprobación y una apertura no lleva a un destino ajeno. Sólo opera
/// archivos regulares y directorios; nunca crea nada al leer.
final class SecureContextStore {
  SecureContextStore._(this._posix, this._rootFd);

  /// Ancla [root], un directorio absoluto canónico, abriéndolo desde `/`
  /// componente a componente sin seguir enlaces.
  static Future<SecureContextStore> open(
    Directory root, {
    NativePosix? api,
  }) async {
    final NativePosix posix =
        api ?? storeGuard(() => NativePosix(currentPosixAbi()));
    if (!root.isAbsolute) throw const ContextStoreFailure('unsafe_path');
    var fd = storeGuard(() => posix.openRoot('/'));
    for (final segment in root.path.split('/').where((s) => s.isNotEmpty)) {
      final next = storeGuard(() {
        try {
          return posix.openDirectory(fd, segment);
        } finally {
          posix.close(fd);
        }
      });
      fd = next;
    }
    return SecureContextStore._(posix, fd);
  }

  final NativePosix _posix;
  int? _rootFd;

  /// Los bytes de [path], hasta `maxBytes + 1` para que quien los lea pueda
  /// rechazar un exceso sin materializarlo; null si no existe.
  Future<List<int>?> readRelative(String path, {required int maxBytes}) async {
    final (parent, name) = _split(path);
    final dir = _walk(parent, create: false);
    if (dir == null) return null;
    return _using(dir, () => readRegular(_posix, dir, name, maxBytes + 1));
  }

  /// Publica [bytes] en [path] si la versión actual tiene [expectedSha256]
  /// (null: ausente). Su directorio ya debe existir.
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) async {
    final (parent, name) = _split(path);
    final dir =
        _walk(parent, create: false) ?? (throw const ContextStoreFailure('io'));
    _using(dir, () => publishAt(_posix, dir, name, bytes, expectedSha256));
  }

  /// Retira [path] si su versión actual tiene [expectedSha256].
  Future<void> removeRelative(
    String path, {
    required String expectedSha256,
  }) async {
    final (parent, name) = _split(path);
    final dir =
        _walk(parent, create: false) ??
        (throw const ContextStoreFailure('concurrent_change'));
    _using(dir, () => removeAt(_posix, dir, name, expectedSha256));
  }

  /// Crea [path] y los directorios que le falten; devuelve los creados.
  Future<List<String>> createDirectory(String path) async {
    _validate(path);
    final created = <String>[];
    final dir = _walk(path.split('/'), create: true, created: created)!;
    _posix.close(dir);
    return created;
  }

  /// El lock del contexto, abierto sin truncar. Su directorio debe existir.
  ContextResource contextLock() => ContextResource('context', () {
    final (parent, name) = _split(contextLockPath);
    final dir =
        _walk(parent, create: false) ?? (throw const ContextStoreFailure('io'));
    return _using(dir, () {
      final fd = _posix.openLockFile(dir, name);
      if (_posix.fstat(fd).type != NativeFileType.regular) {
        _posix.close(fd);
        throw const ContextStoreFailure('unsafe_path');
      }
      return fd;
    });
  });

  /// El directorio anclado mismo como recurso: para el exclude común, sin
  /// crear un archivo de lock en la administración de Git.
  ContextResource directoryLock() =>
      ContextResource('directory', () => _posix.openDirectory(_fd, '.'));

  Future<ContextLease> acquirePublication(
    List<ContextResource> resources,
  ) async => acquireResources(_posix, resources);

  Future<void> close() async {
    final fd = _rootFd;
    _rootFd = null;
    if (fd != null) _posix.close(fd);
  }

  int get _fd => _rootFd ?? (throw const ContextStoreFailure('io'));

  /// Los tramos padre y el nombre final de una ruta de ubicación propia.
  (List<String>, String) _split(String path) {
    _validate(path);
    final segments = path.split('/');
    return (segments.sublist(0, segments.length - 1), segments.last);
  }

  void _validate(String path) {
    if (path == '.' || !isLocationPath(path)) {
      throw const ContextStoreFailure('unsafe_path');
    }
  }

  /// El descriptor de [segments] bajo la raíz, o null si falta un tramo y
  /// no se pide crearlo. Nunca sigue un enlace.
  int? _walk(
    List<String> segments, {
    required bool create,
    List<String>? created,
  }) {
    var fd = storeGuard(() => _posix.openDirectory(_fd, '.'));
    for (final (index, segment) in segments.indexed) {
      final entry = storeGuard(() => _posix.lstatAt(fd, segment));
      if (entry == null && !create) {
        _posix.close(fd);
        return null;
      }
      if (entry == null) {
        storeGuard(() => _posix.mkdirat(fd, segment, _directoryMode));
        created?.add(segments.sublist(0, index + 1).join('/'));
      }
      fd = _descend(fd, segment);
    }
    return fd;
  }

  int _descend(int fd, String segment) {
    try {
      return storeGuard(() => _posix.openDirectory(fd, segment));
    } finally {
      _posix.close(fd);
    }
  }

  T _using<T>(int dir, T Function() body) {
    try {
      return storeGuard(body);
    } finally {
      _posix.close(dir);
    }
  }
}
