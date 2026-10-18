import 'dart:convert';
import 'dart:io';

enum ChecksumFailure { unavailable, failed, unreadable }

final class ChecksumException implements Exception {
  const ChecksumException(this.kind, this.message);

  final ChecksumFailure kind;
  final String message;

  @override
  String toString() => message;
}

final class ChecksumEvidence {
  const ChecksumEvidence({required this.sha256, required this.tool});

  final String sha256;

  /// La herramienta del sistema que produjo [sha256].
  final String tool;
}

final class ChecksumTool {
  const ChecksumTool({required this.executable, required this.arguments});

  final String executable;
  final List<String> arguments;

  String get description => [executable, ...arguments].join(' ');
}

/// La herramienta de SHA-256 de cada plataforma soportada; ninguna se
/// sustituye por otra ni por una implementación propia.
ChecksumTool checksumToolFor(String operatingSystem) =>
    switch (operatingSystem) {
      'macos' => const ChecksumTool(
        executable: 'shasum',
        arguments: ['-a', '256'],
      ),
      'linux' => const ChecksumTool(executable: 'sha256sum', arguments: []),
      _ => throw ChecksumException(
        ChecksumFailure.unavailable,
        'no hay herramienta de SHA-256 declarada para $operatingSystem.',
      ),
    };

Future<ChecksumEvidence> computeSha256(File artifact) =>
    computeSha256With(artifact, checksumToolFor(Platform.operatingSystem));

Future<ChecksumEvidence> computeSha256With(
  File artifact,
  ChecksumTool tool,
) async {
  final ProcessResult result;
  try {
    result = await Process.run(tool.executable, [
      ...tool.arguments,
      artifact.path,
    ]);
  } on ProcessException catch (error) {
    throw ChecksumException(
      ChecksumFailure.unavailable,
      'no se pudo ejecutar «${tool.description}»: ${error.message}.',
    );
  }
  if (result.exitCode != 0) {
    throw ChecksumException(
      ChecksumFailure.failed,
      '«${tool.description}» terminó con código ${result.exitCode}: '
              '${result.stderr}'
          .trim(),
    );
  }
  final lines = const LineSplitter().convert(result.stdout as String);
  final match = lines.length == 1
      ? RegExp(r'^([0-9a-f]{64}) [ *](.+)$').firstMatch(lines.single)
      : null;
  if (match == null || match.group(2) != artifact.path) {
    throw ChecksumException(
      ChecksumFailure.unreadable,
      '«${tool.description}» no devolvió un único digest de ${artifact.path}.',
    );
  }
  return ChecksumEvidence(sha256: match.group(1)!, tool: tool.description);
}
