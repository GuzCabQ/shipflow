import 'cli_application.dart';
import 'cli_response.dart';

const internalFailureExitCode = 70;
const internalFailureMessage = 'no se pudo completar la operación';
const internalFailureDiagnostic = '$cliName: $internalFailureMessage.\n';

/// La respuesta pública ante un fallo interno: no nombra la excepción, la
/// traza ni ninguna ruta.
CliResponse internalFailure({required bool json}) => json
    ? jsonResponse(internalFailureExitCode, {
        'schemaVersion': schemaVersion,
        'type': errorResponseType,
        'code': 'internal_error',
        'message': internalFailureMessage,
        'exitCode': internalFailureExitCode,
      })
    : const CliResponse(
        exitCode: internalFailureExitCode,
        channel: CliOutputChannel.stderr,
        payload: internalFailureDiagnostic,
      );
