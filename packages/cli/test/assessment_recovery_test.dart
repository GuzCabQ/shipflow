@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_recovery.dart';
import 'package:cli/src/assessment/assessment_store.dart';
import 'package:cli/src/context/state_layout.dart';
import 'package:cli/src/context/state_ownership.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_store_support.dart';
import 'support/context_service_support.dart';

void main() {
  late AssessmentBox box;
  late AssessmentDocument first;
  setUp(() async {
    box = await AssessmentBox.initialized();
    (first, _) = await twoRevisions();
  });
  tearDown(() => box.dispose());

  /// La primera publicación muere después de [writes] escrituras.
  Future<void> crashAfter(int writes) => expectLater(
    box.publish(first, wrap: (real) => CrashingStore(real, writes)),
    throwsA(isA<SimulatedCrash>()),
  );

  Future<AssessmentRecovery> recover({
    Future<void> Function(AssessmentDocument)? revalidate,
  }) async {
    final layout = await observeStateLayout(box.box.root) as ObservedLayout;
    return box.withStore(
      (store) => recoverAssessment(
        store,
        projectId: first.projectId,
        candidates: layout.assessmentCandidates,
        revalidate: revalidate ?? (_) async {},
      ),
    );
  }

  bool leftovers() =>
      File(box.path(assessmentJournalPath)).existsSync() ||
      Directory(
        box.path('shipflow/local/assessment-staging'),
      ).listSync().isNotEmpty;

  test(
    'a staged candidate without journal is identified and removed',
    () async {
      await crashAfter(1);
      final ownership = await inspectStateOwnership(box.box.root);
      expect(ownership.kind, StateOwnershipKind.owned);
      final recovery = await recover();
      expect(recovery.outcome, AssessmentRecoveryOutcome.leftoversRemoved);
      expect(box.document.existsSync(), isFalse);
      expect(leftovers(), isFalse);
    },
  );

  test('an interrupted publication before the rename is finished', () async {
    await crashAfter(2);
    final recovery = await recover();
    expect(recovery.outcome, AssessmentRecoveryOutcome.published);
    expect(recovery.published, isTrue);
    expect(box.document.readAsBytesSync(), encodeAssessment(first));
    expect(leftovers(), isFalse);
  });

  test('changed sources abort and keep what there was', () async {
    await crashAfter(2);
    final recovery = await recover(
      revalidate: (_) async => throw const AssessmentAbort('source_changed'),
    );
    expect(recovery.outcome, AssessmentRecoveryOutcome.aborted);
    expect(box.document.existsSync(), isFalse);
    expect(leftovers(), isFalse);
  });

  for (final writes in [3, 4, 5, 6]) {
    test(
      'after the rename ($writes writes) only cleans, never republishes',
      () async {
        await crashAfter(writes);
        final bytes = box.document.readAsBytesSync();
        final recovery = await recover(
          revalidate: (_) async => fail('no se revalida lo ya publicado'),
        );
        expect(recovery.outcome, AssessmentRecoveryOutcome.cleaned);
        expect(box.document.readAsBytesSync(), bytes);
        expect(decodeAssessment(bytes).revision, 1);
        expect(leftovers(), isFalse);
      },
    );
  }

  test('a document that is neither before nor after is a conflict', () async {
    await crashAfter(2);
    box.document.writeAsStringSync('{"ajeno": true}\n');
    final before = box.state();
    final recovery = await recover();
    expect(recovery.outcome, AssessmentRecoveryOutcome.conflict);
    expect(box.state(), before);
  });

  test('a corrupted candidate is preserved, never published', () async {
    await crashAfter(2);
    final staging =
        Directory(
              box.path('shipflow/local/assessment-staging'),
            ).listSync().single
            as Directory;
    File('${staging.path}/candidate.json').writeAsStringSync('{}\n');
    final before = box.state();
    final recovery = await recover();
    expect(recovery.outcome, AssessmentRecoveryOutcome.conflict);
    expect(box.state(), before);
    expect(box.document.existsSync(), isFalse);
  });

  test('a temporary without journal does not prove ownership', () async {
    Directory(
      box.path('shipflow/local/assessment-staging/$operationA'),
    ).createSync(recursive: true);
    File(
      box.path(
        'shipflow/local/assessment-staging/$operationA/'
        '.candidate.json.0123456789abcdef.tmp',
      ),
    ).writeAsStringSync('{');
    final ownership = await inspectStateOwnership(box.box.root);
    expect(ownership.kind, StateOwnershipKind.invalid);
    expect(ownership.findings.single, contains('.candidate.json.'));
  });
}
