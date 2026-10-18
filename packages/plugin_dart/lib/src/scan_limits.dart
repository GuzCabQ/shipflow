/// Las cotas del recorrido. Cada máximo es inclusivo: el primer elemento que
/// lo excedería corta el recorrido y deja constancia.
final class ScanLimits {
  const ScanLimits({
    this.maxEntries = 100000,
    this.maxDepth = 32,
    this.maxManifests = 4096,
    this.maxManifestBytes = 262144,
    this.maxMarkerBytes = 4096,
    this.maxTotalSourceBytes = 16777216,
  });

  /// Toda entidad observada, incluso las excluidas.
  final int maxEntries;

  /// La raíz tiene profundidad 0.
  final int maxDepth;
  final int maxManifests;
  final int maxManifestBytes;
  final int maxMarkerBytes;

  /// El tamaño de cada fuente aceptada, contado una vez aunque se lea dos.
  final int maxTotalSourceBytes;
}
