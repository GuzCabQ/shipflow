import 'dart:collection';

import 'derived_observation_budget.dart';

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

/// Un conflicto que todavía apunta a borradores, no a IDs. Se crea con
/// [conflictDraft], que lo cobra antes de unir su mensaje.
final class ConflictDraft {
  ConflictDraft(this.code, this.message, List<EvidenceDraft> evidence)
    : evidence = List.unmodifiable(evidence);

  final String code;
  final String message;
  final List<EvidenceDraft> evidence;
}

/// Cobra a [budget] la fila del conflicto, una posición por cada evidencia
/// que cita y las partes de su mensaje, y sólo entonces lo une. Los bytes de
/// los IDs citados se cobran al proyectarlo, cuando ya existen.
ConflictDraft conflictDraft(
  DerivedObservationBudget budget,
  String code,
  List<String> messageParts,
  List<EvidenceDraft> evidence,
) {
  budget.charge(items: 1 + evidence.length, texts: [code, ...messageParts]);
  return ConflictDraft(code, messageParts.join(), evidence);
}

/// Asigna `e0001`, `e0002`… en orden de ruta, tipo y valor, para que el
/// orden en que se observó no cambie ningún ID. Cada ID se cobra a [budget]
/// al asignarse; la evidencia ya se cobró al observarse.
Map<EvidenceDraft, String> assignEvidenceIds(
  Iterable<EvidenceDraft> drafts,
  DerivedObservationBudget budget,
) {
  final sorted = [...drafts]..sort(_byPathKindValue);
  final ids = LinkedHashMap<EvidenceDraft, String>.identity();
  for (final (index, draft) in sorted.indexed) {
    final id = 'e${(index + 1).toString().padLeft(4, '0')}';
    budget.charge(texts: [id]);
    ids[draft] = id;
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
