import 'package:core/core.dart';

/// Bases construidas en memoria para probar la selección y los cambios.
/// Las huellas son marcadores: rules no calcula ni verifica huellas.
const project = '00000001-0000-4000-8000-000000000000';

String uuid(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

String digestOf(int n) => 'sha256:${n.toRadixString(16).padLeft(64, '0')}';

BasisScope at(List<String> prefixes) =>
    BasisScope(kind: BasisScopeKind.paths, paths: prefixes);

BasisActor actorOf([BasisScope? scope]) => BasisActor(
  label: 'Responsable',
  role: 'mantenimiento',
  scope: scope ?? BasisScope.project(),
);

BasisRule rule({
  BasisScope? scope,
  BasisRuleLifecycle lifecycle = BasisRuleLifecycle.active,
  BasisRuleClass ruleClass = BasisRuleClass.obligation,
  String? alternative,
  String? replacementRef,
  BasisSupport support = BasisSupport.humanDeclaration,
  List<BasisReference> sourceRefs = const [],
  String statement = 'Se revisa.',
}) => BasisRule(
  title: 'Regla',
  scope: scope ?? BasisScope.project(),
  lifecycle: lifecycle,
  replacementRef: replacementRef,
  statement: statement,
  reason: 'Motivo.',
  ruleClass: ruleClass,
  alternative: alternative,
  exceptionPolicy: BasisExceptionPolicy.requiresAuthority,
  support: support,
  sourceRefs: sourceRefs,
);

BasisPending pending({
  BasisScope? scope,
  BasisDecisionReview? review,
  BasisPendingStatus status = BasisPendingStatus.open,
  String? resolution,
}) => BasisPending(
  title: 'Pendiente',
  scope: scope ?? BasisScope.unknown(),
  status: status,
  question: '¿Qué falta?',
  reason: 'Sin datos.',
  revisitWhen: 'Antes de publicar.',
  sourceRefs: const [],
  resolution: resolution,
  decisionReview: review,
);

BasisSource source({BasisScope? scope, String? digest}) => BasisSource(
  title: 'Fuente',
  scope: scope ?? BasisScope.project(),
  lifecycle: BasisSourceLifecycle.active,
  sourceType: BasisSourceType.local,
  locator: 'docs/politica.md',
  purpose: 'Referencia.',
  contentDigest: digest ?? digestOf(77),
  observation: BasisObservation.current,
);

BasisDecisionReview review(int id, int version) =>
    BasisDecisionReview(ref: uuid(id), version: version, reviewer: null);

BasisRecordVersion v(int id, int version, BasisPayload payload) =>
    BasisRecordVersion(
      id: uuid(id),
      version: version,
      previousVersion: version == 1 ? null : version - 1,
      payload: payload,
    );

/// Una historia con un evento por lote, encadenada.
BasisDocument history(
  List<List<BasisRecordVersion>> batches, {
  List<BasisActor>? actors,
}) => BasisDocument(
  projectId: project,
  revision: batches.length,
  producerVersion: '0.0.0-prueba',
  events: [
    for (final (i, changes) in batches.indexed)
      BasisEvent(
        revision: i + 1,
        operationId: uuid(0x100 + i),
        acceptedAt: '2026-11-06T12:00:00Z',
        actor: actors?[i] ?? actorOf(),
        reason: 'Aceptación.',
        draftDigest: digestOf(0x200 + i),
        previousEventDigest: i == 0 ? null : digestOf(0x300 + i - 1),
        changes: changes,
        eventDigest: digestOf(0x300 + i),
      ),
  ],
  digest: digestOf(0x400),
);

List<String> ids(List<BasisRecordVersion> versions) => [
  for (final r in versions) '${r.id}@${r.version}',
];

String key(int id, int version) => '${uuid(id)}@$version';
