import 'recognition_contribution.dart';
import 'recognition_proposal.dart';
import 'report_budget.dart';

/// Vuelve a contar, con un contador propio, todo lo que el reporte retendrá
/// de [merged] y [proposal], y lanza [ReportLimitExceeded] si no cabe en
/// [limits]. Es una validación del conjunto ya finito, con las mismas reglas
/// que el productor: una fila por elemento, una posición por referencia y
/// los bytes UTF-8 de cada texto retenido.
void admitAssembled(
  RecognitionContribution merged,
  RecognitionProposal proposal,
  ReportLimits limits,
) {
  final count = _Recount(limits);
  for (final e in merged.evidence) {
    count.row([e.id, e.kind, e.path, e.value, e.fingerprint]);
  }
  for (final c in merged.candidates) {
    count.row([c.id, c.displayName, c.pluginId], references: c.evidenceIds);
  }
  for (final u in merged.units) {
    count.row([u.id, u.name, u.kind, u.path], references: u.evidenceIds);
  }
  for (final c in merged.conflicts) {
    count.row([c.code, c.message], references: c.evidenceIds);
  }
  for (final l in merged.limitations) {
    count.row([l.code, l.message, ?l.path]);
  }
  for (final a in proposal.actions) {
    count.row([a.code, a.description]);
  }
  count.text(proposal.pluginIds);
}

final class _Recount {
  _Recount(this.limits);

  final ReportLimits limits;
  var _used = const DerivedUsage();

  /// Una fila y, después, una posición por cada referencia con su ID.
  void row(List<String> texts, {List<String> references = const []}) {
    _charge(1, texts);
    for (final id in references) {
      _charge(1, [id]);
    }
  }

  void text(List<String> texts) => _charge(0, texts);

  void _charge(int items, List<String> texts) => _used = admitDerivedUsage(
    _used,
    limits,
    items: items,
    textBytes: texts.fold(0, (sum, t) => sum + utf8Length(t)),
  );
}
