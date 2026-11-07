@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'init_process_support.dart';
import 'support/basis_process_support.dart';
import 'support/basis_service_support.dart';

void main() {
  final process = InitProcessSandbox()..register();
  late BasisWalk walk;

  Future<void> initialized(ProjectShape shape) async {
    shape.files.forEach(process.place);
    final init = await process.run(['init', '--json']);
    expect(init.exitCode, 0, reason: init.stdout);
    walk = BasisWalk(process);
  }

  test('R2: a review keeps its v1 binding across scope and owner '
      'changes', () async {
    await initialized(dartPackage);
    await _ruleWithUnownedReview(walk, dartPackage);
    final (rule, review) = (
      walk.current('Contratos'),
      walk.current('Revisión'),
    );
    await _ruleGoesGlobal(walk, dartPackage, rule.id);
    await _reviewerAssigned(walk, rule.id, review.id);
    await _currentSourceApartFromHistoricalReview(walk, dartPackage);
    await _reviewResolved(walk, rule.id, review.id);
    await _historyKeepsTheAntecedent(walk, dartPackage, rule.id);
  });

  for (final shape in [flutterMinimal, dartPackage, independentLayout]) {
    test('the contract walkthrough on ${shape.name}', () async {
      await initialized(shape);
      await _basisWithPending(walk);
      final (global, scoped) = await _globalAndScoped(walk, shape);
      await _consultedByScope(walk, shape);
      await _replaced(walk, shape, scoped);
      final history = await walk.bootstrap(['--show', '--history']);
      expect(history.history, hasLength(3));
      expect(codesOf(history), contains('history_sources_not_rechecked'));
      await _staleSupportKeepsTheRule(walk, shape, global);
    });
  }
}

BasisScope _area(ProjectShape shape) => at([shape.area]);

BasisChange _sourced(String key, ProjectShape shape, BasisScope scope) =>
    create(
      key,
      ruleOf(
        scope: scope,
        support: BasisSupport.sourceSupported,
        sourceRefs: [BasisReference(ref: 'new:doc', version: 1)],
      ),
    );

Future<void> _ruleWithUnownedReview(BasisWalk w, ProjectShape shape) async {
  await w.publish([
    create('doc', localSource(shape.source)),
    _sourced('compat', shape, _area(shape)),
    create(
      'review',
      pendingOf(
        scope: _area(shape),
        review: BasisDecisionReview(
          ref: 'new:compat',
          version: 1,
          reviewer: null,
        ),
      ),
    ),
  ]);
  final shown = await w.bootstrap(['--show', '--scope', shape.area]);
  expect(shown.exitCode, 0);
  expect(shown.selected.where((v) => v.payload is BasisRule), hasLength(1));
  final review = shown.pending.single.payload as BasisPending;
  expect(review.decisionReview!.reviewer, isNull);
}

Future<void> _ruleGoesGlobal(
  BasisWalk w,
  ProjectShape shape,
  String ruleId,
) async {
  final doc = w.current('Política').id;
  await w.publish([
    revise(
      ruleId,
      1,
      ruleOf(
        support: BasisSupport.sourceSupported,
        sourceRefs: [BasisReference(ref: doc, version: 1)],
      ),
    ),
  ]);
  final elsewhere = await w.bootstrap(['--show', '--scope', shape.other]);
  final rule = elsewhere.selected.singleWhere((v) => v.id == ruleId);
  expect((rule.version, rule.payload.scope.kind), (2, BasisScopeKind.project));
  final target = elsewhere.reviewTargets.single;
  expect((target.id, target.version), (ruleId, 1));
  expect(target.payload.scope.paths, [shape.area]);
}

BasisPending _review(
  ProjectShape shape,
  String ruleId, {
  BasisPendingStatus status = BasisPendingStatus.open,
  String? resolution,
}) => pendingOf(
  scope: _area(shape),
  status: status,
  resolution: resolution,
  review: BasisDecisionReview(
    ref: ruleId,
    version: 1,
    reviewer: 'Equipo de contratos',
  ),
);

Future<void> _reviewerAssigned(
  BasisWalk w,
  String ruleId,
  String reviewId,
) async {
  await w.publish([revise(reviewId, 1, _review(dartPackage, ruleId))]);
  final shown = await w.bootstrap(['--show']);
  final review = shown.pending.single.payload as BasisPending;
  expect(review.decisionReview!.reviewer, 'Equipo de contratos');
  expect(review.decisionReview!.version, 1);
}

