import '../recognition/recognition_context.dart';
import '../recognition/recognition_contribution.dart';
import '../recognition/recognition_enums.dart';
import '../recognition/recognition_evidence.dart';
import '../recognition/recognition_findings.dart';
import '../recognition/recognition_json.dart';
import '../recognition/recognition_omissions.dart';
import '../recognition/recognition_proposal.dart';
import '../recognition/recognition_relations.dart';
import '../recognition/recognition_report.dart';
import '../recognition/recognition_topology.dart';
import '../recognition/recognition_validation.dart';
import '../recognition/report_admission.dart';
import '../recognition/report_budget.dart';
import 'context_validation.dart';

/// Lo que un contexto guardado conserva de un reconocimiento: sus hechos
/// tipados, sin raíces absolutas, repositorio, propuesta ni efectos, que
/// son datos de una ejecución o autoridad que no se importa.
///
/// Sólo un reconocimiento completo y sin bloqueos, con una unidad, un
/// candidato y exactamente la omisión del estado propio, cabe aquí.
final class PortableRecognition {
  PortableRecognition({
    required List<StackCandidate> candidates,
    required List<ProjectUnit> units,
    required List<RecognitionEvidence> evidence,
    required List<RecognitionConflict> conflicts,
    required List<RecognitionLimitation> limitations,
    required List<RecognitionRelation> relations,
    required List<ContextSource> contextSources,
    required List<RecognitionOmission> omissions,
  }) : candidates = List.unmodifiable(candidates),
       units = List.unmodifiable(units),
       evidence = List.unmodifiable(evidence),
       conflicts = List.unmodifiable(conflicts),
       limitations = List.unmodifiable(limitations),
       relations = List.unmodifiable(relations),
       contextSources = List.unmodifiable(contextSources),
       omissions = List.unmodifiable(omissions) {
    _validate(this);
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory PortableRecognition.fromJson(Map<String, Object?> json) {
    requireSemantic(json['status'] == 'recognized', 'not_eligible');
    requireSemantic(
      json['recognitionScope'] == declaredProjectRecognition,
      'scope',
    );
    return PortableRecognition(
      candidates: readObjects(json['candidates'], StackCandidate.fromJson),
      units: readObjects(json['units'], ProjectUnit.fromJson),
      evidence: readObjects(json['evidence'], RecognitionEvidence.fromJson),
      conflicts: readObjects(json['conflicts'], RecognitionConflict.fromJson),
      limitations: readObjects(
        json['limitations'],
        RecognitionLimitation.fromJson,
      ),
      relations: readObjects(json['relations'], RecognitionRelation.fromJson),
      contextSources: readObjects(
        json['contextSources'],
        ContextSource.fromJson,
      ),
      omissions: readObjects(json['omissions'], RecognitionOmission.fromJson),
    );
  }

  final List<StackCandidate> candidates;
  final List<ProjectUnit> units;
  final List<RecognitionEvidence> evidence;
  final List<RecognitionConflict> conflicts;
  final List<RecognitionLimitation> limitations;
  final List<RecognitionRelation> relations;
  final List<ContextSource> contextSources;
  final List<RecognitionOmission> omissions;

  /// Siempre reconocido: nada más se guarda.
  final RecognitionStatus status = RecognitionStatus.recognized;
  final String recognitionScope = declaredProjectRecognition;

  Map<String, Object?> toJson() => {
    'status': status.toWireName(),
    'recognitionScope': recognitionScope,
    'candidates': [for (final c in candidates) c.toJson()],
    'units': [for (final u in units) u.toJson()],
    'evidence': [for (final e in evidence) e.toJson()],
    'conflicts': [for (final c in conflicts) c.toJson()],
    'limitations': [for (final l in limitations) l.toJson()],
    'relations': [for (final r in relations) r.toJson()],
    'contextSources': [for (final s in contextSources) s.toJson()],
    'omissions': [for (final o in omissions) o.toJson()],
  };

  RecognitionContribution _asContribution() => RecognitionContribution(
    candidates: candidates,
    units: units,
    evidence: evidence,
    conflicts: conflicts,
    limitations: limitations,
    relations: relations,
    contextSources: contextSources,
    omissions: omissions,
  );
}

/// La proyección portable de [report], si es elegible. La elegibilidad sale
/// del reconocimiento actual: nunca se importa de un documento.
PortableRecognition projectRecognition(RecognitionReport report) {
  requireSemantic(
    report.status == RecognitionStatus.recognized && report.proposal.eligible,
    'not_eligible',
  );
  return PortableRecognition(
    candidates: report.candidates,
    units: report.units,
    evidence: report.evidence,
    conflicts: report.conflicts,
    limitations: report.limitations,
    relations: report.relations,
    contextSources: report.contextSources,
    omissions: report.omissions,
  );
}

/// Recuenta [recognition] con las reglas del reporte derivado y lanza
/// [ReportLimitExceeded] si no cabe en [limits].
void admitPortable(PortableRecognition recognition, ReportLimits limits) =>
    admitAssembled(
      recognition._asContribution(),
      RecognitionProposal(
        eligible: true,
        pluginIds: const [],
        actions: const [],
      ),
      limits,
    );

void _validate(PortableRecognition r) {
  requireSemantic(_texts(r).every(isWellFormedText), 'invalid_text');
  _contribution(r);
  _targets(r);
  requireSemantic(
    r.candidates.isNotEmpty && r.units.isNotEmpty,
    'empty_recognition',
  );
  requireSemantic(
    r.conflicts.isEmpty && r.limitations.every((l) => !l.blocking),
    'not_eligible',
  );
  requireSemantic(
    r.omissions.where((o) => o.rule == OmissionRule.toolState).length == 1,
    'tool_state_omission',
  );
  try {
    admitPortable(r, const ReportLimits.extended());
  } on ReportLimitExceeded {
    requireSemantic(false, 'budget_exceeded');
  }
}

/// Las reglas compartidas con una contribución: IDs únicos, referencias y
/// relaciones sin resolver con diagnóstico.
void _contribution(PortableRecognition r) {
  try {
    validateContribution(r._asContribution());
  } on ArgumentError catch (e) {
    requireSemantic(false, switch (e.name) {
      'id' => 'duplicate_id',
      'relations' => 'undiagnosed_relation',
      _ => 'missing_reference',
    });
  }
}

/// Una relación corroborada nombra la ruta de la unidad que cita.
void _targets(PortableRecognition r) {
  final paths = {for (final u in r.units) u.id: u.path};
  for (final relation in r.relations) {
    if (relation.status != RelationStatus.corroborated) continue;
    requireSemantic(
      paths[relation.targetUnitId] == relation.targetPath,
      'relation_target',
      '/relations/${relation.id}',
    );
  }
}

Iterable<String> _texts(PortableRecognition r) => [
  for (final c in r.candidates) ...[c.id, c.displayName, c.pluginId],
  for (final u in r.units) ...[u.id, u.name, u.kind, u.path],
  for (final e in r.evidence) ...[e.id, ...evidenceTexts(e)],
  for (final c in r.conflicts) ...[c.code, c.message],
  for (final l in r.limitations) ...[l.code, l.message, ?l.path],
  for (final rel in r.relations) ...relationTexts(rel),
  for (final s in r.contextSources) ...[s.scopePath, s.path],
];
