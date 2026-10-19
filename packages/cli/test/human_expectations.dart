import 'package:cli/cli.dart';
import 'package:core/core.dart';

import 'recognition_reports.dart';

// Los textos esperados viven aquí, escritos a mano: no salen del renderer.
const expectedHead = 'Shipflow · reconocimiento del proyecto\n';

/// Entorno, fuentes y cobertura sin nada que mostrar, hasta el resultado.
const expectedEmptyBlocks =
    '\n'
    'Entorno declarado\n'
    '  No se observaron declaraciones de entorno.\n'
    '\n'
    'Fuentes candidatas\n'
    '  No se consultaron fuentes candidatas.\n'
    '\n'
    'Cobertura\n'
    '  No se omitió ningún árbol por reglas de alcance.\n'
    '\n';

/// Identidad, unidades y bloques vacíos del reporte de dos paquetes.
const expectedTwoUnits =
    '\n'
    'Identidad\n'
    '  Tecnología: Stack\n'
    '\n'
    'Unidades y relaciones\n'
    '  Paquetes observados: 2\n'
    '    a · packages/a\n'
    '    b · packages/b\n'
    '  Relaciones declaradas: ninguna\n'
    '$expectedEmptyBlocks';
const expectedScope =
    '  No se comprobó si el proyecto compila, si sus pruebas pasan, si '
    'respeta su arquitectura, si sus recursos existen ni si el SDK está '
    'instalado.\n';
const expectedEffects =
    '  No se modificó el proyecto. Shipflow no guardó este reporte ni creó un '
    'expediente.\n';
const expectedDetail =
    '\n'
    'Para repetir la inspección con detalle estructurado:\n'
    '  shipflow init --dry-run --json\n';
const expectedRecognizedNext =
    '  La inspección terminó. Esta versión sólo entrega esta ficha: no '
    'aplica la inicialización ni inicia tareas.\n';
const expectedLimitsNext =
    '  Revisa las causas indicadas; el reconocimiento está incompleto. Si una '
    'causa depende del alcance de esta versión y no del proyecto, esta '
    'versión no puede resolverla.\n';

String human(RecognitionReport report, [ReportBudgetProfile? profile]) =>
    presentRecognition(
      report,
      json: false,
      budgetProfile: profile ?? ReportBudgetProfile.standard,
    ).payload;

RecognitionReport wide({
  int units = 0,
  List<RecognitionConflict> conflicts = const [],
  List<RecognitionLimitation> limitations = const [],
}) => assembleRecognition(
  requestedRoot: '/r',
  resolvedRoot: '/r',
  repository: absentRepository,
  contributions: [
    RecognitionContribution(
      candidates: [
        StackCandidate(
          id: 'dart',
          displayName: 'Dart',
          pluginId: 'p',
          evidenceIds: const ['e0000'],
        ),
      ],
      units: [
        for (var i = 0; i < units; i++)
          ProjectUnit(
            id: 'u$i',
            name: 'p${i.toString().padLeft(2, '0')}',
            kind: 'k',
            path: 'packages/p${i.toString().padLeft(2, '0')}',
            evidenceIds: const ['e0000'],
          ),
      ],
      evidence: [evidence('e0000', 'pubspec.yaml', 'x')],
      conflicts: conflicts,
      limitations: limitations,
    ),
  ],
);

RecognitionLimitation limitation(String code, {bool blocking = true}) =>
    RecognitionLimitation(
      code: code,
      message: 'mensaje $code',
      path: null,
      blocking: blocking,
    );

/// Un paquete Flutter con descripción, entorno, una relación, fuentes
/// candidatas y omisiones: cada bloque de la ficha tiene algo que mostrar.
RecognitionReport scopedReport({
  List<RecognitionLimitation> limitations = const [],
  List<RecognitionConflict> conflicts = const [],
  List<RecognitionOmission>? omissions,
  String description = 'App de pedidos',
}) => assembleRecognition(
  requestedRoot: '/freya',
  resolvedRoot: '/freya',
  repository: absentRepository,
  contributions: [
    RecognitionContribution(
      candidates: [
        StackCandidate(
          id: 'flutter',
          displayName: 'Flutter',
          pluginId: 'p',
          evidenceIds: const ['e0001'],
        ),
      ],
      units: [
        _unit('u0001', 'freya', '.', const ['e0001', 'e0002', 'e0003']),
        _unit('u0002', 'componentes', 'packages/componentes', const ['e0005']),
      ],
      evidence: _scopedEvidence(description),
      conflicts: conflicts,
      limitations: limitations,
      relations: [_dependency],
      contextSources: _scopedSources,
      omissions: omissions ?? _scopedOmissions,
    ),
  ],
);

