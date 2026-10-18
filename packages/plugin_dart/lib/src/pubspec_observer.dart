import 'dart:convert';

import 'package:core/core.dart';
import 'package:yaml/yaml.dart';

import 'observed_value.dart';
import 'project_scanner.dart';
import 'recognition_codes.dart';

/// El parser de YAML es recursivo: más allá de esta profundidad de
/// colecciones de flujo agota la pila. Ningún manifiesto real se le acerca.
const maxFlowNesting = 64;

const _pathDependencySections = [
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
];

final class PathDependencyFact {
  const PathDependencyFact(this.section, this.name, this.path);

  final String section;
  final String name;

  /// Tal como la declara el manifiesto, relativa a su directorio o absoluta.
  final String path;
}

/// Sólo los hechos que el reconocimiento usa, nunca el árbol entero.
final class ManifestFacts {
  ManifestFacts({
    required this.source,
    required this.name,
    required this.sdkConstraint,
    required this.flutterConstraint,
    required this.flutterDependency,
    required List<PathDependencyFact> pathDependencies,
    required List<String> workspace,
  }) : pathDependencies = List.unmodifiable(pathDependencies),
       workspace = List.unmodifiable(workspace);

  final ScannedSource source;
  final String? name;
  final String? sdkConstraint;
  final String? flutterConstraint;
  final bool flutterDependency;
  final List<PathDependencyFact> pathDependencies;
  final List<String> workspace;
}

final class ManifestObservation {
  ManifestObservation(this.facts, List<RecognitionLimitation> limitations)
    : limitations = List.unmodifiable(limitations);

  /// Null si el manifiesto no se pudo leer como un mapa YAML.
  final ManifestFacts? facts;
  final List<RecognitionLimitation> limitations;
}

ManifestObservation observeManifest(ScannedSource source) {
  final observer = _Observer(source);
  final document = observer.document();
  if (document == null) return ManifestObservation(null, observer.limitations);
  final environment = observer.map(document['environment'], 'environment');
  final facts = ManifestFacts(
    source: source,
    name: observer.text(document['name'], 'name', keepTruncated: true),
    sdkConstraint: observer.text(environment?['sdk'], 'environment.sdk'),
    flutterConstraint: observer.text(
      environment?['flutter'],
      'environment.flutter',
    ),
    flutterDependency: _hasFlutterDependency(document['dependencies']),
    pathDependencies: [
      for (final section in _pathDependencySections)
        ...observer.pathDependencies(document[section], section),
    ],
    workspace: observer.texts(document['workspace'], 'workspace'),
  );
  return ManifestObservation(facts, observer.limitations);
}

bool _hasFlutterDependency(Object? dependencies) =>
    dependencies is YamlMap &&
    dependencies['flutter'] is YamlMap &&
    (dependencies['flutter'] as YamlMap)['sdk'] == 'flutter';

final class _Observer {
  _Observer(this.source);

  final ScannedSource source;
  final limitations = <RecognitionLimitation>[];

  YamlMap? document() {
    final String text;
    try {
      text = utf8.decode(source.read.bytes);
    } on FormatException {
      return _invalid('no es texto UTF-8');
    }
    if (_flowNesting(text) > maxFlowNesting) {
      return _invalid('anida más de $maxFlowNesting colecciones');
    }
    final Object? parsed;
    try {
      parsed = loadYaml(text, recover: false);
    } on YamlException {
      return _invalid('no es YAML válido');
    }
    return parsed is YamlMap ? parsed : _invalid('no es un mapa YAML');
  }

  YamlMap? map(Object? node, String field) {
    if (node == null || node is YamlMap) return node as YamlMap?;
    return _invalid('«$field» no es un mapa');
  }

  /// [node] como texto acotado. Un valor truncado se conserva sólo con
  /// [keepTruncated]: interpretar un adelanto como el valor sería inventar.
  String? text(Object? node, String field, {bool keepTruncated = false}) {
    if (node == null) return null;
    if (node is! String) return _invalid('«$field» no es texto');
    final (:text, :truncated) = boundObservedValue(node);
    if (!truncated) return text;
    _limit(
      LimitationCode.observedValueTruncated,
      '«$field» excede $maxObservedValueBytes bytes y se conserva truncado',
    );
    return keepTruncated ? text : null;
  }

  List<String> texts(Object? node, String field) {
    if (node == null) return const [];
    if (node is! YamlList) {
      _invalid('«$field» no es una lista');
      return const [];
    }
    return [for (final item in node) ?text(item, field)];
  }

  List<PathDependencyFact> pathDependencies(Object? node, String section) {
    final dependencies = map(node, section);
    if (dependencies == null) return const [];
    return [
      for (final MapEntry(:key, :value) in dependencies.entries)
        if (key is String && value is YamlMap && value.containsKey('path'))
          if (text(value['path'], '$section.$key.path') case final path?)
            PathDependencyFact(section, key, path),
    ];
  }

  Null _invalid(String why) {
    _limit(LimitationCode.invalidManifest, 'el manifiesto $why');
    return null;
  }

  void _limit(String code, String message) => limitations.add(
    RecognitionLimitation(
      code: code,
      message: message,
      path: source.path,
      blocking: true,
    ),
  );
}

/// La mayor profundidad de `[` y `{`, contando también los que estén dentro
/// de cadenas: sobreestimar sólo convierte un manifiesto raro en limitación.
int _flowNesting(String text) {
  var depth = 0;
  var deepest = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0x5B || unit == 0x7B) {
      depth++;
      if (depth > deepest) deepest = depth;
    } else if ((unit == 0x5D || unit == 0x7D) && depth > 0) {
      depth--;
    }
  }
  return deepest;
}
