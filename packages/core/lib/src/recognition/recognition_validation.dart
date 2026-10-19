import 'recognition_contribution.dart';
import 'recognition_enums.dart';
import 'recognition_relations.dart';

/// Rechaza con [ArgumentError] lo que un plugin no debe contribuir: IDs o
/// filas repetidas, referencias a evidencia o unidades inexistentes y
/// relaciones sin resolver que no tengan un diagnóstico donde ubicarlas.
void validateContribution(RecognitionContribution merged) {
  final (:evidenceIds, :unitIds) = _uniqueRows(merged);
  _referenced('evidenceIds', evidenceIds, [
    for (final c in merged.candidates) ...c.evidenceIds,
    for (final u in merged.units) ...u.evidenceIds,
    for (final c in merged.conflicts) ...c.evidenceIds,
    for (final r in merged.relations) ...r.evidenceIds,
    for (final o in merged.omissions) ...o.evidenceIds,
  ]);
  _referenced('targetUnitId', unitIds, [
    for (final r in merged.relations) ?r.targetUnitId,
  ]);
  for (final relation in merged.relations) {
    if (relation.status == RelationStatus.unresolved &&
        !_diagnosed(relation, merged)) {
      throw ArgumentError.value(
        relation.id,
        'relations',
        'una relación sin resolver necesita un diagnóstico de su ruta o de '
            'la fuente que la declara',
      );
    }
  }
}

/// Los IDs de evidencia y de unidad, tras comprobar que ninguna fila con
/// identidad se repite.
({Set<String> evidenceIds, Set<String> unitIds}) _uniqueRows(
  RecognitionContribution merged,
) {
  final evidenceIds = _unique('evidencia', merged.evidence.map((e) => e.id));
  final unitIds = _unique('unidad', merged.units.map((u) => u.id));
  _unique('candidato', merged.candidates.map((c) => c.id));
  _unique('relación', merged.relations.map((r) => r.id));
  _unique(
    'fuente candidata',
    merged.contextSources.map((s) => '${s.scopePath}\u0000${s.path}'),
  );
  _unique(
    'omisión',
    merged.omissions.map((o) => '${o.path}\u0000${o.rule.toWireName()}'),
  );
  return (evidenceIds: evidenceIds, unitIds: unitIds);
}

/// Un conflicto que cita su evidencia, o una limitación bloqueante en su
/// destino o en la fuente que la declara.
bool _diagnosed(RecognitionRelation relation, RecognitionContribution merged) {
  final cited = relation.evidenceIds.toSet();
  final paths = {
    ?relation.targetPath,
    for (final e in merged.evidence)
      if (cited.contains(e.id)) e.path,
  };
  return merged.conflicts.any((c) => c.evidenceIds.any(cited.contains)) ||
      merged.limitations.any((l) => l.blocking && paths.contains(l.path));
}

void _referenced(String field, Set<String> known, List<String> references) {
  for (final id in references) {
    if (!known.contains(id)) {
      throw ArgumentError.value(id, field, 'no existe ese ID');
    }
  }
}

Set<String> _unique(String what, Iterable<String> ids) {
  final seen = <String>{};
  for (final id in ids) {
    if (!seen.add(id)) {
      throw ArgumentError.value(id, 'id', '$what repetida o repetido');
    }
  }
  return seen;
}
