import 'dart:io';

import 'package:cli/src/context/context_handles.dart' show acquireResources;
import 'package:cli/src/context/context_request.dart';
import 'package:cli/src/context/native/posix_api.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:cli/src/context/state_layout.dart' show projectPath;
import 'package:core/core.dart';

import 'context_service_support.dart';
import 'store_spy_support.dart';

/// Un POSIX real que anota cómo se sueltan los descriptores del lease. Con
/// [failUnlockAt], la llamada número n a unlock suelta y cierra de verdad y
/// después lanza: el fallo es inyectado, los locks quedan libres.
final class RecordingPosix extends NativePosix {
  RecordingPosix(this.events, {this.failUnlockAt}) : super(currentPosixAbi());

  final List<String> events;
  final (int, InjectedFailure)? failUnlockAt;
  var _unlocks = 0;

  @override
  void unlock(int fd) {
    super.unlock(fd);
    events.add('lease.unlock');
    if (failUnlockAt case (final n, (final e, final t)) when ++_unlocks == n) {
      events.add('lease.unlock.fail');
      Error.throwWithStackTrace(e, t);
    }
  }

  @override
  void close(int fd) {
    super.close(fd);
    events.add('lease.close');
  }
}

/// Un almacén real visto desde fuera, con sus operaciones en un registro
/// común: [name] distingue la raíz prestada de la administración. Puede
/// fallar al adquirir, al leer después de adquirir o al cerrar.
final class TracedStore implements ContextStore {
  TracedStore(
    this.name,
    this.real,
    this.events, {
    this.posix,
    this.failAcquire,
    this.failReadAfterAcquire,
    this.failClose,
  });

  final String name;
  final ContextStore real;
  final List<String> events;
  final NativePosix? posix;
  final InjectedFailure? failAcquire;
  final InjectedFailure? failReadAfterAcquire;
  final InjectedFailure? failClose;
  var _acquired = false;

  int get closes => events.where((e) => e == '$name.close').length;

  void _log(String op) => events.add('$name.$op');

  /// Si el almacén real todavía lee: después de un cierre efectivo, no.
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
    _log('read');
    if (_acquired && failReadAfterAcquire != null) {
      _log('read.fail');
      final (e, t) = failReadAfterAcquire!;
      return Future.error(e, t);
    }
    return real.readRelative(path, maxBytes: maxBytes);
  }

  @override
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) {
    _log('publish');
    return real.publishRelative(path, bytes, expectedSha256: expectedSha256);
  }

  @override
  Future<void> removeRelative(String path, {required String expectedSha256}) {
    _log('remove');
    return real.removeRelative(path, expectedSha256: expectedSha256);
  }

  @override
  Future<List<String>> createDirectory(String path) {
    _log('mkdir');
    return real.createDirectory(path);
  }

  @override
  Future<void> removeDirectory(String path) {
    _log('rmdir');
    return real.removeDirectory(path);
  }

  @override
  ContextResource contextLock() => real.contextLock();

  @override
  ContextResource directoryLock() => real.directoryLock();

  @override
  Future<ContextLease> acquirePublication(
    List<ContextResource> resources,
  ) async {
    if (failAcquire case (final e, final t)) {
      _log('acquire.fail');
      return Future.error(e, t);
    }
    final lease = posix == null
        ? await real.acquirePublication(resources)
        : acquireResources(posix!, resources);
    _acquired = true;
    _log('acquire');
    return lease;
  }

  @override
  Future<void> close() async {
    _log('close');
    if (failClose case (final e, final t)) return Future.error(e, t);
    await real.close();
  }
}

/// Las administraciones que abre la recuperación, trazadas en [events]. Con
/// [failOpen], abrir falla antes de devolver nada. [dispose] cierra los
/// almacenes reales directamente, después de medir.
final class TracedAdmins {
  TracedAdmins(this.events, {this.failOpen, this.failClose});

  final List<String> events;
  final InjectedFailure? failOpen;
  final InjectedFailure? failClose;
  final opened = <TracedStore>[];

  Future<ContextStore> open(Directory directory) async {
    if (failOpen case (final e, final t)) {
      events.add('admin.open.fail');
      return Future.error(e, t);
    }
    final admin = TracedStore(
      'admin',
      await SecureContextStore.open(directory),
      events,
      failClose: failClose,
    );
    events.add('admin.open');
    opened.add(admin);
    return admin;
  }

  Future<void> dispose() async {
    for (final admin in opened) {
      await admin.real.close();
    }
  }
}

/// Un fallo con una traza propia, para reconocerlo intacto donde llegue.
InjectedFailure failure(Object error, String trace) =>
    (error, StackTrace.fromString(trace));

/// Init que muere tras cuatro escrituras: deja un journal propio. Con
/// [git], el journal incluye el exclude y la recuperación abre la
/// administración.
Future<void> interruptedInit(ServiceSandbox box, {required bool git}) async {
  try {
    await box.run(
      ContextOperation.init,
      sharing: git ? SharingChoice.local : null,
      git: git ? box.realGit : null,
      wrap: (real) => CrashingStore(real, 4),
    );
  } on SimulatedCrash {
    return;
  }
  throw StateError('init no se interrumpió');
}

/// Lo que devuelve o lanza una recuperación, con su traza, y si la raíz
/// prestada seguía utilizable al volver, antes de que su dueño la cierre.
typedef Recovered = ({
  ContextOperationResult? result,
  Object? error,
  StackTrace? trace,
  bool rootUsable,
});

/// Recupera con la raíz trazada como `root` y las administraciones de
/// [admins]; nunca lanza: devuelve el resultado o el error con su traza. La
/// prueba es dueña de la raíz: la abre, la presta y la cierra al final.
Future<Recovered> recoverTraced(
  ServiceSandbox box,
  List<String> events,
  TracedAdmins admins, {
  bool git = true,
  RecordingPosix? posix,
  InjectedFailure? failAcquire,
  InjectedFailure? failReadAfterAcquire,
}) async {
  final real = await SecureContextStore.open(box.root);
  final root = TracedStore(
    'root',
    real,
    events,
    posix: posix ?? RecordingPosix(events),
    failAcquire: failAcquire,
    failReadAfterAcquire: failReadAfterAcquire,
  );
  final service = box.service(
    root,
    git: git ? box.realGit : null,
    openAdministration: admins.open,
  );
  try {
    final result = await service.run(_recover);
    return (
      result: result,
      error: null,
      trace: null,
      rootUsable: await root.stillReads(projectPath),
    );
  } on Object catch (error, trace) {
    final usable = await root.stillReads(projectPath);
    return (result: null, error: error, trace: trace, rootUsable: usable);
  } finally {
    await real.close();
  }
}

const _recover = ContextRequest(operation: ContextOperation.recover);
