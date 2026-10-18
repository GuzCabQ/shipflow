import 'recognition_json.dart';

/// Evidencias incompatibles que el reconocimiento no resuelve por inferencia.
final class RecognitionConflict {
  RecognitionConflict({
    required this.code,
    required this.message,
    required List<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds);

  factory RecognitionConflict.fromJson(Map<String, Object?> json) =>
      RecognitionConflict(
        code: json['code']! as String,
        message: json['message']! as String,
        evidenceIds: readStrings(json['evidenceIds']),
      );

  final String code;
  final String message;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'evidenceIds': evidenceIds,
  };
}

/// Algo que no se pudo inspeccionar. Si es bloqueante, el resultado no puede
/// ser un reconocimiento completo.
final class RecognitionLimitation {
  const RecognitionLimitation({
    required this.code,
    required this.message,
    required this.path,
    required this.blocking,
  });

  factory RecognitionLimitation.fromJson(Map<String, Object?> json) =>
      RecognitionLimitation(
        code: json['code']! as String,
        message: json['message']! as String,
        path: json['path'] as String?,
        blocking: json['blocking']! as bool,
      );

  final String code;
  final String message;

  /// Relativa a la raíz resuelta, o null si no hay una ruta a la que apuntar.
  final String? path;
  final bool blocking;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'path': path,
    'blocking': blocking,
  };
}
