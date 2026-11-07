import 'package:core/core.dart';
import 'package:test/test.dart';

import 'basis_fixtures.dart';

Matcher rejects(String code) =>
    throwsA(isA<ContextFormatException>().having((e) => e.code, 'code', code));

void main() {
  group('history_requires_contiguous_versions', () {
    test('a valid history replays to its current versions', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf())],
        [versionOf(1, 2, ruleOf(statement: 'Revisada.'))],
      ]);
      final current = replayBasis(document);
      expect(current[uuid(1)]!.version, 2);
    });

    test('a version gap is history_gap', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf())],
        [versionOf(1, 3, ruleOf(), previous: 1)],
      ]);
      expect(() => validateBasisDocument(document), rejects('history_gap'));
    });

    test('a revision that does not count the events is history_gap', () {
      final valid = documentOf([
        [versionOf(1, 1, ruleOf())],
      ]);
      final document = BasisDocument(
        projectId: valid.projectId,
        revision: 2,
        producerVersion: valid.producerVersion,
        events: valid.events,
        digest: valid.digest,
      );
      expect(() => validateBasisDocument(document), rejects('history_gap'));
    });

    test('an empty first acceptance is valid, a later one is not', () {
      expect(replayBasis(documentOf([[]])), isEmpty);
      expect(
        () => validateBasisDocument(documentOf([[], []])),
        rejects('invalid_schema'),
      );
    });

    test('an ID keeps its kind across versions', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf())],
        [versionOf(1, 2, pendingOf())],
      ]);
      expect(
        () => validateBasisDocument(document),
        rejects('invalid_reference'),
      );
    });
  });

  group('normative coverage', () {
    test('an empty basis keeps not_established', () {
      expect(
        basisCoverage(replayBasis(documentOf([[]]))),
        BasisCoverage.notEstablished,
      );
    });

    test('only proposals or pendings do not establish coverage', () {
      final current = replayBasis(
        documentOf([
          [
            versionOf(1, 1, ruleOf(lifecycle: BasisRuleLifecycle.proposed)),
            versionOf(2, 1, pendingOf()),
          ],
        ]),
      );
      expect(basisCoverage(current), BasisCoverage.notEstablished);
    });

    test('an active rule is declared_partial, never complete', () {
      final current = replayBasis(
        documentOf([
          [versionOf(1, 1, ruleOf())],
        ]),
      );
      expect(basisCoverage(current), BasisCoverage.declaredPartial);
    });
  });

  group('review links', () {
    final review = BasisDecisionReview(
      ref: uuid(1),
      version: 1,
      reviewer: null,
    );

    test('review_link_keeps_exact_version_and_null_reviewer', () {
      final current = replayBasis(
        documentOf([
          [
            versionOf(2, 1, pendingOf(review: review)),
            versionOf(1, 1, ruleOf()),
          ],
        ]),
      );
      final pending = current[uuid(2)]!.payload as BasisPending;
      expect(pending.decisionReview!.version, 1);
      expect(pending.decisionReview!.reviewer, isNull);
    });

    test('history_target_must_exist_at_event', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf())],
        [
          versionOf(
            2,
            1,
            pendingOf(
              review: BasisDecisionReview(
                ref: uuid(1),
                version: 2,
                reviewer: null,
              ),
            ),
          ),
        ],
        [versionOf(1, 2, ruleOf(statement: 'Revisada.'))],
      ]);
      expect(
        () => validateBasisDocument(document),
        rejects('invalid_reference'),
      );
    });

    test('review_binding_cannot_change', () {
      final other = BasisDecisionReview(
        ref: uuid(3),
        version: 1,
        reviewer: null,
      );
      final document = documentOf([
        [
          versionOf(1, 1, ruleOf()),
          versionOf(3, 1, ruleOf()),
          versionOf(2, 1, pendingOf(review: review)),
        ],
        [versionOf(2, 2, pendingOf(review: other))],
      ]);
      expect(
        () => validateBasisDocument(document),
        rejects('invalid_reference'),
      );
    });

    test('an ordinary pending cannot become a review', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf()), versionOf(2, 1, pendingOf())],
        [versionOf(2, 2, pendingOf(review: review))],
      ]);
      expect(
        () => validateBasisDocument(document),
        rejects('invalid_reference'),
      );
    });

    test('ordinary_pending_can_refine_scope', () {
      final document = documentOf([
        [versionOf(2, 1, pendingOf(scope: BasisScope.unknown()))],
        [
          versionOf(2, 2, pendingOf(scope: paths(['lib/a']))),
        ],
      ]);
      expect(replayBasis(document)[uuid(2)]!.version, 2);
    });

    test('a review pins the scope of its version', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf()), versionOf(2, 1, pendingOf(review: review))],
        [
          versionOf(2, 2, pendingOf(review: review, scope: paths(['lib']))),
        ],
      ]);
      expect(
        () => validateBasisDocument(document),
        rejects('invalid_reference'),
      );
    });

    test('the target must be an active rule of the same scope', () {
      for (final target in [
        ruleOf(lifecycle: BasisRuleLifecycle.proposed),
        ruleOf(scope: paths(['lib'])),
        pendingOf(),
      ]) {
        final document = documentOf([
          [versionOf(1, 1, target), versionOf(2, 1, pendingOf(review: review))],
        ]);
        expect(
          () => validateBasisDocument(document),
          rejects('invalid_reference'),
        );
      }
    });

    test('a later revision of the rule keeps the old link valid', () {
      final document = documentOf([
        [versionOf(1, 1, ruleOf()), versionOf(2, 1, pendingOf(review: review))],
        [versionOf(1, 2, ruleOf(lifecycle: BasisRuleLifecycle.retired))],
        [
          versionOf(
            2,
            2,
            pendingOf(
              review: BasisDecisionReview(
                ref: uuid(1),
                version: 1,
                reviewer: 'Ana',
              ),
            ),
          ),
        ],
      ]);
      expect(replayBasis(document)[uuid(2)]!.version, 2);
    });
  });
}
