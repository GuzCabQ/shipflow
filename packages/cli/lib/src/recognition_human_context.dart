import 'package:core/core.dart';

import 'recognition_human_support.dart';

const _maxUnits = 20;
const _maxRelations = 20;
const _maxDeclarations = 20;
const _maxSources = 20;
const _maxOmittedPaths = 5;

/// Los bloques de la ficha antes del resultado: identidad, unidades y
/// relaciones, entorno declarado, fuentes candidatas y cobertura. Sólo
/// proyecta valores de core: agrupa evidencias por rol y no interpreta
/// tipos tecnológicos.
List<String> scopedBlocks(RecognitionReport report) {
  final declarations = [
    for (final e in report.evidence)
      if (e.role == EvidenceRole.description) e,
    for (final e in report.evidence)
      if (_declaresSetting(e.role)) e,
  ];
  final visible = declarations.take(_maxDeclarations).toList();
  return [
    '',
    'Identidad',
    ..._identity(report, visible),
    '',
    'Unidades y relaciones',
    ..._units(report),
    ..._relations(report),
    '',
    'Entorno declarado',
    ..._settings(report, visible, declarations.length - visible.length),
    '',
    ..._sources(report),
    '',
    'Cobertura',
    ..._coverage(report),
  ];
}

List<String> _identity(
  RecognitionReport report,
  List<RecognitionEvidence> visible,
) {
  final owners = {
    for (final u in report.units)
      for (final id in u.evidenceIds) id: u.name,
  };
  final technology = report.candidates.isEmpty
      ? 'no identificada'
      : report.candidates.map((c) => shown(c.displayName)).join(', ');
  return [
    '  Tecnología: $technology',
    for (final e in visible)
      if (e.role == EvidenceRole.description)
        '  ${owners[e.id] == null ? 'Se' : '${shown(owners[e.id]!)} se'} '
            'describe como «${shown(e.value)}» · ${shown(e.path)}',
  ];
}

/// El rol de las declaraciones de entorno: el que no es identidad,
/// descripción, relación ni recurso. Nombrarlo por exclusión mantiene fuera
/// de lib/ la palabra con que se lee el entorno del proceso, que sólo el
/// composition root puede tocar.
bool _declaresSetting(EvidenceRole role) => switch (role) {
  EvidenceRole.identity ||
  EvidenceRole.description ||
  EvidenceRole.relation ||
  EvidenceRole.resource => false,
  _ => true,
};

List<String> _units(RecognitionReport report) => [
  '  Paquetes observados: ${report.units.length}',
  for (final u in report.units.take(_maxUnits))
    '    ${shown(u.name)} · ${shown(u.path)}',
  ?more(report.units.length - _maxUnits, 'paquete', 'paquetes', '    '),
];

List<String> _relations(RecognitionReport report) {
  if (report.relations.isEmpty) {
    return const ['  Relaciones declaradas: ninguna'];
  }
  return [
    '  Relaciones declaradas: ${report.relations.length}',
    for (final r in report.relations.take(_maxRelations)) '    ${_relation(r)}',
    ?more(
      report.relations.length - _maxRelations,
      'relación',
      'relaciones',
      '    ',
    ),
  ];
}

String _relation(RecognitionRelation r) {
  final kind = switch (r.kind) {
    RelationKind.localDependency when r.declaredName != null =>
      'dependencia local «${shown(r.declaredName!)}»',
    RelationKind.localDependency => 'dependencia local',
    RelationKind.workspaceMember => 'miembro del workspace',
  };
  final status = r.status == RelationStatus.corroborated
      ? 'corroborada'
      : 'sin resolver';
  final target = r.targetPath == null
      ? 'destino no establecido'
      : shown(r.targetPath!);
  return '${shown(r.fromPath)} → $target · $kind · $status';
}

