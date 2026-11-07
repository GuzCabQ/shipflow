@Timeout(Duration(minutes: 3))
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';
import 'support/context_service_support.dart';

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  List<BasisChange> ruleAndReview() => [
    create('compat', ruleOf()),
    create(
      'debt',
      pendingOf(
        review: BasisDecisionReview(
          ref: 'new:compat',
          version: 1,
          reviewer: null,
        ),
      ),
    ),
  ];

  group('accepted_rule_and_review_publish_together', () {
    test('one event with both, the link resolved to the rule UUID', () async {
      await box.publish(box.input(ruleAndReview()));
      final event = box.document.events.single;
      expect(event.changes, hasLength(2));
      final rule = event.changes.firstWhere((c) => c.payload is BasisRule);
      final pending = event.changes
          .map((c) => c.payload)
          .whereType<BasisPending>()
          .single;
      expect(pending.decisionReview!.ref, rule.id);
      expect(pending.decisionReview!.version, 1);
      expect(pending.decisionReview!.reviewer, isNull);
    });

    test('a crash before the rename recovers both or none', () async {
      final prepared = await box.prepare(box.input(ruleAndReview()));
      box.storeWrap = (real) => CrashingStore(real, 2);
      await expectLater(
        box.accept(prepared.draftDigest!),
        throwsA(isA<SimulatedCrash>()),
      );
      box.storeWrap = null;
      expect(box.basis.existsSync(), isFalse);
      await box.recover();
      expect(box.document.events.single.changes, hasLength(2));
    });
  });

  test('resolving_review_keeps_original_version', () async {
    await box.publish(box.input(ruleAndReview()));
    final rule = currentOf(box, 'rule');
    final pending = currentOf(box, 'pending');
    final link = (pending.payload as BasisPending).decisionReview!;
    final prepared = await box.prepare(
      box.input([revise(pending.id, 1, _resolved(link, rule.id))]),
    );
    final accepted = await box.accept(prepared.draftDigest!);
    expect(accepted.published, isTrue);
    final events = box.document.events;
    expect(events, hasLength(2));
    final original =
        events.first.changes.firstWhere((c) => c.id == pending.id).payload
            as BasisPending;
    expect(original.status, BasisPendingStatus.open);
    expect(original.decisionReview!.version, 1);
    expect(currentOf(box, 'rule').version, rule.version);
    final again = await box.accept(prepared.draftDigest!);
    expect(again.outcome, BasisOutcome.alreadyApplied);
    expect(box.document.events, hasLength(2));
  });

  test('preparing the same input again keeps its IDs and digest', () async {
    final first = await box.prepare(box.input([create('rule', ruleOf())]));
    final bytes = box.draft.readAsBytesSync();
    final again = await box.prepare(box.input([create('rule', ruleOf())]));
    expect(again.draftDigest, first.draftDigest);
    expect(again.outcome, BasisOutcome.draftPrepared);
    expect(box.draft.readAsBytesSync(), bytes);
  });

  test('stale_source_after_publish_does_not_rollback', () async {
    box.box.file('docs/politica.md', 'v1\n');
    await box.publish(box.input(ruleWithSource('docs/politica.md')));
    final bytes = box.basis.readAsBytesSync();
    box.box.file('docs/politica.md', 'v2\n');
    final shown = await box.show();
    expect(shown.exitCode, 65);
    expect(codesOf(shown), contains('source_unverified'));
    expect(shown.selection.complete, isTrue);
    expect(shown.selected.where((r) => r.payload is BasisRule), hasLength(1));
    expect(
      [for (final s in shown.sourceStatus) s.status],
      [BasisSourceState.stale],
    );
    final recovered = await box.recover();
    expect(recovered.outcome, BasisOutcome.noChanges);
    expect(box.basis.readAsBytesSync(), bytes);
  });
}

/// La versión resuelta de una revisión, con su vínculo intacto.
BasisPending _resolved(BasisDecisionReview link, String ruleId) => pendingOf(
  review: link,
  status: BasisPendingStatus.resolved,
  resolution: 'rule:$ruleId@1',
);
