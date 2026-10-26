import 'native/posix_api.dart';

/// Por qué el almacén no completó una operación, sin rutas ni contenido:
/// `busy`, `concurrent_change`, `unsafe_path`, `io` o
/// `unsupported_platform`. Nunca sigue a un efecto parcial no informado.
final class ContextStoreFailure implements Exception {
  const ContextStoreFailure(this.code);

  final String code;

  @override
  String toString() => 'ContextStoreFailure($code)';
}

/// Lo que el coordinador necesita de un almacén anclado. La implementación
/// de producción es `SecureContextStore`; las pruebas la envuelven para
/// simular la muerte del proceso entre dos escrituras, con el mismo
/// contrato.
abstract interface class ContextStore {
  Future<List<int>?> readRelative(String path, {required int maxBytes});

  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  });

  Future<void> removeRelative(String path, {required String expectedSha256});

  Future<List<String>> createDirectory(String path);

  /// Retira el directorio [path] si está vacío; si no existe, nada.
  Future<void> removeDirectory(String path);

  ContextResource contextLock();

  ContextResource directoryLock();

  Future<ContextLease> acquirePublication(List<ContextResource> resources);

  Future<void> close();
}

/// [body], con cada [PosixError] traducido a su [ContextStoreFailure].
T storeGuard<T>(T Function() body) {
  try {
    return body();
  } on PosixError catch (e) {
    throw ContextStoreFailure(switch (e.kind) {
      PosixErrorKind.loop ||
      PosixErrorKind.notDirectory ||
      PosixErrorKind.isDirectory => 'unsafe_path',
      PosixErrorKind.wouldBlock => 'busy',
      PosixErrorKind.unsupported => 'unsupported_platform',
      _ => 'io',
    });
  }
}

/// Algo que se bloquea antes de publicar: un archivo de lock bajo la raíz
/// o el directorio de administración mismo, abierto desde su ancla. Su
/// nombre es lógico; no lleva una ruta que un journal pudiera dictar.
final class ContextResource {
  ContextResource(this.name, this._open);

  final String name;
  final int Function() _open;

  /// Un descriptor nuevo, una descripción abierta propia para su flock.
  int open() => _open();
}

/// Los locks tomados de una publicación. Se sueltan al liberar o cuando el
/// proceso termina; nunca se borra un archivo de lock.
final class ContextLease {
  ContextLease(this._posix, List<int> descriptors)
    : _descriptors = List.of(descriptors);

  final NativePosix _posix;
  final List<int> _descriptors;

  /// Repetirla no hace nada.
  Future<void> release() async {
    while (_descriptors.isNotEmpty) {
      final fd = _descriptors.removeLast();
      try {
        _posix.unlock(fd);
      } finally {
        _posix.close(fd);
      }
    }
  }
}

/// Toma [resources] en orden de identidad física, sin esperar: si uno está
/// ocupado suelta los ya tomados y falla con `busy`.
ContextLease acquireResources(
  NativePosix posix,
  List<ContextResource> resources,
) {
  final opened = <({int fd, int device, int inode})>[];
  try {
    for (final resource in resources) {
      final fd = storeGuard(resource.open);
      final stat = storeGuard(() => posix.fstat(fd));
      opened.add((fd: fd, device: stat.device, inode: stat.inode));
    }
    opened.sort(
      (a, b) => a.device != b.device
          ? a.device.compareTo(b.device)
          : a.inode.compareTo(b.inode),
    );
    final taken = <int>[];
    for (final entry in opened) {
      if (!storeGuard(() => posix.tryLock(entry.fd))) {
        throw const ContextStoreFailure('busy');
      }
      taken.add(entry.fd);
    }
    return ContextLease(posix, taken);
  } on ContextStoreFailure {
    for (final entry in opened) {
      posix.close(entry.fd);
    }
    rethrow;
  }
}
