// Constructores mínimos para las pruebas del ensamblador.
import 'package:core/core.dart';

const absentRepository = RepositoryContext(
  status: RepositoryStatus.absent,
  root: null,
  relation: RepositoryRelation.none,
);

RecognitionEvidence evidence(String id, {String path = 'a/manifest'}) =>
    RecognitionEvidence(
      id: id,
      kind: 'manifest.package_name',
      path: path,
      value: id,
      role: EvidenceRole.identity,
      label: 'Nombre',
      fingerprint: 'sha256:$id',
    );

StackCandidate candidate(String id, List<String> evidenceIds) => StackCandidate(
  id: id,
  displayName: id.toUpperCase(),
  pluginId: 'plugin-$id',
  evidenceIds: evidenceIds,
);

ProjectUnit unit(String id, String path, List<String> evidenceIds) =>
    ProjectUnit(
      id: id,
      name: id,
      kind: 'package',
      path: path,
      evidenceIds: evidenceIds,
    );

RecognitionContribution contribution({
  List<StackCandidate> candidates = const [],
  List<ProjectUnit> units = const [],
  List<RecognitionEvidence> evidence = const [],
  List<RecognitionConflict> conflicts = const [],
  List<RecognitionLimitation> limitations = const [],
  List<RecognitionRelation> relations = const [],
  List<ContextSource> contextSources = const [],
  List<RecognitionOmission> omissions = const [],
}) => RecognitionContribution(
  candidates: candidates,
  units: units,
  evidence: evidence,
  conflicts: conflicts,
  limitations: limitations,
  relations: relations,
  contextSources: contextSources,
  omissions: omissions,
);

RecognitionReport assemble(List<RecognitionContribution> contributions) =>
    assembleRecognition(
      requestedRoot: '/solicitada',
      resolvedRoot: '/resuelta',
      repository: absentRepository,
      contributions: contributions,
    );

RecognitionContribution recognizable({
  List<RecognitionConflict> conflicts = const [],
  List<RecognitionLimitation> limitations = const [],
  List<ProjectUnit>? units,
}) => contribution(
  candidates: [
    candidate('stack', ['e0001']),
  ],
  units:
      units ??
      [
        unit('unit', 'app', ['e0001']),
      ],
  evidence: [evidence('e0001')],
  conflicts: conflicts,
  limitations: limitations,
);
