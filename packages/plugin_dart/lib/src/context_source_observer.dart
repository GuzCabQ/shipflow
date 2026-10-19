import 'dart:io';

import 'package:core/core.dart';

import 'context_source_rule.dart';
import 'derived_observation_budget.dart';
import 'path_probe.dart';

/// Lo que necesita una consulta del catálogo y nada más: dónde está la
/// raíz, qué árboles se omitieron y cómo consumir una entrada del recorrido.
final class ContextProbe {
  const ContextProbe({
    required this.root,
    required this.maxDepth,
    required this.omitted,
    required this.consumeEntry,
    required this.budget,
  });

  final Directory root;
  final int maxDepth;

  /// Si una ruta relativa está bajo un árbol que no se recorrió.
  final bool Function(String path) omitted;

  /// Consume una entrada del presupuesto de lectura, o devuelve false si ya
  /// no queda: entonces la consulta no ocurre.
  final bool Function() consumeEntry;
  final DerivedObservationBudget budget;
}

/// Las fuentes del catálogo [rules] en cada raíz de [scopes], de a una, o
/// hasta la primera consulta que no cabe: entonces `stoppedAt` la nombra.
/// Sólo mira metadatos sin seguir enlaces; nunca abre un archivo.
({List<ContextSource> sources, String? stoppedAt}) observeContextSources(
  List<String> scopes,
  List<ContextSourceRule> rules,
  ContextProbe probe,
) {
  final sources = <ContextSource>[];
  for (final scope in scopes) {
    for (final rule in rules) {
      final path = scope == '.'
          ? rule.relativePath
          : '$scope/${rule.relativePath}';
      final found = _locate(scope, path, probe);
      if (found == null) return (sources: sources, stoppedAt: path);
      sources.add(_admitted(scope, path, rule.kind, found, probe.budget));
    }
  }
  return (sources: sources, stoppedAt: null);
}

typedef _Located = (ContextEntityType, ContextReason);

/// Cobra la fila antes de construirla.
ContextSource _admitted(
  String scope,
  String path,
  ContextSourceKind kind,
  _Located found,
  DerivedObservationBudget budget,
) {
  final (type, reason) = found;
  budget.row([
    scope,
    path,
    kind.toWireName(),
    type.toWireName(),
    reason.toWireName(),
    contextNotInspected,
  ]);
  return ContextSource(
    scopePath: scope,
    path: path,
    kind: kind,
    entityType: type,
    reason: reason,
  );
}

/// Tramo a tramo desde [scope]: un ancestro enlazado, ausente o que no es
/// un directorio termina la consulta. Null si una consulta no cabe.
_Located? _locate(String scope, String path, ContextProbe probe) {
  final tail = scope == '.' ? path : path.substring(scope.length + 1);
  final parts = tail.split('/');
  var current = scope;
  for (final (index, part) in parts.indexed) {
    current = current == '.' ? part : '$current/$part';
    if (probe.omitted(current)) {
      return (ContextEntityType.unavailable, ContextReason.excluded);
    }
    if (current.split('/').length > probe.maxDepth) {
      return (ContextEntityType.unavailable, ContextReason.accessFailed);
    }
    if (!probe.consumeEntry()) return null;
    final absolute = '${probe.root.path}/$current';
    final type = FileSystemEntity.typeSync(absolute, followLinks: false);
    final last = index == parts.length - 1;
    if (last || type != FileSystemEntityType.directory) {
      return _classify(type, absolute, ancestor: !last);
    }
  }
  throw StateError('una ruta del catálogo no puede estar vacía');
}

_Located _classify(
  FileSystemEntityType type,
  String absolute, {
  required bool ancestor,
}) => switch (type) {
  FileSystemEntityType.notFound when isAbsentPath(absolute) => (
    ContextEntityType.missing,
    ContextReason.notFound,
  ),
  FileSystemEntityType.notFound => (
    ContextEntityType.unavailable,
    ContextReason.accessFailed,
  ),
  FileSystemEntityType.link when ancestor => (
    ContextEntityType.unavailable,
    ContextReason.ancestorLink,
  ),
  // Debajo de un archivo no puede existir nada: ENOTDIR.
  _ when ancestor => (ContextEntityType.missing, ContextReason.notFound),
  FileSystemEntityType.file => (ContextEntityType.file, ContextReason.observed),
  FileSystemEntityType.directory => (
    ContextEntityType.directory,
    ContextReason.observed,
  ),
  FileSystemEntityType.link => (ContextEntityType.link, ContextReason.observed),
  _ => (ContextEntityType.special, ContextReason.observed),
};
