import 'dart:io';

import 'package:cli/src/context/secure_context_store.dart';

/// Un fallo que el espía devuelve tal cual, con la traza que se le dio,
/// para comprobar que llega intacto a quien llama.
typedef InjectedFailure = (Object error, StackTrace trace);

/// Un almacén real visto desde fuera: registra cada llamada del código de
/// producción en orden, cuenta los intentos de cierre y puede fallar donde
/// se le pida. Nunca se cierra por su cuenta: al terminar la prueba se
/// cierra el real, sin pasar por el espía.
final class StoreSpy implements ContextStore {
  StoreSpy(
    this.real, {
    this.failRead,
    this.failPublish,
    this.failClose,
    this.onClose,
  });

  final ContextStore real;
  final InjectedFailure? failRead;
  final InjectedFailure? failPublish;
  final InjectedFailure? failClose;

  /// Lo que se observa justo antes de delegar el cierre.
  final Future<void> Function()? onClose;
  final calls = <String>[];

  int get closes => calls.where((c) => c == 'close').length;

  /// Si [path] todavía se lee por el almacén real: después de un cierre
  /// efectivo, su descriptor ya no existe.
  Future<bool> stillReads(String path) async {
    try {
      await real.readRelative(path, maxBytes: 1 << 20);
      return true;
    } on ContextStoreFailure {
      return false;
    }
  }

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) {
    calls.add('read $path');
    if (failRead case (final e, final t)) return Future.error(e, t);
    return real.readRelative(path, maxBytes: maxBytes);
  }

  @override
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) {
    calls.add('publish $path');
    if (failPublish case (final e, final t)) return Future.error(e, t);
    return real.publishRelative(path, bytes, expectedSha256: expectedSha256);
  }

  @override
  Future<void> removeRelative(String path, {required String expectedSha256}) {
    calls.add('remove $path');
    return real.removeRelative(path, expectedSha256: expectedSha256);
  }

  @override
  Future<List<String>> createDirectory(String path) {
    calls.add('create $path');
    return real.createDirectory(path);
  }

  @override
  Future<void> removeDirectory(String path) {
    calls.add('rmdir $path');
    return real.removeDirectory(path);
  }

  @override
  ContextResource contextLock() {
    calls.add('contextLock');
    return real.contextLock();
  }

  @override
  ContextResource directoryLock() {
    calls.add('directoryLock');
    return real.directoryLock();
  }

  @override
  Future<ContextLease> acquirePublication(List<ContextResource> resources) {
    calls.add('acquire');
    return real.acquirePublication(resources);
  }

  @override
  Future<void> close() async {
    calls.add('close');
    await onClose?.call();
    if (failClose case (final e, final t)) return Future.error(e, t);
    await real.close();
  }
}

/// Las administraciones que abre el servicio, cada una con su espía. Al
/// terminar, [dispose] cierra los almacenes reales directamente.
final class AdminSpies {
  final opened = <StoreSpy>[];

  Future<ContextStore> Function(Directory) opener({
    InjectedFailure? failRead,
    InjectedFailure? failPublish,
    InjectedFailure? failClose,
    Future<void> Function()? onClose,
  }) => (directory) async {
    final spy = StoreSpy(
      await SecureContextStore.open(directory),
      failRead: failRead,
      failPublish: failPublish,
      failClose: failClose,
      onClose: onClose,
    );
    opened.add(spy);
    return spy;
  };

  Future<void> dispose() async {
    for (final spy in opened) {
      await spy.real.close();
    }
  }
}

/// Si nadie tiene tomados el lock del contexto de [root] ni el directorio
/// de administración [commonDir]: se toman y se sueltan enseguida.
Future<bool> publicationFree(Directory root, Directory commonDir) async {
  final store = await SecureContextStore.open(root);
  final admin = await SecureContextStore.open(commonDir);
  try {
    final lease = await store.acquirePublication([
      store.contextLock(),
      admin.directoryLock(),
    ]);
    await lease.release();
    return true;
  } on ContextStoreFailure {
    return false;
  } finally {
    await admin.close();
    await store.close();
  }
}
