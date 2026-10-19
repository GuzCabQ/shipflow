import 'package:core/core.dart';

const absentRepository = RepositoryContext(
  status: RepositoryStatus.absent,
  root: null,
  relation: RepositoryRelation.none,
);

RecognitionEvidence evidence(String id, String path, String value) =>
    RecognitionEvidence(
      id: id,
      kind: 'manifest.package_name',
      path: path,
      value: value,
      fingerprint: 'sha256:${id * 8}',
    );

/// Un reporte cuyas colecciones entran desordenadas: el ensamblador las
/// ordena y las proyecciones no vuelven a hacerlo.
RecognitionReport report({
  List<RecognitionConflict> conflicts = const [],
  List<RecognitionLimitation> limitations = const [],
  RepositoryContext repository = absentRepository,
  bool withCandidate = true,
  String unitName = 'b',
}) => assembleRecognition(
  requestedRoot: '/solicitada',
  resolvedRoot: '/resuelta',
  repository: repository,
  contributions: [
    _contribution(
      conflicts: conflicts,
      limitations: limitations,
      withCandidate: withCandidate,
      unitName: unitName,
    ),
  ],
);

RecognitionContribution _contribution({
  required List<RecognitionConflict> conflicts,
  required List<RecognitionLimitation> limitations,
  required bool withCandidate,
  required String unitName,
}) => RecognitionContribution(
  candidates: [
    if (withCandidate)
      StackCandidate(
        id: 'stack',
        displayName: 'Stack',
        pluginId: 'plugin',
        evidenceIds: const ['e0002', 'e0001'],
      ),
  ],
  units: _units(unitName),
  evidence: [
    evidence('e0002', 'packages/b/manifest', unitName),
    evidence('e0001', 'packages/a/manifest', 'a'),
  ],
  conflicts: conflicts,
  limitations: limitations,
);

/// Dos unidades fuera de orden, para que el ensamblador las ordene.
List<ProjectUnit> _units(String unitName) => [
  ProjectUnit(
    id: 'u0002',
    name: unitName,
    kind: 'package',
    path: 'packages/b',
    evidenceIds: const ['e0002'],
  ),
  ProjectUnit(
    id: 'u0001',
    name: 'a',
    kind: 'package',
    path: 'packages/a',
    evidenceIds: const ['e0001'],
  ),
];
