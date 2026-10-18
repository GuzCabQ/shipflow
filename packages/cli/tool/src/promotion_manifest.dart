import 'dart:convert';
import 'dart:io';

import 'promotion_layout.dart';

const _schemaVersion = 1;

/// En qué punto de la promoción se escribió el manifiesto.
enum PromotionPhase { staging, swapping, committing }

/// Lo que una promoción en curso deja escrito para poder terminarla o
/// deshacerla.
final class PromotionManifest {
  const PromotionManifest({
    required this.phase,
    required this.candidateVersion,
    required this.candidateSha256,
    this.previousVersion,
    this.previousSha256,
  });

  final PromotionPhase phase;
  final String candidateVersion;
  final String candidateSha256;
  final String? previousVersion;
  final String? previousSha256;

  PromotionManifest at(PromotionPhase next) => PromotionManifest(
    phase: next,
    candidateVersion: candidateVersion,
    candidateSha256: candidateSha256,
    previousVersion: previousVersion,
    previousSha256: previousSha256,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': _schemaVersion,
    'phase': phase.name,
    'candidateVersion': candidateVersion,
    'candidateSha256': candidateSha256,
    'previousVersion': previousVersion,
    'previousSha256': previousSha256,
  };
}

PromotionManifest readManifest(File file) {
  final decoded = _decode(file);
  final phase = PromotionPhase.values
      .where((p) => decoded?['phase'] == p.name)
      .firstOrNull;
  if (decoded == null ||
      decoded['schemaVersion'] != _schemaVersion ||
      phase == null ||
      decoded['candidateVersion'] is! String ||
      decoded['candidateSha256'] is! String ||
      decoded['previousVersion'] is! String? ||
      decoded['previousSha256'] is! String? ||
      (decoded['previousSha256'] == null) !=
          (decoded['previousVersion'] == null)) {
    throw PromotionException(
      '${file.path} no es un manifiesto de promoción legible; no se toca '
      'nada hasta revisarlo.',
    );
  }
  return PromotionManifest(
    phase: phase,
    candidateVersion: decoded['candidateVersion'] as String,
    candidateSha256: decoded['candidateSha256'] as String,
    previousVersion: decoded['previousVersion'] as String?,
    previousSha256: decoded['previousSha256'] as String?,
  );
}

Map<String, Object?>? _decode(File file) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// Escribe un borrador y lo renombra sobre el manifiesto: una interrupción deja
/// el manifiesto anterior o el nuevo, nunca uno a medias.
void writeManifest(PromotionLayout layout, PromotionManifest manifest) {
  try {
    layout.manifestDraft.writeAsStringSync(
      '${jsonEncode(manifest.toJson())}\n',
      flush: true,
    );
    layout.manifestDraft.renameSync(layout.manifest.path);
  } on FileSystemException catch (error) {
    throw PromotionException(
      'no se pudo escribir ${layout.manifest.path}: '
      '${error.osError ?? error.message}.',
    );
  }
}
