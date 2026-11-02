import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_service.dart';
import 'package:cli/src/assessment/assessment_store.dart';
import 'package:cli/src/cli_command.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'context_service_support.dart';

/// Un proyecto de dos paquetes inicializado por V2 sin Git, con assess
/// compuesto como en producción: detector real, inventario real y doctor
/// V2 real. Cuenta cuántas veces corre el detector.
final class AssessServiceBox {
  AssessServiceBox._(this.box);

  static Future<AssessServiceBox> initialized({bool init = true}) async {
    final box = ServiceSandbox.create();
    box.file('pubspec.yaml', '''
name: app
environment:
  sdk: ^3.6.0
dependencies:
  widgets:
    path: packages/widgets
''');
    box.file('packages/widgets/pubspec.yaml', 'name: widgets\n');
    box.file('packages/widgets/lib/widget.dart', 'class W {}\n');
    box.file('lib/main.dart', "import 'package:widgets/widget.dart';\n");
    box.file('lib/other.dart', "import 'main.dart';\n");
    box.file('README.md', '# app\n');
    final assess = AssessServiceBox._(box);
    if (init) await assess.v2(ContextOperation.init);
    return assess;
  }

  final ServiceSandbox box;
  var observations = 0;
  var clock = DateTime.utc(2026, 11, 2, 12);
  Map<String, String>? git;

  /// Una envoltura del detector real, para provocar cambios durante una
  /// observación.
  AssessmentObserver Function(AssessmentObserver real)? observerWrap;
  AssessmentLimits Function(AssessmentProfile)? limitsFor;

  String path(String relative) => box.path(relative);
  File get document => File(path(assessmentPath));

  Future<ContextOperationResult> v2(ContextOperation operation) =>
      box.run(operation, git: git);

  Future<AssessmentResult> run(
    AssessmentOperation operation, {
    bool previous = false,
    AssessmentProfile profile = AssessmentProfile.standard,
  }) async {
    final store = await SecureContextStore.open(box.root);
    try {
      return await _service(store).run(
        AssessmentRequest(
          operation: operation,
          profile: profile,
          previous: previous,
        ),
      );
    } finally {
      await store.close();
    }
  }

  AssessmentService _service(ContextStore store) {
    Future<AssessmentObservation> counted(
      Directory root,
      ProjectContext context,
      AssessmentLimits limits,
    ) {
      observations++;
      return observeDartSources(root, context, limits);
    }

    return AssessmentService(
      root: box.root,
      store: store,
      observe: observerWrap?.call(counted) ?? counted,
      observeInputs: observeDartInputs,
      basisOf: projectDartAssessmentContext,
      doctor: (profile) => box.run(
        ContextOperation.doctor,
        git: git,
        profile: profile == AssessmentProfile.extended
            ? ReportBudgetProfile.extended
            : ReportBudgetProfile.standard,
      ),
      version: '0.0.0-prueba',
      now: () => clock,
      newId: box.newId,
      limitsFor: limitsFor,
    );
  }

  /// Tipo y bytes de cada entrada del proyecto, para probar que no se
  /// escribió nada.
  Map<String, String> snapshot() => box.snapshot();

  void dispose() => box.dispose();
}

List<String> diagnosticCodes(AssessmentResult r) => [
  for (final d in r.diagnostics) d.code,
];

/// Cada acción propuesta como su línea de argumentos.
List<String> actionArgs(AssessmentResult r) => [
  for (final a in r.nextActions) a.argv.join(' '),
];

/// Una publicación real que muere después de staging y journal.
Future<void> interruptPublication(AssessServiceBox box) async {
  final bytes = box.document.readAsBytesSync();
  final saved = decodeAssessment(bytes);
  final candidate = AssessmentDocument(
    projectId: saved.projectId,
    revision: saved.revision + 1,
    current: saved.current,
    previous: saved.current,
  );
  final real = await SecureContextStore.open(box.box.root);
  try {
    await expectLater(
      AssessmentStore(CrashingStore(real, 2)).publish(
        candidate,
        operationId: '44444444-4444-4444-8444-444444444444',
        expectedSha256: sha256Of(bytes),
        baseContextDigest: saved.current.contextDigest,
        preconditions: () async {},
        revalidate: () async {},
      ),
      throwsA(isA<SimulatedCrash>()),
    );
  } finally {
    await real.close();
  }
}
