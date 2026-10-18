import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

const _markerName = '.git';
const _gitdirDirective = 'gitdir:';
const maxMarkerFileBytes = 4096;

/// Busca el marcador del repositorio desde [resolvedRoot] hacia sus
/// ancestros, mirando sólo `<ancestro>/.git` en cada nivel: no lista
/// directorios, no lee código fuera de la raíz ni ejecuta procesos.
///
/// [resolvedRoot] tiene que ser canónica: la relación con el repositorio se
/// decide comparando rutas.
Future<RepositoryContext> inspectRepositoryContext(
  Directory resolvedRoot,
) async {
  var current = resolvedRoot.absolute;
  while (true) {
    final status = await _markerStatus(current);
    if (status != null) {
      return RepositoryContext(
        status: status,
        root: current.path,
        relation: current.path == resolvedRoot.absolute.path
            ? RepositoryRelation.same
            : RepositoryRelation.ancestor,
      );
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      return const RepositoryContext(
        status: RepositoryStatus.absent,
        root: null,
        relation: RepositoryRelation.none,
      );
    }
    current = parent;
  }
}

/// Qué dice el marcador de [directory], o null si no tiene ninguno.
Future<RepositoryStatus?> _markerStatus(Directory directory) async {
  final path = '${directory.path}/$_markerName';
  return switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    FileSystemEntityType.notFound => null,
    FileSystemEntityType.directory => RepositoryStatus.detected,
    FileSystemEntityType.file => await _gitdirFileStatus(File(path)),
    _ => RepositoryStatus.indeterminate,
  };
}

/// Un archivo `.git` vale sólo si es una única directiva `gitdir:` acotada
/// cuyo destino es un directorio; el contenido del destino no se mira.
Future<RepositoryStatus> _gitdirFileStatus(File marker) async {
  final String content;
  try {
    content = utf8.decode(await _boundedBytes(marker));
  } on FileSystemException {
    return RepositoryStatus.indeterminate;
  } on FormatException {
    return RepositoryStatus.indeterminate;
  }
  final directive = content.trim();
  if (directive.contains('\n') || !directive.startsWith(_gitdirDirective)) {
    return RepositoryStatus.indeterminate;
  }
  final target = directive.substring(_gitdirDirective.length).trim();
  if (target.isEmpty) return RepositoryStatus.indeterminate;
  final resolved = target.startsWith('/')
      ? target
      : '${marker.parent.path}/$target';
  return FileSystemEntity.typeSync(resolved) == FileSystemEntityType.directory
      ? RepositoryStatus.detected
      : RepositoryStatus.indeterminate;
}

/// Lee a lo sumo un byte más que el máximo, para saber si lo excede sin leer
/// un archivo arbitrariamente grande.
Future<List<int>> _boundedBytes(File file) async {
  final handle = await file.open();
  try {
    final bytes = await handle.read(maxMarkerFileBytes + 1);
    if (bytes.length > maxMarkerFileBytes) {
      throw const FormatException('el marcador excede su tamaño máximo');
    }
    return bytes;
  } finally {
    await handle.close();
  }
}
