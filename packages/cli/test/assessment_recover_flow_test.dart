@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';
import 'support/context_service_support.dart';

void main() {
  late AssessServiceBox box;
  setUp(() async {
    box = await AssessServiceBox.initialized();
    await box.run(AssessmentOperation.observe);
  });
  tearDown(() => box.dispose());

  Future<AssessmentResult> recover() => box.run(AssessmentOperation.recover);

  test('an interrupted publication is finished and then current', () async {
    await interruptPublication(box);
    final recovered = await recover();
    expect(
      (recovered.outcome, recovered.exitCode),
      (AssessmentOutcome.recovered, 0),
    );
    expect(recovered.effects.published, isTrue);
    expect(File(box.path(assessmentJournalPath)).existsSync(), isFalse);
    expect(decodeAssessment(box.document.readAsBytesSync()).revision, 2);
    final shown = await box.run(AssessmentOperation.show);
    expect(shown.freshness, AssessmentFreshness.current);
  });

  test('changed sources abort the recovery and keep the previous', () async {
    final bytes = box.document.readAsBytesSync();
    await interruptPublication(box);
    box.box.file('lib/nuevo.dart', 'class N {}\n');
    final recovered = await recover();
    expect(
      (recovered.outcome, recovered.exitCode),
      (AssessmentOutcome.recovered, 0),
    );
    expect(diagnosticCodes(recovered), contains('recovery_aborted'));
    expect(recovered.effects.published, isFalse);
    expect(box.document.readAsBytesSync(), bytes);
  });

  test('nothing to recover changes nothing', () async {
    final before = box.snapshot();
    final result = await recover();
    expect((result.outcome, result.exitCode), (AssessmentOutcome.unchanged, 0));
    expect(box.snapshot(), before);
  });

  test('an unfinished init operation is sent to init --recover', () async {
    box.box.file('packages/c/pubspec.yaml', 'name: c\n');
    await expectLater(
      box.box.run(
        ContextOperation.refresh,
        wrap: (real) => CrashingStore(real, 1),
      ),
      throwsA(isA<SimulatedCrash>()),
    );
    final result = await recover();
    expect(result.exitCode, 75);
    expect(actionArgs(result), contains('shipflow init --recover'));
    await interruptPublication(box);
    final both = await recover();
    expect(diagnosticCodes(both), contains('recovery_conflict'));
    expect(File(box.path(assessmentJournalPath)).existsSync(), isTrue);
  });

  test('contextChangedBeforeRecovery aborts and keeps the previous', () async {
    final bytes = box.document.readAsBytesSync();
    await interruptPublication(box);
    box.box.file('packages/widgets/pubspec.yaml', 'name: widgets\n# r2\n');
    expect((await box.v2(ContextOperation.refresh)).exitCode, 0);
    final recovered = await recover();
    expect(diagnosticCodes(recovered), contains('recovery_aborted'));
    expect(box.document.readAsBytesSync(), bytes);
  });

  test(
    'nothing to recover is 0 even over a partial saved assessment',
    () async {
      box.box.file('lib/roto.dart', 'class {');
      expect(
        (await box.run(AssessmentOperation.observe)).coverage,
        AssessmentCoverage.partial,
      );
      final result = await recover();
      expect(
        (result.outcome, result.exitCode),
        (AssessmentOutcome.unchanged, 0),
      );
      expect(result.snapshot, isNull);
      expect(actionArgs(result), contains('shipflow assess --show'));
    },
  );
}
