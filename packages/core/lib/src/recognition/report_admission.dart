import 'recognition_contribution.dart';
import 'recognition_proposal.dart';
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
    yield (1, [e.id, e.kind, e.path, e.value, e.fingerprint]);
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
  for (final a in proposal.actions) {
    yield (1, [a.code, a.description]);
  }
  yield (0, proposal.pluginIds);
}

/// Una posición por referencia, con los bytes de su ID.
Iterable<(int, List<String>)> _references(List<String> ids) sync* {
  for (final id in ids) {
    yield (1, [id]);
  }
}
