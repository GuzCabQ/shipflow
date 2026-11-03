import 'package:cli/src/assessment/assessment_binding.dart';
import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/context/context_codec.dart';
import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

import 'support/assessment_fixtures.dart';

void main() {
  test('every context binding vector of the package holds', () async {
    final contextBytes = await v3Bytes('v2-project.json');
    final context = const ContextCodec().decodeProject(contextBytes);
    final cases =
        (await v3Json('context-binding-cases.json'))! as List<Object?>;
    for (final item in cases.cast<Map<String, Object?>>()) {
      final name = item['file']! as String;
      final document = decodeAssessment(await v3Bytes(name));
      String verdict;
      try {
        verdict = switch (bindToContext(
          projectId: document.projectId,
          snapshot: document.current,
          context: context,
          contextDigest: sha256Of(contextBytes),
          basisOf: projectDartAssessmentContext,
        )) {
          AssessmentBinding.matched => 'matched',
          AssessmentBinding.basisUnavailable => 'basis_unavailable',
        };
      } on ContextFormatException {
        verdict = 'rejected';
      }
      expect(verdict, item['expected'], reason: name);
    }
  });

  test('a foreign project is blocked even with a matching digest', () async {
    final contextBytes = await v3Bytes('v2-project.json');
    final context = const ContextCodec().decodeProject(contextBytes);
    final document = decodeAssessment(
      await v3Bytes('binding-foreign-project.json'),
    );
    expect(
      () => bindToContext(
        projectId: document.projectId,
        snapshot: document.current,
        context: context,
        contextDigest: sha256Of(contextBytes),
        basisOf: projectDartAssessmentContext,
      ),
      rejectsAssessment('project_identity'),
    );
  });
}
