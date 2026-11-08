import 'dart:convert';
import 'dart:io';

// ContextSourceKind se oculta de core: tiene que llegar del barrel del
// plugin, que lo reexporta, o esta prueba no vería que se perdió.
import 'package:core/core.dart' hide ContextSourceKind;
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

/// La superficie pública del plugin, tal como la ve quien sólo importa su
/// barrel. Los tear-offs comprueban asignabilidad, no igualdad exacta de
/// firmas: la igualdad la da el volcado resuelto de la evidencia. Los
/// defaults se comprueban por su comportamiento.
void main() {
  test('the barrel exports the contract constants with their values', () {
    expect(assessmentContract, 'source-topology-v3.2');
    expect(assessmentPluginId, 'plugin_dart');
    expect(parserVersion, '14.1.0');
  });

  test('the exported functions keep their signatures', () {
    final Future<RecognitionContribution> Function(
      Directory, {
      ScanLimits limits,
      ReportLimits reportLimits,
      List<ContextSourceRule> contextSources,
      List<AuthorizedOmission> authorizedOmissions,
    })
    recognize = recognizeDartProject;
    final Future<AssessmentObservation> Function(
      Directory,
      ProjectContext,
      AssessmentLimits, {
      DirectiveParser? parser,
      int Function()? elapsedMillis,
    })
    sources = observeDartSources;
    final Future<List<AssessmentInput>> Function(
      Directory,
      ProjectContext,
      AssessmentLimits,
    )
    inputs = observeDartInputs;
    final AssessmentContextBasis Function(ProjectContext) basis =
        projectDartAssessmentContext;
    expect([recognize, sources, inputs, basis], everyElement(isA<Function>()));
  });

  test('the exported types keep their shape', () {
    const rule = ContextSourceRule(
      relativePath: 'docs',
      kind: ContextSourceKind.documentation,
      expectsDirectory: true,
    );
    expect(
      (rule.relativePath, rule.kind, rule.expectsDirectory),
      ('docs', ContextSourceKind.documentation, true),
    );
    expect(ContextSourceKind.values.map((k) => k.name), [
      'documentation',
      'instructions',
      'analysisConfiguration',
      'taskConfiguration',
      'ciConfiguration',
    ]);
    const DirectiveParser? parser = null;
    expect(parser, isNull);
  });

  test('the scan limits keep their contract defaults', () {
    const limits = ScanLimits();
    expect(
      [
        limits.maxEntries,
        limits.maxDepth,
        limits.maxManifests,
        limits.maxManifestBytes,
        limits.maxMarkerBytes,
        limits.maxTotalSourceBytes,
      ],
      [100000, 32, 4096, 262144, 4096, 16777216],
    );
  });

  test(
    'recognizing without optional arguments uses the declared defaults',
    () async {
      final root = await Directory.systemTemp.createTemp('shipflow-api-');
      addTearDown(() => root.delete(recursive: true));
      File(
        '${root.path}/pubspec.yaml',
      ).writeAsStringSync('name: app\nenvironment:\n  sdk: ^3.6.0\n');
      final implicit = await recognizeDartProject(root);
      final explicit = await recognizeDartProject(
        root,
        limits: const ScanLimits(),
        reportLimits: const ReportLimits(),
        contextSources: const [],
        authorizedOmissions: const [],
      );
      expect(jsonEncode(implicit.toJson()), jsonEncode(explicit.toJson()));
      expect(implicit.candidates.single.pluginId, 'plugin_dart');
    },
  );
}
