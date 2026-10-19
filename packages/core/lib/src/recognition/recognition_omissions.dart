import 'recognition_enums.dart';
import 'recognition_json.dart';

/// Un árbol que no se recorrió por una regla de alcance. No cuenta archivos
/// ni afirma que lo de adentro sea generado, seguro o irrelevante.
final class RecognitionOmission {
  RecognitionOmission({
    required this.path,
    required this.rule,
    required List<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds) {
    if (rule != OmissionRule.baselineExclusion && evidenceIds.isEmpty) {
      throw ArgumentError.value(
        path,
        'evidenceIds',
        'la regla ${rule.toWireName()} necesita la evidencia que la justifica',
      );
    }
  }

  factory RecognitionOmission.fromJson(Map<String, Object?> json) =>
      RecognitionOmission(
        path: json['path']! as String,
        rule: OmissionRule.fromWireName(json['rule']! as String),
        evidenceIds: readStrings(json['evidenceIds']),
      );

  /// Relativa a la raíz resuelta.
  final String path;
  final OmissionRule rule;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'path': path,
    'rule': rule.toWireName(),
    'evidenceIds': evidenceIds,
  };
}
