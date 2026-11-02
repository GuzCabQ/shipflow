import 'package:core/core.dart';

// Los mismos valores que los fixtures del paquete V2, escritos a mano.
const fixtureProjectId = '12345678-1234-4234-8234-123456789abc';
const fixtureOperationId = '87654321-1234-4234-8234-123456789abc';
const stagedProject = 'local/staging/$fixtureOperationId/project.json';
const fixtureDigest =
    '2d38557759f812e04357f90102a4f1b748283e5bfc4490417495185e0e95ead1';
const _zeroes =
    '0000000000000000000000000000000000000000000000000000000000000000';

RecognitionEvidence fixtureEvidence([String id = 'e0001']) =>
    RecognitionEvidence(
      id: id,
      kind: 'name',
      role: EvidenceRole.identity,
      label: 'Name',
      path: 'manifest.example',
      value: 'example',
      fingerprint: _zeroes,
    );

RecognitionOmission toolStateOmission() => RecognitionOmission(
  path: 'shipflow',
  rule: OmissionRule.toolState,
  evidenceIds: const [],
);

/// Un reconocimiento del ejemplo neutral; con un conflicto si no es
/// [eligible].
RecognitionReport eligibleReport({
  bool eligible = true,
  bool toolState = true,
}) => assembleRecognition(
  requestedRoot: '/tmp/ejemplo',
  resolvedRoot: '/private/tmp/ejemplo',
  repository: const RepositoryContext(
    status: RepositoryStatus.absent,
    root: null,
    relation: RepositoryRelation.none,
  ),
  contributions: [
    RecognitionContribution(
      candidates: [_candidate()],
      units: [_unit()],
      evidence: [fixtureEvidence()],
      conflicts: [
        if (!eligible)
          RecognitionConflict(code: 'c', message: 'm', evidenceIds: ['e0001']),
      ],
      limitations: const [],
      omissions: [if (toolState) toolStateOmission()],
    ),
  ],
);

StackCandidate _candidate() => StackCandidate(
  id: 'example',
  displayName: 'Example',
  pluginId: 'plugin_example',
  evidenceIds: const ['e0001'],
);

ProjectUnit _unit({String id = 'u0001', String path = '.'}) => ProjectUnit(
  id: id,
  name: 'example',
  kind: 'package',
  path: path,
  evidenceIds: const ['e0001'],
);

/// Las listas de un reconocimiento portable, para alterarlas antes de
/// construirlo.
final class PortableParts {
  final candidates = [_candidate()];
  final units = [_unit()];
  final evidence = [fixtureEvidence()];
  final conflicts = <RecognitionConflict>[];
  final limitations = <RecognitionLimitation>[];
  final relations = <RecognitionRelation>[];
  final omissions = [toolStateOmission()];

  void duplicateEvidence() => evidence.add(fixtureEvidence());

  void danglingUnit() => units
    ..clear()
    ..add(
      ProjectUnit(
        id: 'u0001',
        name: 'example',
        kind: 'package',
        path: '.',
        evidenceIds: const ['missing'],
      ),
    );

  void noUnits() => units.clear();

  void addConflict() => conflicts.add(
    RecognitionConflict(code: 'c', message: 'm', evidenceIds: ['e0001']),
  );

  void addBlocking() => limitations.add(_limitation(blocking: true));

  void addWarning() => limitations.add(_limitation(blocking: false));

  void twoToolStates() => omissions.add(toolStateOmission());

  void loneSurrogate() => evidence
    ..clear()
    ..add(
      RecognitionEvidence(
        id: 'e0001',
        kind: 'name',
        role: EvidenceRole.identity,
        label: 'Name',
        path: 'manifest.example',
        value: 'mal\ud800',
        fingerprint: _zeroes,
      ),
    );

  /// Una relación corroborada hacia `.` que nombra una unidad en `sub`.
  void misplacedRelation() {
    units.add(_unit(id: 'u0002', path: 'sub'));
    relations.add(
      RecognitionRelation(
        id: 'r0001',
        kind: RelationKind.localDependency,
        fromPath: 'sub',
        declaredName: 'example',
        targetPath: '.',
        targetUnitId: 'u0002',
        status: RelationStatus.corroborated,
        evidenceIds: const ['e0001'],
      ),
    );
  }

  PortableRecognition build() => PortableRecognition(
    candidates: candidates,
    units: units,
    evidence: evidence,
    conflicts: conflicts,
    limitations: limitations,
    relations: relations,
    contextSources: const [],
    omissions: omissions,
  );
}

RecognitionLimitation _limitation({required bool blocking}) =>
    RecognitionLimitation(
      code: 'x',
      message: 'm',
      path: null,
      blocking: blocking,
    );

ProjectContext projectContext({
  String at = '2026-10-25T00:00:00Z',
  String id = fixtureProjectId,
  int revision = 1,
  List<String> pluginIds = const ['plugin_example'],
}) => ProjectContext(
  projectId: id,
  revision: revision,
  producer: ContextProducer(
    version: '0.0.0-fixture',
    recognitionContract: 'declared-project-v2.1',
    pluginIds: pluginIds,
  ),
  observedAt: at,
  recognition: PortableParts().build(),
  observationDigest: fixtureDigest,
);

ContextTransaction transaction({
  String project = stagedProject,
  bool repeatTarget = false,
}) {
  final target = TransactionTarget(
    resource: TransactionResource.project,
    before: null,
    after: '1' * 64,
  );
  return ContextTransaction(
    operationId: fixtureOperationId,
    projectId: fixtureProjectId,
    operation: TransactionOperation.init,
    choice: SharingChoice.pending,
    phase: TransactionPhase.prepared,
    targets: [target, if (repeatTarget) target],
    staging: TransactionStaging(
      project: project,
      settingsBefore: null,
      settingsAfter: null,
    ),
    exclude: const TransactionExclude(
      blockId: null,
      beforeBlock: null,
      afterBlock: null,
    ),
  );
}

ContextOperationResult doctorResult({
  List<String> created = const [],
  ContextOperation operation = ContextOperation.doctor,
  bool repeatCheck = false,
  int exitCode = 0,
}) {
  const check = ContextCheck(
    id: ContextCheckId.contextPresence,
    status: ContextCheckStatus.passed,
    code: 'context_found',
    scope: 'shipflow/project.json',
    message: 'Contexto disponible',
  );
  return ContextOperationResult(
    command: ContextCommand.doctor,
    operation: operation,
    outcome: ContextOutcome.available,
    exitCode: exitCode,
    contextState: ContextState.present,
    freshness: ContextFreshness.current,
    sharing: const ContextSharing(
      choice: SharingChoice.pending,
      gitState: GitState.notInstalled,
      effective: SharingEffective.pending,
    ),
    checks: [check, if (repeatCheck) check],
    diagnostics: const [],
    context: PortableParts().build(),
    effects: ContextEffects(filesCreated: created),
    nextActions: const [],
  );
}
