/// Una observación localizada en la raíz reconocida y su huella.
final class RecognitionEvidence {
  const RecognitionEvidence({
    required this.id,
    required this.kind,
    required this.path,
    required this.value,
    required this.fingerprint,
  });

  factory RecognitionEvidence.fromJson(Map<String, Object?> json) =>
      RecognitionEvidence(
        id: json['id']! as String,
        kind: json['kind']! as String,
        path: json['path']! as String,
        value: json['value']! as String,
        fingerprint: json['fingerprint']! as String,
      );

  final String id;
  final String kind;

  /// Relativa a la raíz resuelta.
  final String path;
  final String value;
  final String fingerprint;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'path': path,
    'value': value,
    'fingerprint': fingerprint,
  };
}
