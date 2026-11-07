import 'package:core/core.dart';

/// Documentos de base construidos en memoria. Core no calcula huellas: las
/// de estos documentos son marcadores y sólo importa su encadenamiento.
const basisProject = '00000001-0000-4000-8000-000000000000';

String uuid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

String digestOf(int n) => 'sha256:${n.toRadixString(16).padLeft(64, '0')}';

BasisScope paths(List<String> prefixes) =>
    BasisScope(kind: BasisScopeKind.paths, paths: prefixes);

BasisActor actorOf([BasisScope? scope]) => BasisActor(
  label: 'Responsable',
  role: 'mantenimiento',
  scope: scope ?? BasisScope.project(),
);

BasisRule ruleOf({
  BasisScope? scope,
  BasisRuleLifecycle lifecycle = BasisRuleLifecycle.active,
  BasisRuleClass ruleClass = BasisRuleClass.obligation,
  String? alternative,
  BasisExceptionPolicy policy = BasisExceptionPolicy.requiresAuthority,
  String? replacementRef,
  BasisSupport support = BasisSupport.humanDeclaration,
  List<BasisReference> sourceRefs = const [],
  String statement = 'Los contratos públicos se revisan.',
}) => BasisRule(
  title: 'Contratos',
  scope: scope ?? BasisScope.project(),
  lifecycle: lifecycle,
  replacementRef: replacementRef,
  statement: statement,
  reason: 'Compatibilidad.',
  ruleClass: ruleClass,
  alternative: alternative,
  exceptionPolicy: policy,
  support: support,
  sourceRefs: sourceRefs,
);

BasisPending pendingOf({
  BasisScope? scope,
  BasisDecisionReview? review,
  BasisPendingStatus status = BasisPendingStatus.open,
  String? resolution,
  String revisitWhen = 'Al integrar el segundo consumidor.',
}) => BasisPending(
  title: 'Revisión',
  scope: scope ?? BasisScope.project(),
  status: status,
  question: '¿Sigue valiendo?',
  reason: 'Falta confirmar consumidores.',
  revisitWhen: revisitWhen,
  sourceRefs: const [],
  resolution: resolution,
  decisionReview: review,
);

BasisSource sourceOf({String locator = 'docs/politica.md'}) => BasisSource(
  title: 'Política',
  scope: BasisScope.project(),
  lifecycle: BasisSourceLifecycle.active,
  sourceType: BasisSourceType.local,
  locator: locator,
  purpose: 'Referencia.',
  contentDigest: digestOf(99),
  observation: BasisObservation.current,
);

BasisRecordVersion versionOf(
  int id,
  int version,
  BasisPayload payload, {
  int? previous,
}) => BasisRecordVersion(
  id: uuid(id),
  version: version,
  previousVersion: version == 1 ? null : (previous ?? version - 1),
  payload: payload,
);

/// Una historia con un evento por lista de [batches], encadenada.
BasisDocument documentOf(
  List<List<BasisRecordVersion>> batches, {
  List<BasisActor>? actors,
}) {
  final events = <BasisEvent>[];
  for (final (i, changes) in batches.indexed) {
    events.add(
      BasisEvent(
        revision: i + 1,
        operationId: uuid(0x100 + i),
        acceptedAt: '2026-11-06T12:0$i:00Z',
        actor: actors?[i] ?? actorOf(),
        reason: 'Aceptación $i.',
        draftDigest: digestOf(0x200 + i),
        previousEventDigest: i == 0 ? null : digestOf(0x300 + i - 1),
        changes: changes,
        eventDigest: digestOf(0x300 + i),
      ),
    );
  }
  return BasisDocument(
    projectId: basisProject,
    revision: events.length,
    producerVersion: '0.0.0-prueba',
    events: events,
    digest: digestOf(0x400),
  );
}
