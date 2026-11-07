import 'dart:convert';

import 'basis_enums.dart';
import 'basis_model.dart';
import 'basis_payload.dart';
import 'basis_proposed_change.dart';
import 'basis_response_parts.dart';
import 'basis_result.dart';
import 'basis_validation.dart';

/// La coherencia de una respuesta que su schema no expresa: los targets
/// de revisión deduplicados en orden de ID y versión, completos cuando la
/// selección lo es, idénticos a la regla vigente si coinciden, vacíos en
/// la historia; los cambios propuestos sólo en un borrador y con su efecto
/// real; una consulta sin efectos y una publicación identificada.
void validateBasisResponse(BasisResponse r) {
  _targets(r);
  _copies(r);
  _proposed(r);
  requireBasis(
    r.operation != BasisOperation.show ||
        (!r.published && r.changedFiles.isEmpty),
    'invalid_schema',
    'published',
  );
  requireBasis(
    !r.published || r.basisDigest != null,
    'invalid_schema',
    'basisDigest',
  );
}

void _targets(BasisResponse r) {
  final keys = [for (final t in r.reviewTargets) _key(t)];
  final sorted = [...r.reviewTargets]..sort(compareBasisVersions);
  requireBasis(
    keys.toSet().length == keys.length &&
        _same(keys, [for (final t in sorted) _key(t)]),
    'invalid_schema',
    'reviewTargets',
  );
  requireBasis(
    r.history.isEmpty || r.reviewTargets.isEmpty,
    'invalid_schema',
    'reviewTargets',
  );
  if (r.selection.complete && r.history.isEmpty) {
    requireBasis(
      _needed(r.pending).containsAll(keys) &&
          keys.toSet().containsAll(_needed(r.pending)),
      'invalid_schema',
      'reviewTargets',
    );
  }
}

/// Cada cambio propuesto declara el efecto que su versión tiene, en una
/// cadena válida; sólo un borrador sin aceptar ni historia los lleva.
void _proposed(BasisResponse r) {
  for (final p in r.proposedChanges) {
    final v = p.version;
    requireBasis(
      v.previousVersion == null
          ? v.version == 1
          : v.previousVersion == v.version - 1,
      'invalid_schema',
      'proposedChanges',
    );
    requireBasis(
      p.change == changeKindOf(v),
      'invalid_schema',
      'proposedChanges',
    );
  }
  requireBasis(
    r.proposedChanges.isEmpty ||
        (r.draftDigest != null && !r.published && r.history.isEmpty),
    'invalid_schema',
    'proposedChanges',
  );
}

/// Un target que coincide con una regla vigente seleccionada es la misma
/// versión byte a byte, aunque cumpla otro papel.
void _copies(BasisResponse r) {
  final targets = {for (final t in r.reviewTargets) _key(t): t};
  for (final selected in r.selected) {
    final target = targets[_key(selected)];
    requireBasis(
      target == null ||
          jsonEncode(target.toJson()) == jsonEncode(selected.toJson()),
      'invalid_schema',
      'reviewTargets',
    );
  }
}

/// Orden de los targets: ID por unidades de código y versión ascendente.
int compareBasisVersions(BasisRecordVersion a, BasisRecordVersion b) {
  final id = a.id.compareTo(b.id);
  return id != 0 ? id : a.version.compareTo(b.version);
}

String _key(BasisRecordVersion v) => '${v.id}@${v.version}';

bool _same(List<String> a, List<String> b) =>
    a.length == b.length &&
    [for (var i = 0; i < a.length; i++) i].every((i) => a[i] == b[i]);

/// Las versiones citadas por los pendientes abiertos de revisión.
Set<String> _needed(List<BasisRecordVersion> pending) => {
  for (final p in pending)
    if (p.payload case BasisPending(
      :final decisionReview?,
      :final status,
    ) when status == BasisPendingStatus.open)
      '${decisionReview.ref}@${decisionReview.version}',
};
