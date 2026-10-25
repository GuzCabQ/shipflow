import 'package:core/core.dart';

/// Instancias canónicas con un valor distinguible en cada campo: si uno no
/// sobrevive el viaje, la comparación lo nombra.
const evidence = RecognitionEvidence(
  id: 'e0001',
  kind: 'manifest.package_name',
  path: 'packages/app/manifest.yaml',
  value: 'app',
  role: EvidenceRole.identity,
  label: 'Nombre del paquete',
  fingerprint:
      'sha256:abababababababababababababababababababababababababababababababab',
);

final candidate = StackCandidate(
  id: 'stack-a',
  displayName: 'Stack A',
  pluginId: 'plugin-a',
  evidenceIds: const ['e0001'],
);

final unit = ProjectUnit(
  id: 'unit-app',
  name: 'app',
  kind: 'package',
  path: 'packages/app',
  evidenceIds: const ['e0001'],
);

final conflict = RecognitionConflict(
  code: 'versions_disagree',
  message: 'dos versiones exactas distintas',
  evidenceIds: const ['e0001'],
);

const limitation = RecognitionLimitation(
  code: 'subtree_unreadable',
  message: 'no se pudo listar',
  path: 'packages/locked',
  blocking: true,
);

const repository = RepositoryContext(
  status: RepositoryStatus.detected,
  root: '/repositorio',
  relation: RepositoryRelation.ancestor,
);

const action = ProposedAction(
  code: 'record_project_identity',
  description: 'Registra la identidad.',
);

final proposal = RecognitionProposal(
  eligible: true,
  pluginIds: const ['plugin-a'],
  actions: const [action],
);

const effects = RecognitionEffects(
  filesWritten: 1,
  directoriesCreated: 2,
  processesStarted: 3,
  networkRequests: 4,
);

final relation = RecognitionRelation(
  id: 'r0001',
  kind: RelationKind.localDependency,
  fromPath: 'packages/app',
  declaredName: 'app',
  targetPath: 'packages/app',
  targetUnitId: 'unit-app',
  status: RelationStatus.corroborated,
  evidenceIds: const ['e0001'],
);

final contextSource = ContextSource(
  scopePath: 'packages/app',
  path: 'packages/app/README.md',
  kind: ContextSourceKind.documentation,
  entityType: ContextEntityType.file,
  reason: ContextReason.observed,
);

final omission = RecognitionOmission(
  path: 'packages/app/assets',
  rule: OmissionRule.declaredResource,
  evidenceIds: const ['e0001'],
);

final contribution = RecognitionContribution(
  candidates: [candidate],
  units: [unit],
  evidence: const [evidence],
  conflicts: [conflict],
  limitations: const [limitation],
  relations: [relation],
  contextSources: [contextSource],
  omissions: [omission],
);

final report = RecognitionReport(
  status: RecognitionStatus.ambiguous,
  requestedRoot: '/solicitada',
  resolvedRoot: '/resuelta',
  repository: repository,
  candidates: [candidate],
  units: [unit],
  evidence: const [evidence],
  conflicts: [conflict],
  limitations: const [limitation],
  relations: [relation],
  contextSources: [contextSource],
  omissions: [omission],
  proposal: proposal,
  effects: effects,
);
