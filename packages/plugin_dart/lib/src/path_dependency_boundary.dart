import 'dart:io';

import 'pubspec_observer.dart';

/// Si [dependency], resuelta canónicamente desde su manifiesto, queda fuera
/// de [root]. Sólo resuelve rutas y enlaces: no lee lo que hay del otro lado.
bool isOutsideRoot(
  Directory root,
  ManifestFacts facts,
  PathDependencyFact dependency,
) {
  final manifest = '${root.path}/${facts.source.path}';
  final directory = manifest.substring(0, manifest.lastIndexOf('/'));
  final declared = dependency.path.startsWith('/')
      ? dependency.path
      : '$directory/${dependency.path}';
  final target = _canonical(Uri.file(declared).normalizePath().toFilePath());
  return target != root.path && !target.startsWith('${root.path}/');
}

/// Resuelve los enlaces del tramo más largo que existe y le agrega el resto,
/// para que un enlace a mitad de camino no esconda adónde va la ruta.
String _canonical(String path) {
  var existing = path;
  var rest = '';
  while (FileSystemEntity.typeSync(existing) == FileSystemEntityType.notFound) {
    final slash = existing.lastIndexOf('/');
    if (slash <= 0) return path;
    rest = '${existing.substring(slash)}$rest';
    existing = existing.substring(0, slash);
  }
  try {
    return '${File(existing).resolveSymbolicLinksSync()}$rest';
  } on FileSystemException {
    return path;
  }
}
