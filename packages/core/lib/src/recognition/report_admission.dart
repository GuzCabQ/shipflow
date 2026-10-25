import 'recognition_context.dart';
import 'recognition_contribution.dart';
import 'recognition_evidence.dart';
import 'recognition_proposal.dart';
import 'recognition_relations.dart';
import 'recognition_report.dart';
import 'report_budget.dart';

/// Vuelve a contar, desde cero, todo lo que el reporte retendrá de [merged]
/// y [proposal], y lanza [ReportLimitExceeded] si no cabe en [limits]. Es una
/// validación del conjunto ya finito, con las mismas reglas que el
/// productor: una fila por elemento, una posición por referencia y los bytes
/// UTF-8 de cada texto retenido.
void admitAssembled(
  RecognitionContribution merged,
  RecognitionProposal proposal,
  ReportLimits limits,
) {
  var used = const DerivedUsage();
  for (final (items, texts) in _rows(merged, proposal)) {
    used = admitDerivedUsage(
      used,
      limits,
      items: items,
      textBytes: texts.fold(0, (sum, text) => sum + utf8Length(text)),
    );
  }
}

/// Cada cobro como elementos y textos, en el orden del reporte.
Iterable<(int, List<String>)> _rows(
  RecognitionContribution merged,
  RecognitionProposal proposal,
) sync* {
  for (final e in merged.evidence) {
    yield (1, [e.id, ...evidenceTexts(e)]);
  }
  for (final c in merged.candidates) {
    yield (1, [c.id, c.displayName, c.pluginId]);
    yield* _references(c.evidenceIds);
  }
  for (final u in merged.units) {
    yield (1, [u.id, u.name, u.kind, u.path]);
    yield* _references(u.evidenceIds);
  }
  for (final c in merged.conflicts) {
    yield (1, [c.code, c.message]);
    yield* _references(c.evidenceIds);
  }
  for (final l in merged.limitations) {
    yield (1, [l.code, l.message, ?l.path]);
  }
  yield* _scopedRows(merged);
  for (final a in proposal.actions) {
    yield (1, [a.code, a.description]);
  }
  yield (0, proposal.pluginIds);
  yield (0, const [declaredProjectRecognition]);
}

/// Relaciones, fuentes candidatas y omisiones, cada una con sus referencias.
Iterable<(int, List<String>)> _scopedRows(
  RecognitionContribution merged,
) sync* {
  for (final r in merged.relations) {
    yield (1, relationTexts(r));
    yield* _references(r.evidenceIds);
  }
  for (final s in merged.contextSources) {
    yield (1, contextSourceTexts(s));
  }
  for (final o in merged.omissions) {
    yield (1, [o.path, o.rule.toWireName()]);
    yield* _references(o.evidenceIds);
  }
}

/// Los textos que retiene una evidencia, salvo su ID, que se asigna aparte.
List<String> evidenceTexts(RecognitionEvidence e) => [
  e.kind,
  e.role.toWireName(),
  e.label,
  e.path,
  e.value,
  e.fingerprint,
];

/// Los textos de la fila de una relación, sin sus referencias.
List<String> relationTexts(RecognitionRelation r) => [
  r.id,
  r.kind.toWireName(),
  r.fromPath,
  ?r.declaredName,
  ?r.targetPath,
  ?r.targetUnitId,
  r.status.toWireName(),
];

/// Los textos de la fila de una fuente candidata.
List<String> contextSourceTexts(ContextSource s) => [
  s.scopePath,
  s.path,
  s.kind.toWireName(),
  s.entityType.toWireName(),
  s.reason.toWireName(),
  s.contentStatus,
];

/// Una posición por referencia, con los bytes de su ID.
Iterable<(int, List<String>)> _references(List<String> ids) sync* {
  for (final id in ids) {
    yield (1, [id]);
  }
}
