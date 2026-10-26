import 'dart:convert';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';

import 'canonical_json.dart';
import 'context_document_shape.dart';
import 'context_recognition_shape.dart';
import 'context_response_shape.dart';
import 'strict_json.dart';

/// Los máximos inclusivos, en bytes reales con su salto final.
const maxProjectBytes = 4194304;
const maxSettingsBytes = 16384;
const maxTransactionBytes = 65536;
const maxResponseBytes = 4194304;

/// Lee y escribe los documentos del contexto persistente. Cada lectura es
/// JSON estricto, después la forma del schema congelado y después las
/// reglas semánticas; nunca convierte un mapa arbitrario por cast.
final class ContextCodec {
  const ContextCodec();

  /// `shipflow/project.json`, con su digest comprobado.
  ProjectContext decodeProject(List<int> bytes) {
    final json = decodeStrictJson(bytes, maxBytes: maxProjectBytes);
    shapeProject(json);
    final context = _semantic(() => ProjectContext.fromJson(_map(json)));
    requireSemantic(
      digest(context.recognition) == context.observationDigest,
      'digest_mismatch',
    );
    return context;
  }

  /// Un reconocimiento portable suelto, con las mismas reglas que dentro
  /// de un documento.
  PortableRecognition decodeRecognition(List<int> bytes) {
    final json = decodeStrictJson(bytes, maxBytes: maxProjectBytes);
    shapeRecognition(json, '');
    return _semantic(() => PortableRecognition.fromJson(_map(json)));
  }

  LocalSettings decodeSettings(List<int> bytes) {
    final json = decodeStrictJson(bytes, maxBytes: maxSettingsBytes);
    shapeSettings(json);
    return _semantic(() => LocalSettings.fromJson(_map(json)));
  }

  ContextTransaction decodeTransaction(List<int> bytes) {
    final json = decodeStrictJson(bytes, maxBytes: maxTransactionBytes);
    shapeTransaction(json);
    return _semantic(() => ContextTransaction.fromJson(_map(json)));
  }

  /// Una respuesta schema 3 de init o doctor.
  ContextOperationResult decodeResponse(List<int> bytes) {
    final json = decodeStrictJson(bytes, maxBytes: maxResponseBytes);
    shapeResponse(json);
    return _semantic(() => ContextOperationResult.fromJson(_map(json)));
  }

  /// Comprueba la forma de una respuesta de reconocimiento schema 3.
  void checkDryRun(List<int> bytes) {
    shapeDryRun(decodeStrictJson(bytes, maxBytes: maxResponseBytes));
  }

  /// El documento legible de disco, o un rechazo si no cabe entero.
  List<int> encodeProject(ProjectContext context) =>
      _document(context.toJson(), maxProjectBytes);

  List<int> encodeSettings(LocalSettings settings) =>
      _document(settings.toJson(), maxSettingsBytes);

  List<int> encodeTransaction(ContextTransaction transaction) =>
      _document(transaction.toJson(), maxTransactionBytes);

  /// Los bytes canónicos que cubre el digest.
  List<int> canonicalRecognition(PortableRecognition recognition) =>
      canonicalJson(recognition.toJson());

  /// SHA-256 hexadecimal de [canonicalRecognition].
  String digest(PortableRecognition recognition) =>
      sha256.convert(canonicalRecognition(recognition)).toString();
}

/// Dos espacios y salto final; el digest no depende de esta forma.
List<int> _document(Map<String, Object?> json, int maxBytes) {
  final bytes = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  requireSemantic(bytes.length <= maxBytes, 'too_large');
  return bytes;
}

Map<String, Object?> _map(Object? json) => json! as Map<String, Object?>;

/// [build], con cualquier invariante incumplida como rechazo semántico.
T _semantic<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError {
    throw const ContextFormatException(
      ContextFormatLayer.semantic,
      'invalid_value',
    );
  }
}
