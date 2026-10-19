import 'observed_value.dart';

final class PathDependencyFact {
  const PathDependencyFact(this.section, this.name, this.path);

  final String section;
  final String name;

  /// Tal como la declara el manifiesto, relativa a su directorio o absoluta.
  final String path;

  /// Cómo se muestra como evidencia, acotada.
  String get evidenceValue => _observed.text;

  /// Si la evidencia no cabe entera: entonces la ruta no se interpreta.
  bool get truncated => _observed.truncated;

  ObservedValue get _observed =>
      boundObservedValue(describePathDependency(section, name, path));
}

String describePathDependency(String section, String name, String path) =>
    '$section.$name: $path';
