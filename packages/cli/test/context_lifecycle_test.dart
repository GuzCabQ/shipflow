@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/command/cli_command.dart';
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

  group('without Git: a local record, pending choice', () {
    test('first init writes only its own files', () async {
      final result = await box.run(ContextOperation.init);
      expect(result.outcome, ContextOutcome.initialized, reason: '$codes');
      expect(result.exitCode, 0);
      expect(result.sharing.choice, SharingChoice.pending);
      expect(result.sharing.gitState, GitState.notInstalled);
      expect(
        result.effects.filesCreated,
        containsAll([
          'shipflow/project.json',
          'shipflow/.gitignore',
          'shipflow/local/settings.json',
        ]),
      );
      expect(result.effects.excludeModified, isFalse);
      final saved = box.savedContext();
      expect(saved.revision, 1);
      expect(saved.recognition.omissions.single.rule, OmissionRule.toolState);
      expect(Directory(box.path('shipflow/local/staging')).listSync(), isEmpty);
      expect(
        File(box.path('shipflow/local/transaction.json')).existsSync(),
        isFalse,
      );
    });

    test(
      'S12: a second session reads, asks nothing and writes nothing',
      () async {
        await box.run(ContextOperation.init);
        final before = box.snapshot();
        final again = await box.run(
          ContextOperation.init,
          choose: (_) => fail('no debe preguntar'),
        );
        expect(again.outcome, ContextOutcome.unchanged);
        expect(again.exitCode, 0);
        expect(again.freshness, ContextFreshness.current);
        final doctor = await box.run(ContextOperation.doctor);
        expect(doctor.outcome, ContextOutcome.available);
        expect(doctor.exitCode, 0);
        expect(doctor.effects.wrote, isFalse);
        expect(
          doctor.checks.map((c) => c.id).toSet(),
          ContextCheckId.values.toSet(),
        );
        expect(box.snapshot(), before);
      },
    );

    test('S02: a new manifest makes it stale and leaves it intact', () async {
      await box.run(ContextOperation.init);
      final before = File(box.path('shipflow/project.json')).readAsBytesSync();
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      final doctor = await box.run(ContextOperation.doctor);
      expect(doctor.freshness, ContextFreshness.stale);
      expect(doctor.exitCode, 65);
      final init = await box.run(ContextOperation.init);
      expect(init.exitCode, 65);
      expect(init.nextActions.single.arguments, ['--refresh']);
      expect(File(box.path('shipflow/project.json')).readAsBytesSync(), before);
    });

    test('refresh keeps the identity and raises the revision', () async {
      await box.run(ContextOperation.init);
      final first = box.savedContext();
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      final result = await box.run(ContextOperation.refresh);
      expect(
        result.outcome,
        ContextOutcome.refreshed,
        reason: '${codes(result)}',
      );
      final second = box.savedContext();
      expect(second.projectId, first.projectId);
      expect(second.revision, 2);
      expect(
        File(box.path('shipflow/local/previous.json')).existsSync(),
        isTrue,
      );
      expect((await box.run(ContextOperation.doctor)).exitCode, 0);
    });

    test('an ineligible refresh keeps the bytes', () async {
      await box.run(ContextOperation.init);
      final saved = File(box.path('shipflow/project.json')).readAsBytesSync();
      box.file('pubspec.yaml', 'name: app\ndependencies:\n  x: {path: ../x}\n');
      final result = await box.run(ContextOperation.refresh);
      expect(result.exitCode, 65);
      expect(codes(result), contains('not_eligible'));
      expect(File(box.path('shipflow/project.json')).readAsBytesSync(), saved);
    });

    test('refresh or recover without a record', () async {
      final refresh = await box.run(ContextOperation.refresh);
      expect(codes(refresh), contains('not_initialized'));
      expect(refresh.exitCode, 65);
      final recover = await box.run(ContextOperation.recover);
      expect(recover.exitCode, 65);
      expect(Directory(box.path('shipflow')).existsSync(), isFalse);
    });

    test(
      'an explicit sharing choice without Git fails without writing',
      () async {
        final result = await box.run(
          ContextOperation.init,
          sharing: SharingChoice.local,
        );
        expect(codes(result), contains('sharing_unavailable'));
        expect(result.exitCode, 65);
        expect(Directory(box.path('shipflow')).existsSync(), isFalse);
      },
    );

    test('S06: a copy elsewhere without settings reads as current', () async {
      await box.run(ContextOperation.init);
      Directory(box.path('shipflow/local')).deleteSync(recursive: true);
      final doctor = await box.run(ContextOperation.doctor);
      expect(doctor.freshness, ContextFreshness.current);
      expect(doctor.exitCode, 0);
      expect(doctor.sharing.choice, SharingChoice.pending);
      expect(Directory(box.path('shipflow/local')).existsSync(), isFalse);
    });

    test(
      'S08: a foreign shipflow folder is occupied, never overwritten',
      () async {
        box.file('shipflow/main.go', 'package main\n');
        final before = box.snapshot();
        final result = await box.run(ContextOperation.init);
        expect(codes(result), contains('state_occupied'));
        expect(result.exitCode, 65);
        expect(box.snapshot(), before);
      },
    );
  });

  test(
    'M2: a stale init with another choice proposes refresh with it',
    () async {
      await box.run(ContextOperation.init);
      box.file('packages/b/pubspec.yaml', 'name: b\n');
      final init = await box.run(
        ContextOperation.init,
        sharing: SharingChoice.share,
      );
      expect(init.exitCode, 65);
      expect(init.nextActions.single.arguments, [
        '--refresh',
        '--sharing=share',
      ]);
    },
  );

  group('extendedContextDoesNotRaiseObservationBudget', () {
    test(
      'a context saved under extended is unverified under standard',
      () async {
        // Descripciones largas: superan el texto del perfil normal, no el
        // del ampliado.
        for (var i = 0; i < 400; i++) {
          box.file(
            'packages/p$i/pubspec.yaml',
            'name: p$i\ndescription: ${'d' * 3000}\n',
          );
        }
        final saved = await box.run(
          ContextOperation.init,
          profile: ReportBudgetProfile.extended,
        );
        expect(saved.exitCode, 0, reason: '${codes(saved)}');
        final before = box.snapshot();
        final doctor = await box.run(ContextOperation.doctor);
        expect(doctor.freshness, ContextFreshness.unverified);
        expect(doctor.exitCode, 65);
        expect(
          doctor.nextActions.expand((a) => a.arguments),
          contains('--report-budget=extended'),
        );
        expect(box.snapshot(), before);
      },
    );
  });
}
