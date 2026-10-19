import 'recognition_contribution.dart';
import 'recognition_enums.dart';
import 'recognition_findings.dart';
import 'recognition_omissions.dart';
import 'recognition_proposal.dart';
import 'recognition_relations.dart';
import 'recognition_report.dart';
import 'recognition_topology.dart';
import 'recognition_validation.dart';
import 'repository_context.dart';
import 'report_admission.dart';
import 'report_budget.dart';

const recordProjectIdentity = ProposedAction(
  code: 'record_project_identity',
  description: 'Registra la identidad del proyecto reconocido.',
);

const enableStackPlugin = ProposedAction(
  code: 'enable_stack_plugin',
  description: 'Habilita el plugin del stack reconocido.',
);

/// Reúne las contribuciones en un reporte ordenado y decide su estado.
///
/// Un ID repetido o una referencia a evidencia inexistente es un defecto del
/// plugin que contribuyó, no un resultado: se rechaza con [ArgumentError].
/// Si el conjunto, con las acciones de su propuesta, no cabe en [limits],
/// lanza [ReportLimitExceeded].
RecognitionReport assembleRecognition({
  required String requestedRoot,
  required String resolvedRoot,
  required RepositoryContext repository,
  required List<RecognitionContribution> contributions,
  ReportLimits limits = const ReportLimits(),
}) {
  final merged = _merge(contributions);
  validateContribution(merged);
  final status = _statusOf(merged);
  final proposal = _proposalFor(status, merged.candidates);
  admitAssembled(merged, proposal, limits);
  return RecognitionReport(
    status: status,
    requestedRoot: requestedRoot,
    resolvedRoot: resolvedRoot,
    repository: repository,
    candidates: merged.candidates,
    units: merged.units,
    evidence: merged.evidence,
    conflicts: merged.conflicts,
    limitations: merged.limitations,
    relations: merged.relations,
    contextSources: merged.contextSources,
    omissions: merged.omissions,
    proposal: proposal,
    effects: RecognitionEffects.none,
  );
}

/// Todas las contribuciones en una, con cada colección en su orden estable.
RecognitionContribution _merge(List<RecognitionContribution> contributions) {
  List<T> all<T>(List<T> Function(RecognitionContribution) of) => [
    for (final contribution in contributions) ...of(contribution),
  ];
  return RecognitionContribution(
    candidates: all((c) => c.candidates).map(_sortedCandidate).toList()
      ..sort((a, b) => a.id.compareTo(b.id)),
    units: all((c) => c.units).map(_sortedUnit).toList()
      ..sort((a, b) => _compare([a.path, a.id], [b.path, b.id])),
    evidence: all((c) => c.evidence)..sort((a, b) => a.id.compareTo(b.id)),
    conflicts: all((c) => c.conflicts).map(_sortedConflict).toList()
      ..sort((a, b) => _compare(_conflictKey(a), _conflictKey(b))),
    limitations: all((c) => c.limitations)
      ..sort((a, b) => _compare(_limitationKey(a), _limitationKey(b))),
    relations: all((c) => c.relations).map(_sortedRelation).toList()
      ..sort((a, b) => _compare(_relationKey(a), _relationKey(b))),
    contextSources: all((c) => c.contextSources)
      ..sort((a, b) => _compare([a.scopePath, a.path], [b.scopePath, b.path])),
    omissions: all((c) => c.omissions).map(_sortedOmission).toList()
      ..sort(
        (a, b) => _compare(
          [a.path, a.rule.toWireName()],
          [b.path, b.rule.toWireName()],
        ),
      ),
  );
}

List<String> _relationKey(RecognitionRelation r) => [
  r.fromPath,
  r.kind.toWireName(),
  r.targetPath ?? '',
  r.declaredName ?? '',
  r.evidenceIds.join(','),
  r.id,
];

List<String> _conflictKey(RecognitionConflict c) => [
  c.code,
  c.message,
  c.evidenceIds.join(','),
];

List<String> _limitationKey(RecognitionLimitation l) => [
  l.code,
  l.path ?? '',
  l.message,
  '${l.blocking}',
];

int _compare(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}

List<String> _sortedIds(List<String> ids) => [...ids]..sort();

StackCandidate _sortedCandidate(StackCandidate c) => StackCandidate(
  id: c.id,
  displayName: c.displayName,
  pluginId: c.pluginId,
  evidenceIds: _sortedIds(c.evidenceIds),
);

ProjectUnit _sortedUnit(ProjectUnit u) => ProjectUnit(
  id: u.id,
  name: u.name,
  kind: u.kind,
  path: u.path,
  evidenceIds: _sortedIds(u.evidenceIds),
);

RecognitionRelation _sortedRelation(RecognitionRelation r) =>
    RecognitionRelation(
      id: r.id,
      kind: r.kind,
      fromPath: r.fromPath,
      declaredName: r.declaredName,
      targetPath: r.targetPath,
      targetUnitId: r.targetUnitId,
      status: r.status,
      evidenceIds: _sortedIds(r.evidenceIds),
    );

RecognitionOmission _sortedOmission(RecognitionOmission o) =>
    RecognitionOmission(
      path: o.path,
      rule: o.rule,
      evidenceIds: _sortedIds(o.evidenceIds),
    );

RecognitionConflict _sortedConflict(RecognitionConflict c) =>
    RecognitionConflict(
      code: c.code,
      message: c.message,
      evidenceIds: _sortedIds(c.evidenceIds),
    );

RecognitionStatus _statusOf(RecognitionContribution merged) {
  final blocked = merged.limitations.any((l) => l.blocking);
  if (merged.candidates.isEmpty && !blocked) {
    return RecognitionStatus.unsupported;
  }
  if (merged.candidates.length == 1 &&
      merged.units.isNotEmpty &&
      merged.conflicts.isEmpty &&
      !blocked) {
    return RecognitionStatus.recognized;
  }
  return RecognitionStatus.ambiguous;
}

/// Sólo un reconocimiento inequívoco propone algo.
RecognitionProposal _proposalFor(
  RecognitionStatus status,
  List<StackCandidate> candidates,
) => status == RecognitionStatus.recognized
    ? RecognitionProposal(
        eligible: true,
        pluginIds: [candidates.single.pluginId],
        actions: const [recordProjectIdentity, enableStackPlugin],
      )
    : RecognitionProposal(
        eligible: false,
        pluginIds: const [],
        actions: const [],
      );
