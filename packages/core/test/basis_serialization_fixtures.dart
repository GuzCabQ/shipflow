import 'package:core/core.dart';

import 'assessment_serialization_fixtures.dart' show SerializationCase;
import 'basis_fixtures.dart';

/// Una instancia de cada clase serializable de la base, con un valor
/// distinguible en cada campo, y cómo reconstruirla.
Map<String, SerializationCase> basisSerializationCases() => {
  ..._recordCases(),
  ..._documentCases(),
  ..._responseCases(),
};

final _review = BasisDecisionReview(ref: uuid(1), version: 2, reviewer: 'Ana');
final _reference = BasisReference(ref: uuid(9), version: 3);
final _source = BasisSource(
  title: 'Política',
  scope: paths(['docs', 'lib/a']),
  lifecycle: BasisSourceLifecycle.retired,
  sourceType: BasisSourceType.local,
  locator: 'docs/politica.md',
  purpose: 'Referencia.',
  contentDigest: digestOf(7),
  observation: BasisObservation.current,
);
final _rule = BasisRule(
  title: 'No usar SQL directo',
  scope: paths(['lib/data']),
  lifecycle: BasisRuleLifecycle.replaced,
  replacementRef: uuid(4),
  statement: 'Prohibido SQL directo.',
  reason: 'Auditoría.',
  ruleClass: BasisRuleClass.prohibition,
  alternative: 'Usar el repositorio.',
  exceptionPolicy: BasisExceptionPolicy.notAllowed,
  support: BasisSupport.sourceSupported,
  sourceRefs: [_reference],
);
final _pending = BasisPending(
  title: 'Revisión',
  scope: paths(['lib/data']),
  status: BasisPendingStatus.resolved,
  question: '¿Sigue valiendo?',
  reason: 'Consumidores nuevos.',
  revisitWhen: 'Al integrar el segundo consumidor.',
  sourceRefs: [_reference],
  resolution: 'disposition:Se mantiene.',
  decisionReview: _review,
);
final _version = BasisRecordVersion(
  id: uuid(5),
  version: 2,
  previousVersion: 1,
  payload: _rule,
);
final _actor = BasisActor(
  label: 'Ana',
  role: 'arquitectura',
  scope: paths(['lib']),
);
final _event = BasisEvent(
  revision: 3,
  operationId: uuid(6),
  acceptedAt: '2026-11-06T12:00:00Z',
  actor: _actor,
  reason: 'Revisión anual.',
  draftDigest: digestOf(8),
  previousEventDigest: digestOf(10),
  changes: [_version],
  eventDigest: digestOf(11),
);
final _reading = BasisSourceReading(path: 'docs/a.md', digest: digestOf(12));
final _change = BasisChange(
  key: 'datos',
  targetId: uuid(5),
  expectedVersion: 1,
  payload: _rule,
);
final _input = BasisInput(
  projectId: basisProject,
  expectedBasisDigest: digestOf(13),
  actor: _actor,
  reason: 'Revisión anual.',
  changes: [_change],
);

SerializationCase _case(
  Map<String, Object?> json,
  Map<String, Object?> Function(Map<String, Object?>) rebuild,
) => (json, rebuild);

Map<String, SerializationCase> _recordCases() => {
  'BasisScope': _case(
    _source.scope.toJson(),
    (j) => BasisScope.fromJson(j).toJson(),
  ),
  'BasisActor': _case(_actor.toJson(), (j) => BasisActor.fromJson(j).toJson()),
  'BasisReference': _case(
    _reference.toJson(),
    (j) => BasisReference.fromJson(j).toJson(),
  ),
  'BasisDecisionReview': _case(
    _review.toJson(),
    (j) => BasisDecisionReview.fromJson(j).toJson(),
  ),
  'BasisSource': _case(
    _source.toJson(),
    (j) => BasisSource.fromJson(j).toJson(),
  ),
  'BasisRule': _case(_rule.toJson(), (j) => BasisRule.fromJson(j).toJson()),
  'BasisPending': _case(
    _pending.toJson(),
    (j) => BasisPending.fromJson(j).toJson(),
  ),
  'BasisRecordVersion': _case(
    _version.toJson(),
    (j) => BasisRecordVersion.fromJson(j).toJson(),
  ),
  'BasisEvent': _case(_event.toJson(), (j) => BasisEvent.fromJson(j).toJson()),
};

