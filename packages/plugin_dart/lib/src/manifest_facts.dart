import 'package:core/core.dart';

import 'observed_value.dart';
import 'path_dependency_facts.dart';
import 'project_scanner.dart';

/// Sólo los hechos que el reconocimiento usa, nunca el árbol entero.
final class ManifestFacts {
  ManifestFacts({
    required this.source,
    required this.name,
    required this.sdkConstraint,
    required this.flutterConstraint,
    required this.flutterDependency,
    required List<PathDependencyFact> pathDependencies,
    required List<WorkspaceMemberFact> workspace,
    this.description,
    List<String> resourceDirectories = const [],
  }) : pathDependencies = List.unmodifiable(pathDependencies),
       workspace = List.unmodifiable(workspace),
       resourceDirectories = List.unmodifiable(resourceDirectories);

  final ScannedSource source;
  final String? name;
  final ObservedValue? sdkConstraint;
  final ObservedValue? flutterConstraint;
  final bool flutterDependency;
  final List<PathDependencyFact> pathDependencies;
  final List<WorkspaceMemberFact> workspace;

  /// Entera o ausente: una descripción que no cabe no se conserva.
  final String? description;

  /// Directorios literales bajo `assets/`, normalizados y con `/` final;
  /// sólo los de un paquete que declara la dependencia del SDK Flutter.
  final List<String> resourceDirectories;
}

final class ManifestObservation {
  ManifestObservation(this.facts, List<RecognitionLimitation> limitations)
    : limitations = List.unmodifiable(limitations);

  /// Null si el manifiesto no se pudo leer como un mapa YAML.
  final ManifestFacts? facts;
  final List<RecognitionLimitation> limitations;
}