List<RecognitionEvidence> _scopedEvidence(String description) => [
  _fact('e0001', EvidenceRole.identity, 'Nombre del paquete', 'freya'),
  _fact('e0002', EvidenceRole.description, 'Descripción', description),
  _fact('e0003', EvidenceRole.environment, 'SDK de Dart', '^3.5.0'),
  _fact('e0004', EvidenceRole.relation, 'Dependencia local', 'c'),
  _fact(
    'e0005',
    EvidenceRole.identity,
    'Nombre del paquete',
    'componentes',
    path: 'packages/componentes/pubspec.yaml',
  ),
  _fact('e0006', EvidenceRole.resource, 'Recursos', 'assets/fonts/'),
];

final _dependency = RecognitionRelation(
  id: 'r0001',
  kind: RelationKind.localDependency,
  fromPath: '.',
  declaredName: 'componentes',
  targetPath: 'packages/componentes',
  targetUnitId: 'u0002',
  status: RelationStatus.corroborated,
  evidenceIds: const ['e0004', 'e0005'],
);

final _scopedSources = [
  _source('README.md', ContextEntityType.file, ContextReason.observed),
  _source('docs', ContextEntityType.missing, ContextReason.notFound),
  _source('CLAUDE.md', ContextEntityType.link, ContextReason.observed),
];

final _scopedOmissions = [
  RecognitionOmission(
    path: 'assets/fonts',
    rule: OmissionRule.declaredResource,
    evidenceIds: const ['e0006'],
  ),
  RecognitionOmission(
    path: '.git',
    rule: OmissionRule.baselineExclusion,
    evidenceIds: const [],
  ),
];

ProjectUnit _unit(String id, String name, String path, List<String> ids) =>
    ProjectUnit(id: id, name: name, kind: 'k', path: path, evidenceIds: ids);

RecognitionEvidence _fact(
  String id,
  EvidenceRole role,
  String label,
  String value, {
  String path = 'pubspec.yaml',
}) => RecognitionEvidence(
  id: id,
  kind: 'k',
  role: role,
  label: label,
  path: path,
  value: value,
  fingerprint: 'sha256:$id',
);

ContextSource _source(
  String path,
  ContextEntityType type,
  ContextReason reason,
) => ContextSource(
  scopePath: '.',
  path: path,
  kind: ContextSourceKind.documentation,
  entityType: type,
  reason: reason,
);

/// [count] relaciones, declaraciones de entorno y fuentes encontradas.
RecognitionReport crowded(int count) => assembleRecognition(
  requestedRoot: '/r',
  resolvedRoot: '/r',
  repository: absentRepository,
  contributions: [
    RecognitionContribution(
      candidates: const [],
      units: [
        _unit('u0001', 'a', 'a', const ['e0000']),
      ],
      evidence: [
        _fact('e0000', EvidenceRole.identity, 'Nombre del paquete', 'a'),
        for (var i = 0; i < count; i++)
          _fact('e1$i', EvidenceRole.environment, 'Restricción', '^$i.0.0'),
      ],
      conflicts: const [],
      limitations: const [],
      relations: [for (var i = 0; i < count; i++) _member(i)],
      contextSources: [
        for (var i = 0; i < count; i++)
          _source('f$i', ContextEntityType.file, ContextReason.observed),
      ],
    ),
  ],
);

RecognitionRelation _member(int index) => RecognitionRelation(
  id: 'r${index.toString().padLeft(4, '0')}',
  kind: RelationKind.workspaceMember,
  fromPath: '.',
  declaredName: null,
  targetPath: 'a',
  targetUnitId: 'u0001',
  status: RelationStatus.corroborated,
  evidenceIds: const ['e0000'],
);
