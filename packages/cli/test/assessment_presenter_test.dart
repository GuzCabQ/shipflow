@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_human.dart';
import 'package:cli/src/assessment/assessment_presenter.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_fixtures.dart';
import 'support/assessment_service_support.dart';

void main() {
  group('over a real observation', () {
    late AssessServiceBox box;
    late AssessmentResult saved;
    setUp(() async {
      box = await AssessServiceBox.initialized();
      saved = await box.run(AssessmentOperation.observe);
    });
    tearDown(() => box.dispose());

    test('roundTripPreservesEvidenceAndLimits', () async {
      final json = presentAssessment(saved, json: true, root: '/r').payload;
      final decoded = decodeAssessmentResponse(utf8.encode(json));
      expect(decoded.toJson(), saved.toJson());
      final disk = decodeAssessment(box.document.readAsBytesSync()).current;
      expect(disk.toJson(), saved.snapshot!.toJson());
      expect(
        projectAssessment(disk).map((c) => c.toJson()),
        projectAssessment(saved.snapshot!).map((c) => c.toJson()),
      );
    });

    test('both views come from the same result', () {
      final human = humanAssessment(saved, root: '/r');
      expect(human, startsWith('Levantamiento guardado\n'));
      expect(human, contains('app → widgets: 1 referencia\n'));
      expect(human, isNot(contains('(always)')));
      expect(
        human,
        contains('lib/main.dart:1:1 → packages/widgets/lib/widget.dart'),
      );
      expect(human, contains('Dependencias declaradas (la declaración no '));
      expect(human, isNot(contains('sin uso')));
      expect(human, isNot(contains('sin impacto')));
      final body =
          jsonDecode(presentAssessment(saved, json: true, root: '/r').payload)
              as Map<String, Object?>;
      expect(
        (body['kind'], body['command'], body['operation']),
        ('shipflow.assessment-response', 'assess', 'observe'),
      );
    });

    test('publishedPartialExit65IsNotComplete', () async {
      box.box.file('lib/roto.dart', 'class {');
      await box.v2(ContextOperation.init);
      final partial = await box.run(AssessmentOperation.observe);
      expect((partial.exitCode, partial.effects.published), (65, true));
      expect(partial.coverage, AssessmentCoverage.partial);
      final human = humanAssessment(partial, root: '/r');
      expect(human, startsWith('Levantamiento parcial guardado'));
      expect(human, contains('archivos que el parser no aceptó: 1'));
    });

    test('an oversized JSON is compact with its true effects', () {
      final compact = presentAssessment(
        saved,
        json: true,
        root: '/r',
        maxJsonBytes: 100,
      );
      final decoded = decodeAssessmentResponse(utf8.encode(compact.payload));
      expect(decoded.snapshot, isNull);
      expect(decoded.effects.toJson(), saved.effects.toJson());
      expect(compact.exitCode, saved.exitCode);
    });
  });

  test('historicalPartialExitZeroIsStillHistoricalPartial', () async {
    final result = decodeAssessmentResponse(
      await v3Bytes('valid-historical-partial-response.json'),
    );
    expect(result.exitCode, 0);
    final human = humanAssessment(result, root: '/r');
    expect(human, startsWith('Levantamiento anterior parcial (histórico)'));
    expect(human, contains('no se certifica vigente'));
  });

  test('counts read as words, not as wire values', () async {
    final local = await loadAssessmentFixture('valid-zero-references.json');
    final human = humanAssessment(_shown(local.current), root: '/r');
    expect(human, contains('Pruebas presentes: ningún archivo'));
    expect(human, contains('Referencias: ninguna en total'));
  });

  test('S3: a declared-only dependency is never shown as observed', () async {
    final local = await loadAssessmentFixture('valid-zero-references.json');
    final human = humanAssessment(_shown(local.current), root: '/r');
    expect(human, contains('Conexiones comprobadas entre unidades: ninguna'));
    expect(human, isNot(contains('→')));
  });

  test('project strings are escaped for the terminal', () async {
    final local = await loadAssessmentFixture('valid-local.json');
    final json = local.current.toJson();
    ((json['units']! as List<Object?>).first!
            as Map<String, Object?>)['label'] =
        '\u001b[31mrojo\u202e';
    final human = humanAssessment(
      _shown(AssessmentSnapshot.fromJson(json)),
      root: '/r\nfalsa',
    );
    expect(human, isNot(contains('\u001b')));
    expect(human, isNot(contains('\u202e')));
    expect(human, contains(r'\x1b[31mrojo'));
    expect(human, contains(r'/r\nfalsa'));
  });
}

AssessmentResult _shown(AssessmentSnapshot snapshot) => AssessmentResult(
  operation: AssessmentOperation.show,
  exitCode: 0,
  outcome: AssessmentOutcome.shown,
  freshness: AssessmentFreshness.current,
  coverage: snapshot.coverage,
  snapshot: snapshot,
  diagnostics: const [],
  effects: AssessmentEffects(
    created: const [],
    replaced: const [],
    removed: const [],
    published: false,
    gitQueries: 0,
  ),
  nextActions: const [],
  comparison: null,
  retiredRevision: null,
);
