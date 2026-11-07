import '../recognition/recognition_json.dart';
import 'basis_model.dart';

/// Lo que aplica a una consulta: reglas y fuentes vigentes, propuestas y
/// pendientes, y las versiones exactas que citan las revisiones abiertas.
/// [excludedCount] cuenta sólo lo que quedó fuera por ámbito.
final class BasisSelection {
  BasisSelection({
    required List<BasisRecordVersion> selected,
    required List<BasisRecordVersion> pending,
    required List<BasisRecordVersion> reviewTargets,
    required this.excludedCount,
  }) : selected = List.unmodifiable(selected),
       pending = List.unmodifiable(pending),
       reviewTargets = List.unmodifiable(reviewTargets);

  factory BasisSelection.fromJson(Map<String, Object?> json) => BasisSelection(
    selected: readObjects(json['selected'], BasisRecordVersion.fromJson),
    pending: readObjects(json['pending'], BasisRecordVersion.fromJson),
    reviewTargets: readObjects(
      json['reviewTargets'],
      BasisRecordVersion.fromJson,
    ),
    excludedCount: json['excludedCount']! as int,
  );

  final List<BasisRecordVersion> selected;
  final List<BasisRecordVersion> pending;

  /// Históricas: una revisión pendiente no convierte su versión en regla
  /// vigente ni traslada su autoridad a otra versión.
  final List<BasisRecordVersion> reviewTargets;
  final int excludedCount;

  Map<String, Object?> toJson() => {
    'selected': [for (final r in selected) r.toJson()],
    'pending': [for (final r in pending) r.toJson()],
    'reviewTargets': [for (final r in reviewTargets) r.toJson()],
    'excludedCount': excludedCount,
  };
}

/// Por qué una propuesta no se puede preparar: un código del catálogo y la
/// ubicación en la entrada, nunca el contenido.
final class BasisValidationIssue {
  BasisValidationIssue({required this.code, required this.at});

  factory BasisValidationIssue.fromJson(Map<String, Object?> json) =>
      BasisValidationIssue(
        code: json['code']! as String,
        at: json['at']! as String,
      );

  final String code;
  final String at;

  Map<String, Object?> toJson() => {'code': code, 'at': at};
}
