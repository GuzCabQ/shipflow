@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_fixtures.dart';
import 'support/assessment_store_support.dart';

void main() {
  late AssessmentBox box;
  setUp(() async => box = await AssessmentBox.initialized());
  tearDown(() => box.dispose());

  /// Un snapshot válido del paquete con [excluded] árboles excluidos más,
  /// para que el documento con dos revisiones pase de 16 MiB.
  Future<AssessmentSnapshot> large(int excluded, String seed) async {
    final base = (await loadAssessmentFixture('valid-local.json')).current;
    final json = base.toJson();
    final inputs =
        (json['inputs']! as List<Object?>).cast<Map<String, Object?>>()
          ..addAll([
            for (var i = 0; i < excluded; i++)
              {
                'path': 'excluido/$seed/${i.toString().padLeft(6, '0')}',
                'kind': 'excluded',
                'state': 'excluded',
                'sha256': null,
                'reason': 'baseline_exclusion',
              },
          ])
          ..sort(
            (a, b) => (a['path']! as String).compareTo(b['path']! as String),
          );
    json['inputs'] = inputs;
    final witness = (json['witnesses']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere((w) => w['capability'] == 'source_inventory');
    witness
      ..['expected'] = inputs.length
      ..['processed'] = inputs.length;
    json['snapshotId'] = snapshotIdOf(AssessmentSnapshot.fromJson(json));
    return AssessmentSnapshot.fromJson(json);
  }

  test(
    'documents over 16 MiB are replaced and cleaned like any other',
    () async {
      final first = await large(70000, 'a');
      final second = await large(70001, 'b');
      final third = await large(70002, 'c');
      final projectId = (await loadAssessmentFixture(
        'valid-local.json',
      )).projectId;
      var expected = null as String?;
      var previous = null as AssessmentSnapshot?;
      for (final (revision, current) in [(1, first), (2, second), (3, third)]) {
        final document = AssessmentDocument(
          projectId: projectId,
          revision: revision,
          current: current,
          previous: previous,
        );
        final publication = await box.publish(
          document,
          expected: expected,
          operationId: '2222222$revision-2222-4222-8222-222222222222',
        );
        expect(publication.published, isTrue, reason: 'revisión $revision');
        expect(
          File(box.path(assessmentJournalPath)).existsSync(),
          isFalse,
          reason: 'revisión $revision',
        );
        expected = sha256Of(box.document.readAsBytesSync());
        previous = current;
      }
      expect(box.document.lengthSync(), greaterThan(16 * 1024 * 1024));
    },
  );
}
