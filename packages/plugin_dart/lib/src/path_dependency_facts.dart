import 'observed_value.dart';

final class PathDependencyFact {
  const PathDependencyFact(
    this.section,
    this.name,
    this.path, {
    this.literal = true,
  });

  final String section;
  final String name;

  /// Tal como la declara el manifiesto, relativa a su directorio o absoluta.
  final String path;

  /// False si el manifiesto no declara texto: [path] sólo lo muestra, la
  /// declaración falló y nunca se interpreta como ruta.
  final bool literal;

  /// Cómo se muestra como evidencia, acotada.
  String get evidenceValue => _observed.text;

  /// Si la evidencia no cabe entera: entonces la ruta no se interpreta.
  bool get truncated => _observed.truncated;

  ObservedValue get _observed =>
      boundObservedValue(describePathDependency(section, name, path));
}

String describePathDependency(String section, String name, String path) =>
    '$section.$name: $path';

/// Un miembro del workspace tal como se declara.
final class WorkspaceMemberFact {
  const WorkspaceMemberFact(this.shown, {this.literal = true});

  final ObservedValue shown;

  /// False si el manifiesto no declara texto: [shown] sólo lo muestra, la
  /// declaración falló y nunca se interpreta como ruta.
  final bool literal;

  String get text => shown.text;
  bool get truncated => shown.truncated;
}

/// Cómo se muestra un valor declarado que no es texto, sin interpretarlo.
String shownValue(Object? node) => switch (node) {
  Map() => '{…}',
  List() => '[…]',
  _ => '$node',
};
