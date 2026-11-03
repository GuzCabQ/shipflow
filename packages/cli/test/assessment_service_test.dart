@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';

void main() {
  late AssessServiceBox box;
  setUp(() async => box = await AssessServiceBox.initialized());
  tearDown(() => box.dispose());

  Future<AssessmentResult> observe() => box.run(AssessmentOperation.observe);

  test('a first observation is saved with a localizable connection', () async {
    final saved = await observe();
    expect(
      (saved.outcome, saved.exitCode, saved.coverage),
      (AssessmentOutcome.saved, 0, AssessmentCoverage.complete),
    );
    expect(saved.effects.published, isTrue);
    expect(saved.effects.created, contains('shipflow/assessment.json'));
    final snapshot = saved.snapshot!;
    final connection = projectAssessment(
      snapshot,
    ).firstWhere((c) => c.sourceUnitId != c.targetUnitId);
    final claim = snapshot.claims.firstWhere(
      (c) => c.id == connection.claimIds.single,
    );
    expect(claim.targetLabel, 'packages/widgets/lib/widget.dart');
    expect((claim.evidence.line, claim.evidence.column), (1, 1));
  });

  test('S3: the declared dependency stays a separate context link', () async {
    final snapshot = (await observe()).snapshot!;
    final declared = snapshot.contextLinks.where(
      (l) => l.kind == AssessmentLinkKind.declaredDependency,
    );
    expect(declared, hasLength(1));
    expect(
      snapshot.claims.map((c) => c.id),
      isNot(contains(declared.single.sourceId)),
    );
  });

  test(
    'S1: a source changed before the commit is 75 and keeps previous',
    () async {
      await observe();
      final bytes = box.document.readAsBytesSync();
      box.box.file('lib/other.dart', "import 'main.dart';\n// v2\n");
      box.observerWrap = (real) => (root, context, limits) async {
        final observation = await real(root, context, limits);
        box.box.file('lib/tarde.dart', 'class T {}\n');
        return observation;
      };
      final result = await observe();
      expect(result.exitCode, 75);
      expect(diagnosticCodes(result), contains('source_changed'));
      expect(result.effects.published, isFalse);
      expect(box.document.readAsBytesSync(), bytes);
    },
  );

  test('a stable parser error is current, partial and 65', () async {
    box.box.file('lib/roto.dart', 'class {');
    await box.v2(ContextOperation.init);
    final saved = await observe();
    expect(
      (saved.freshness, saved.coverage, saved.exitCode),
      (AssessmentFreshness.current, AssessmentCoverage.partial, 65),
    );
    expect(saved.effects.published, isTrue);
  });

  test('S2: partialReobservationHasNoDisappearanceCounts', () async {
    await observe();
    final first = decodeAssessment(box.document.readAsBytesSync());
    Process.runSync('chmod', ['000', box.path('lib/other.dart')]);
    final partial = await observe();
    expect(partial.coverage, AssessmentCoverage.partial);
    expect(partial.comparison, isNull);
    expect(diagnosticCodes(partial), contains('comparison_unavailable'));
    final saved = decodeAssessment(box.document.readAsBytesSync());
    expect(saved.previous!.snapshotId, first.current.snapshotId);
  });

  test(
    'a confirmed deletion over a complete inventory is not observed now',
    () async {
      await observe();
      box.box.file('lib/other.dart', '// sin directivas\n');
      final again = await observe();
      expect(again.comparison!.notObservedNow, 1);
      expect(again.comparison!.repeatedReferences, 1);
    },
  );

  test('a third revision retires the oldest one visibly', () async {
    await observe();
    box.box.file('lib/other.dart', '// segunda\n');
    await observe();
    box.box.file('lib/other.dart', "import 'main.dart';\n// tercera\n");
    final third = await observe();
    expect(third.retiredRevision, 1);
    expect(diagnosticCodes(third), contains('revision_retired'));
    final saved = decodeAssessment(box.document.readAsBytesSync());
    expect(saved.revision, 3);
  });

  test('another cited context makes the comparison unavailable', () async {
    await observe();
    box.box.file('packages/widgets/lib/extra.dart', 'class E {}\n');
    box.box.file('packages/widgets/pubspec.yaml', 'name: widgets\n# r2\n');
    await box.v2(ContextOperation.refresh);
    final again = await observe();
    expect(again.comparison, isNull);
    expect(diagnosticCodes(again), contains('comparison_unavailable'));
  });
}
