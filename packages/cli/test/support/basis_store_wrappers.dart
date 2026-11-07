import 'package:cli/src/context/secure_context_store.dart';

import 'context_service_support.dart';

/// Ejecuta [before] justo antes de tomar el lock de publicación: otra
/// operación se intercala exactamente ahí.
final class BeforeLock extends CrashingStore {
  BeforeLock(ContextStore real, this.before) : super(real, 1 << 30);

  final Future<void> Function() before;

  @override
  Future<ContextLease> acquirePublication(
    List<ContextResource> resources,
  ) async {
    await before();
    return real.acquirePublication(resources);
  }
}

/// `shipflow/basis.json` existe pero no se puede leer.
final class UnreadableBasis extends CrashingStore {
  UnreadableBasis(ContextStore real) : super(real, 1 << 30);

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) {
    if (path == 'shipflow/basis.json') {
      throw const ContextStoreFailure('io');
    }
    return real.readRelative(path, maxBytes: maxBytes);
  }
}

/// Cuenta los bytes de contenido leídos bajo `docs/`.
final class CountingReads extends CrashingStore {
  CountingReads(ContextStore real) : super(real, 1 << 30);

  var contentBytes = 0;

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) async {
    final data = await real.readRelative(path, maxBytes: maxBytes);
    if (path.startsWith('docs/')) contentBytes += data?.length ?? 0;
    return data;
  }
}

/// Ejecuta [meanwhile] justo después de escribir el journal de bootstrap:
/// algo cambia entre el journal y la revalidación bajo el lock.
final class AfterJournal extends CrashingStore {
  AfterJournal(ContextStore real, this.meanwhile) : super(real, 1 << 30);

  final void Function() meanwhile;

  @override
  Future<void> publishRelative(
    String path,
    List<int> bytes, {
    required String? expectedSha256,
  }) async {
    await real.publishRelative(path, bytes, expectedSha256: expectedSha256);
    if (path == 'shipflow/local/basis-transaction.json') meanwhile();
  }
}
