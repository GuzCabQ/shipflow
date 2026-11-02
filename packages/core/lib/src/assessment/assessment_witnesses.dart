import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'assessment_enums.dart';
import 'assessment_sources.dart';

/// El testigo de una capacidad: cuánto esperaba el inventario y cuánto se
/// procesó, falló u omitió. Lo esperado nunca lo decide el propio detector.
final class AssessmentWitness {
  AssessmentWitness({
    required this.capability,
    required this.producerVersion,
    required this.state,
    required this.expected,
    required this.processed,
    required this.failed,
    required this.omitted,
  }) : id = capability.toWireName() {
    requireSemantic(
      [expected, processed, failed, omitted].every((n) => n >= 0) &&
          expected == processed + failed + omitted,
      'witness_counts',
      '/witnesses',
    );
    requireSemantic(
      switch (state) {
        AssessmentWitnessState.complete => failed == 0 && omitted == 0,
        AssessmentWitnessState.notRun => processed == 0 && failed == 0,
        _ => true,
      },
      'witness_state',
      '/witnesses',
    );
  }

  factory AssessmentWitness.fromJson(Map<String, Object?> json) {
    final capability = AssessmentCapability.fromWireName(
      json['capability']! as String,
    );
    requireSemantic(
      json['id'] == capability.toWireName(),
      'witness_identity',
      '/witnesses',
    );
    return AssessmentWitness(
      capability: capability,
      producerVersion: json['producerVersion']! as String,
      state: AssessmentWitnessState.fromWireName(json['state']! as String),
      expected: json['expected']! as int,
      processed: json['processed']! as int,
      failed: json['failed']! as int,
      omitted: json['omitted']! as int,
    );
  }

  /// Siempre el nombre de su capacidad.
  final String id;
  final AssessmentCapability capability;
  final String producerVersion;
  final AssessmentWitnessState state;
  final int expected;
  final int processed;
  final int failed;
  final int omitted;

  Map<String, Object?> toJson() => {
    'id': id,
    'capability': capability.toWireName(),
    'producerVersion': producerVersion,
    'state': state.toWireName(),
    'expected': expected,
    'processed': processed,
    'failed': failed,
    'omitted': omitted,
  };
}

/// Un vínculo a la evidencia del reconocimiento citado: una dependencia
/// declarada o una fuente candidata sin inspeccionar. No es una norma
/// adoptada ni una referencia observada en el código.
final class AssessmentContextLink {
  AssessmentContextLink({
    required this.kind,
    required this.sourceId,
    required this.sourcePath,
    required this.label,
    required this.targetUnitId,
  }) {
    requireSemantic(isAssessmentPath(sourcePath), 'path', '/contextLinks');
    requireSemantic(
      kind == AssessmentLinkKind.declaredDependency || targetUnitId == null,
      'link_target',
      '/contextLinks',
    );
  }

  factory AssessmentContextLink.fromJson(Map<String, Object?> json) =>
      AssessmentContextLink(
        kind: AssessmentLinkKind.fromWireName(json['kind']! as String),
        sourceId: json['sourceId']! as String,
        sourcePath: json['sourcePath']! as String,
        label: json['label']! as String,
        targetUnitId: json['targetUnitId'] as String?,
      );

  final AssessmentLinkKind kind;
  final String sourceId;
  final String sourcePath;
  final String label;
  final String? targetUnitId;

  Map<String, Object?> toJson() => {
    'kind': kind.toWireName(),
    'sourceId': sourceId,
    'sourcePath': sourcePath,
    'label': label,
    'targetUnitId': targetUnitId,
  };
}

/// Un grupo de diagnósticos con código, consecuencia y acción estables, su
/// cuenta total y hasta cinco rutas de ejemplo ordenadas.
final class AssessmentDiagnostic {
  AssessmentDiagnostic({
    required this.code,
    required this.path,
    required this.consequence,
    required this.actionCode,
    required this.count,
    required List<String> examples,
  }) : examples = List.unmodifiable(examples) {
    requireSemantic(
      count >= 1 &&
          examples.length <= 5 &&
          (path == null || isAssessmentPath(path!)) &&
          examples.every(isAssessmentPath) &&
          isStrictlySorted(examples, (a, b) => a.compareTo(b)),
      'diagnostic',
      '/diagnostics',
    );
  }

  factory AssessmentDiagnostic.fromJson(Map<String, Object?> json) =>
      AssessmentDiagnostic(
        code: json['code']! as String,
        path: json['path'] as String?,
        consequence: json['consequence']! as String,
        actionCode: json['actionCode']! as String,
        count: json['count']! as int,
        examples: readStrings(json['examples']),
      );

  final String code;
  final String? path;
  final String consequence;
  final String actionCode;
  final int count;
  final List<String> examples;

  Map<String, Object?> toJson() => {
    'code': code,
    'path': path,
    'consequence': consequence,
    'actionCode': actionCode,
    'count': count,
    'examples': examples,
  };
}

/// Si [items] están en orden estricto según [compare]: sin repetidos.
bool isStrictlySorted<T>(List<T> items, int Function(T, T) compare) {
  for (var i = 1; i < items.length; i++) {
    if (compare(items[i - 1], items[i]) >= 0) return false;
  }
  return true;
}
