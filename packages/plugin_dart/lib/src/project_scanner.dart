import 'dart:io';

import 'package:core/core.dart';

import 'recognition_codes.dart';
import 'scan_limits.dart';
import 'stable_file_reader.dart';

/// Lista un directorio sin seguir enlaces; las pruebas lo sustituyen para
/// provocar fallos que el sistema de archivos no reproduce a pedido.
typedef DirectoryLister = List<FileSystemEntity> Function(Directory directory);

List<FileSystemEntity> listWithoutFollowing(Directory directory) =>
    directory.listSync(followLinks: false);

const _excludedDirectories = {
  '.git',
  '.dart_tool',
  'build',
  '.symlinks',
  'Pods',
  'node_modules',
};

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

final class ScanResult {
  ScanResult(List<ScannedSource> sources, List<RecognitionLimitation> found)
    : sources = List.unmodifiable(sources),
      limitations = List.unmodifiable(found);

  final List<ScannedSource> sources;
  final List<RecognitionLimitation> limitations;
}

/// Recorre [root] en orden de ruta, sin seguir enlaces y dentro de
/// [limits]. Lo que no pudo mirar queda como limitación bloqueante.
Future<ScanResult> scanProject(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  DirectoryLister list = listWithoutFollowing,
  ByteReader readBytes = readBoundedBytes,
}) async {
  final scan = _Scan(root, limits, list, readBytes);
  await scan.visit(root, 0);
  return ScanResult(scan.sources, scan.limitations);
}

final class _Scan {
  _Scan(this.root, this.limits, this.list, this.readBytes);

  final Directory root;
  final ScanLimits limits;
  final DirectoryLister list;
  final ByteReader readBytes;
  final sources = <ScannedSource>[];
  final limitations = <RecognitionLimitation>[];
  var _entries = 0;
  var _manifests = 0;
  var _sourceBytes = 0;
  var _stopped = false;

  Future<void> visit(Directory directory, int depth) async {
    final List<FileSystemEntity> children;
    try {
      children = list(directory)..sort(_byName);
    } on FileSystemException {
      return _block(
        LimitationCode.subtreeUnreadable,
        'no se pudo listar este directorio; su contenido no se inspeccionó',
        directory.path,
      );
    }
    if (children.isNotEmpty && depth + 1 > limits.maxDepth) {
      return _block(
        LimitationCode.scanLimitReached,
        'excede la profundidad máxima de ${limits.maxDepth}; no se inspeccionó',
        directory.path,
      );
    }
    for (final child in children) {
      if (_stopped) return;
      if (++_entries > limits.maxEntries) {
        return _stop('entradas', limits.maxEntries, child.path);
      }
      await _visitEntity(child, depth + 1);
    }
  }

  Future<void> _visitEntity(FileSystemEntity entity, int depth) async {
    final name = _nameOf(entity.path);
    if (entity is! File && _excludedDirectories.contains(name)) return;
    switch (entity) {
      case Link():
        _block(
          LimitationCode.symlinkNotFollowed,
          'es un enlace simbólico y no se sigue',
          entity.path,
        );
      case Directory():
        await visit(entity, depth);
      case File():
        final kind = _kindOf(name, depth);
        if (kind != null) await _accept(entity, kind);
    }
  }

  SourceKind? _kindOf(String name, int depth) => switch (name) {
    manifestFileName => SourceKind.manifest,
    fvmConfigFileName when depth == 1 => SourceKind.fvmConfig,
    flutterVersionFileName when depth == 1 => SourceKind.flutterVersionFile,
    _ => null,
  };

  Future<void> _accept(File file, SourceKind kind) async {
    final isManifest = kind == SourceKind.manifest;
    if (isManifest && ++_manifests > limits.maxManifests) {
      return _stop('manifiestos', limits.maxManifests, file.path);
    }
    final read = await readStableFile(
      file,
      maxBytes: isManifest ? limits.maxManifestBytes : limits.maxMarkerBytes,
      readBytes: readBytes,
    );
    if (read is StableSource) return _keep(file, kind, read);
    final (code, message) = _rejection(read);
    _block(code, message, file.path);
  }

  void _keep(File file, SourceKind kind, StableSource read) {
    if (_sourceBytes + read.size > limits.maxTotalSourceBytes) {
      return _stop('bytes', limits.maxTotalSourceBytes, file.path);
    }
    _sourceBytes += read.size;
    sources.add(ScannedSource(_relative(file.path), kind, read));
  }

  (String, String) _rejection(StableRead read) => switch (read) {
    OversizedSource(:final size) => (
      LimitationCode.sourceTooLarge,
      'mide $size bytes y excede su máximo; no se leyó',
    ),
    UnstableSource() => (
      LimitationCode.sourceChanged,
      'cambió entre dos lecturas; la observación no es estable',
    ),
    UnreadableSource(:final reason) => (
      LimitationCode.sourceUnreadable,
      'no se pudo leer ($reason)',
    ),
    StableSource() => throw StateError('una fuente estable no se rechaza'),
  };

  void _stop(String what, int max, String path) {
    _stopped = true;
    _block(
      LimitationCode.scanLimitReached,
      'se alcanzó el máximo de $max $what; el resto no se inspeccionó',
      path,
    );
  }

  void _block(String code, String message, String path) => limitations.add(
    RecognitionLimitation(
      code: code,
      message: message,
      path: _relative(path),
      blocking: true,
    ),
  );

  String _relative(String path) {
    final prefix = root.path.endsWith('/') ? root.path : '${root.path}/';
    return path == root.path ? '.' : path.substring(prefix.length);
  }
}

String _nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

int _byName(FileSystemEntity a, FileSystemEntity b) =>
    _nameOf(a.path).compareTo(_nameOf(b.path));