Future<void> _currentSourceApartFromHistoricalReview(
  BasisWalk w,
  ProjectShape shape,
) async {
  final source = File('${w.process.root.path}/${shape.source}');
  final original = source.readAsStringSync();
  source.writeAsStringSync('Otra política.\n');
  final shown = await w.bootstrap(['--show']);
  expect(shown.sourceStatus.single.status, BasisSourceState.stale);
  expect(shown.selected.where((v) => v.payload is BasisRule), hasLength(1));
  expect(shown.reviewTargets.single.version, 1);
  expect(codesOf(shown), contains('historical_support_not_rechecked'));
  source.writeAsStringSync(original);
  final restored = await w.bootstrap(['--show']);
  expect(restored.sourceStatus.single.status, BasisSourceState.current);
}

Future<void> _reviewResolved(
  BasisWalk w,
  String ruleId,
  String reviewId,
) async {
  await w.publish([
    revise(
      reviewId,
      2,
      _review(
        dartPackage,
        ruleId,
        status: BasisPendingStatus.resolved,
        resolution: 'rule:$ruleId@2',
      ),
    ),
  ]);
  final shown = await w.bootstrap(['--show']);
  expect(shown.pending, isEmpty);
  expect(shown.reviewTargets, isEmpty);
}

Future<void> _historyKeepsTheAntecedent(
  BasisWalk w,
  ProjectShape shape,
  String ruleId,
) async {
  final shown = await w.bootstrap(['--show', '--history']);
  expect(shown.history.map((e) => e.revision), [1, 2, 3, 4]);
  final first = shown.history.first.changes.singleWhere((c) => c.id == ruleId);
  expect(first.payload.scope.paths, [shape.area]);
  final bindings = [
    for (final e in shown.history)
      for (final c in e.changes)
        if (c.payload case BasisPending(:final decisionReview?))
          (decisionReview.ref, decisionReview.version),
  ];
  expect(bindings, everyElement((ruleId, 1)));
  expect(bindings, hasLength(3));
}

Future<void> _basisWithPending(BasisWalk w) async {
  await w.publish([create('open', pendingOf(scope: BasisScope.unknown()))]);
  final other = await w.bootstrap(['--show']);
  expect(other.exitCode, 0);
  expect(other.pending.single.payload.scope.kind, BasisScopeKind.unknown);
  expect(other.normativeCoverage, BasisCoverage.notEstablished);
}

/// Una decisión global y otra acotada en la misma propuesta; se acepta
/// exactamente el borrador consultado.
Future<(String, String)> _globalAndScoped(
  BasisWalk w,
  ProjectShape shape,
) async {
  final prepared = await w.prepare([
    create('doc', localSource(shape.source)),
    _sourced('global', shape, BasisScope.project()),
    create('scoped', ruleOf(scope: _area(shape), statement: 'Sólo aquí.')),
  ]);
  final draft = await w.bootstrap(['--show', '--draft']);
  expect(draft.draftDigest, prepared.draftDigest);
  expect(codesOf(draft), contains('draft_not_accepted'));
  final accepted = await w.bootstrap(['--accept', prepared.draftDigest!]);
  expect(accepted.published, isTrue);
  final rules = replayBasis(
    w.document,
  ).values.where((v) => v.payload is BasisRule);
  final scoped = rules.singleWhere((v) => v.payload.scope.paths.isNotEmpty);
  final global = rules.singleWhere((v) => v.payload.scope.paths.isEmpty);
  return (global.id, scoped.id);
}

Future<void> _consultedByScope(BasisWalk w, ProjectShape shape) async {
  final inside = await w.bootstrap(['--show', '--scope', shape.area]);
  final outside = await w.bootstrap(['--show', '--scope', shape.other]);
  int rules(BasisResponse r) =>
      r.selected.where((v) => v.payload is BasisRule).length;
  expect((rules(inside), rules(outside)), (2, 1));
  expect(outside.selection.excludedCount, 1);
  expect(outside.pending, hasLength(1), reason: 'el ámbito desconocido');
}

Future<void> _replaced(BasisWalk w, ProjectShape shape, String scopedId) async {
  await w.publish([
    create('nueva', ruleOf(statement: 'Ahora en todo el proyecto.')),
    revise(
      scopedId,
      1,
      ruleOf(
        scope: _area(shape),
        lifecycle: BasisRuleLifecycle.replaced,
        replacementRef: 'new:nueva',
        statement: 'Sólo aquí.',
      ),
    ),
  ]);
  final shown = await w.bootstrap(['--show']);
  expect(shown.selected.where((v) => v.id == scopedId), isEmpty);
}

Future<void> _staleSupportKeepsTheRule(
  BasisWalk w,
  ProjectShape shape,
  String globalId,
) async {
  File('${w.process.root.path}/${shape.source}').writeAsStringSync('v2\n');
  final shown = await w.bootstrap(['--show']);
  expect(shown.sourceStatus.single.status, BasisSourceState.stale);
  expect(shown.selected.map((v) => v.id), contains(globalId));
  expect(w.document.revision, 3);
}
