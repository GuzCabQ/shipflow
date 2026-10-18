import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'checksum.dart';
import 'promotion_layout.dart';

const versionTimeout = Duration(seconds: 30);

/// La versión que un ejecutable informa, o null si no responde el contrato.
typedef VersionReader = Future<String?> Function(File executable);

/// Pregunta `--version` a [executable] con [timeout] para terminar y cerrar su
/// salida. Si no llega, lo mata y espera a que termine antes de volver.
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
  final out = _Capture(process.stdout);
  final err = _Capture(process.stderr);
  final int exitCode;
  try {
    (exitCode, _, _) = await (
      process.exitCode,
      out.done,
      err.done,
    ).wait.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await (out.abandon(), err.abandon()).wait;
    return null;
  }
  final match = RegExp(r'^shipflow (\S+)\n$').firstMatch(out.text ?? '');
  if (exitCode != 0 || err.text != '' || match == null) return null;
  return match.group(1);
}

/// Junta lo que emite un stream de un proceso.
final class _Capture {
  _Capture(Stream<List<int>> stream) {
    _subscription = stream.listen(
      _bytes.addAll,
      onDone: _done.complete,
      onError: _done.completeError,
      cancelOnError: true,
    );
  }

  final _bytes = <int>[];
  final _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;

  Future<void> get done => _done.future;

  /// Lo emitido, o null si no es UTF-8: no hace fallar la lectura, sólo deja
  /// de cumplir el contrato.
  String? get text {
    try {
      return utf8.decode(_bytes);
    } on FormatException {
      return null;
    }
  }

  /// Deja de leer; un nieto que heredó el pipe no retiene al llamador.
  Future<void> abandon() => _subscription.cancel();
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
