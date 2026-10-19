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
/// [admitConflict], que lo admite antes de construir cada parte.
final class ConflictDraft {
  ConflictDraft(this.code, this.message, List<EvidenceDraft> evidence)
    : evidence = List.unmodifiable(evidence);

  final String code;
  final String message;
  final List<EvidenceDraft> evidence;
}

/// Admite un conflicto y lo construye de a poco: primero su fila, con
/// [code] y [head]; después, de a una, cada fuente de [sources] —una
/// posición de referencia y su parte del mensaje, con el separador—, antes
/// de agregarla. Ninguna parte ni referencia se construye sin admitirse, y
/// el primero que no cabe detiene el recorrido. Los bytes de los IDs
/// citados se cobran al proyectarlo, cuando ya existen.
ConflictDraft admitConflict<S>(
  DerivedObservationBudget budget,
  String code,
  String head,
  Iterable<S> sources, {
  required EvidenceDraft Function(S source) evidenceOf,
  String Function(S source)? partOf,
  String separator = ', ',
}) {
  budget.charge(items: 1, texts: [code, head]);
  final message = StringBuffer(head);
  final evidence = <EvidenceDraft>[];
  for (final (index, source) in sources.indexed) {
    final part = partOf == null
        ? ''
        : '${index > 0 ? separator : ''}${partOf(source)}';
    budget.charge(items: 1, texts: [part]);
    message.write(part);
    evidence.add(evidenceOf(source));
  }
  return ConflictDraft(code, message.toString(), evidence);
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
