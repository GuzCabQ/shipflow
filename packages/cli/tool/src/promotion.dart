import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'checksum.dart';
import 'semver.dart';

const _installedName = 'shipflow';
const _candidateName = '.shipflow.candidate';
const _previousName = '.shipflow.previous';
const _manifestName = '.shipflow.promote.json';
const _manifestDraftName = '.shipflow.promote.json.tmp';
const _lockName = '.shipflow.promote.lock';

const _phaseStaging = 'staging';
const _phaseSwapping = 'swapping';
const _phaseCommitting = 'committing';

const _versionTimeout = Duration(seconds: 30);

final class PromotionRequest {
  const PromotionRequest({
    required this.artifact,
    required this.expectedSha256,
    required this.expectedVersion,
    required this.binDirectory,
  });

  final File artifact;
  final String expectedSha256;
  final String expectedVersion;
  final Directory binDirectory;
}

final class PromotionException implements Exception {
  const PromotionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reemplaza `shipflow` en [PromotionRequest.binDirectory] por el artefacto,
/// conservando el anterior hasta que el nuevo responda su versión.
///
/// El candidato se verifica antes de tocar el destino. Bajo el lock, primero
/// se reconcilia lo que una promoción interrumpida haya dejado y después se
/// promueve; ante cualquier fallo el destino vuelve a su estado previo.
Future<void> promote(PromotionRequest request) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(request.expectedSha256)) {
    throw PromotionException(
      '«${request.expectedSha256}» no es un SHA-256 en hexadecimal.',
    );
  }
  if (!isValidSemVer(request.expectedVersion)) {
    throw PromotionException('«${request.expectedVersion}» no es SemVer 2.0.');
  }
  final bin = request.binDirectory.absolute;
  _requireType(bin.path, FileSystemEntityType.directory, 'el bin-dir');
  _requireType(
    request.artifact.path,
    FileSystemEntityType.file,
    'el artefacto',
  );

  final digest = await _sha256(request.artifact);
  if (digest != request.expectedSha256) {
    throw PromotionException(
      'el SHA-256 de ${request.artifact.path} es $digest y se esperaba '
      '${request.expectedSha256}; la instalación no se tocó.',
    );
  }
  await _requireVersion(request.artifact, request.expectedVersion);

  for (final name in [
    _installedName,
    _candidateName,
    _previousName,
    _manifestName,
    _manifestDraftName,
    _lockName,
  ]) {
    _rejectLink('${bin.path}/$name');
  }

  final lock = await _acquireLock(bin);
  try {
    await _reconcile(bin);
    await _replace(bin, request, digest);
  } on FileSystemException catch (error) {
    throw PromotionException(
      'no se pudo modificar ${bin.path} '
      '(${error.osError?.message ?? error.message}); lo que haya quedado a '
      'medias conserva su manifiesto y se reconcilia en la próxima ejecución.',
    );
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

Future<void> _replace(
  Directory bin,
  PromotionRequest request,
  String digest,
) async {
  final installed = File('${bin.path}/$_installedName');
  final candidate = File('${bin.path}/$_candidateName');
  final previous = File('${bin.path}/$_previousName');

  String? previousVersion;
  String? previousSha256;
  if (installed.existsSync()) {
    previousSha256 = await _sha256(installed);
    previousVersion = await _reportedVersion(installed);
    if (previousVersion == null) {
      throw PromotionException(
        '${installed.path} no responde --version; sin una instalación '
        'verificable no hay a qué volver, así que no se reemplaza.',
      );
    }
    if (previousVersion == request.expectedVersion) {
      if (previousSha256 == digest) return;
      throw PromotionException(
        'ya está instalada la misma versión ${request.expectedVersion} con '
        'otros bytes; una build distinta necesita una versión distinguible.',
      );
    }
  }

  final manifest = <String, Object>{
    'schemaVersion': 1,
    'phase': _phaseStaging,
    'candidateVersion': request.expectedVersion,
    'candidateSha256': digest,
    if (previousVersion != null && previousSha256 != null) ...{
      'previousVersion': previousVersion,
      'previousSha256': previousSha256,
    },
  };
  _writeManifest(bin, manifest);
  try {
    await request.artifact.copy(candidate.path);
    await _makeExecutable(candidate);
    if (await _sha256(candidate) != digest) {
      throw const PromotionException(
        'la copia del candidato no conserva el SHA-256 verificado.',
      );
    }
    await _requireVersion(candidate, request.expectedVersion);

    _writeManifest(bin, {...manifest, 'phase': _phaseSwapping});
    if (installed.existsSync()) await installed.rename(previous.path);
    await candidate.rename(installed.path);
    await _requireVersion(installed, request.expectedVersion);

    _writeManifest(bin, {...manifest, 'phase': _phaseCommitting});
  } on Object catch (error) {
    final failure = _describe(error);
    try {
      await _restore(bin, manifest);
    } on Object catch (restoreError) {
      throw PromotionException(
        '$failure\nAdemás, la restauración no terminó: '
        '${_describe(restoreError)}',
      );
    }
    throw PromotionException('$failure\nSe restauró la instalación previa.');
  }
  await _finish(bin);
}

/// Un fallo como frase para quien promueve: sin el tipo, la ruta ni la traza
/// de la excepción.
String _describe(Object error) => switch (error) {
  PromotionException(:final message) => message,
  FileSystemException(:final osError?) =>
    'falló una operación de archivo (${osError.message})',
  FileSystemException(:final message) =>
    'falló una operación de archivo ($message)',
  ProcessException(:final message) => 'no se pudo lanzar un proceso ($message)',
  _ => 'falló la promoción por un error inesperado',
};

/// Una promoción verificada termina borrando el respaldo y el manifiesto.
Future<void> _finish(Directory bin) async {
  final previous = File('${bin.path}/$_previousName');
  if (previous.existsSync()) await previous.delete();
  final candidate = File('${bin.path}/$_candidateName');
  if (candidate.existsSync()) await candidate.delete();
  await File('${bin.path}/$_manifestName').delete();
}

/// Lleva a su fin, o deshace, lo que dejó una promoción interrumpida. Sólo
/// actúa cuando cada archivo presente coincide con el manifiesto; cualquier
/// otra combinación se informa sin tocar nada.
Future<void> _reconcile(Directory bin) async {
  final draft = File('${bin.path}/$_manifestDraftName');
  if (draft.existsSync()) await draft.delete();
  final manifestFile = File('${bin.path}/$_manifestName');
  if (!manifestFile.existsSync()) {
    final residues = [
      _candidateName,
      _previousName,
    ].where((name) => File('${bin.path}/$name').existsSync()).toList();
    if (residues.isNotEmpty) {
      throw PromotionException(
        'hay residuos de una promoción sin manifiesto (${residues.join(', ')}) '
        'en ${bin.path}; no se sobrescriben a ciegas.',
      );
    }
    return;
  }
  final manifest = _readManifest(manifestFile);
  if (manifest['phase'] == _phaseCommitting) {
    final installed = File('${bin.path}/$_installedName');
    final previous = File('${bin.path}/$_previousName');
    if (!installed.existsSync() ||
        await _sha256(installed) != manifest['candidateSha256']) {
      throw _inconsistent(bin, 'el instalado no es el candidato verificado');
    }
    if (previous.existsSync() &&
        await _sha256(previous) != manifest['previousSha256']) {
      throw _inconsistent(bin, 'el respaldo no es el del manifiesto');
    }
    await _finish(bin);
    return;
  }
  await _restore(bin, manifest);
}

/// Devuelve el destino al estado anterior a la promoción que describe
/// [manifest].
Future<void> _restore(Directory bin, Map<String, Object?> manifest) async {
  final installed = File('${bin.path}/$_installedName');
  final candidate = File('${bin.path}/$_candidateName');
  final previous = File('${bin.path}/$_previousName');
  final candidateSha256 = manifest['candidateSha256'];
  final previousSha256 = manifest['previousSha256'];
  final previousVersion = manifest['previousVersion'];

  if (previous.existsSync()) {
    if (await _sha256(previous) != previousSha256) {
      throw _inconsistent(bin, 'el respaldo no es el del manifiesto');
    }
    if (installed.existsSync()) {
      if (await _sha256(installed) != candidateSha256) {
        throw _inconsistent(
          bin,
          'el instalado no es ni el respaldo ni el candidato',
        );
      }
      await installed.delete();
    }
    await previous.rename(installed.path);
  } else if (previousSha256 != null) {
    if (!installed.existsSync() || await _sha256(installed) != previousSha256) {
      throw _inconsistent(bin, 'falta la instalación previa');
    }
  } else if (installed.existsSync()) {
    if (await _sha256(installed) != candidateSha256) {
      throw _inconsistent(bin, 'hay un instalado que la promoción no creó');
    }
    await installed.delete();
  }
  if (candidate.existsSync()) await candidate.delete();
  if (previousVersion is String) {
    await _requireVersion(installed, previousVersion);
  }
  await File('${bin.path}/$_manifestName').delete();
}

Map<String, Object?> _readManifest(File file) {
  Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException {
    decoded = null;
  }
  final valid =
      decoded is Map<String, Object?> &&
      decoded['schemaVersion'] == 1 &&
      [
        _phaseStaging,
        _phaseSwapping,
        _phaseCommitting,
      ].contains(decoded['phase']) &&
      decoded['candidateVersion'] is String &&
      decoded['candidateSha256'] is String &&
      (decoded['previousSha256'] == null) ==
          (decoded['previousVersion'] == null);
  if (!valid) {
    throw PromotionException(
      '${file.path} no es un manifiesto de promoción legible; no se toca '
      'nada hasta revisarlo.',
    );
  }
  return decoded;
}

/// Escribe un borrador y lo renombra sobre el manifiesto: una interrupción deja
/// el manifiesto anterior o el nuevo, nunca uno a medias.
void _writeManifest(Directory bin, Map<String, Object> manifest) {
  final file = File('${bin.path}/$_manifestName');
  final draft = File('${bin.path}/$_manifestDraftName');
  try {
    draft.writeAsStringSync('${jsonEncode(manifest)}\n', flush: true);
    draft.renameSync(file.path);
  } on FileSystemException catch (error) {
    throw PromotionException(
      'no se pudo escribir ${file.path}: ${error.osError ?? error.message}.',
    );
  }
}

PromotionException _inconsistent(Directory bin, String detail) =>
    PromotionException(
      'el estado de ${bin.path} no coincide con su manifiesto: $detail; no se '
      'toca nada hasta revisarlo.',
    );

/// El lock es exclusivo y no bloqueante: una segunda promoción falla en vez
/// de esperar. El archivo queda vacío y en su lugar para que todas las
/// ejecuciones sincronicen sobre el mismo inode.
///
/// Es un lock de proceso: cerrar cualquier descriptor de este archivo dentro
/// del mismo proceso lo libera, así que nada más lo abre mientras dura.
Future<RandomAccessFile> _acquireLock(Directory bin) async {
  final path = '${bin.path}/$_lockName';
  final RandomAccessFile lock;
  try {
    lock = await File(path).open(mode: FileMode.append);
  } on FileSystemException catch (error) {
    throw PromotionException(
      'no se pudo abrir $path: ${error.osError ?? error.message}.',
    );
  }
  try {
    await lock.lock(FileLock.exclusive);
  } on FileSystemException {
    await lock.close();
    throw PromotionException(
      'otra promoción tiene el lock de ${bin.path}; no se modificó nada.',
    );
  }
  return lock;
}

void _requireType(String path, FileSystemEntityType expected, String what) {
  final actual = FileSystemEntity.typeSync(path, followLinks: false);
  if (actual == FileSystemEntityType.link) {
    throw PromotionException(
      '$what $path es un enlace simbólico; no se sigue.',
    );
  }
  if (actual != expected) {
    throw PromotionException(
      '$what $path no existe o no es del tipo esperado.',
    );
  }
}

void _rejectLink(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw PromotionException('$path es un enlace simbólico; no se sigue.');
  }
}

Future<String> _sha256(File file) async {
  try {
    return (await computeSha256(file)).sha256;
  } on ChecksumException catch (error) {
    throw PromotionException(error.message);
  }
}

Future<void> _makeExecutable(File file) async {
  final result = await Process.run('chmod', ['0755', file.path]);
  if (result.exitCode != 0) {
    throw PromotionException(
      'no se pudo marcar ${file.path} como ejecutable: ${result.stderr}',
    );
  }
}

Future<void> _requireVersion(File executable, String version) async {
  if (await _reportedVersion(executable) != version) {
    throw PromotionException(
      '${executable.path} no responde «shipflow $version» a --version.',
    );
  }
}

/// La versión que [executable] informa, o null si no responde el contrato.
Future<String?> _reportedVersion(File executable) async {
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
    exitCode = await process.exitCode.timeout(_versionTimeout);
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
