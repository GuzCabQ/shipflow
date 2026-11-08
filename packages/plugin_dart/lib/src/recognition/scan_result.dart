import 'package:core/core.dart';

import 'manifest_evidence.dart';
import 'recognition_exclusions.dart';
import 'scanned_source.dart';

/// Lo que dejó el recorrido, en orden de ruta. Cada manifiesto se leyó y
/// analizó una sola vez, antes de descender en su directorio.
final class ScanResult {
  ScanResult({
    required List<ScannedSource> sources,
    required List<RecognitionLimitation> limitations,
    List<ManifestEvidence> manifests = const [],
    List<RecognitionLimitation> manifestLimitations = const [],
    List<OmissionDraft> omissions = const [],
    List<ContextSource> contextSources = const [],
  }) : sources = List.unmodifiable(sources),
       limitations = List.unmodifiable(limitations),
       manifests = List.unmodifiable(manifests),
       manifestLimitations = List.unmodifiable(manifestLimitations),
       omissions = List.unmodifiable(omissions),
       contextSources = List.unmodifiable(contextSources);

  /// Manifiestos y marcadores aceptados.
  final List<ScannedSource> sources;

  /// Lo que el recorrido no pudo mirar.
  final List<RecognitionLimitation> limitations;

  /// Los manifiestos que se pudieron analizar, con sus evidencias.
  final List<ManifestEvidence> manifests;

  /// Lo que el análisis de los manifiestos no pudo interpretar.
  final List<RecognitionLimitation> manifestLimitations;
  final List<OmissionDraft> omissions;
  final List<ContextSource> contextSources;
}

/// Las fuentes candidatas en orden de alcance y de ruta.
int compareContextSources(ContextSource a, ContextSource b) =>
    a.scopePath == b.scopePath
    ? a.path.compareTo(b.path)
    : a.scopePath.compareTo(b.scopePath);
