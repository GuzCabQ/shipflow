import 'executable_checks.dart';
import 'promotion_layout.dart';
import 'promotion_manifest.dart';

/// Lleva a su fin, o deshace, lo que dejó una promoción interrumpida. Sólo
/// actúa cuando cada archivo presente coincide con el manifiesto; cualquier
/// otra combinación se informa sin tocar nada.
Future<void> reconcile(
  PromotionLayout layout,
  VersionReader readVersion,
) async {
  if (layout.manifestDraft.existsSync()) await layout.manifestDraft.delete();
  if (!layout.manifest.existsSync()) return _rejectResidues(layout);
  final manifest = readManifest(layout.manifest);
  if (manifest.phase != PromotionPhase.committing) {
    return restore(layout, manifest, readVersion);
  }
  final installed = layout.installed;
  if (!installed.existsSync() ||
      await sha256Of(installed) != manifest.candidateSha256) {
    throw inconsistentState(
      layout,
      'el instalado no es el candidato verificado',
    );
  }
  final previous = layout.previous;
  if (previous.existsSync() &&
      await sha256Of(previous) != manifest.previousSha256) {
    throw inconsistentState(layout, 'el respaldo no es el del manifiesto');
  }
  await finish(layout);
}

void _rejectResidues(PromotionLayout layout) {
  final residues = [layout.candidate, layout.previous]
      .where((file) => file.existsSync())
      .map((file) => file.uri.pathSegments.last);
  if (residues.isNotEmpty) {
    throw PromotionException(
      'hay residuos de una promoción sin manifiesto (${residues.join(', ')}) '
      'en ${layout.bin.path}; no se sobrescriben a ciegas.',
    );
  }
}

/// Devuelve el destino al estado anterior a la promoción que describe
/// [manifest].
Future<void> restore(
  PromotionLayout layout,
  PromotionManifest manifest,
  VersionReader readVersion,
) async {
  if (layout.previous.existsSync()) {
    await _putPreviousBack(layout, manifest);
  } else if (manifest.previousSha256 != null) {
    final installed = layout.installed;
    if (!installed.existsSync() ||
        await sha256Of(installed) != manifest.previousSha256) {
      throw inconsistentState(layout, 'falta la instalación previa');
    }
  } else if (layout.installed.existsSync()) {
    if (await sha256Of(layout.installed) != manifest.candidateSha256) {
      throw inconsistentState(
        layout,
        'hay un instalado que la promoción no creó',
      );
    }
    await layout.installed.delete();
  }
  if (layout.candidate.existsSync()) await layout.candidate.delete();
  final previousVersion = manifest.previousVersion;
  if (previousVersion != null) {
    await requireVersion(layout.installed, previousVersion, readVersion);
  }
  await layout.manifest.delete();
}

Future<void> _putPreviousBack(
  PromotionLayout layout,
  PromotionManifest manifest,
) async {
  if (await sha256Of(layout.previous) != manifest.previousSha256) {
    throw inconsistentState(layout, 'el respaldo no es el del manifiesto');
  }
  if (layout.installed.existsSync()) {
    if (await sha256Of(layout.installed) != manifest.candidateSha256) {
      throw inconsistentState(
        layout,
        'el instalado no es ni el respaldo ni el candidato',
      );
    }
    await layout.installed.delete();
  }
  await layout.previous.rename(layout.installed.path);
}

/// Una promoción verificada termina borrando el respaldo y el manifiesto.
Future<void> finish(PromotionLayout layout) async {
  if (layout.previous.existsSync()) await layout.previous.delete();
  if (layout.candidate.existsSync()) await layout.candidate.delete();
  await layout.manifest.delete();
}