Map<String, SerializationCase> _documentCases() => {
  'BasisDocument': _case(
    _basisDocument.toJson(),
    (j) => BasisDocument.fromJson(j).toJson(),
  ),
  'BasisChange': _case(
    _change.toJson(),
    (j) => BasisChange.fromJson(j).toJson(),
  ),
  'BasisInput': _case(_input.toJson(), (j) => BasisInput.fromJson(j).toJson()),
  'BasisSourceReading': _case(
    _reading.toJson(),
    (j) => BasisSourceReading.fromJson(j).toJson(),
  ),
  'BasisDraft': _case(
    _basisDraft.toJson(),
    (j) => BasisDraft.fromJson(j).toJson(),
  ),
  'BasisTransaction': _case(
    _basisTransaction.toJson(),
    (j) => BasisTransaction.fromJson(j).toJson(),
  ),
  'BasisLimits': _case(
    BasisLimits.forProfile(BasisProfile.extended).toJson(),
    (j) => BasisLimits.fromJson(j).toJson(),
  ),
};

final _diagnostic = BasisDiagnostic(
  code: 'source_unverified',
  message: 'La fuente no se pudo comprobar.',
  path: 'docs/a.md',
);
final _status = BasisSourceStatus(
  sourceId: uuid(9),
  sourceVersion: 3,
  status: BasisSourceState.stale,
  diagnostics: [_diagnostic],
);
final _action = BasisAction(
  command: 'bootstrap',
  arguments: ['--accept', digestOf(8)],
  purpose: 'Aceptar el borrador revisado.',
  effect: BasisActionEffect.writeOwnState,
);
final _integrity = BasisStorageIntegrity(
  basis: BasisIntegrity.valid,
  draft: BasisIntegrity.invalid,
  transaction: BasisIntegrity.unverified,
);
final _selection = BasisSelectionSummary(
  scope: paths(['lib/a']),
  complete: false,
  excludedCount: 2,
);

Map<String, SerializationCase> _responseCases() => {
  ..._selectionCases(),
  'BasisDiagnostic': _case(
    _diagnostic.toJson(),
    (j) => BasisDiagnostic.fromJson(j).toJson(),
  ),
  'BasisSourceStatus': _case(
    _status.toJson(),
    (j) => BasisSourceStatus.fromJson(j).toJson(),
  ),
  'BasisAction': _case(
    _action.toJson(),
    (j) => BasisAction.fromJson(j).toJson(),
  ),
  'BasisStorageIntegrity': _case(
    _integrity.toJson(),
    (j) => BasisStorageIntegrity.fromJson(j).toJson(),
  ),
  'BasisSelectionSummary': _case(
    _selection.toJson(),
    (j) => BasisSelectionSummary.fromJson(j).toJson(),
  ),
  'BasisResponse': _case(
    _basisResponse.toJson(),
    (j) => BasisResponse.fromJson(j).toJson(),
  ),
};

final _basisDocument = BasisDocument(
  projectId: basisProject,
  revision: 3,
  producerVersion: '1.2.3',
  events: [_event],
  digest: digestOf(14),
);

final _basisDraft = BasisDraft(
  projectId: basisProject,
  operationId: uuid(6),
  createdAt: '2026-11-06T11:00:00Z',
  expectedBasisDigest: digestOf(13),
  contextProjectDigest: digestOf(15),
  input: _input,
  preparedChanges: [_version],
  sourceReads: [_reading],
  digest: digestOf(8),
);

final _basisTransaction = BasisTransaction(
  projectId: basisProject,
  operationId: uuid(6),
  phase: BasisTransactionPhase.published,
  before: digestOf(13),
  after: digestOf(16),
  acceptedDraftDigest: digestOf(8),
  acceptedAt: '2026-11-06T12:00:00Z',
  actor: _actor,
  contextProjectDigest: digestOf(15),
  sourceReads: [_reading],
  candidatePath: basisCandidatePath(uuid(6)),
  digest: digestOf(17),
);

final _basisResponse = BasisResponse(
  operation: BasisOperation.show,
  exitCode: 65,
  outcome: BasisOutcome.shown,
  storageIntegrity: _integrity,
  basisDigest: digestOf(14),
  draftDigest: digestOf(8),
  published: true,
  changedFiles: ['shipflow/basis.json'],
  normativeCoverage: BasisCoverage.declaredPartial,
  selected: [_version],
  reviewTargets: [_version],
  pending: [_version],
  sourceStatus: [_status],
  actor: _actor,
  reason: 'Consulta.',
  history: [_event],
  selection: _selection,
  diagnostics: [_diagnostic],
  nextActions: [_action],
);

Map<String, SerializationCase> _selectionCases() => {
  'BasisSelection': _case(
    BasisSelection(
      selected: [_version],
      pending: [_version],
      reviewTargets: [_version],
      excludedCount: 4,
    ).toJson(),
    (j) => BasisSelection.fromJson(j).toJson(),
  ),
  'BasisValidationIssue': _case(
    BasisValidationIssue(code: 'invalid_reference', at: 'changes/1').toJson(),
    (j) => BasisValidationIssue.fromJson(j).toJson(),
  ),
};
