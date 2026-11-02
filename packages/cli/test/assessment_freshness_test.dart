@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';

void main() {
  late AssessServiceBox box;
  setUp(() async {
    box = await AssessServiceBox.initialized();
    final saved = await box.run(AssessmentOperation.observe);
    expect(saved.exitCode, 0, reason: '${diagnosticCodes(saved)}');
    box.observations = 0;
  });
  tearDown(() => box.dispose());

  Future<AssessmentResult> show() => box.run(AssessmentOperation.show);

  test('show reads, checks and never runs the detector nor writes', () async {
    final before = box.snapshot();
    final shown = await show();
    expect(
      (shown.outcome, shown.freshness, shown.exitCode),
      (AssessmentOutcome.shown, AssessmentFreshness.current, 0),
    );
    expect(box.observations, 0);
    expect(box.snapshot(), before);
    expect(shown.effects.published, isFalse);
  });

  test('changed content with the same size and time is stale', () async {
    final file = File(box.path('lib/other.dart'));
    final stamp = file.lastModifiedSync();
    final length = file.lengthSync();
    file.writeAsStringSync("import 'mainX.dart';\n".substring(0, length));
    file.setLastModifiedSync(stamp);
    final shown = await show();
    expect(shown.freshness, AssessmentFreshness.stale);
    expect(shown.exitCode, 65);
    expect(diagnosticCodes(shown), contains('assessment_stale'));
  });

  test('a new source without any commit is stale', () async {
    box.box.file('lib/nuevo.dart', 'class N {}\n');
    expect((await show()).freshness, AssessmentFreshness.stale);
  });

  test('deletedSourceInvalidatesWithoutHeadChange', () async {
    File(box.path('lib/other.dart')).deleteSync();
    final shown = await show();
    expect(shown.freshness, AssessmentFreshness.stale);
    expect(shown.snapshot, isNotNull);
  });

  test(
    'a changed manifest without refresh is stale and blocks observe',
    () async {
      box.box.file('packages/widgets/pubspec.yaml', 'name: widgets\n# x\n');
      expect((await show()).freshness, AssessmentFreshness.stale);
      final observe = await box.run(AssessmentOperation.observe);
      expect(observe.outcome, AssessmentOutcome.blocked);
      expect(diagnosticCodes(observe), contains('context_stale'));
      expect(actionArgs(observe), contains('shipflow init --refresh'));
    },
  );

  test('deletedUnitRequiresContextRefresh', () async {
    Directory(box.path('packages/widgets')).deleteSync(recursive: true);
    box.box.file('pubspec.yaml', 'name: app\n');
    expect((await show()).freshness, AssessmentFreshness.stale);
    expect(
      (await box.run(AssessmentOperation.observe)).outcome,
      AssessmentOutcome.blocked,
    );
    expect((await box.v2(ContextOperation.refresh)).exitCode, 0);
    final again = await box.run(AssessmentOperation.observe);
    expect(again.outcome, AssessmentOutcome.saved);
    final history = await box.run(AssessmentOperation.show, previous: true);
    expect(history.snapshot!.units.map((u) => u.label), contains('widgets'));
  });

  test('an unreadable source can never be current', () async {
    Process.runSync('chmod', ['000', box.path('lib/other.dart')]);
    final shown = await show();
    expect(shown.freshness, isNot(AssessmentFreshness.current));
    expect(shown.exitCode, 65);
  });

  test('a check that does not fit its budget is unverified', () async {
    final standard = AssessmentLimits.forProfile(AssessmentProfile.standard);
    box.limitsFor = (_) =>
        AssessmentLimits.fromJson(standard.toJson()..['maxEntries'] = 2);
    final shown = await show();
    expect(shown.freshness, AssessmentFreshness.unverified);
    expect(diagnosticCodes(shown), contains('assessment_unverified'));
  });

  test('returning without changes keeps snapshot and time', () async {
    final bytes = box.document.readAsBytesSync();
    box.clock = box.clock.add(const Duration(hours: 1));
    final again = await box.run(AssessmentOperation.observe);
    expect(again.outcome, AssessmentOutcome.unchanged);
    expect(box.document.readAsBytesSync(), bytes);
    expect(again.snapshot!.observedAt, '2026-11-02T12:00:00Z');
  });
}
