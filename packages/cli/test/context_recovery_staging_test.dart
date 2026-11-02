@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';

void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create();
    box.project();
    box.gitInit();
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];
  File exclude() => File(box.path('.git/info/exclude'));
  File settings() => File(box.path('shipflow/local/settings.json'));
  bool journal() =>
      File(box.path('shipflow/local/transaction.json')).existsSync();
  File stagedSettings() => Directory(box.path('shipflow/local/staging'))
      .listSync(recursive: true)
      .whereType<File>()
      .singleWhere((f) => f.path.endsWith('/settings.after.json'));

  /// Cambia la modalidad a [to] y muere después de [writes] escrituras.
  Future<void> switchCrashing(SharingChoice to, int writes) => expectLater(
    box.run(
      ContextOperation.init,
      sharing: to,
      git: box.realGit,
      wrap: (real) => CrashingStore(real, writes),
    ),
    throwsA(isA<SimulatedCrash>()),
  );

  Future<void> start(SharingChoice choice) =>
      box.run(ContextOperation.init, sharing: choice, git: box.realGit);

  /// Recover deshace el cambio de modalidad y deja vigente [kept].
  Future<void> expectAborted(SharingChoice kept, List<int>? excluded) async {
    final recover = await box.run(ContextOperation.recover, git: box.realGit);
    expect(recover.exitCode, 65, reason: '${codes(recover)}');
    expect(codes(recover), contains('recovery_aborted'));
    expect(recover.nextActions.first.arguments, [
      '--sharing=${kept == SharingChoice.share ? 'local' : 'share'}',
    ]);
    expect(journal(), isFalse);
    expect(settings().readAsStringSync(), contains('"${kept.toWireName()}"'));
    expect(
      exclude().existsSync() ? exclude().readAsBytesSync() : null,
      excluded,
    );
    final doctor = await box.run(ContextOperation.doctor, git: box.realGit);
    expect(doctor.exitCode, 0, reason: '${codes(doctor)}');
    expect(doctor.sharing.choice, kept);
  }

  List<int>? excludeBytes() =>
      exclude().existsSync() ? exclude().readAsBytesSync() : null;

  test(
    'RV2-01: share to local without its settings staging is undone',
    () async {
      await start(SharingChoice.share);
      final before = excludeBytes();
      await switchCrashing(SharingChoice.local, 1);
      expect(journal(), isTrue);
      await expectAborted(SharingChoice.share, before);
    },
  );

  test(
    'RV2-01: local to share without its settings staging is undone',
    () async {
      await start(SharingChoice.local);
      final before = excludeBytes();
      await switchCrashing(SharingChoice.share, 1);
      expect(journal(), isTrue);
      await expectAborted(SharingChoice.local, before);
    },
  );

  test(
    'RV2-01: an invalid staging reverts the exclude already applied',
    () async {
      await start(SharingChoice.share);
      final before = excludeBytes();
      await switchCrashing(SharingChoice.local, 3);
      expect(exclude().readAsStringSync(), contains('# shipflow:'));
      stagedSettings().writeAsStringSync('{"alterado": true}\n');
      await expectAborted(SharingChoice.share, before);
    },
  );

  test('RV2-01: settings already applied need no staging to finish', () async {
    await start(SharingChoice.share);
    await switchCrashing(SharingChoice.local, 5);
    expect(settings().readAsStringSync(), contains('"local"'));
    stagedSettings().deleteSync();
    final recover = await box.run(ContextOperation.recover, git: box.realGit);
    expect(recover.exitCode, 0, reason: '${codes(recover)}');
    expect(recover.sharing.effective, SharingEffective.localExcluded);
    expect(journal(), isFalse);
    final doctor = await box.run(ContextOperation.doctor, git: box.realGit);
    expect(doctor.exitCode, 0, reason: '${codes(doctor)}');
  });
}
