enum CliOutputChannel { stdout, stderr }

final class CliResponse {
  const CliResponse({
    required this.exitCode,
    required this.channel,
    required this.payload,
  });

  final int exitCode;
  final CliOutputChannel channel;

  /// La salida completa; termina en exactamente una nueva línea.
  final String payload;
}
