import 'package:core/core.dart';
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'basis_test_support.dart';

BasisChange create(String key, BasisPayload payload) => BasisChange(
  key: key,
  targetId: null,
  expectedVersion: null,
  payload: payload,
);

BasisChange revise(int id, int expected, BasisPayload payload) => BasisChange(
  key: 'k$id',
  targetId: uuid(id),
  expectedVersion: expected,
  payload: payload,
);

BasisInput input(List<BasisChange> changes, {BasisActor? actor}) => BasisInput(
  projectId: project,
  expectedBasisDigest: null,
  actor: actor ?? actorOf(),
  reason: 'Propuesta.',
  changes: changes,
);

List<String> codes(List<BasisValidationIssue> issues) => [
  for (final i in issues) i.code,
];

BasisDecisionReview link(String ref, int version) =>
    BasisDecisionReview(ref: ref, version: version, reviewer: null);

void main() {
  group('same_batch_review_reference_resolves_before_publish', () {
    test('a new rule and its review are accepted together', () {
      final changes = input([
        create('compat', rule()),
        create(
          'debt',
          pending(scope: BasisScope.project(), review: link('new:compat', 1)),
        ),
      ]);
      expect(validateBasisChangeSet(changes, null), isEmpty);
      final resolved = resolveBasisChanges(changes, null, _ids());
      final pendingPayload = resolved[1].payload as BasisPending;
      expect(pendingPayload.decisionReview!.ref, resolved[0].id);
      expect(isUuidV4(pendingPayload.decisionReview!.ref), isTrue);
    });

    test('a source, a future version or a proposal is invalid_reference', () {
      for (final (target, version) in [
        (_unread(), 1),
        (rule(), 2),
        (rule(lifecycle: BasisRuleLifecycle.proposed), 1),
      ]) {
        final changes = input([
          create('t', target),
          create(
            'debt',
            pending(
              scope: BasisScope.project(),
              review: link('new:t', version),
            ),
          ),
        ]);
        expect(codes(validateBasisChangeSet(changes, null)), [
          'invalid_reference',
        ]);
      }
    });

    test('a review of an accepted version resolves against the basis', () {
      final basis = history([
        [v(1, 1, rule())],
      ]);
      final ok = input([
        create(
          'debt',
          pending(scope: BasisScope.project(), review: link(uuid(1), 1)),
        ),
      ]);
      expect(validateBasisChangeSet(ok, basis), isEmpty);
      final future = input([
        create(
          'debt',
          pending(scope: BasisScope.project(), review: link(uuid(1), 2)),
        ),
      ]);
      expect(codes(validateBasisChangeSet(future, basis)), [
        'invalid_reference',
      ]);
    });

    test('review_scope_cannot_escape_authority', () {
      final basis = history([
        [v(1, 1, rule())],
      ]);
      final local = input([
        create(
          'debt',
          pending(scope: BasisScope.project(), review: link(uuid(1), 1)),
        ),
      ], actor: actorOf(at(['lib/a'])));
      expect(codes(validateBasisChangeSet(local, basis)), ['authority_scope']);
    });
  });

  test('rejects_active_unknown_and_incomplete_prohibition', () {
    expect(
      codes(
        validateBasisChangeSet(
          input([create('r', rule(scope: BasisScope.unknown()))]),
          null,
        ),
      ),
      ['unknown_active_scope'],
    );
    expect(
      codes(
        validateBasisChangeSet(
          input([create('r', rule(ruleClass: BasisRuleClass.prohibition))]),
          null,
        ),
      ),
      ['missing_alternative'],
    );
  });

  group('actor_scope_cannot_escalate', () {
    final basis = history([
      [v(1, 1, rule())],
    ]);
    final local = actorOf(at(['lib/a']));

    test('a paths actor cannot activate a global rule', () {
      expect(
        codes(
          validateBasisChangeSet(
            input([create('r', rule())], actor: local),
            null,
          ),
        ),
        ['authority_scope'],
      );
    });

    test('a paths actor cannot narrow a global rule to its own path', () {
      final narrowed = input([
        revise(1, 1, rule(scope: at(['lib/a']))),
      ], actor: local);
      expect(codes(validateBasisChangeSet(narrowed, basis)), [
        'authority_scope',
      ]);
    });

    test('a project actor can narrow it', () {
      final narrowed = input([
        revise(1, 1, rule(scope: at(['lib/a']))),
      ]);
      expect(validateBasisChangeSet(narrowed, basis), isEmpty);
    });
  });

  group('new_refs_resolve_only_same_batch_sources', () {
    test('new:<key> to a source created in the batch resolves', () {
      final changes = input([
        create('doc', source(digest: null)),
        create(
          'r',
          rule(
            support: BasisSupport.sourceSupported,
            sourceRefs: [BasisReference(ref: 'new:doc', version: 1)],
          ),
        ),
      ]);
      final unread = input([
        BasisChange(
          key: 'doc',
          targetId: null,
          expectedVersion: null,
          payload: _unread(),
        ),
        changes.changes[1],
      ]);
      expect(validateBasisChangeSet(unread, null), isEmpty);
    });

    test('new:<key> to a rule or an unknown key is invalid_reference', () {
      for (final ref in ['new:other', 'new:missing']) {
        final changes = input([
          create('other', rule()),
          create(
            'r',
            rule(
              support: BasisSupport.sourceSupported,
              sourceRefs: [BasisReference(ref: ref, version: 1)],
            ),
          ),
        ]);
        expect(codes(validateBasisChangeSet(changes, null)), [
          'invalid_reference',
        ]);
      }
    });

    test('a UUID source must exist in the basis at that version', () {
      final basis = history([
        [v(9, 1, source())],
      ]);
      BasisInput citing(int version) => input([
        create(
          'r',
          rule(
            support: BasisSupport.sourceSupported,
            sourceRefs: [BasisReference(ref: uuid(9), version: version)],
          ),
        ),
      ]);
      expect(validateBasisChangeSet(citing(1), basis), isEmpty);
      expect(codes(validateBasisChangeSet(citing(2), basis)), [
        'invalid_reference',
      ]);
    });
  });

  group('retirement_preserves_history', () {
    final basis = history([
      [v(1, 1, rule())],
    ]);

    test('retiring revises the exact current version', () {
      final retire = input([
        revise(1, 1, rule(lifecycle: BasisRuleLifecycle.retired)),
      ]);
      expect(validateBasisChangeSet(retire, basis), isEmpty);
      final resolved = resolveBasisChanges(retire, basis, _ids());
      expect(resolved.single.version, 2);
      expect(resolved.single.previousVersion, 1);
    });

    test('a stale expected version is invalid_reference', () {
      final stale = input([
        revise(1, 2, rule(lifecycle: BasisRuleLifecycle.retired)),
      ]);
      expect(codes(validateBasisChangeSet(stale, basis)), [
        'invalid_reference',
      ]);
    });

    test('a review of version 1 survives the retirement', () {
      final later = history([
        [
          v(1, 1, rule()),
          v(2, 1, pending(scope: BasisScope.project(), review: review(1, 1))),
        ],
        [v(1, 2, rule(lifecycle: BasisRuleLifecycle.retired))],
      ]);
      final reviewer = input([
        revise(
          2,
          1,
          pending(
            scope: BasisScope.project(),
            review: BasisDecisionReview(
              ref: uuid(1),
              version: 1,
              reviewer: 'Ana',
            ),
          ),
        ),
      ]);
      expect(validateBasisChangeSet(reviewer, later), isEmpty);
    });
  });
}

BasisSource _unread() => BasisSource(
  title: 'Fuente',
  scope: BasisScope.project(),
  lifecycle: BasisSourceLifecycle.active,
  sourceType: BasisSourceType.local,
  locator: 'docs/politica.md',
  purpose: 'Referencia.',
  contentDigest: null,
  observation: BasisObservation.unverified,
);

String Function() _ids() {
  var n = 0xA00;
  return () => uuid(n++);
}
