import 'dart:convert';

import 'package:core/core.dart';

import 'cli_application.dart';

const _recognitionType = 'init_dry_run';
const _unrecognizedExitCode = 65;
const _invalidRootExitCode = 66;

/// El código de salida de cada estado: un reconocimiento no verde sigue
/// siendo un reporte válido.
int recognitionExitCode(RecognitionStatus status) => switch (status) {
  RecognitionStatus.recognized => successExitCode,
  RecognitionStatus.ambiguous ||
  RecognitionStatus.unsupported => _unrecognizedExitCode,
  RecognitionStatus.invalidRoot => _invalidRootExitCode,
};

/// La respuesta JSON de [report], con su envoltura y el salto final, si
/// cabe en [maxBytes] UTF-8; si no, null y nunca un fragmento. Mide lo que
/// el encoder escribe, escapes incluidos, y deja de retener al pasarse.
String? encodeRecognitionWithinLimit(
  RecognitionReport report, {
  required int maxBytes,
}) {
  final exitCode = recognitionExitCode(report.status);
  final sink = _BoundedSink(maxBytes);
  try {
    const JsonEncoder().startChunkedConversion(sink)
      ..add({
        'schemaVersion': schemaVersion,
        'type': _recognitionType,
        ...report.toJson(),
        'exitCode': exitCode,
      })
      ..close();
    sink.add('\n');
  } on _Overflow {
    return null;
  }
  return sink.text;
}

final class _Overflow implements Exception {
  const _Overflow();
}

/// Acumula lo escrito mientras quepa; el primer trozo que no cabe corta.
final class _BoundedSink implements Sink<String> {
  _BoundedSink(this.maxBytes);

  final int maxBytes;
  final _buffer = StringBuffer();
  var _bytes = 0;

  @override
  void add(String chunk) {
    _bytes += utf8Length(chunk);
    if (_bytes > maxBytes) throw const _Overflow();
    _buffer.write(chunk);
  }

  @override
  void close() {}

  String get text => _buffer.toString();
}
