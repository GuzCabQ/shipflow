import 'dart:io';

import 'executable_checks.dart';
import 'promotion_layout.dart';
import 'promotion_lock.dart';
import 'promotion_manifest.dart';
import 'promotion_recovery.dart';
import 'semver.dart';

export 'promotion_layout.dart' show PromotionException;

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

/// Reemplaza `shipflow` en [PromotionRequest.binDirectory] por el artefacto,
/// conservando el anterior hasta que el nuevo responda su versión.
///
/// El candidato se verifica antes de tocar el destino. Bajo el lock, primero
/// se reconcilia lo que una promoción interrumpida haya dejado y después se
/// promueve; ante cualquier fallo el destino vuelve a su estado previo.
/// [readVersion] pregunta la versión a cada ejecutable.
Future<void> promote(
  PromotionRequest request, {
  VersionReader readVersion = reportedVersion,
}) async {
  final layout = PromotionLayout(request.binDirectory);
  final digest = await _verifyRequest(request, layout, readVersion);
  await withPromotionLock(layout, () async {
    try {
      await reconcile(layout, readVersion);
      await _replace(layout, request, digest, readVersion);
    } on FileSystemException catch (error) {
      throw PromotionException(
        'no se pudo modificar ${layout.bin.path} '
        '(${error.osError?.message ?? error.message}); lo que haya quedado a '
        'medias conserva su manifiesto y se reconcilia en la próxima ejecución.',
      );
    }
  });
}

/// Devuelve el SHA-256 del candidato una vez que todo lo que se puede
/// comprobar sin el lock resultó.
Future<String> _verifyRequest(
  PromotionRequest request,
  PromotionLayout layout,
  VersionReader readVersion,
) async {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(request.expectedSha256)) {
    throw PromotionException(
      '«${request.expectedSha256}» no es un SHA-256 en hexadecimal.',
    );
  }
  if (!isValidSemVer(request.expectedVersion)) {
    throw PromotionException('«${request.expectedVersion}» no es SemVer 2.0.');
  }
  _requireType(layout.bin.path, FileSystemEntityType.directory, 'el bin-dir');
  final artifact = request.artifact;
  _requireType(artifact.path, FileSystemEntityType.file, 'el artefacto');
  final digest = await sha256Of(artifact);
  if (digest != request.expectedSha256) {
    throw PromotionException(
      'el SHA-256 de ${artifact.path} es $digest y se esperaba '
      '${request.expectedSha256}; la instalación no se tocó.',
    );
  }
  await requireVersion(artifact, request.expectedVersion, readVersion);
  layout.all.forEach(_rejectLink);
  return digest;
}

Future<void> _replace(
  PromotionLayout layout,
  PromotionRequest request,
  String digest,
  VersionReader readVersion,
) async {
  final manifest = await _stagingManifest(layout, request, digest, readVersion);
  if (manifest == null) return;
  writeManifest(layout, manifest);
  try {
    await _swap(layout, request.artifact, manifest, readVersion);
  } on Object catch (error, stack) {
    await _rollBack(layout, manifest, readVersion, error, stack);
  }
  await finish(layout);
}

/// Restaura ante cualquier fallo de [_swap]. Un fallo operativo se informa
/// como frase; un defecto de programación se relanza con su tipo y su traza,
/// y si la restauración también falla, el primer defecto es el que sale.
Future<Never> _rollBack(
  PromotionLayout layout,
  PromotionManifest manifest,
  VersionReader readVersion,
  Object error,
  StackTrace stack,
) async {
  final failure = _describe(error);
  try {
    await restore(layout, manifest, readVersion);
  } on Object catch (restoreError, restoreStack) {
    if (failure == null) Error.throwWithStackTrace(error, stack);
    final unrestored =
        _describe(restoreError) ??
        Error.throwWithStackTrace(restoreError, restoreStack);
    throw PromotionException(
      '$failure\nAdemás, la restauración no terminó: $unrestored',
    );
  }
  if (failure == null) Error.throwWithStackTrace(error, stack);
  throw PromotionException('$failure\nSe restauró la instalación previa.');
}

/// El manifiesto con el que empieza la promoción, o null si lo pedido ya es
/// exactamente lo instalado.
Future<PromotionManifest?> _stagingManifest(
  PromotionLayout layout,
  PromotionRequest request,
  String digest,
  VersionReader readVersion,
) async {
  final version = request.expectedVersion;
  final previous = layout.installed.existsSync()
      ? await _installedIdentity(layout.installed, readVersion)
      : null;
  if (previous != null && previous.version == version) {
    if (previous.sha256 == digest) return null;
    throw PromotionException(
      'ya está instalada la misma versión $version con otros bytes; una '
      'build distinta necesita una versión distinguible.',
    );
  }
  return PromotionManifest(
    phase: PromotionPhase.staging,
    candidateVersion: version,
    candidateSha256: digest,
    previousVersion: previous?.version,
    previousSha256: previous?.sha256,
  );
}

/// La versión y el digest del instalado, sin los cuales no hay a qué volver.
Future<({String version, String sha256})> _installedIdentity(
  File installed,
  VersionReader readVersion,
) async {
  final sha256 = await sha256Of(installed);
  final version = await readVersion(installed);
  if (version == null) {
    throw PromotionException(
      '${installed.path} no responde --version; sin una instalación '
      'verificable no hay a qué volver, así que no se reemplaza.',
    );
  }
  return (version: version, sha256: sha256);
}

/// Copia, verifica y pone el candidato en el lugar del instalado, dejando
/// escrita cada fase antes de entrar en ella.
Future<void> _swap(
  PromotionLayout layout,
  File artifact,
  PromotionManifest manifest,
  VersionReader readVersion,
) async {
  final candidate = layout.candidate;
  final version = manifest.candidateVersion;
  await artifact.copy(candidate.path);
  await makeExecutable(candidate);
  if (await sha256Of(candidate) != manifest.candidateSha256) {
    throw const PromotionException(
      'la copia del candidato no conserva el SHA-256 verificado.',
    );
  }
  await requireVersion(candidate, version, readVersion);
  writeManifest(layout, manifest.at(PromotionPhase.swapping));
  if (layout.installed.existsSync()) {
    await layout.installed.rename(layout.previous.path);
  }
  await candidate.rename(layout.installed.path);
  await requireVersion(layout.installed, version, readVersion);
  writeManifest(layout, manifest.at(PromotionPhase.committing));
}

/// Un fallo operativo como frase para quien promueve, sin el tipo, la ruta ni
/// la traza de la excepción; null si [error] no es uno de los previstos.
String? _describe(Object error) => switch (error) {
  PromotionException(:final message) => message,
  FileSystemException(:final osError?) =>
    'falló una operación de archivo (${osError.message})',
  FileSystemException(:final message) =>
    'falló una operación de archivo ($message)',
  ProcessException(:final message) => 'no se pudo lanzar un proceso ($message)',
  _ => null,
};

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

void _rejectLink(File file) {
  if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
      FileSystemEntityType.link) {
    throw PromotionException(
      '${file.path} es un enlace simbólico; no se sigue.',
    );
  }
}
