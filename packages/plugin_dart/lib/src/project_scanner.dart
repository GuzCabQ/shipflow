import 'dart:io';

import 'package:core/core.dart';

import 'derived_observation_budget.dart';
import 'recognition_codes.dart';
import 'scan_limits.dart';
import 'stable_file_reader.dart';

/// Enumera un directorio sin seguir enlaces y a demanda, para que el
/// recorrido deje de pedir entradas al agotar su presupuesto. Las pruebas lo
/// sustituyen para provocar fallos que el sistema no reproduce a pedido.
typedef DirectoryLister =
    Stream<FileSystemEntity> Function(Directory directory);

Stream<FileSystemEntity> listWithoutFollowing(Directory directory) =>
    directory.list(followLinks: false);

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
/// [limits]. Lo que no pudo mirar queda como limitación bloqueante, cobrada
/// a [budget] antes de crearse.
Future<ScanResult> scanProject(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  DirectoryLister list = listWithoutFollowing,
  ByteReader readBytes = readBoundedBytes,
  DerivedObservationBudget? budget,
}) async {
  final scan = _Scan(
    root,
    limits,
    list,
    readBytes,
    budget ?? DerivedObservationBudget(const ReportLimits()),
  );
  await scan.visit(root, 0);
  return ScanResult(scan.sources, scan.limitations);
}

final class _Scan {
  _Scan(this.root, this.limits, this.list, this.readBytes, this.budget)
    : _authorizedRoot = _canonical(root.path);

  final Directory root;

  /// La raíz real al empezar. Las rutas se comparan con ella y no con una
  /// nueva resolución de [root], que otro proceso pudo cambiar por un enlace.
  final String? _authorizedRoot;
  final ScanLimits limits;
  final DirectoryLister list;
  final ByteReader readBytes;
  final DerivedObservationBudget budget;
  final sources = <ScannedSource>[];
  final limitations = <RecognitionLimitation>[];
  var _entries = 0;
  var _manifests = 0;
  var _sourceBytes = 0;
  var _stopped = false;

  /// Pide a lo sumo una entrada más de las que caben: si el directorio no
  /// cabe entero se corta en él, porque qué entradas llegaron primero depende
  /// del orden del sistema de archivos.
  Future<void> visit(Directory directory, int depth) async {
    final deep = depth + 1 > limits.maxDepth;
    final room = limits.maxEntries - _entries;
    final children = await _list(directory, deep ? 1 : room + 1);
    if (children == null) return;
    final why = depth == 0 ? null : _escaped(directory.path, _directory);
    if (why != null) return _block(why.code, why.message, directory.path);
    if (children.length > room) {
      return _stop('entradas', limits.maxEntries, directory.path);
    }
    _entries += children.length;
    if (children.isEmpty) return;
    if (deep) {
      return _block(
        LimitationCode.scanLimitReached,
        'excede la profundidad máxima de ${limits.maxDepth}; no se inspeccionó',
        directory.path,
      );
    }
    for (final child in children..sort(_byName)) {
      if (_stopped) return;
      await _visitEntity(child, depth + 1);
    }
  }

  /// Hasta [count] entradas de [directory], o null si no se pudo listar.
  Future<List<FileSystemEntity>?> _list(Directory directory, int count) async {
    try {
      return await list(directory).take(count).toList();
    } on FileSystemException {
      _block(
        LimitationCode.subtreeUnreadable,
        'no se pudo listar este directorio; su contenido no se inspeccionó',
        directory.path,
      );
      return null;
    }
  }

  Future<void> _visitEntity(FileSystemEntity entity, int depth) async {
    final name = _nameOf(entity.path);
    if (entity is! File && _excludedDirectories.contains(name)) return;
    switch (entity) {
      case Link():
        _block(LimitationCode.symlinkNotFollowed, _linkMessage, entity.path);
      case Directory():
        if (_escaped(entity.path, _directory) case final why?) {
          return _block(why.code, why.message, entity.path);
        }
        await visit(entity, depth);
      case File():
        final kind = _kindOf(name, depth);
        if (kind == null) return;
        if (_escaped(entity.path, _file) case final why?) {
          return _block(why.code, why.message, entity.path);
        }
        await _accept(entity, kind);
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
      readBytes: _revalidatedRead,
    );
    if (_escaped(file.path, _file) case final why?) {
      return _block(why.code, why.message, file.path);
    }
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

  /// Revalida antes de cada lectura, no sólo antes de la primera: abrir lo
  /// que ya no es la fuente enumerada podría leer fuera de la raíz o, con un
  /// FIFO, no volver nunca. El motivo exacto lo informa [_accept] después.
  Future<List<int>> _revalidatedRead(File file, int maxBytes) {
    if (_escaped(file.path, _file) != null) {
      throw const FileSystemException('cambió antes de leerse');
    }
    return readBytes(file, maxBytes);
  }

  /// Por qué [path] ya no es lo que se enumeró: un [expected] sin enlaces
  /// dentro de la raíz. Se comprueba antes y después de usarlo, porque entre
  /// la enumeración y el uso otro proceso pudo cambiar un tramo por un enlace
  /// y el sistema lo seguiría. Queda la ventana de cambiarlo y restaurarlo
  /// entre ambas comprobaciones; en una fuente, además con lecturas iguales.
  ({String code, String message})? _escaped(
    String path,
    FileSystemEntityType expected,
  ) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      return (code: LimitationCode.symlinkNotFollowed, message: _linkMessage);
    }
    if (type != expected) {
      return expected == _file
          ? (
              code: LimitationCode.sourceUnreadable,
              message: 'no es un archivo regular; no se abrió',
            )
          : (
              code: LimitationCode.sourceChanged,
              message: 'dejó de ser un directorio durante el recorrido',
            );
    }
    if (_authorizedRoot != null &&
        _canonical(path) == '$_authorizedRoot/${_relative(path)}') {
      return null;
    }
    return (
      code: LimitationCode.sourceChanged,
      message: 'su ruta salió de la raíz durante el recorrido; no se usó',
    );
  }

  void _stop(String what, int max, String path) {
    _stopped = true;
    _block(
      LimitationCode.scanLimitReached,
      'se alcanzó el máximo de $max $what; el resto no se inspeccionó',
      path,
    );
  }

  void _block(String code, String message, String path) {
    final relative = _relative(path);
    budget.row([code, message, relative]);
    limitations.add(
      RecognitionLimitation(
        code: code,
        message: message,
        path: relative,
        blocking: true,
      ),
    );
  }

  String _relative(String path) {
    final prefix = root.path.endsWith('/') ? root.path : '${root.path}/';
    return path == root.path ? '.' : path.substring(prefix.length);
  }
}

const _directory = FileSystemEntityType.directory;
const _file = FileSystemEntityType.file;
const _linkMessage = 'es un enlace simbólico y no se sigue';

/// La ruta real de [path], o null si ya no se puede resolver.
String? _canonical(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return null;
  }
}

String _nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

int _byName(FileSystemEntity a, FileSystemEntity b) =>
    _nameOf(a.path).compareTo(_nameOf(b.path));
