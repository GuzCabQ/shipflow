import 'dart:convert';

import 'package:core/core.dart';
import 'package:yaml/yaml.dart';

export 'path_dependency_facts.dart';

import 'derived_observation_budget.dart';
import 'evidence_draft.dart';
import 'manifest_resources.dart';
import 'observed_value.dart';
import 'path_dependency_facts.dart';
import 'yaml_nesting_guard.dart';
import 'project_scanner.dart';
import 'recognition_codes.dart';

/// El valor de la evidencia de una dependencia `flutter: {sdk: flutter}`.
const flutterDependencyValue = 'sdk: flutter';

const _pathDependencySections = [
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
];

/// Sólo los hechos que el reconocimiento usa, nunca el árbol entero.
final class ManifestFacts {
  ManifestFacts({
    required this.source,
    required this.name,
    required this.sdkConstraint,
    required this.flutterConstraint,
    required this.flutterDependency,
    required List<PathDependencyFact> pathDependencies,
    required List<ObservedValue> workspace,
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
  final List<ObservedValue> workspace;

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

/// Los hechos de [source]. Cada uno que será evidencia se cobra a [budget]
/// al extraerse, antes de retenerlo; las listas se recorren de a uno.
ManifestObservation observeManifest(
  ScannedSource source, {
  DerivedObservationBudget? budget,
}) {
  final observer = _Observer(
    source,
    budget ?? DerivedObservationBudget(const ReportLimits()),
  );
  final document = observer.document();
  if (document == null) return ManifestObservation(null, observer.limitations);
  final facts = observer.facts(document);
  return ManifestObservation(facts, observer.limitations);
}

bool _hasFlutterDependency(Object? dependencies) =>
    dependencies is YamlMap &&
    dependencies['flutter'] is YamlMap &&
    (dependencies['flutter'] as YamlMap)['sdk'] == 'flutter';

final class _Observer {
  _Observer(this.source, this.budget);

  final ScannedSource source;
  final DerivedObservationBudget budget;
  final limitations = <RecognitionLimitation>[];

  /// Los hechos de [document], cada uno cobrado al extraerse.
  ManifestFacts facts(YamlMap document) {
    final environment = map(document['environment'], 'environment');
    final flutter = flutterDependency(document['dependencies']);
    return ManifestFacts(
      source: source,
      name: fact(EvidenceKind.packageName, document['name'], 'name')?.text,
      sdkConstraint: fact(
        EvidenceKind.sdkConstraint,
        environment?['sdk'],
        'environment.sdk',
      ),
      flutterConstraint: fact(
        EvidenceKind.flutterConstraint,
        environment?['flutter'],
        'environment.flutter',
      ),
      flutterDependency: flutter,
      pathDependencies: [
        for (final section in _pathDependencySections)
          ...pathDependencies(document[section], section),
      ],
      workspace: workspace(document['workspace']),
      description: description(document['description']),
      resourceDirectories: flutter ? resources(document['flutter']) : const [],
    );
  }

  /// La descripción, cobrada como evidencia, o una limitación que no
  /// bloquea: es opcional.
  String? description(Object? node) {
    final (:value, :problem) = declaredDescription(node);
    if (problem != null) {
      _limit(
        LimitationCode.optionalDescriptionUnavailable,
        '«description» $problem; se omite y no afecta el reconocimiento',
        blocking: false,
      );
    }
    if (value != null) {
      budget.row(_evidenceTexts(EvidenceKind.description, value));
    }
    return value;
  }

  /// Los directorios de recursos admitidos, de a uno: cada uno se cobra
  /// como evidencia y cada forma no soportada se informa sin bloquear.
  List<String> resources(Object? flutter) => [
    for (final entry in resourceEntries(flutter))
      if (_admitResource(entry) case final path?) path,
  ];

  String? _admitResource(ResourceEntry entry) => switch (entry) {
    ResourceDirectory(:final path) => _resourceDirectory(path),
    UnsupportedResource(:final message) => _limit(
      LimitationCode.unsupportedResourceDeclaration,
      '$message; no concede exclusiones y el recorrido ordinario sigue',
      blocking: false,
    ),
  };

  String _resourceDirectory(String path) {
    budget.row(_evidenceTexts(EvidenceKind.resourceDirectory, path));
    return path;
  }

  /// Las partes de la evidencia de [value] que el reporte retendrá.
  List<String> _evidenceTexts(String kind, String value) =>
      evidenceRowTexts(kind, source.path, value, source.read.fingerprint);

  /// [node] como texto acotado y ya cobrado como evidencia de [kind].
  ObservedValue? fact(String kind, Object? node, String field) {
    final observed = text(node, field);
    if (observed != null) budget.row(_evidenceTexts(kind, observed.text));
    return observed;
  }

  bool flutterDependency(Object? dependencies) {
    if (!_hasFlutterDependency(dependencies)) return false;
    budget.row(
      _evidenceTexts(EvidenceKind.flutterDependency, flutterDependencyValue),
    );
    return true;
  }

  YamlMap? document() {
    final String text;
    try {
      text = utf8.decode(source.read.bytes);
    } on FormatException {
      return _invalid('no es texto UTF-8');
    }
    if (nestsTooDeep(text)) {
      return _invalid('anida más de $maxYamlNesting niveles');
    }
    final Object? parsed;
    try {
      parsed = loadYaml(text, recover: false);
    } on YamlException {
      return _invalid('no es YAML válido');
    } on StackOverflowError {
      return _invalid('anida más de lo que se puede leer');
    }
    return parsed is YamlMap ? parsed : _invalid('no es un mapa YAML');
  }

  YamlMap? map(Object? node, String field) {
    if (node == null || node is YamlMap) return node as YamlMap?;
    return _invalid('«$field» no es un mapa');
  }

  /// [node] como texto acotado. Un valor truncado se conserva como adelanto
  /// para explicar el resultado; quien lo use no debe interpretarlo.
  ObservedValue? text(Object? node, String field) {
    if (node == null) return null;
    if (node is! String) return _invalid('«$field» no es texto');
    final observed = boundObservedValue(node);
    if (observed.truncated) {
      _limit(
        LimitationCode.observedValueTruncated,
        '«$field» excede $maxObservedValueBytes bytes y se conserva truncado',
      );
    }
    return observed;
  }

  List<ObservedValue> workspace(Object? node) {
    if (node == null) return const [];
    if (node is! YamlList) {
      _invalid('«workspace» no es una lista');
      return const [];
    }
    return budget
        .admitEach(
          node.map((item) => text(item, 'workspace')).nonNulls,
          textsOf: (m) => _evidenceTexts(EvidenceKind.workspaceMember, m.text),
          build: (m) => m,
        )
        .toList();
  }

  List<PathDependencyFact> pathDependencies(Object? node, String section) {
    final dependencies = map(node, section);
    if (dependencies == null) return const [];
    return budget
        .admitEach(
          dependencies.entries
              .where(
                (e) =>
                    e.key is String &&
                    e.value is YamlMap &&
                    (e.value as YamlMap).containsKey('path'),
              )
              .map(
                (e) => _pathDependency(
                  section,
                  e.key as String,
                  (e.value as YamlMap)['path'],
                ),
              )
              .nonNulls,
          textsOf: (d) =>
              _evidenceTexts(EvidenceKind.pathDependency, d.evidenceValue),
          build: (d) => d,
        )
        .toList();
  }

  /// La dependencia, marcada como truncada si su evidencia
  /// `<sección>.<nombre>: <ruta>` no cabe entera.
  PathDependencyFact? _pathDependency(
    String section,
    String key,
    Object? path,
  ) {
    if (path is! String) return _invalid('«$section.*.path» no es texto');
    final dependency = PathDependencyFact(section, key, path);
    if (dependency.truncated) {
      _limit(
        LimitationCode.observedValueTruncated,
        'una dependencia local de «$section» excede $maxObservedValueBytes '
        'bytes; se conserva truncada y no se interpreta',
      );
    }
    return dependency;
  }

  Null _invalid(String why) {
    _limit(LimitationCode.invalidManifest, 'el manifiesto $why');
    return null;
  }

  Null _limit(String code, String message, {bool blocking = true}) {
    budget.row([code, message, source.path]);
    limitations.add(
      RecognitionLimitation(
        code: code,
        message: message,
        path: source.path,
        blocking: blocking,
      ),
    );
    return null;
  }
}