/// Lo que el proyecto declara, nunca lo que está instalado.
List<String> _settings(
  RecognitionReport report,
  List<RecognitionEvidence> visible,
  int hidden,
) {
  final settings = [
    for (final e in visible)
      if (_declaresSetting(e.role))
        '  ${shown(e.label)}: ${shown(e.value)} · ${shown(e.path)}',
  ];
  if (settings.isEmpty && hidden == 0) {
    return const ['  No se observaron declaraciones de entorno.'];
  }
  return [
    ...settings,
    ?more(hidden, 'declaración', 'declaraciones', '  '),
    !_contradicted(report)
        ? '  Sin contradicciones entre las declaraciones examinadas.'
        : '  Hay contradicciones entre declaraciones; se detallan en '
              '«Resultado».',
    '  Son declaraciones del proyecto: no se comprobó qué SDK está instalado.',
  ];
}

/// Si algún conflicto cita una declaración de entorno: un conflicto de
/// relaciones no contradice el entorno.
bool _contradicted(RecognitionReport report) {
  final settings = {
    for (final e in report.evidence)
      if (_declaresSetting(e.role)) e.id,
  };
  return report.conflicts.any((c) => c.evidenceIds.any(settings.contains));
}

/// Las fuentes encontradas, sin abrirlas; las ausentes sólo se cuentan.
List<String> _sources(RecognitionReport report) {
  if (report.contextSources.isEmpty) {
    return const [
      'Fuentes candidatas',
      '  No se consultaron fuentes candidatas.',
    ];
  }
  final found = [
    for (final s in report.contextSources)
      if (s.entityType != ContextEntityType.missing) s,
  ];
  final missing = report.contextSources.length - found.length;
  return [
    'Fuentes candidatas (no se abrió ni contrastó su contenido)',
    for (final s in found.take(_maxSources))
      '  ${shown(s.path)} · ${_purpose(s.kind)} · ${_state(s)}',
    ?more(found.length - _maxSources, 'fuente', 'fuentes', '  '),
    ?_missing(missing, anyFound: found.isNotEmpty),
  ];
}

String? _missing(int missing, {required bool anyFound}) => switch (missing) {
  0 => null,
  1 when anyFound => '  Otra ruta del catálogo no existe.',
  1 => '  La ruta del catálogo no existe.',
  _ when anyFound => '  Otras $missing rutas del catálogo no existen.',
  _ => '  Ninguna de las $missing rutas del catálogo existe.',
};

String _purpose(ContextSourceKind kind) => switch (kind) {
  ContextSourceKind.documentation => 'documentación',
  ContextSourceKind.instructions => 'instrucciones',
  ContextSourceKind.analysisConfiguration => 'configuración de análisis',
  ContextSourceKind.taskConfiguration => 'configuración de tareas',
  ContextSourceKind.ciConfiguration => 'configuración de CI',
};

String _state(ContextSource s) => switch ((s.entityType, s.reason)) {
  (ContextEntityType.file, _) => 'archivo encontrado',
  (ContextEntityType.directory, _) => 'directorio encontrado',
  (ContextEntityType.link, _) => 'enlace, no se siguió',
  (ContextEntityType.special, _) => 'archivo especial, no se abrió',
  (_, ContextReason.ancestorLink) => 'detrás de un enlace que no se sigue',
  (_, ContextReason.excluded) => 'dentro de un árbol omitido',
  _ => 'no se pudo consultar',
};

List<String> _coverage(RecognitionReport report) {
  if (report.omissions.isEmpty) {
    return const ['  No se omitió ningún árbol por reglas de alcance.'];
  }
  return [
    '  No se recorrieron, por reglas de alcance:',
    for (final rule in OmissionRule.values)
      ?_omitted(rule, [
        for (final o in report.omissions)
          if (o.rule == rule) o.path,
      ]),
    '  Puede haber paquetes no referenciados dentro de lo omitido: esta '
        'ficha no es un inventario global.',
  ];
}

String? _omitted(OmissionRule rule, List<String> paths) {
  if (paths.isEmpty) return null;
  final label = switch (rule) {
    OmissionRule.baselineExclusion => 'exclusión fija',
    OmissionRule.temporaryDirectory => 'directorio temporal',
    OmissionRule.declaredResource => 'recurso declarado',
  };
  final rest = paths.length - _maxOmittedPaths;
  return '    $label (${paths.length}): '
      '${paths.take(_maxOmittedPaths).map(shown).join(', ')}'
      '${rest > 0 ? ' y $rest más' : ''}';
}
