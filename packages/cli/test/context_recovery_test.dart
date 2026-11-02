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
  });
  tearDown(() => box.dispose());

  List<String> codes(ContextOperationResult r) => [
    for (final d in r.diagnostics) d.code,
  ];
  bool journal() =>
      File(box.path('shipflow/local/transaction.json')).existsSync();

  /// Init que muere después de [writes] escrituras.
  Future<void> crashAfter(
    int writes, {
    SharingChoice? sharing,
    bool git = false,
  }) => expectLater(
    box.run(
      ContextOperation.init,
      sharing: sharing,
      git: git ? box.realGit : null,
      wrap: (real) => CrashingStore(real, writes),
    ),
    throwsA(isA<SimulatedCrash>()),
  );

  group('S01: every interrupted publication is recovered or explained', () {
    for (var writes = 0; writes <= 9; writes++) {
      test('after $writes writes', () async {
        await crashAfter(writes);
        final doctor = await box.run(ContextOperation.doctor);
        if (journal()) {
          expect(doctor.contextState, ContextState.recoveryRequired);
          expect(doctor.exitCode, 75);
          final init = await box.run(ContextOperation.init);
          expect(init.exitCode, 75);
          expect(init.nextActions.single.arguments, ['--recover']);
        }
        final recover = await box.run(ContextOperation.recover);
        expect(recover.exitCode, anyOf(0, 65), reason: '${codes(recover)}');
        expect(journal(), isFalse);
        final again = await box.run(ContextOperation.init);
        expect(again.exitCode, 0, reason: '${codes(again)}');
        expect((await box.run(ContextOperation.doctor)).exitCode, 0);
      });
    }
  });

  test('S01: a crash between the exclude and the record is not done', () async {
    box.gitInit();
    // journal, exclude: el contexto todavía no es visible.
    await crashAfter(4, sharing: SharingChoice.local, git: true);
    final doctor = await box.run(ContextOperation.doctor, git: box.realGit);
    expect(doctor.contextState, isNot(ContextState.present));
    expect(doctor.outcome, isNot(ContextOutcome.available));
    final recover = await box.run(ContextOperation.recover, git: box.realGit);
    expect(
      recover.outcome,
      ContextOutcome.recovered,
      reason: '${codes(recover)}',
    );
    expect(recover.sharing.effective, SharingEffective.localExcluded);
  });

  test(
    'S09: sources changed during the first recovery abort cleanly',
    () async {
      await crashAfter(3);
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      final recover = await box.run(ContextOperation.recover);
      expect(recover.exitCode, 65);
      expect(journal(), isFalse);
      expect(File(box.path('shipflow/project.json')).existsSync(), isFalse);
      expect(recover.nextActions.single.arguments, isEmpty);
      expect((await box.run(ContextOperation.init)).exitCode, 0);
    },
  );

  test('a third-party edit makes recovery a conflict, journal kept', () async {
    await box.run(ContextOperation.init);
    box.file('packages/b/pubspec.yaml', 'name: b\n');
    await expectLater(
      box.run(ContextOperation.refresh, wrap: (r) => CrashingStore(r, 4)),
      throwsA(isA<SimulatedCrash>()),
    );
    box.file('shipflow/project.json', '{"editado": true}\n');
    final recover = await box.run(ContextOperation.recover);
    expect(recover.exitCode, 75, reason: '${codes(recover)}');
    expect(codes(recover), contains('recovery_conflict'));
    expect(journal(), isTrue);
  });

  test('unknownBootstrapTemporaryIsPreserved', () async {
    box.file('shipflow/.project.json.0123456789abcdef.tmp', 'resto');
    for (final op in [ContextOperation.init, ContextOperation.recover]) {
      final result = await box.run(op);
      expect(result.exitCode, 65);
      expect(codes(result), contains('bootstrap_unverified'));
    }
    expect(
      File(
        box.path('shipflow/.project.json.0123456789abcdef.tmp'),
      ).readAsStringSync(),
      'resto',
    );
  });

  test('S07: a corrupt record is never reset nor migrated', () async {
    await box.run(ContextOperation.init);
    box.file('shipflow/project.json', '{"schemaVersion": 9}\n');
    final before = box.snapshot();
    for (final op in [
      ContextOperation.init,
      ContextOperation.recover,
      ContextOperation.refresh,
      ContextOperation.doctor,
    ]) {
      final result = await box.run(op);
      expect(result.exitCode, 65, reason: '$op ${codes(result)}');
    }
    expect(box.snapshot(), before);
  });

  test('recovery never reports a write it did not need', () async {
    await box.run(ContextOperation.init);
    box.file('packages/b/pubspec.yaml', 'name: b\n');
    // journal, staging y previous.json: muere al publicar el contexto.
    await expectLater(
      box.run(ContextOperation.refresh, wrap: (r) => CrashingStore(r, 3)),
      throwsA(isA<SimulatedCrash>()),
    );
    final recover = await box.run(ContextOperation.recover);
    expect(
      recover.outcome,
      ContextOutcome.recovered,
      reason: '${codes(recover)}',
    );
    expect(recover.effects.filesReplaced, ['shipflow/project.json']);
  });

  test(
    'I2: own temporaries of an interrupted publish are recovered too',
    () async {
      await crashAfter(4);
      final op = Directory(
        box.path('shipflow/local/staging'),
      ).listSync().single;
      final name = op.path.split('/').last;
      for (final temp in [
        'shipflow/.project.json.0123456789abcdef.tmp',
        'shipflow/..gitignore.0123456789abcdef.tmp',
        'shipflow/local/.settings.json.0123456789abcdef.tmp',
        'shipflow/local/staging/$name/.settings.after.json.0123456789abcdef.tmp',
      ]) {
        box.file(temp, 'a medias');
      }
      final recover = await box.run(ContextOperation.recover);
      expect(
        recover.outcome,
        ContextOutcome.recovered,
        reason: '${codes(recover)}',
      );
      expect(recover.effects.filesRemoved, hasLength(4));
      final doctor = await box.run(ContextOperation.doctor);
      expect(doctor.exitCode, 0, reason: '${codes(doctor)}');
    },
  );

  test(
    'I2: a foreign folder does not claim there is nothing pending',
    () async {
      box.file('shipflow/main.go', 'package main\n');
      final doctor = await box.run(ContextOperation.doctor);
      final check = doctor.checks.firstWhere(
        (c) => c.id == ContextCheckId.transactionState,
      );
      expect(check.status, ContextCheckStatus.notChecked);
    },
  );

  test(
    'I3: recover without a journal over an intact context is unchanged',
    () async {
      await box.run(ContextOperation.init);
      final before = box.snapshot();
      final recover = await box.run(ContextOperation.recover);
      expect(recover.exitCode, 0, reason: '${codes(recover)}');
      expect(recover.outcome, ContextOutcome.unchanged);
      expect(recover.contextState, ContextState.present);
      expect(recover.freshness, ContextFreshness.current);
      expect(recover.context, isNotNull);
      expect(box.snapshot(), before);
    },
  );

  test(
    'M4: recovery does not claim a modality it cannot corroborate',
    () async {
      box.gitInit();
      // Muere al actualizar el journal, con el contexto ya publicado.
      await crashAfter(7, sharing: SharingChoice.local, git: true);
      box.file('.gitignore', '!shipflow/\n!shipflow/project.json\n');
      final recover = await box.run(ContextOperation.recover, git: box.realGit);
      expect(recover.exitCode, 65, reason: '${codes(recover)}');
      expect(codes(recover), contains('sharing_conflict'));
    },
  );

  test(
    'M5: a revert that cannot restore settings keeps them, never deletes',
    () async {
      await box.run(ContextOperation.init);
      box.gitInit();
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      // journal, staging de proyecto y settings, settings: muere en previous.
      await expectLater(
        box.run(
          ContextOperation.refresh,
          sharing: SharingChoice.share,
          git: box.realGit,
          wrap: (r) => CrashingStore(r, 5),
        ),
        throwsA(isA<SimulatedCrash>()),
      );
      final settings = File(box.path('shipflow/local/settings.json'));
      final applied = settings.readAsBytesSync();
      final staged = Directory(
        box.path('shipflow/local/staging'),
      ).listSync().single;
      File('${staged.path}/settings.before.json').deleteSync();
      box.file('packages/c/pubspec.yaml', 'name: c\n');
      final recover = await box.run(ContextOperation.recover, git: box.realGit);
      expect(recover.exitCode, 75, reason: '${codes(recover)}');
      expect(settings.readAsBytesSync(), applied);
      expect(journal(), isTrue);
    },
  );
}
