@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';
import 'support/store_spy_support.dart';

/// El directorio de administración Git que init abre para el exclude es
/// suyo: lo cierra una vez, en cada salida, y no toca el almacén del
/// proyecto, que es de quien lo prestó.
void main() {
  late ServiceSandbox box;
  late AdminSpies spies;
  setUp(() {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
    spies = AdminSpies();
  });
  tearDown(() async {
    await spies.dispose();
    box.dispose();
  });

  Directory commonDir() => Directory(box.path('.git'));
  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];

  test('a local init closes it once, last, after the lease', () async {
    StoreSpy? root;
    bool? free, rootReads;
    final result = await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
      wrap: (real) => root = StoreSpy(real),
      openAdministration: spies.opener(
        onClose: () async {
          free = await publicationFree(box.root, commonDir());
          rootReads = await root!.stillReads('pubspec.yaml');
        },
      ),
    );
    expect(result.exitCode, 0, reason: '${codes(result)}');
    final admin = spies.opened.single;
    expect(admin.closes, 1);
    expect(admin.calls.last, 'close');
    expect(admin.calls, contains('publish info/exclude'));
    expect(free, isTrue, reason: 'el lease se suelta antes de cerrar');
    expect(await admin.stillReads('HEAD'), isFalse);
    expect(rootReads, isTrue);
    expect(root!.closes, 0);
  });

  test('a change of modality closes it; keeping it never opens it', () async {
    await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
    );
    final share = await box.run(
      ContextOperation.init,
      sharing: SharingChoice.share,
      git: box.realGit,
      openAdministration: spies.opener(),
    );
    expect(share.exitCode, 0, reason: '${codes(share)}');
    expect(spies.opened.single.closes, 1);
    expect(
      File(box.path('.git/info/exclude')).readAsStringSync(),
      isNot(contains('shipflow')),
    );
    box.file('pubspec.yaml', 'name: app\ndescription: otra\n');
    final refresh = await box.run(
      ContextOperation.refresh,
      git: box.realGit,
      openAdministration: spies.opener(),
    );
    expect(refresh.outcome, ContextOutcome.refreshed);
    expect(spies.opened, hasLength(1));
  });

  test('a refused exclude closes it without writing anything', () async {
    final foreign = File('${box.base.path}/ajeno')..writeAsStringSync('x\n');
    final exclude = File(box.path('.git/info/exclude'));
    if (exclude.existsSync()) exclude.deleteSync();
    Link(exclude.path).createSync(foreign.path);
    final before = box.snapshot();
    final result = await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
      openAdministration: spies.opener(),
    );
    expect(codes(result), contains('sharing_conflict'));
    expect(spies.opened.single.closes, 1);
    expect(box.snapshot(), before);
    expect(foreign.readAsStringSync(), 'x\n');
  });

  test('nothing to publish closes it and only reports the choice', () async {
    await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
    );
    final before = box.snapshot();
    final result = await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.gitFailingAfterObservation,
      openAdministration: spies.opener(),
    );
    expect(codes(result), contains('git_unavailable'));
    final admin = spies.opened.single;
    expect(admin.closes, 1);
    expect(admin.calls, isNot(contains('directoryLock')));
    expect(box.snapshot(), before);
  });

  test('a busy publication closes it and keeps the root open', () async {
    await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
    );
    final holder = await SecureContextStore.open(box.root);
    final lease = await holder.acquirePublication([holder.contextLock()]);
    StoreSpy? root;
    try {
      final result = await box.run(
        ContextOperation.init,
        sharing: SharingChoice.share,
        git: box.realGit,
        wrap: (real) => root = StoreSpy(real),
        openAdministration: spies.opener(),
      );
      expect(codes(result), contains('busy'));
    } finally {
      await lease.release();
      await holder.close();
    }
    expect(spies.opened.single.closes, 1);
    expect(root!.closes, 0);
  });
}
