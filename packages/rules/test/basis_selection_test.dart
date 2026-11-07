import 'package:core/core.dart';
import 'package:rules/rules.dart';
import 'package:test/test.dart';

import 'basis_test_support.dart';

void main() {
  group('global_survives_local_filter', () {
    final basis = history([
      [
        v(1, 1, rule()),
        v(2, 1, rule(scope: at(['lib/a']))),
        v(3, 1, rule(scope: at(['lib/b']))),
        v(4, 1, pending()),
        v(5, 1, pending(scope: at(['lib/b']))),
        v(6, 1, rule(scope: at(['lib/ab']))),
      ],
    ]);

    test('a local query keeps global rules and unknown pendings', () {
      final selection = selectBasis(basis, path: 'lib/a/x.md');
      expect(ids(selection.selected), contains(key(1, 1)));
      expect(ids(selection.selected), contains(key(2, 1)));
      expect(ids(selection.pending), contains(key(4, 1)));
      expect(ids(selection.selected), isNot(contains(key(3, 1))));
    });

    test('lib/a is not lib/ab, and exclusions are only by scope', () {
      final selection = selectBasis(basis, path: 'lib/a');
      expect(ids(selection.selected), isNot(contains(key(6, 1))));
      expect(selection.excludedCount, 3);
    });

    test('without a path the whole current state is selected', () {
      final selection = selectBasis(basis);
      expect(selection.selected, hasLength(4));
      expect(selection.pending, hasLength(2));
      expect(selection.excludedCount, 0);
    });

    test('a consulted folder includes rules nested in it', () {
      final selection = selectBasis(basis, path: 'lib');
      expect(
        ids(selection.selected),
        containsAll([key(2, 1), key(3, 1), key(6, 1)]),
      );
    });
  });

  group('sources follow the version their rule cites', () {
    test('a global rule brings its source even outside the path', () {
      final basis = history([
        [
          v(9, 1, source(scope: at(['docs']))),
          v(
            1,
            1,
            rule(
              support: BasisSupport.sourceSupported,
              sourceRefs: [BasisReference(ref: uuid(9), version: 1)],
            ),
          ),
        ],
      ]);
      final selection = selectBasis(basis, path: 'lib/a');
      expect(ids(selection.selected), containsAll([key(1, 1), key(9, 1)]));
    });

    test(
      'a rule citing version 1 keeps version 1 after the source changes',
      () {
        final basis = history([
          [
            v(9, 1, source(scope: at(['docs']))),
            v(
              1,
              1,
              rule(
                support: BasisSupport.sourceSupported,
                sourceRefs: [BasisReference(ref: uuid(9), version: 1)],
              ),
            ),
          ],
          [
            v(9, 2, source(scope: at(['docs']), digest: digestOf(78))),
          ],
        ]);
        final selection = selectBasis(basis, path: 'lib/a');
        expect(ids(selection.selected), contains(key(9, 1)));
        expect(ids(selection.selected), isNot(contains(key(9, 2))));
      },
    );
  });

  group('review debt', () {
    test('review_debt_follows_selected_rule_id', () {
      final basis = history([
        [
          v(1, 1, rule(scope: at(['lib/a']))),
          v(2, 1, pending(scope: at(['lib/a']), review: review(1, 1))),
        ],
        [v(1, 2, rule())],
      ]);
      final selection = selectBasis(basis, path: 'lib/b');
      expect(ids(selection.pending), contains(key(2, 1)));
      expect(ids(selection.reviewTargets), [key(1, 1)]);
      expect(ids(selection.selected), contains(key(1, 2)));
      expect(selection.excludedCount, 0);
    });

    test('retired_target_does_not_reactivate_rule', () {
      final basis = history([
        [
          v(1, 1, rule(scope: at(['lib/a']))),
          v(2, 1, pending(scope: at(['lib/a']), review: review(1, 1))),
        ],
        [
          v(
            1,
            2,
            rule(scope: at(['lib/a']), lifecycle: BasisRuleLifecycle.retired),
          ),
        ],
      ]);
      final selection = selectBasis(basis, path: 'lib/a');
      expect(ids(selection.selected), isNot(contains(key(1, 2))));
      expect(ids(selection.selected), isNot(contains(key(1, 1))));
      expect(ids(selection.pending), contains(key(2, 1)));
      expect(ids(selection.reviewTargets), [key(1, 1)]);
    });

    test('target_sources_are_not_expanded', () {
      final basis = history([
        [
          v(9, 1, source(scope: at(['docs']))),
          v(
            1,
            1,
            rule(
              scope: at(['lib/a']),
              support: BasisSupport.sourceSupported,
              sourceRefs: [BasisReference(ref: uuid(9), version: 1)],
            ),
          ),
          v(2, 1, pending(scope: at(['lib/a']), review: review(1, 1))),
        ],
        [
          v(
            1,
            2,
            rule(scope: at(['lib/a']), lifecycle: BasisRuleLifecycle.retired),
          ),
        ],
      ]);
      final selection = selectBasis(basis, path: 'lib/a');
      expect(ids(selection.reviewTargets), [key(1, 1)]);
      expect(ids(selection.selected), isNot(contains(key(9, 1))));
    });

    test('a resolved review stays only in history', () {
      final basis = history([
        [
          v(1, 1, rule()),
          v(2, 1, pending(scope: BasisScope.project(), review: review(1, 1))),
        ],
        [
          v(
            2,
            2,
            pending(
              scope: BasisScope.project(),
              review: review(1, 1),
              status: BasisPendingStatus.resolved,
              resolution: 'rule:${uuid(1)}@1',
            ),
          ),
        ],
      ]);
      final selection = selectBasis(basis);
      expect(selection.pending, isEmpty);
      expect(selection.reviewTargets, isEmpty);
    });
  });
}
