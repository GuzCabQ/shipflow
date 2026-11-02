import 'package:core/core.dart';

import 'source_inventory.dart';

/// Adónde lleva una referencia: un archivo incluido de la raíz, una
/// biblioteca externa nombrada sin comprobar, o nada, con su motivo.
final class ReferenceTarget {
  const ReferenceTarget.local(String this.path)
    : resolution = AssessmentResolution.local,
      label = path,
      reason = null;

  const ReferenceTarget.external(String this.label)
    : resolution = AssessmentResolution.external,
      path = null,
      reason = null;

  /// [label] sólo si es una ruta interna normalizada; nunca un literal.
  const ReferenceTarget.unresolved(String this.reason, [this.label])
    : resolution = AssessmentResolution.unresolved,
      path = null;

  final AssessmentResolution resolution;
  final String? path;
  final String? label;
  final String? reason;
}

final _scheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');
final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');
final _platformName = RegExp(r'^[a-z_][a-z0-9_]*(?:[._][a-z0-9_]+)*$');
final _unsafe = RegExp(r'[\\%?#\u0000-\u001f\u007f]');

/// Resuelve sobre el inventario ya sellado y el reconocimiento citado, sin
/// volver al disco: no sigue enlaces, no sale de la raíz y no enlaza un
/// paquete vecino por coincidencia de nombre.
final class LocalReferenceResolver {
  LocalReferenceResolver(this.inventory, PortableRecognition recognition)
    : _units = {for (final u in recognition.units) u.path: u.name},
      _dependencies = _corroborated(recognition),
      _sources = {for (final s in inventory.sources) s.path: s.state},
      _owners = {for (final s in inventory.sources) s.path: s.unitPath};

  final SourceInventory inventory;
  final Map<String, String> _units;
  final Map<String, Map<String, String>> _dependencies;
  final Map<String, AssessmentInputState> _sources;
  final Map<String, String> _owners;

  /// La unidad dueña de una fuente inventariada.
  String ownerOf(String path) => _owners[path]!;

  ReferenceTarget resolve(String sourcePath, String unitPath, String? uri) {
    if (uri == null) return const ReferenceTarget.unresolved('uri_not_literal');
    if (uri.isEmpty || _unsafe.hasMatch(uri)) {
      return const ReferenceTarget.unresolved('unsafe_uri');
    }
    if (uri.startsWith('dart:')) {
      return _platformName.hasMatch(uri.substring(5))
          ? ReferenceTarget.external(uri)
          : const ReferenceTarget.unresolved('unsafe_uri');
    }
    if (uri.startsWith('package:')) return _package(uri, unitPath);
    if (_scheme.hasMatch(uri)) {
      return const ReferenceTarget.unresolved('unsupported_scheme');
    }
    if (uri.startsWith('/')) {
      return const ReferenceTarget.unresolved('outside_root');
    }
    final slash = sourcePath.lastIndexOf('/');
    final base = slash < 0 ? '' : sourcePath.substring(0, slash);
    final target = normalizeRelative(base, uri);
    return target == null
        ? const ReferenceTarget.unresolved('outside_root')
        : _local(target);
  }

  /// `package:` del propio paquete, de una dependencia local corroborada o,
  /// si no, externo con su nombre normalizado.
  ReferenceTarget _package(String uri, String unitPath) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0 || slash == rest.length - 1) {
      return const ReferenceTarget.unresolved('unsafe_uri');
    }
    final name = rest.substring(0, slash);
    final inner = normalizeRelative('', rest.substring(slash + 1));
    if (!_packageName.hasMatch(name) || inner == null) {
      return const ReferenceTarget.unresolved('unsafe_uri');
    }
    final owner = _packageUnit(name, unitPath);
    if (owner == '') {
      return const ReferenceTarget.unresolved('ambiguous_package');
    }
    if (owner == null) return ReferenceTarget.external('package:$name/$inner');
    return _local(owner == '.' ? 'lib/$inner' : '$owner/lib/$inner');
  }

  /// La unidad local del paquete [name] visto desde [unitPath]: la propia si
  /// se llama así y es la única con ese nombre, o el destino de una única
  /// dependencia local corroborada; '' si es ambiguo, null si es externo.
  String? _packageUnit(String name, String unitPath) {
    if (_units[unitPath] == name) {
      final same = _units.values.where((n) => n == name).length;
      return same == 1 ? unitPath : '';
    }
    return _dependencies[unitPath]?[name];
  }

  ReferenceTarget _local(String path) {
    if (_excluded(path)) {
      return ReferenceTarget.unresolved('target_excluded', path);
    }
    final state = _sources[path];
    if (state == AssessmentInputState.unreadable) {
      return ReferenceTarget.unresolved('target_unreadable', path);
    }
    if (state != null) return ReferenceTarget.local(path);
    final slash = path.lastIndexOf('/');
    final parent = slash < 0 ? '.' : path.substring(0, slash);
    final missing =
        !inventory.knownEntries.contains(path) &&
        inventory.listedDirectories.contains(parent);
    return ReferenceTarget.unresolved(
      missing ? 'target_missing' : 'target_not_inventoried',
      path,
    );
  }

  bool _excluded(String path) {
    var at = path;
    while (true) {
      if (inventory.excluded.contains(at)) return true;
      final slash = at.lastIndexOf('/');
      if (slash < 0) return false;
      at = at.substring(0, slash);
    }
  }
}

/// Las dependencias locales corroboradas por unidad declarante, por nombre;
/// un nombre repetido no se resuelve.
Map<String, Map<String, String>> _corroborated(PortableRecognition r) {
  final found = <String, Map<String, String?>>{};
  for (final relation in r.relations) {
    final name = relation.declaredName;
    if (relation.kind != RelationKind.localDependency ||
        relation.status != RelationStatus.corroborated ||
        name == null) {
      continue;
    }
    final byName = found.putIfAbsent(relation.fromPath, () => {});
    byName[name] = byName.containsKey(name) ? null : relation.targetPath;
  }
  return {
    for (final MapEntry(:key, :value) in found.entries)
      key: {
        for (final MapEntry(key: name, value: target) in value.entries)
          if (target != null) name: target,
      },
  };
}

/// [relative] resuelta léxicamente desde [base], ambas sin `/` inicial; null
/// si sale de la raíz o queda vacía.
String? normalizeRelative(String base, String relative) {
  final segments = base.isEmpty ? <String>[] : base.split('/');
  for (final segment in relative.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
    } else {
      segments.add(segment);
    }
  }
  return segments.isEmpty ? null : segments.join('/');
}
