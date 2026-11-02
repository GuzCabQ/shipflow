import 'package:core/core.dart';

import 'context_fixtures.dart';

// Instancias con un valor distinguible en cada campo, para los casos de ida
// y vuelta de serializacion_test.
final binding = GitBinding(
  repositoryRoot: '/repo',
  gitDir: '/repo/.git/worktrees/w',
  commonDir: '/repo/.git',
  prefix: 'apps/app/',
);

final managedExclude = ManagedExcludeRecord(
  path: '/repo/.git/info/exclude',
  blockId: 'a' * 64,
  sha256: 'b' * 64,
);

final settings = LocalSettings(
  projectId: fixtureProjectId,
  choice: SharingChoice.local,
  binding: binding,
  applied: true,
  managedExclude: managedExclude,
);

final target = TransactionTarget(
  resource: TransactionResource.exclude,
  before: 'c' * 64,
  after: 'd' * 64,
);

const staging = TransactionStaging(
  project: stagedProject,
  settingsBefore: 'local/staging/$fixtureOperationId/settings.before.json',
  settingsAfter: 'local/staging/$fixtureOperationId/settings.after.json',
);

const exclude = TransactionExclude(
  blockId: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  beforeBlock: '# antes\n',
  afterBlock: '# después\n',
);

final journal = ContextTransaction(
  operationId: fixtureOperationId,
  projectId: fixtureProjectId,
  operation: TransactionOperation.sharing,
  choice: SharingChoice.local,
  phase: TransactionPhase.sharingApplied,
  targets: [target],
  staging: staging,
  exclude: exclude,
);

const sharing = ContextSharing(
  choice: SharingChoice.share,
  gitState: GitState.available,
  effective: SharingEffective.shareReady,
);

const check = ContextCheck(
  id: ContextCheckId.recognitionFreshness,
  status: ContextCheckStatus.failed,
  code: 'stale',
  scope: 'shipflow/project.json',
  message: 'Necesita actualizarse',
);

const diagnostic = ContextDiagnostic(
  code: 'recognition_changed',
  message: 'Cambió un manifiesto',
  path: 'manifest.lock',
);

final contextEffects = ContextEffects(
  filesCreated: ['shipflow/project.json'],
  filesReplaced: ['shipflow/local/settings.json'],
  filesRemoved: ['shipflow/local/transaction.json'],
  directoriesCreated: ['shipflow'],
  processesStarted: 5,
  excludeModified: true,
);

final nextAction = ContextNextAction(
  command: ContextCommand.init,
  arguments: ['--refresh'],
  purpose: 'Actualizar el contexto',
  effect: 'Reemplaza project.json',
);

const formatError = ContextFormatException(
  ContextFormatLayer.schema,
  'enum',
  '/recognition/units/0/kind',
);

final operationResult = ContextOperationResult(
  command: ContextCommand.init,
  operation: ContextOperation.refresh,
  outcome: ContextOutcome.needsAttention,
  exitCode: 65,
  contextState: ContextState.present,
  freshness: ContextFreshness.stale,
  sharing: sharing,
  checks: [check],
  diagnostics: [diagnostic],
  context: PortableParts().build(),
  effects: contextEffects,
  nextActions: [nextAction],
);
