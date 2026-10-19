import 'recognition_enums.dart';

/// Una observación localizada en la raíz reconocida y su huella.
final class RecognitionEvidence {
  const RecognitionEvidence({
    required this.id,
    required this.kind,
    required this.role,
    required this.label,
    required this.path,
    required this.value,
    required this.fingerprint,
  });

  factory RecognitionEvidence.fromJson(Map<String, Object?> json) =>
      RecognitionEvidence(
        id: json['id']! as String,
        kind: json['kind']! as String,
        role: EvidenceRole.fromWireName(json['role']! as String),
        label: json['label']! as String,
        path: json['path']! as String,
        value: json['value']! as String,
        fingerprint: json['fingerprint']! as String,
      );

  final String id;

  /// Opaco para todo lo que no sea el plugin que lo produjo.
  final String kind;
  final EvidenceRole role;

  /// Cómo nombrarla ante una persona, provista por el plugin.
  final String label;

  /// Relativa a la raíz resuelta.
  final String path;
  final String value;
  final String fingerprint;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'role': role.toWireName(),
    'label': label,
    'path': path,
    'value': value,
    'fingerprint': fingerprint,
  };
}
