import 'dart:io';

import 'pubspec_observer.dart';

enum PathDependencyPlacement { inside, outside, unresolved }

/// Dónde queda [dependency], resuelta desde su manifiesto como la resolvería
/// el sistema. Sólo resuelve rutas y enlaces: no lee lo que hay del otro lado.
PathDependencyPlacement placePathDependency(
  Directory root,
  ManifestFacts facts,
  PathDependencyFact dependency,
) {
  final manifest = '${root.path}/${facts.source.path}';
  final directory = manifest.substring(0, manifest.lastIndexOf('/'));
  final declared = dependency.path.startsWith('/')
      ? dependency.path
      : '$directory/${dependency.path}';
  final target = _resolve(declared);
  if (target == null) return PathDependencyPlacement.unresolved;
  return target == root.path || target.startsWith('${root.path}/')
      ? PathDependencyPlacement.inside
      : PathDependencyPlacement.outside;
}

/// [path] tramo a tramo: cada tramo que existe se resuelve con sus enlaces
/// antes de aplicar el siguiente `..`, que sube desde el destino real. Lo que
/// no existe sólo alarga la ruta; un `..` detrás de un tramo inexistente, o
/// un enlace que no resuelve, la dejan sin resolver en lugar de suponerla.
/// Una ruta con NUL tampoco es una que el sistema pueda resolver.
String? _resolve(String path) {
  if (path.contains('\x00')) return null;
  var current = ''; // canónica; vacía es `/`
  var missing = false;
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (missing) return null;
      if (current.isNotEmpty) {
        current = current.substring(0, current.lastIndexOf('/'));
      }
      continue;
    }
    current = '$current/$segment';
    if (missing) continue;
    if (FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.notFound) {
      missing = true;
      continue;
    }
    try {
      current = File(current).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }
  return current.isEmpty ? '/' : current;
}
