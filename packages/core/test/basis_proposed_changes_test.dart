import 'package:core/core.dart';
import 'package:test/test.dart';

import 'basis_fixtures.dart';

BasisResponse _draftResponse(
  List<BasisProposedChange> changes, {
  bool published = false,
  bool draft = true,
}) => BasisResponse(
  operation: published ? BasisOperation.accept : BasisOperation.prepare,
  exitCode: published ? 0 : 65,
  outcome: published ? BasisOutcome.published : BasisOutcome.draftPrepared,
  storageIntegrity: BasisStorageIntegrity(
    basis: BasisIntegrity.valid,
    draft: BasisIntegrity.valid,
    transaction: BasisIntegrity.absent,
  ),
  basisDigest: digestOf(1),
  draftDigest: draft ? digestOf(8) : null,
  published: published,
  changedFiles: const [],
  normativeCoverage: BasisCoverage.declaredPartial,
  selected: const [],
  reviewTargets: const [],
  proposedChanges: changes,
  pending: const [],
  sourceStatus: const [],
  actor: null,
  reason: null,
  history: const [],
  selection: BasisSelectionSummary(
    scope: null,
    complete: true,
    excludedCount: 0,
  ),
  diagnostics: const [],
  nextActions: const [],
);

void main() {
  group('each proposed change states its effect', () {
    for (final (name, version, kind) in [
      ('a new record', versionOf(1, 1, ruleOf()), BasisChangeKind.create),
      ('a revision', versionOf(1, 2, ruleOf()), BasisChangeKind.revise),
      (
        'a retirement',
        versionOf(1, 2, ruleOf(lifecycle: BasisRuleLifecycle.retired)),
        BasisChangeKind.retire,
      ),
      (
        'a replacement',
        versionOf(
          1,
          2,
          ruleOf(
            lifecycle: BasisRuleLifecycle.replaced,
            replacementRef: uuid(2),
          ),
        ),
        BasisChangeKind.replace,
      ),
      (
        'a resolution',
        versionOf(
          3,
          2,
          pendingOf(
            status: BasisPendingStatus.resolved,
            resolution: 'disposition:Hecho.',
          ),
        ),
        BasisChangeKind.resolve,
      ),
    ]) {
      test(name, () {
        expect(BasisProposedChange.of(version).change, kind);
      });
    }
  });

  test('a response accepts the exact effects of a draft', () {
    final changes = [
      BasisProposedChange.of(versionOf(1, 1, ruleOf())),
      BasisProposedChange.of(
        versionOf(2, 2, ruleOf(lifecycle: BasisRuleLifecycle.retired)),
      ),
    ];
    expect(
      () => validateBasisResponse(_draftResponse(changes)),
      returnsNormally,
    );
  });

  test('an effect that does not match its version is rejected', () {
    final wrong = BasisProposedChange(
      change: BasisChangeKind.retire,
      version: versionOf(1, 1, ruleOf()),
    );
    expect(
      () => validateBasisResponse(_draftResponse([wrong])),
      throwsA(isA<ContextFormatException>()),
    );
  });

  test('only an unaccepted draft carries proposed changes', () {
    final created = [BasisProposedChange.of(versionOf(1, 1, ruleOf()))];
    for (final response in [
      _draftResponse(created, published: true),
      _draftResponse(created, draft: false),
    ]) {
      expect(
        () => validateBasisResponse(response),
        throwsA(isA<ContextFormatException>()),
      );
    }
  });
}
