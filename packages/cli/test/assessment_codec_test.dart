import 'dart:convert';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_fixtures.dart';
import 'v2_fixtures.dart';

void main() {
  Object decoderFor(String schema, List<int> bytes) => switch (schema) {
    'assessment.schema.json' => decodeAssessment(bytes),
    'assessment-response.schema.json' => decodeAssessmentResponse(
      currentMajor(bytes, from: 1, to: 2),
    ),
    _ => decodeAssessmentTransaction(bytes),
  };

  // Cada fixture inválido cae por su propia regla, no por una incidental.
  const rejections = {
    'invalid-dangling.json': 'claim_target',
    'invalid-false-complete.json': 'witness_state',
    'invalid-witness-count.json': 'witness_counts',
    'invalid-local-no-target.json': 'claim_target',
    'invalid-parse-failed-claim.json': 'unparsed_claim',
    'invalid-path-escape.json': 'pattern',
    'invalid-date.json': 'observed_at',
    'invalid-digest.json': 'digest',
    'invalid-stale-success.json': 'stale_success',
    'invalid-transaction-target.json': 'candidate_path',
    'invalid-duplicate-key.json': 'duplicate_key',
    'invalid-omission-as-complete.json': 'coverage',
    'invalid-witness-producer.json': 'witness_identity',
    'invalid-file-input-path.json': 'file_input',
    'invalid-context-input-digest.json': 'context_input',
    'invalid-complete-with-omissions.json': 'witness_state',
    'invalid-duplicate-source-input.json': 'duplicate_input',
  };

  test('every package fixture is accepted or rejected as indexed', () async {
    final index = (await v3Json('index.json'))! as List<Object?>;
    for (final item in index.cast<Map<String, Object?>>()) {
      final name = item['file']! as String;
      final bytes = await v3Bytes(name);
      final schema = item['schema']! as String;
      if (item['valid']! as bool) {
        expect(() => decoderFor(schema, bytes), returnsNormally, reason: name);
      } else {
        expect(
          () => decoderFor(schema, bytes),
          rejectsAssessment(rejections[name]!),
          reason: name,
        );
      }
    }
    expect(
      index.where((i) => !((i! as Map<String, Object?>)['valid']! as bool)),
      hasLength(rejections.length),
    );
  });

  test('local claim must point to an included file', () async {
    final document = await loadAssessmentFixture('valid-local.json');
    expect(projectAssessment(document.current).single.claimIds, isNotEmpty);
    expect(
      () async => decodeAssessment(await v3Bytes('invalid-dangling.json')),
      throwsA(isA<ContextFormatException>()),
    );
  });

  test(
    'the size limit holds at its exact bound and rejects one more',
    () async {
      final bytes = await v3Bytes('valid-local.json');
      expect(decodeAssessment(bytes, maxBytes: bytes.length).revision, 1);
      expect(
        () => decodeAssessment(bytes, maxBytes: bytes.length - 1),
        rejectsAssessment('too_large', ContextFormatLayer.parser),
      );
    },
  );

  test('a duplicate key is rejected before any shape', () async {
    expect(
      () async => decodeAssessment(await v3Bytes('invalid-duplicate-key.json')),
      rejectsAssessment('duplicate_key', ContextFormatLayer.parser),
    );
  });

  Future<Map<String, Object?>> localJson() async =>
      (await v3Json('valid-local.json'))! as Map<String, Object?>;
  List<int> bytesOf(Object? json) => utf8.encode(jsonEncode(json));

  test('an altered snapshotId is rejected', () async {
    final json = await localJson();
    (json['current']! as Map<String, Object?>)['snapshotId'] = 'f' * 64;
    expect(() => decodeAssessment(bytesOf(json)), rejectsAssessment('digest'));
  });

  test('an id that is not derived from its content is rejected', () async {
    final json = await localJson();
    final current = json['current']! as Map<String, Object?>;
    final claim =
        (current['claims']! as List<Object?>).single! as Map<String, Object?>;
    claim['id'] = 'c_${'0' * 64}';
    current['snapshotId'] = snapshotIdOf(AssessmentSnapshot.fromJson(current));
    expect(
      () => decodeAssessment(bytesOf(json)),
      rejectsAssessment('claim_id'),
    );
  });

  test('another version or kind is not this document', () async {
    final version = await localJson();
    version['schemaVersion'] = 2;
    expect(
      () => decodeAssessment(bytesOf(version)),
      rejectsAssessment('const', ContextFormatLayer.schema),
    );
    final kind = await localJson();
    kind['kind'] = 'shipflow.project-context';
    expect(
      () => decodeAssessment(bytesOf(kind)),
      rejectsAssessment('const', ContextFormatLayer.schema),
    );
  });

  test('a stale or unverified response never succeeds', () async {
    expect(
      () async => decodeAssessmentResponse(
        currentMajor(
          await v3Bytes('invalid-stale-success.json'),
          from: 1,
          to: 2,
        ),
      ),
      rejectsAssessment('stale_success', ContextFormatLayer.semantic),
    );
  });

  test('the canonical identity matches the package Unicode vector', () async {
    final vectors =
        (await v3Json('canonical-vectors.json'))! as Map<String, Object?>;
    final keys = (vectors['unicodeKeysUtf16Order']! as List<Object?>)
        .cast<String>();
    final value = {for (final (i, k) in keys.indexed) k: i + 1};
    expect(canonicalAssessmentJson(value), vectors['unicodeCanonical']);
    expect(
      sha256Of(utf8.encode(canonicalAssessmentJson(value))),
      vectors['unicodeSha256'],
    );
    expect(assessmentIdOf(unitIdPrefix, unitTuple('.')), vectors['unitRootId']);
  });

  test('encoding is readable, ends in a newline and round trips', () async {
    final document = await loadAssessmentFixture('valid-local.json');
    final bytes = encodeAssessment(document);
    expect(utf8.decode(bytes), endsWith('}\n'));
    expect(utf8.decode(bytes), contains('\n  "kind": "shipflow.assessment"'));
    expect(decodeAssessment(bytes).toJson(), document.toJson());
  });
}
