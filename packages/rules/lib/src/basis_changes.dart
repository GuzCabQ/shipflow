import 'package:core/core.dart';

/// Las versiones que propone [input] sobre [before] (null: base ausente):
/// cada cambio revisa la versión actual exacta de su registro o crea uno
/// con un ID nuevo de [newId], y cada `new:<key>` queda resuelto al ID de
/// su registro del lote. Rechaza con un código del catálogo.
List<BasisRecordVersion> resolveBasisChanges(
  BasisInput input,
  BasisDocument? before,
  String Function() newId,
) => resolveBasisLedgerChanges(input, _ledger(before), newId);

/// [resolveBasisChanges] sobre una historia ya reconstruida.
List<BasisRecordVersion> resolveBasisLedgerChanges(
  BasisInput input,
  BasisLedger ledger,
  String Function() newId,
) {
  validateBasisInput(input);
  final ids = <String, String>{};
  final used = <String>{};
  for (final (i, change) in input.changes.indexed) {
    final target = change.targetId;
    if (target != null) {
      requireBasis(
        ledger.currentOf(target)?.version == change.expectedVersion,
        'invalid_reference',
        'changes/$i/expectedVersion',
      );
    }
    ids[change.key] = target ?? _fresh(ledger, used, newId);
  }
  String resolve(String ref) =>
      ref.startsWith('new:') ? ids[ref.substring(4)] ?? ref : ref;
  return [
    for (final change in input.changes)
      BasisRecordVersion(
        id: ids[change.key]!,
        version: (change.expectedVersion ?? 0) + 1,
        previousVersion: change.expectedVersion,
        payload: _resolved(change.payload, resolve),
      ),
  ];
}

/// Los problemas de [input] sobre [before]: aplica las versiones resueltas
/// como un evento virtual con las mismas reglas de historia que la base
/// publicada. Vacía si se puede preparar.
List<BasisValidationIssue> validateBasisChangeSet(
  BasisInput input,
  BasisDocument? before,
) {
  try {
    final ledger = _ledger(before);
    final changes = resolveBasisLedgerChanges(input, ledger, _provisional());
    if (ledger.revision > 0 && changes.isEmpty) return const [];
    applyBasisEvent(ledger, _virtual(input, ledger, changes), '');
    return const [];
  } on ContextFormatException catch (e) {
    return [BasisValidationIssue(code: e.code, at: e.at)];
  }
}

BasisLedger _ledger(BasisDocument? before) =>
    before == null ? BasisLedger() : replayBasisLedger(before);

const _placeholder =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';

BasisEvent _virtual(
  BasisInput input,
  BasisLedger ledger,
  List<BasisRecordVersion> changes,
) => BasisEvent(
  revision: ledger.revision + 1,
  operationId: _provisional()(),
  acceptedAt: '1970-01-01T00:00:00Z',
  actor: input.actor,
  reason: input.reason,
  draftDigest: _placeholder,
  previousEventDigest: ledger.lastEventDigest,
  changes: changes,
  eventDigest: _placeholder,
);

/// IDs provisionales sólo para validar: nunca se publican.
String Function() _provisional() {
  var n = 0;
  return () =>
      'ffffffff-ffff-4fff-bfff-${(n++).toRadixString(16).padLeft(12, '0')}';
}

String _fresh(BasisLedger ledger, Set<String> used, String Function() newId) {
  while (true) {
    final id = newId();
    if (ledger.currentOf(id) == null && used.add(id)) return id;
  }
}

/// [payload] con cada referencia pasada por [map].
BasisPayload _resolved(BasisPayload payload, String Function(String) map) =>
    switch (payload) {
      BasisRule r => _rule(r, map),
      BasisPending p => _pending(p, map),
      _ => payload,
    };

List<BasisReference> _refs(
  List<BasisReference> list,
  String Function(String) map,
) => [
  for (final r in list) BasisReference(ref: map(r.ref), version: r.version),
];

BasisRule _rule(BasisRule r, String Function(String) map) => BasisRule(
  title: r.title,
  scope: r.scope,
  lifecycle: r.lifecycle,
  replacementRef: r.replacementRef == null ? null : map(r.replacementRef!),
  statement: r.statement,
  reason: r.reason,
  ruleClass: r.ruleClass,
  alternative: r.alternative,
  exceptionPolicy: r.exceptionPolicy,
  support: r.support,
  sourceRefs: _refs(r.sourceRefs, map),
);

BasisPending _pending(BasisPending p, String Function(String) map) {
  final link = p.decisionReview;
  return BasisPending(
    title: p.title,
    scope: p.scope,
    status: p.status,
    question: p.question,
    reason: p.reason,
    revisitWhen: p.revisitWhen,
    sourceRefs: _refs(p.sourceRefs, map),
    resolution: p.resolution,
    decisionReview: link == null
        ? null
        : BasisDecisionReview(
            ref: map(link.ref),
            version: link.version,
            reviewer: link.reviewer,
          ),
  );
}
