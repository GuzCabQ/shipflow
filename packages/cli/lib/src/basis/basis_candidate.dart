import 'package:core/core.dart';

import 'basis_canonical.dart';

/// [time] en UTC con segundos: la forma de `acceptedAt` y `createdAt`.
String basisTimestamp(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

const _unsealed =
    'sha256:0000000000000000000000000000000000000000000000000000000000000000';

/// La base que resultaría de aceptar [draft] sobre [basis] (null: ausente):
/// un evento más, encadenado y sellado, con la hora de aceptación como
/// testigo que no cambia lo aprobado. Valida toda la historia resultante.
BasisDocument buildCandidate(
  BasisDocument? basis,
  BasisDraft draft, {
  required String acceptedAt,
  required String producer,
}) {
  final previous = basis?.events ?? const <BasisEvent>[];
  final event = _sealedEvent(
    BasisEvent(
      revision: previous.length + 1,
      operationId: draft.operationId,
      acceptedAt: acceptedAt,
      actor: draft.input.actor,
      reason: draft.input.reason,
      draftDigest: draft.digest,
      previousEventDigest: previous.isEmpty ? null : previous.last.eventDigest,
      changes: draft.preparedChanges,
      eventDigest: _unsealed,
    ),
  );
  final json = BasisDocument(
    projectId: draft.projectId,
    revision: previous.length + 1,
    producerVersion: producer,
    events: [...previous, event],
    digest: _unsealed,
  ).toJson();
  final candidate = BasisDocument.fromJson({
    ...json,
    'digest': sealedDigest(json, 'digest'),
  });
  validateBasisDocument(candidate);
  return candidate;
}

BasisEvent _sealedEvent(BasisEvent event) {
  final json = event.toJson();
  return BasisEvent.fromJson({
    ...json,
    'eventDigest': sealedDigest(json, 'eventDigest'),
  });
}

/// [draft] sellado por su propia huella.
BasisDraft sealDraft(BasisDraft draft) {
  final json = draft.toJson();
  return BasisDraft.fromJson({...json, 'digest': sealedDigest(json, 'digest')});
}

/// [transaction] sellado por su propia huella.
BasisTransaction sealTransaction(BasisTransaction transaction) {
  final json = transaction.toJson();
  return BasisTransaction.fromJson({
    ...json,
    'digest': sealedDigest(json, 'digest'),
  });
}

/// El evento de [basis] que publicó [draftDigest], si existe.
BasisEvent? eventOfDraft(BasisDocument? basis, String draftDigest) {
  for (final event in basis?.events ?? const <BasisEvent>[]) {
    if (event.draftDigest == draftDigest) return event;
  }
  return null;
}
