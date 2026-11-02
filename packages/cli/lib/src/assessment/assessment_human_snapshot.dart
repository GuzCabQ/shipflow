import 'package:core/core.dart';

import 'assessment_human.dart';
import 'assessment_human_text.dart';

const _maxRelations = 20;
const _maxExamples = 5;

/// Lo observado: unidades, conexiones comprobadas con un ejemplo
/// localizable, dependencias sólo declaradas aparte, referencias externas y
/// sin resolver, pruebas presentes, fuentes candidatas y cobertura.
List<String> snapshotLines(AssessmentSnapshot s) {
  final labels = {for (final u in s.units) u.id: u.label};
  final between = [
    for (final c in projectAssessment(s))
      if (c.sourceUnitId != c.targetUnitId) c,
  ];
  return [
    'Unidades (${s.units.length}): ${_list([for (final u in s.units) '${safe(u.label)} (${safe(u.path)})'], _maxRelations)}',
    ..._connectionLines(s, between, labels),
    ..._declaredLines(s, between, labels),
    _referenceLine(s),
    'Pruebas presentes: ${counted(_tests(s), 'archivo', 'archivos')}, '
        'reconocidos por su ruta; no se ejecutaron.',
    ..._candidateLines(s),
    ..._coverageLines(s),
  ];
}

List<String> _connectionLines(
  AssessmentSnapshot s,
  List<AssessmentConnection> between,
  Map<String, String> labels,
) {
  if (between.isEmpty) {
    return [
      'Conexiones comprobadas entre unidades: ninguna en lo inspeccionado; '
          'no prueba que no existan fuera de ese universo.',
    ];
  }
  final claims = {for (final c in s.claims) c.id: c};
  final files = {for (final f in s.files) f.id: f.path};
  return [
    'Conexiones comprobadas entre unidades (${between.length}):',
    for (final c in between.take(_maxRelations)) ...[
      '  ${safe(labels[c.sourceUnitId]!)} → ${safe(labels[c.targetUnitId]!)}'
          ': ${counted(c.claimIds.length, 'referencia', 'referencias')}'
          '${_condition(c.condition)}',
      '    p. ej. ${_evidence(claims[c.claimIds.first]!, files)}',
    ],
    if (between.length > _maxRelations)
      '  … y ${between.length - _maxRelations} más.',
  ];
}

String _evidence(AssessmentClaim claim, Map<String, String> files) =>
    '${safe(files[claim.sourceFileId]!)}:${claim.evidence.line}:'
    '${claim.evidence.column} → ${safe(claim.targetLabel ?? '')}';

/// Una dependencia declarada nunca aparece como conexión comprobada: se
/// dice aparte si hay referencias comprobadas hacia su unidad.
List<String> _declaredLines(
  AssessmentSnapshot s,
  List<AssessmentConnection> between,
  Map<String, String> labels,
) {
  final declared = [
    for (final l in s.contextLinks)
      if (l.kind == AssessmentLinkKind.declaredDependency) l,
  ];
  if (declared.isEmpty) return const [];
  final reached = {for (final c in between) c.targetUnitId};
  return [
    'Dependencias declaradas (la declaración no prueba uso):',
    for (final l in declared.take(_maxRelations))
      '  ${safe(l.label)} (declarada en ${safe(l.sourcePath)}) — '
          '${reached.contains(l.targetUnitId) ? 'con referencias comprobadas hacia esa unidad' : 'sin referencias comprobadas hacia esa unidad en lo inspeccionado'}',
  ];
}

String _referenceLine(AssessmentSnapshot s) {
  int count(AssessmentResolution r) =>
      s.claims.where((c) => c.resolution == r).length;
  final total = s.claims.isEmpty ? 'ninguna' : '${s.claims.length}';
  return 'Referencias: $total en total; '
      '${count(AssessmentResolution.external)} externas, sin comprobar que '
      'existan; ${count(AssessmentResolution.unresolved)} sin resolver.';
}

int _tests(AssessmentSnapshot s) =>
    s.files.where((f) => f.role == AssessmentFileRole.test).length;

List<String> _candidateLines(AssessmentSnapshot s) {
  final candidates = [
    for (final l in s.contextLinks)
      if (l.kind == AssessmentLinkKind.candidateSource) safe(l.sourcePath),
  ];
  return [
    if (candidates.isNotEmpty)
      'Fuentes de contexto candidatas, sin abrir (${candidates.length}): '
          '${_list(candidates, _maxExamples)}',
  ];
}

List<String> _coverageLines(AssessmentSnapshot s) {
  final parsed = s.files
      .where((f) => f.parseState == AssessmentParseState.parsed)
      .length;
  return [
    s.coverage == AssessmentCoverage.complete
        ? 'Cobertura: completa en su universo (${s.files.length} archivos); '
              'no significa que se comprenda todo el proyecto.'
        : 'Cobertura: ${s.coverage == AssessmentCoverage.failed ? 'fallida' : 'parcial'}'
              ' — se analizaron $parsed de ${s.files.length} archivos.',
    for (final d in s.diagnostics)
      '  - ${assessmentGaps[d.code] ?? safe(d.code)}: ${d.count}'
          '${d.examples.isEmpty ? '' : ' (p. ej. ${d.examples.map(safe).join(', ')})'}',
  ];
}

/// [count] con su sustantivo: ningún, uno o varios.
String counted(int count, String singular, String plural) => switch (count) {
  0 => 'ningún $singular',
  1 => '1 $singular',
  _ => '$count $plural',
};

/// Cuándo aplican las referencias de una conexión, en palabras.
String _condition(AssessmentCondition condition) => switch (condition) {
  AssessmentCondition.always => '',
  AssessmentCondition.conditional => ', condicionales',
  AssessmentCondition.fallback => ', base de alternativas condicionales',
  AssessmentCondition.unknown => ', con una condición no representable',
};

String _list(List<String> items, int max) => [
  ...items.take(max),
  if (items.length > max) 'y ${items.length - max} más',
].join(', ');
