import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recognition_fixtures.dart';

void main() {
  test('mutar las listas originales no cambia el objeto', () {
    final originals = _Originals();
    final built = _builtFrom(originals);
    final before = [for (final value in built) jsonEncode(value)];
    for (final list in originals.all) {
      list.clear();
    }
    expect([for (final value in built) jsonEncode(value)], before);
  });

  test('las listas expuestas no se pueden modificar', () {
    final exposed = <List<Object>>[
      candidate.evidenceIds,
      unit.evidenceIds,
      conflict.evidenceIds,
      proposal.pluginIds,
      proposal.actions,
      contribution.candidates,
      contribution.units,
      contribution.evidence,
      contribution.conflicts,
      contribution.limitations,
      report.candidates,
      report.units,
      report.evidence,
      report.conflicts,
      report.limitations,
    ];
    for (final list in exposed) {
      expect(list.clear, throwsUnsupportedError);
    }
  });

  test('sólo un reporte invalidRoot carece de raíz resuelta', () {
    expect(
      () => _reportWith(RecognitionStatus.unsupported, null),
      throwsArgumentError,
    );
    expect(
      () => _reportWith(RecognitionStatus.invalidRoot, '/a'),
      throwsArgumentError,
    );
    final invalid = RecognitionReport.invalidRoot(
      requestedRoot: '/a',
      reason: limitation,
    );
    expect(invalid.status, RecognitionStatus.invalidRoot);
    expect(invalid.resolvedRoot, isNull);
    expect(invalid.limitations.single.blocking, isTrue);
    expect(invalid.proposal.eligible, isFalse);
    expect(invalid.effects.toJson(), RecognitionEffects.none.toJson());
  });
}

/// Las listas con que se construye cada valor, para mutarlas después.
final class _Originals {
  final ids = ['e0001'];
  final candidates = [candidate];
  final units = [unit];
  final found = [evidence];
  final conflicts = [conflict];
  final limitations = [limitation];
  final plugins = ['plugin-a'];
  final actions = [action];

  List<List<Object>> get all => [
    ids,
    candidates,
    units,
    found,
    conflicts,
    limitations,
    plugins,
    actions,
  ];
}

List<Object> _builtFrom(_Originals o) => [
  StackCandidate(id: 'c', displayName: 'C', pluginId: 'p', evidenceIds: o.ids),
  ProjectUnit(id: 'u', name: 'u', kind: 'k', path: 'p', evidenceIds: o.ids),
  RecognitionConflict(code: 'c', message: 'm', evidenceIds: o.ids),
  RecognitionProposal(eligible: true, pluginIds: o.plugins, actions: o.actions),
  RecognitionContribution(
    candidates: o.candidates,
    units: o.units,
    evidence: o.found,
    conflicts: o.conflicts,
    limitations: o.limitations,
  ),
  _reportFrom(o),
];

RecognitionReport _reportFrom(_Originals o) => RecognitionReport(
  status: RecognitionStatus.ambiguous,
  requestedRoot: '/a',
  resolvedRoot: '/a',
  repository: repository,
  candidates: o.candidates,
  units: o.units,
  evidence: o.found,
  conflicts: o.conflicts,
  limitations: o.limitations,
  proposal: proposal,
  effects: RecognitionEffects.none,
);

RecognitionReport _reportWith(RecognitionStatus status, String? resolved) =>
    RecognitionReport(
      status: status,
      requestedRoot: '/a',
      resolvedRoot: resolved,
      repository: repository,
      candidates: const [],
      units: const [],
      evidence: const [],
      conflicts: const [],
      limitations: const [],
      proposal: proposal,
      effects: RecognitionEffects.none,
    );
