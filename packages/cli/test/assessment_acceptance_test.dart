@Timeout(Duration(minutes: 3))
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';

/// Un proyecto Flutter recién creado, saneado: una sola unidad, su prueba
/// de ejemplo y referencias sólo externas o internas a la unidad.
const _flutterMinimal = {
  'pubspec.yaml': '''
name: minimo
environment:
  sdk: ^3.6.0
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
''',
  'lib/main.dart': '''
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp());
''',
  'test/widget_test.dart': '''
import 'package:flutter_test/flutter_test.dart';
import 'package:minimo/main.dart';

void main() => testWidgets('arranca', (tester) async => main());
''',
};

void main() {
  late AssessServiceBox box;
  setUp(() async {
    box = await AssessServiceBox.initialized(files: _flutterMinimal);
  });
  tearDown(() => box.dispose());

  test(
    'a new project without inter-unit edges is complete, not failed',
    () async {
      final saved = await box.run(AssessmentOperation.observe);
      expect(
        (saved.outcome, saved.exitCode, saved.coverage),
        (AssessmentOutcome.saved, 0, AssessmentCoverage.complete),
      );
      final snapshot = saved.snapshot!;
      expect(snapshot.units.single.label, 'minimo');
      expect(
        projectAssessment(
          snapshot,
        ).where((c) => c.sourceUnitId != c.targetUnitId),
        isEmpty,
      );
      final tests = snapshot.files.where(
        (f) => f.role == AssessmentFileRole.test,
      );
      expect(tests.map((f) => f.path), ['test/widget_test.dart']);
      expect(
        snapshot.claims.where(
          (c) => c.resolution == AssessmentResolution.external,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'the same inventory with the detector not run is never complete',
    () async {
      // Sin presupuesto de fuentes el detector no procesa nada: mismo
      // inventario, cero afirmaciones, y nunca completo.
      final standard = AssessmentLimits.forProfile(AssessmentProfile.standard);
      box.limitsFor = (_) =>
          AssessmentLimits.fromJson(standard.toJson()..['maxSourceFiles'] = 0);
      final notRun = await box.run(AssessmentOperation.observe);
      expect(notRun.coverage, AssessmentCoverage.partial);
      expect(notRun.exitCode, 65);
      final references = notRun.snapshot!.witnesses.singleWhere(
        (w) => w.capability == AssessmentCapability.sourceReferences,
      );
      expect(references.state, AssessmentWitnessState.notRun);
      expect(notRun.snapshot!.claims, isEmpty);
    },
  );
}
