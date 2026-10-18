import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'checksum.dart';
import 'promotion_layout.dart';

const versionTimeout = Duration(seconds: 30);

/// La versión que un ejecutable informa, o null si no responde el contrato.
typedef VersionReader = Future<String?> Function(File executable);

Future<String?> reportedVersion(
  File executable, {
  Duration timeout = versionTimeout,
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable.path,
      ['--version'],
      environment: const {},
      includeParentEnvironment: false,
    );
  } on ProcessException {
    return null;
  }
  final stdoutText = process.stdout.transform(utf8.decoder).join();
  final stderrText = process.stderr.transform(utf8.decoder).join();
  final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    return null;
  }
  final out = await stdoutText;
  final err = await stderrText;
  final match = RegExp(r'^shipflow (\S+)\n$').firstMatch(out);
  if (exitCode != 0 || err.isNotEmpty || match == null) return null;
  return match.group(1);
}

Future<void> requireVersion(
  File executable,
  String version,
  VersionReader readVersion,
) async {
  if (await readVersion(executable) != version) {
    throw PromotionException(
      '${executable.path} no responde «shipflow $version» a --version.',
    );
  }
}

Future<String> sha256Of(File file) async {
  try {
    return (await computeSha256(file)).sha256;
  } on ChecksumException catch (error) {
    throw PromotionException(error.message);
  }
}

Future<void> makeExecutable(File file) async {
  final result = await Process.run('chmod', ['0755', file.path]);
  if (result.exitCode != 0) {
    throw PromotionException(
      'no se pudo marcar ${file.path} como ejecutable: ${result.stderr}',
    );
  }
}
