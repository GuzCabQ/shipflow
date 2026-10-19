import 'dart:io';

import 'package:core/core.dart';

import 'manifest_evidence.dart';
import 'recognition_exclusions.dart';
import 'stable_file_reader.dart';

/// Enumera un directorio sin seguir enlaces y a demanda, para que el
/// recorrido deje de pedir entradas al agotar su presupuesto. Las pruebas lo
/// sustituyen para provocar fallos que el sistema no reproduce a pedido.
typedef DirectoryLister =
    Stream<FileSystemEntity> Function(Directory directory);

Stream<FileSystemEntity> listWithoutFollowing(Directory directory) =>
    directory.list(followLinks: false);

const manifestFileName = 'pubspec.yaml';
const fvmConfigFileName = '.fvmrc';
const flutterVersionFileName = 'flutter-version.txt';

enum SourceKind { manifest, fvmConfig, flutterVersionFile }

/// Una fuente aceptada: estable, dentro de sus límites y sin parsear todavía.
final class ScannedSource {
  const ScannedSource(this.path, this.kind, this.read);

  /// Relativa a la raíz.
  final String path;
  final SourceKind kind;
  final StableSource read;
}

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
