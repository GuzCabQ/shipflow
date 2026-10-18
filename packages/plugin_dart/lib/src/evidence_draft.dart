import 'dart:collection';

/// Una evidencia antes de tener ID: los IDs dependen del orden de todas.
final class EvidenceDraft {
  const EvidenceDraft({
    required this.kind,
    required this.path,
    required this.value,
    required this.fingerprint,
  });

  final String kind;
  final String path;
  final String value;
  final String fingerprint;
}

/// Un conflicto que todavía apunta a borradores, no a IDs.
final class ConflictDraft {
  ConflictDraft(this.code, this.message, List<EvidenceDraft> evidence)
    : evidence = List.unmodifiable(evidence);

  final String code;
  final String message;
  final List<EvidenceDraft> evidence;
}

/// Asigna `e0001`, `e0002`… en orden de ruta, tipo y valor, para que el
/// orden en que se observó no cambie ningún ID.
Map<EvidenceDraft, String> assignEvidenceIds(Iterable<EvidenceDraft> drafts) {
  final sorted = [...drafts]..sort(_byPathKindValue);
  final ids = LinkedHashMap<EvidenceDraft, String>.identity();
  for (final (index, draft) in sorted.indexed) {
    ids[draft] = 'e${(index + 1).toString().padLeft(4, '0')}';
  }
  return ids;
}

int _byPathKindValue(EvidenceDraft a, EvidenceDraft b) {
  for (final order in [
    a.path.compareTo(b.path),
    a.kind.compareTo(b.kind),
    a.value.compareTo(b.value),
    a.fingerprint.compareTo(b.fingerprint),
  ]) {
    if (order != 0) return order;
  }
  return 0;
}
