import 'package:core/core.dart';

import '../terminal_text.dart';
import 'assessment_human_snapshot.dart';
import 'assessment_human_text.dart';

/// [value] en una línea segura para la terminal: nada del proyecto se
/// interpreta como control, escape ni salto.
String safe(String value) => singleLine(value, maxRunes: 160);

/// La vista humana de [result]: primero el estado, después lo observado,
/// la cobertura, la vigencia, los efectos y la siguiente acción. Resume el
/// mismo resultado del JSON; no deduce verde del código de salida.
String humanAssessment(AssessmentResult result, {required String root}) {
  final snapshot = result.snapshot;
  final lines = [
    headlineOf(result),
    '  Raíz: ${safe(root)}',
    if (snapshot != null) ...snapshotLines(snapshot),
    if (snapshot != null) _freshnessLine(result),
    if (result.comparison case final c?) _comparisonLine(c),
    ..._diagnosticLines(result.diagnostics),
    ..._effectLines(result),
    ..._actionLines(result.nextActions),
    if (snapshot != null)
      'Detalle completo guardado: shipflow assess --show --json',
  ];
  return '${lines.join('\n')}\n';
}

/// El estado en una frase: guardado, sin cambios, parcial, obsoleto, no
/// comprobado, histórico o lo que impidió seguir.
String headlineOf(AssessmentResult r) => switch (r.outcome) {
  AssessmentOutcome.saved =>
    r.coverage == AssessmentCoverage.complete
        ? 'Levantamiento guardado'
        : 'Levantamiento parcial guardado',
  AssessmentOutcome.unchanged =>
    r.operation == AssessmentOperation.recover
        ? 'Nada que recuperar'
        : 'Sin cambios: el levantamiento guardado sigue siendo el mismo',
  AssessmentOutcome.recovered =>
    r.diagnostics.any((d) => d.code == 'recovery_aborted')
        ? 'Recuperación abortada: se conservó lo anterior'
        : 'Publicación recuperada',
  AssessmentOutcome.shown => _shownHeadline(r),
  _ => switch (r.operation) {
    AssessmentOperation.observe => 'No se guardó un levantamiento',
    AssessmentOperation.show => 'No se pudo consultar el levantamiento',
    AssessmentOperation.recover => 'No se recuperó la publicación',
  },
};

String _shownHeadline(AssessmentResult r) => switch (r.freshness) {
  AssessmentFreshness.stale => 'Necesita actualizarse',
  AssessmentFreshness.unverified => 'No se pudo comprobar su vigencia',
  AssessmentFreshness.historical =>
    r.coverage == AssessmentCoverage.complete
        ? 'Levantamiento anterior (histórico)'
        : 'Levantamiento anterior parcial (histórico)',
  _ =>
    r.coverage == AssessmentCoverage.complete
        ? 'Levantamiento vigente'
        : 'Levantamiento parcial vigente',
};

String _freshnessLine(AssessmentResult r) => switch (r.freshness) {
  AssessmentFreshness.current =>
    'Vigencia: corresponde a sus insumos de ahora, comprobados por sus '
        'bytes; no es una instantánea atómica del sistema de archivos.',
  AssessmentFreshness.stale =>
    'Vigencia: necesita actualizarse; se muestra como estaba.',
  AssessmentFreshness.unverified =>
    'Vigencia: no se pudo comprobar; no se afirma que siga vigente.',
  AssessmentFreshness.historical =>
    'Vigencia: histórica, no se certifica vigente aunque coincida.',
  AssessmentFreshness.notApplicable => 'Vigencia: no se comprobó.',
};

String _comparisonLine(AssessmentComparison c) =>
    'Respecto de la anterior: ${c.addedReferences} referencias nuevas, '
    '${c.repeatedReferences} repetidas y ${c.notObservedNow} no observadas '
    'ahora (no prueba que ya no existan ni retira nada).';

List<String> _diagnosticLines(List<AssessmentDiagnostic> diagnostics) => [
  for (final d in diagnostics)
    '- ${assessmentMessages[d.code] ?? safe(d.code)}'
        '${d.examples.isEmpty ? '' : ' (${d.examples.map(safe).join(', ')})'}',
];

List<String> _effectLines(AssessmentResult r) {
  final e = r.effects;
  final written = [
    for (final p in e.created) 'se creó ${safe(p)}',
    for (final p in e.replaced) 'se reemplazó ${safe(p)}',
    for (final p in e.removed) 'se retiró ${safe(p)}',
  ];
  return [
    written.isEmpty
        ? 'Efectos: no se escribió nada.'
        : 'Efectos: ${written.join('; ')}. Shipflow no ejecutó git add, '
              'commit ni push.',
    if (r.retiredRevision case final retired?)
      'Revisión que dejó de conservarse: $retired.',
  ];
}

List<String> _actionLines(List<AssessmentNextAction> actions) => [
  if (actions.isNotEmpty) 'Siguiente:',
  for (final a in actions)
    '  ${a.argv.map(safe).join(' ')} — '
        '${assessmentPurposes[a.purpose] ?? safe(a.purpose)}',
];
