@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_human.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_service_support.dart';

void main() {
  late AssessServiceBox box;
  setUp(() async => box = await AssessServiceBox.initialized());
  tearDown(() => box.dispose());

  Future<AssessmentResult> observe() => box.run(AssessmentOperation.observe);

  test('I1: a failure after the commit still says it was saved', () async {
    // Escrituras: candidato, journal, documento; la cuarta (journal
    // publicado) falla con I/O después del rename.
    box.storeWrap = (real) => FailingStore(real, 4);
    final result = await observe();
    expect(box.document.existsSync(), isTrue);
    expect(result.exitCode, 74);
    expect(result.effects.published, isTrue);
    expect(result.effects.created, contains(assessmentPath));
    expect(diagnosticCodes(result), contains('assessment_recovery_pending'));
    expect(
      humanAssessment(result, root: '/r'),
      isNot(contains('no se escribió nada')),
    );
  });

  test('I2: a temporary without journal is not "nothing to recover"', () async {
    await observe();
    final temporary = File(
      box.path(
        'shipflow/local/.assessment-transaction.json.0123456789abcdef.tmp',
      ),
    )..writeAsStringSync('{');
    final result = await box.run(AssessmentOperation.recover);
    expect(result.exitCode, 75);
    expect(diagnosticCodes(result), contains('recovery_conflict'));
    expect(temporary.existsSync(), isTrue);
  });

  test(
    'I3: one oversized reference is a local gap, not a blocked run',
    () async {
      box.box.file(
        'lib/larga.dart',
        "import 'package:remote/${'x' * 5000}.dart';\n",
      );
      box.box.file('lib/relativa.dart', "import '${'y' * 4500}.dart';\n");
      final result = await observe();
      expect(
        result.effects.published,
        isTrue,
        reason: '${diagnosticCodes(result)}',
      );
      expect(diagnosticCodes(result), isNot(contains('assessment_limit')));
      final reasons = result.snapshot!.claims.map((c) => c.reason).toSet();
      expect(reasons, contains('unsafe_uri'));
    },
  );

  test(
    'I4: a corrupted assessment never blocks the context commands',
    () async {
      await observe();
      box.document.writeAsStringSync('<<<<<<< HEAD\n{}\n');
      expect((await box.v2(ContextOperation.doctor)).exitCode, 0);
      box.box.file('packages/widgets/pubspec.yaml', 'name: widgets\n# r2\n');
      expect((await box.v2(ContextOperation.refresh)).exitCode, 0);
      final assess = await observe();
      expect(assess.exitCode, 65);
      expect(diagnosticCodes(assess), contains('assessment_invalid'));
      expect(
        humanAssessment(assess, root: '/r'),
        contains('muévelo fuera de shipflow'),
      );
      expect(box.document.readAsStringSync(), startsWith('<<<<<<<'));
    },
  );

  test(
    'I5: a declared dependency never claims where it was declared',
    () async {
      final human = humanAssessment(await observe(), root: '/r');
      expect(
        human,
        isNot(contains('declarada en packages/widgets/pubspec.yaml')),
      );
      expect(human, contains('evidencia: '));
    },
  );

  test(
    'a manifest changed after the preflight is a change, not a defect',
    () async {
      box.observerWrap = (real) => (root, context, limits) {
        box.box.file(
          'packages/widgets/pubspec.yaml',
          'name: widgets\n# tarde\n',
        );
        return real(root, context, limits);
      };
      final result = await observe();
      expect(result.exitCode, 75);
      expect(diagnosticCodes(result), contains('source_changed'));
      expect(diagnosticCodes(result), isNot(contains('unexpected')));
    },
  );
}
