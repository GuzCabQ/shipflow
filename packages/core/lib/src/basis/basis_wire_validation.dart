import '../context/context_validation.dart';
import 'basis_draft.dart';
import 'basis_enums.dart';
import 'basis_input.dart';
import 'basis_limits.dart';
import 'basis_payload.dart';
import 'basis_references.dart';
import 'basis_transaction.dart';
import 'basis_validation.dart';

final _key = RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$');

/// Las reglas de [input] que no dependen de la base: claves, creación o
/// revisión exacta, observaciones que la entrada no puede aportar y
/// referencias `new:` dentro del mismo lote. Las referencias a IDs
/// existentes las resuelve quien tiene la base.
void validateBasisInput(BasisInput input) {
  requireBasis(isUuidV4(input.projectId), 'invalid_schema', 'projectId');
  validateBasisActor(input.actor, 'actor');
  requireText(input.reason, maxBasisReasonText, 'reason');
  final keys = <String, BasisChange>{};
  final targets = <String>{};
  for (final (i, change) in input.changes.indexed) {
    final at = 'changes/$i';
    requireBasis(
      _key.hasMatch(change.key) && !keys.containsKey(change.key),
      'invalid_schema',
      '$at/key',
    );
    keys[change.key] = change;
    requireBasis(
      (change.targetId == null) == (change.expectedVersion == null) &&
          (change.targetId == null || targets.add(change.targetId!)),
      'invalid_schema',
      at,
    );
    validateBasisPayload(change.payload, '$at/payload');
    _unobserved(change.payload, '$at/payload');
  }
  for (final (i, change) in input.changes.indexed) {
    _batchReferences(input.changes, keys, change, 'changes/$i/payload');
  }
}

/// Una entrada no aporta observaciones: el coordinador las produce.
void _unobserved(BasisPayload payload, String at) {
  if (payload is! BasisSource) return;
  requireBasis(
    payload.contentDigest == null &&
        payload.observation == BasisObservation.unverified,
    'invalid_schema',
    '$at/observation',
  );
}

/// El cambio que crea `new:<key>`, si [ref] es de esa forma.
BasisChange? _created(Map<String, BasisChange> keys, String ref) {
  if (!ref.startsWith('new:')) return null;
  final change = keys[ref.substring(4)];
  return change != null && change.creates ? change : null;
}

void _batchReferences(
  List<BasisChange> changes,
  Map<String, BasisChange> keys,
  BasisChange change,
  String at,
) {
  final payload = change.payload;
  for (final (i, source) in payload.citedSources.indexed) {
    final created = _created(keys, source.ref);
    requireBasis(
      created == null
          ? isUuidV4(source.ref)
          : created.payload is BasisSource && source.version == 1,
      'invalid_reference',
      '$at/sourceRefs/$i',
    );
  }
  if (payload case BasisRule(:final replacementRef?)) {
    final created = _created(keys, replacementRef);
    requireBasis(
      created == null
          ? isUuidV4(replacementRef) && replacementRef != change.targetId
          : created.payload is BasisRule && created != change,
      'invalid_reference',
      '$at/replacementRef',
    );
  }
  if (payload is BasisPending) _batchReview(changes, keys, payload, at);
}

/// Un vínculo `new:<key>` apunta a una regla creada en el lote en versión
/// 1; uno a un ID revisado en el lote, a su versión nueva. Los demás se
/// resuelven contra la base.
void _batchReview(
  List<BasisChange> changes,
  Map<String, BasisChange> keys,
  BasisPending pending,
  String at,
) {
  final link = pending.decisionReview;
  if (link == null) return;
  if (link.ref.startsWith('new:')) {
    final created = _created(keys, link.ref);
    requireBasis(
      created != null && link.version == 1,
      'invalid_reference',
      '$at/decisionReview',
    );
    requireReviewTarget(pending, created!.payload, '$at/decisionReview');
    return;
  }
  requireBasis(isUuidV4(link.ref), 'invalid_reference', '$at/decisionReview');
  for (final change in changes) {
    if (change.targetId == link.ref &&
        change.expectedVersion! + 1 == link.version) {
      requireReviewTarget(pending, change.payload, '$at/decisionReview');
    }
  }
}

/// Las reglas de un borrador que no dependen de la base: corresponde a su
/// entrada y todas sus referencias ya son IDs.
void validateBasisDraft(BasisDraft draft) {
  validateBasisInput(draft.input);
  requireBasis(
    draft.projectId == draft.input.projectId &&
        draft.expectedBasisDigest == draft.input.expectedBasisDigest &&
        draft.preparedChanges.length == draft.input.changes.length,
    'invalid_schema',
    'input',
  );
  requireBasis(isUtcTimestamp(draft.createdAt), 'invalid_schema', 'createdAt');
  for (final (i, change) in draft.preparedChanges.indexed) {
    validateBasisPayload(change.payload, 'preparedChanges/$i/payload');
    requireBasis(
      _resolved(change.payload),
      'invalid_reference',
      'preparedChanges/$i/payload',
    );
  }
  _readings(draft.sourceReads, 'sourceReads');
}

/// Ninguna referencia temporal sobrevive a la preparación.
bool _resolved(BasisPayload payload) =>
    payload.citedSources.every((r) => isUuidV4(r.ref)) &&
    switch (payload) {
      BasisRule(:final replacementRef) =>
        replacementRef == null || isUuidV4(replacementRef),
      BasisPending(:final decisionReview) =>
        decisionReview == null || isUuidV4(decisionReview.ref),
      _ => true,
    };

void _readings(List<BasisSourceReading> reads, String at) {
  final paths = <String>{};
  for (final (i, read) in reads.indexed) {
    requireBasis(
      isBasisPrefix(read.path) && paths.add(read.path),
      'unsafe_path',
      '$at/$i/path',
    );
  }
}

/// Un journal sólo cita el candidato que su operación deriva.
void validateBasisTransaction(BasisTransaction transaction) {
  requireBasis(
    transaction.candidatePath == basisCandidatePath(transaction.operationId),
    'invalid_reference',
    'candidatePath',
  );
  requireBasis(
    isUtcTimestamp(transaction.acceptedAt),
    'invalid_schema',
    'acceptedAt',
  );
  validateBasisActor(transaction.actor, 'actor');
  _readings(transaction.sourceReads, 'sourceReads');
}
