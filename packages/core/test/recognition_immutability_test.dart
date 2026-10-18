import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recognition_fixtures.dart';

void main() {
  test('mutar las listas originales no cambia el objeto', () {
    final ids = ['e0001'];
    final candidates = [candidate];
    final units = [unit];
    final found = [evidence];
    final conflicts = [conflict];
    final limitations = [limitation];
    final plugins = ['plugin-a'];
    final actions = [action];
    final built = [
      StackCandidate(
        id: 'c',
        displayName: 'C',
        pluginId: 'p',
        evidenceIds: ids,
      ),
      ProjectUnit(id: 'u', name: 'u', kind: 'k', path: 'p', evidenceIds: ids),
      RecognitionConflict(code: 'c', message: 'm', evidenceIds: ids),
      RecognitionProposal(eligible: true, pluginIds: plugins, actions: actions),
      RecognitionContribution(
        candidates: candidates,
        units: units,
        evidence: found,
        conflicts: conflicts,
        limitations: limitations,
      ),
      RecognitionReport(
        status: RecognitionStatus.ambiguous,
        requestedRoot: '/a',
        resolvedRoot: '/a',
        repository: repository,
        candidates: candidates,
        units: units,
        evidence: found,
        conflicts: conflicts,
        limitations: limitations,
        proposal: proposal,
        effects: RecognitionEffects.none,
      ),
    ];
    final before = [for (final value in built) jsonEncode(value)];
    for (final list in <List<Object>>[
      ids,
      candidates,
      units,
      found,
      conflicts,
      limitations,
      plugins,
      actions,
    ]) {
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
    RecognitionReport build(RecognitionStatus status, String? resolved) =>
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
    expect(
      () => build(RecognitionStatus.unsupported, null),
      throwsArgumentError,
    );
    expect(
      () => build(RecognitionStatus.invalidRoot, '/a'),
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
