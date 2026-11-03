@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';

/// El contenedor admite 16.384 archivos (REV-V3-001 R9): un proyecto que lo
/// excede no se publica entero en ningún perfil, y no es un defecto.
void main() {
  late AssessServiceBox box;
  setUpAll(() async {
    box = await AssessServiceBox.initialized(
      files: {'pubspec.yaml': 'name: app\n'},
    );
    Directory(box.path('lib')).createSync();
    for (var i = 0; i <= 16384; i++) {
      File(box.path('lib/f$i.dart')).writeAsStringSync('');
    }
  });
  tearDownAll(() => box.dispose());

  Future<AssessmentResult> observe(AssessmentProfile profile) =>
      box.run(AssessmentOperation.observe, profile: profile);

  test(
    'one file over the container is assessment_limit in both profiles',
    () async {
      for (final profile in AssessmentProfile.values) {
        final result = await observe(profile);
        expect(result.exitCode, 65, reason: '$profile');
        expect(diagnosticCodes(result), contains('assessment_limit'));
        expect(diagnosticCodes(result), isNot(contains('unexpected')));
        expect(result.effects.published, isFalse);
        expect(box.document.existsSync(), isFalse);
      }
    },
  );

  test(
    'exactly the container fits: extended complete, standard partial',
    () async {
      File(box.path('lib/f16384.dart')).deleteSync();
      final standard = await observe(AssessmentProfile.standard);
      expect(standard.exitCode, 65);
      expect(standard.effects.published, isTrue);
      expect(diagnosticCodes(standard), contains('coverage_partial'));
      expect(standard.snapshot!.files, hasLength(16384));
      final extended = await observe(AssessmentProfile.extended);
      expect(extended.exitCode, 0, reason: '${diagnosticCodes(extended)}');
      expect(extended.coverage, AssessmentCoverage.complete);
      expect(extended.effects.published, isTrue);
    },
  );
}
