import 'dart:convert';
import 'dart:io';

import 'cli_response.dart';

const _internalFailureExitCode = 70;
const _internalFailureDiagnostic =
    'shipflow: no se pudo completar la operación.\n';

/// Escribe [response] en su canal y devuelve el código de salida del proceso.
///
/// Si el canal requerido falla, la respuesta ya no se puede entregar: avisa
/// por el otro canal, si todavía acepta escritura, y devuelve 70.
Future<int> emitCliResponse(
  CliResponse response, {
  required IOSink standardOut,
  required IOSink standardError,
}) async {
  final (required, alternate) = switch (response.channel) {
    CliOutputChannel.stdout => (standardOut, standardError),
    CliOutputChannel.stderr => (standardError, standardOut),
  };
  if (await _deliver(required, response.payload)) return response.exitCode;
  await _deliver(alternate, _internalFailureDiagnostic);
  return _internalFailureExitCode;
}

Future<bool> _deliver(IOSink sink, String payload) async {
  try {
    sink.add(utf8.encode(payload));
    await sink.flush();
    return true;
  } on Object {
    return false;
  }
}
