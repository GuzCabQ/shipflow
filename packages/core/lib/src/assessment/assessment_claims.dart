import '../context/context_validation.dart';
import 'assessment_enums.dart';

/// Dónde está la directiva en el contenido sellado: offsets y longitud en
/// unidades UTF-16, línea y columna desde 1. No promete columnas visuales.
final class AssessmentEvidence {
  AssessmentEvidence({
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
  }) {
    requireSemantic(
      offset >= 0 && length >= 1 && line >= 1 && column >= 1,
      'evidence',
      '/claims',
    );
  }

  factory AssessmentEvidence.fromJson(Map<String, Object?> json) =>
      AssessmentEvidence(
        offset: json['offset']! as int,
        length: json['length']! as int,
        line: json['line']! as int,
        column: json['column']! as int,
      );

  final int offset;
  final int length;
  final int line;
  final int column;

  Map<String, Object?> toJson() => {
    'offset': offset,
    'length': length,
    'line': line,
    'column': column,
  };
}

/// Metadatos inertes del plugin: core los conserva sin interpretar sus
/// palabras. La condición sólo en forma normalizada segura, o null.
final class AssessmentSourceMetadata {
  const AssessmentSourceMetadata({
    required this.directive,
    required this.conditionText,
  });

  factory AssessmentSourceMetadata.fromJson(Map<String, Object?> json) =>
      AssessmentSourceMetadata(
        directive: json['directive']! as String,
        conditionText: json['conditionText'] as String?,
      );

  final String directive;
  final String? conditionText;

  Map<String, Object?> toJson() => {
    'directive': directive,
    'conditionText': conditionText,
  };
}

/// Una referencia observada en el código, con su testigo y su evidencia.
/// Local nombra el archivo y la unidad de destino; externa y no resuelta,
/// nunca; no resuelta, siempre su motivo. No hay afirmaciones negativas ni
/// normativas.
final class AssessmentClaim {
  AssessmentClaim({
    required this.id,
    required this.witnessId,
    required this.sourceFileId,
    required this.targetFileId,
    required this.targetUnitId,
    required this.targetLabel,
    required this.relation,
    required this.resolution,
    required this.reason,
    required this.condition,
    required this.groupId,
    required this.evidence,
    required this.sourceMetadata,
  }) {
    final local = resolution == AssessmentResolution.local;
    requireSemantic(
      local
          ? targetFileId != null && targetUnitId != null
          : targetFileId == null && targetUnitId == null,
      'claim_target',
      '/claims',
    );
    requireSemantic(
      (resolution == AssessmentResolution.unresolved) == (reason != null),
      'claim_reason',
      '/claims',
    );
  }

  factory AssessmentClaim.fromJson(Map<String, Object?> json) =>
      AssessmentClaim(
        id: json['id']! as String,
        witnessId: json['witnessId']! as String,
        sourceFileId: json['sourceFileId']! as String,
        targetFileId: json['targetFileId'] as String?,
        targetUnitId: json['targetUnitId'] as String?,
        targetLabel: json['targetLabel'] as String?,
        relation: AssessmentRelation.fromWireName(json['relation']! as String),
        resolution: AssessmentResolution.fromWireName(
          json['resolution']! as String,
        ),
        reason: json['reason'] as String?,
        condition: AssessmentCondition.fromWireName(
          json['condition']! as String,
        ),
        groupId: json['groupId']! as String,
        evidence: AssessmentEvidence.fromJson(
          json['evidence']! as Map<String, Object?>,
        ),
        sourceMetadata: AssessmentSourceMetadata.fromJson(
          json['sourceMetadata']! as Map<String, Object?>,
        ),
      );

  final String id;
  final String witnessId;
  final String sourceFileId;
  final String? targetFileId;
  final String? targetUnitId;

  /// Normalizado y seguro: una ruta interna o un nombre externo, nunca un
  /// literal crudo rechazado.
  final String? targetLabel;
  final AssessmentRelation relation;
  final AssessmentResolution resolution;
  final String? reason;
  final AssessmentCondition condition;

  /// Las alternativas de una misma directiva comparten grupo.
  final String groupId;
  final AssessmentEvidence evidence;
  final AssessmentSourceMetadata sourceMetadata;

  Map<String, Object?> toJson() => {
    'id': id,
    'witnessId': witnessId,
    'sourceFileId': sourceFileId,
    'targetFileId': targetFileId,
    'targetUnitId': targetUnitId,
    'targetLabel': targetLabel,
    'relation': relation.toWireName(),
    'resolution': resolution.toWireName(),
    'reason': reason,
    'condition': condition.toWireName(),
    'groupId': groupId,
    'evidence': evidence.toJson(),
    'sourceMetadata': sourceMetadata.toJson(),
  };
}
