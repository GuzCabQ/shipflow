@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/context_service_support.dart';

void main() {
  late AssessServiceBox box;
  tearDown(() => box.dispose());

  test('without init nothing is observed nor written', () async {
    box = await AssessServiceBox.initialized(init: false);
    final before = box.snapshot();
    final result = await box.run(AssessmentOperation.observe);
    expect((result.outcome, result.exitCode), (AssessmentOutcome.blocked, 65));
    expect(diagnosticCodes(result), contains('context_absent'));
    expect(actionArgs(result), contains('shipflow init'));
    expect(box.observations, 0);
    expect(box.snapshot(), before);
  });

  test('a repository without a choice is sent back to init', () async {
    box = await AssessServiceBox.initialized();
    box.box.gitInit();
    box.git = box.box.realGit;
    final result = await box.run(AssessmentOperation.observe);
    expect(diagnosticCodes(result), contains('choice_required'));
    expect(result.exitCode, 65);
    expect(box.document.existsSync(), isFalse);
  });

  test('without Git the pending choice still persists locally', () async {
    box = await AssessServiceBox.initialized();
    final result = await box.run(AssessmentOperation.observe);
    expect(result.outcome, AssessmentOutcome.saved);
    expect(diagnosticCodes(result), contains('git_absent'));
  });

  test('an unfinished init operation blocks with init --recover', () async {
    box = await AssessServiceBox.initialized();
    box.box.file('packages/c/pubspec.yaml', 'name: c\n');
    await expectLater(
      box.box.run(
        ContextOperation.refresh,
        wrap: (real) => CrashingStore(real, 1),
      ),
      throwsA(isA<SimulatedCrash>()),
    );
    final result = await box.run(AssessmentOperation.observe);
    expect(result.exitCode, 75);
    expect(actionArgs(result), contains('shipflow init --recover'));
  });

  test(
    'an unfinished assess publication blocks with assess --recover',
    () async {
      box = await AssessServiceBox.initialized();
      await box.run(AssessmentOperation.observe);
      await interruptPublication(box);
      expect(File(box.path(assessmentJournalPath)).existsSync(), isTrue);
      final result = await box.run(AssessmentOperation.observe);
      expect(result.exitCode, 75);
      expect(actionArgs(result), contains('shipflow assess --recover'));
    },
  );

  group('the cited context', () {
    setUp(() async {
      box = await AssessServiceBox.initialized();
      expect((await box.run(AssessmentOperation.observe)).exitCode, 0);
    });

    test('sameDigestForeignUnitIsRejected', () async {
      final json =
          jsonDecode(box.document.readAsStringSync()) as Map<String, Object?>;
      final current = json['current']! as Map<String, Object?>;
      final units = (current['units']! as List<Object?>)
          .cast<Map<String, Object?>>();
      units.first['label'] = 'ajena';
      current['snapshotId'] = snapshotIdOf(
        AssessmentSnapshot.fromJson(current),
      );
      box.document.writeAsStringSync(jsonEncode(json));
      final shown = await box.run(AssessmentOperation.show);
      expect(shown.exitCode, 65);
      expect(shown.freshness, isNot(AssessmentFreshness.current));
      expect(diagnosticCodes(shown), contains('assessment_context_mismatch'));
    });

    test('changedContextKeepsHistoricalReadable', () async {
      box.box.file('packages/widgets/pubspec.yaml', 'name: widgets\n# r2\n');
      expect((await box.v2(ContextOperation.refresh)).exitCode, 0);
      final shown = await box.run(AssessmentOperation.show);
      expect(shown.freshness, AssessmentFreshness.stale);
      expect(shown.snapshot, isNotNull);
      expect(diagnosticCodes(shown), contains('context_basis_unavailable'));
    });

    test('foreignProjectIsBlocked', () async {
      final text = box.document.readAsStringSync().replaceAll(
        RegExp(r'"projectId": "[^"]+"'),
        '"projectId": "99999999-9999-4999-8999-999999999999"',
      );
      box.document.writeAsStringSync(text);
      final shown = await box.run(AssessmentOperation.show);
      expect((shown.outcome, shown.exitCode), (AssessmentOutcome.blocked, 65));
      expect(shown.snapshot, isNull);
      expect(diagnosticCodes(shown), contains('project_identity'));
    });

    test('a missing previous is 65; a valid one is historical and 0', () async {
      final none = await box.run(AssessmentOperation.show, previous: true);
      expect(none.exitCode, 65);
      expect(diagnosticCodes(none), ['previous_absent']);
      box.box.file('lib/other.dart', '// segunda\n');
      await box.run(AssessmentOperation.observe);
      final history = await box.run(AssessmentOperation.show, previous: true);
      expect(
        (history.freshness, history.exitCode),
        (AssessmentFreshness.historical, 0),
      );
    });
  });
}
