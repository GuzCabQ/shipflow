import 'cli_response.dart';

const internalFailureExitCode = 70;
const internalFailureMessage = 'no se pudo completar la operación';
const internalFailureDiagnostic = 'shipflow: $internalFailureMessage.\n';

/// La respuesta pública ante un fallo interno: no nombra la excepción, la
/// traza ni ninguna ruta.
CliResponse internalFailure({required bool json}) => json
    ? CliResponse(
        exitCode: internalFailureExitCode,
        channel: CliOutputChannel.stdout,
        payload:
            '{"schemaVersion":1,"type":"error","code":"internal_error",'
            '"message":"$internalFailureMessage",'
            '"exitCode":$internalFailureExitCode}\n',
      )
    : const CliResponse(
        exitCode: internalFailureExitCode,
        channel: CliOutputChannel.stderr,
        payload: internalFailureDiagnostic,
      );
