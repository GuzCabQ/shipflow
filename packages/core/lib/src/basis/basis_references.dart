import '../context/context_validation.dart';
import 'basis_enums.dart';
import 'basis_model.dart';
import 'basis_payload.dart';
import 'basis_validation.dart';

/// Lo que hace falta para resolver las referencias de una versión
/// persistida: su [id], su [payload], la versión anterior del mismo ID, las
/// versiones disponibles en el evento (historia anterior más el lote), las
/// aceptadas antes del evento y la última versión de cada ID.
typedef PersistedReferences = ({
  String id,
  BasisPayload payload,
  BasisPayload? prior,
  BasisRecordVersion? Function(String id, int version) available,
  BasisRecordVersion? Function(String id, int version) accepted,
  BasisPayload? Function(String id) latest,
});

/// Exige que toda referencia de una versión persistida sea un ID real con
/// la versión y el tipo que corresponden en su momento. Nunca `new:`.
void requirePersistedReferences(PersistedReferences r, String at) {
  for (final (i, source) in r.payload.citedSources.indexed) {
    requireBasis(
      isUuidV4(source.ref) &&
          r.available(source.ref, source.version)?.payload is BasisSource,
      'invalid_reference',
      '$at/sourceRefs/$i',
    );
  }
  switch (r.payload) {
    case BasisRule(:final replacementRef?):
      requireBasis(
        isUuidV4(replacementRef) &&
            replacementRef != r.id &&
            r.latest(replacementRef) is BasisRule,
        'invalid_reference',
        '$at/replacementRef',
      );
    case BasisPending pending:
      _resolution(r, pending, at);
      _review(r, pending, at);
  }
}

/// Una resolución contra una regla cita una versión aceptada antes: la
/// regla nueva se acepta primero y se cita en otra preparación.
void _resolution(PersistedReferences r, BasisPending pending, String at) {
  final resolution = pending.resolution;
  if (resolution == null) return;
  final rule = parseRuleResolution(resolution);
  if (rule == null) return;
  requireBasis(
    r.accepted(rule.ref, rule.version)?.payload is BasisRule,
    'invalid_reference',
    '$at/resolution',
  );
}

void _review(PersistedReferences r, BasisPending pending, String at) {
  final link = pending.decisionReview;
  if (link != null) {
    final target = isUuidV4(link.ref)
        ? r.available(link.ref, link.version)?.payload
        : null;
    requireReviewTarget(pending, target, '$at/decisionReview');
  }
  final prior = r.prior;
  if (prior is BasisPending) {
    requireStableReview(prior, pending, '$at/decisionReview');
  }
}

/// La versión citada por una revisión es una regla activa en esa versión
/// y con exactamente el mismo ámbito que el pendiente.
void requireReviewTarget(
  BasisPending pending,
  BasisPayload? target,
  String at,
) => requireBasis(
  target is BasisRule &&
      target.lifecycle == BasisRuleLifecycle.active &&
      target.scope.sameAs(pending.scope),
  'invalid_reference',
  at,
);

/// El tipo ordinario o de revisión no cambia; en una revisión vinculada
/// tampoco cambian la regla ni su versión. El ámbito queda fijo porque
/// [requireReviewTarget] lo exige igual al de esa versión inmutable.
void requireStableReview(BasisPending prior, BasisPending next, String at) {
  final before = prior.decisionReview;
  final after = next.decisionReview;
  requireBasis((before == null) == (after == null), 'invalid_reference', at);
  if (before == null || after == null) return;
  requireBasis(
    before.ref == after.ref && before.version == after.version,
    'invalid_reference',
    at,
  );
}
