import '../recognition/recognition_json.dart';
import 'assessment_enums.dart';
import 'assessment_snapshot.dart';

/// Una conexión gruesa entre unidades: la agregación mecánica de
/// referencias locales comprobadas, con sus afirmaciones como evidencia. No
/// es impacto, criticidad ni una decisión de arquitectura.
final class AssessmentConnection {
  AssessmentConnection({
    required this.sourceUnitId,
    required this.targetUnitId,
    required this.relation,
    required this.condition,
    required List<String> claimIds,
  }) : claimIds = List.unmodifiable(claimIds);

  factory AssessmentConnection.fromJson(Map<String, Object?> json) =>
      AssessmentConnection(
        sourceUnitId: json['sourceUnitId']! as String,
        targetUnitId: json['targetUnitId']! as String,
        relation: AssessmentRelation.fromWireName(json['relation']! as String),
        condition: AssessmentCondition.fromWireName(
          json['condition']! as String,
        ),
        claimIds: readStrings(json['claimIds']),
      );

  final String sourceUnitId;
  final String targetUnitId;
  final AssessmentRelation relation;
  final AssessmentCondition condition;
  final List<String> claimIds;

  Map<String, Object?> toJson() => {
    'sourceUnitId': sourceUnitId,
    'targetUnitId': targetUnitId,
    'relation': relation.toWireName(),
    'condition': condition.toWireName(),
    'claimIds': claimIds,
  };
}

/// Las conexiones de [snapshot]: sólo afirmaciones locales, agrupadas por
/// unidad de origen, unidad de destino, relación y condición. Las externas
/// y las no resueltas no son aristas locales. Ordenadas por esa clave.
List<AssessmentConnection> projectAssessment(AssessmentSnapshot snapshot) {
  final units = {for (final f in snapshot.files) f.id: f.unitId};
  final grouped = <String, List<String>>{};
  final keys =
      <String, (String, String, AssessmentRelation, AssessmentCondition)>{};
  for (final claim in snapshot.claims) {
    if (claim.resolution != AssessmentResolution.local) continue;
    final key = (
      units[claim.sourceFileId]!,
      claim.targetUnitId!,
      claim.relation,
      claim.condition,
    );
    final text =
        '${key.$1}\u0000${key.$2}\u0000${key.$3.toWireName()}'
        '\u0000${key.$4.toWireName()}';
    keys[text] = key;
    grouped.putIfAbsent(text, () => []).add(claim.id);
  }
  return [
    for (final text in grouped.keys.toList()..sort())
      AssessmentConnection(
        sourceUnitId: keys[text]!.$1,
        targetUnitId: keys[text]!.$2,
        relation: keys[text]!.$3,
        condition: keys[text]!.$4,
        claimIds: grouped[text]!..sort(),
      ),
  ];
}

/// La diferencia mecánica entre dos observaciones por identidad de
/// afirmación. No calcula similitud ni autoriza retirar nada: no observada
/// ahora sólo dice que el inventario completo de ahora no la contiene.
final class AssessmentComparison {
  const AssessmentComparison({
    required this.addedReferences,
    required this.repeatedReferences,
    required this.notObservedNow,
  });

  factory AssessmentComparison.fromJson(Map<String, Object?> json) =>
      AssessmentComparison(
        addedReferences: json['addedReferences']! as int,
        repeatedReferences: json['repeatedReferences']! as int,
        notObservedNow: json['notObservedNow']! as int,
      );

  final int addedReferences;
  final int repeatedReferences;
  final int notObservedNow;

  Map<String, Object?> toJson() => {
    'addedReferences': addedReferences,
    'repeatedReferences': repeatedReferences,
    'notObservedNow': notObservedNow,
  };
}

/// La comparación de [current] con [previous], o null si no son
/// comparables: ambas completas, con inventario completo, sobre el mismo
/// contexto citado y el mismo contrato del productor. Una lectura parcial
/// nunca produce cuentas de desaparición.
AssessmentComparison? compareAssessments(
  AssessmentSnapshot previous,
  AssessmentSnapshot current,
) {
  bool whole(AssessmentSnapshot s) =>
      s.coverage == AssessmentCoverage.complete && s.inventoryComplete;
  if (!whole(previous) ||
      !whole(current) ||
      previous.contextDigest != current.contextDigest ||
      previous.producer.contract != current.producer.contract) {
    return null;
  }
  final before = {for (final c in previous.claims) c.id};
  final now = {for (final c in current.claims) c.id};
  return AssessmentComparison(
    addedReferences: now.difference(before).length,
    repeatedReferences: now.intersection(before).length,
    notObservedNow: before.difference(now).length,
  );
}
