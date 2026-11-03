@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/src/assessment/assessment_store.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/assessment_store_support.dart';

void main() {
  late AssessmentBox box;
  late AssessmentDocument first;
  late Directory outside;
  setUp(() async {
    box = await AssessmentBox.initialized();
    (first, _) = await twoRevisions();
    outside = Directory.systemTemp.createTempSync('shipflow-fuera-');
  });
  tearDown(() {
    box.dispose();
    outside.deleteSync(recursive: true);
  });

  final refused = throwsA(
    anyOf(isA<ContextStoreFailure>(), isA<AssessmentAbort>()),
  );

  test(
    'a document replaced by a link is never followed nor truncated',
    () async {
      final target = File('${outside.path}/ajeno.json')
        ..writeAsStringSync('ajeno');
      Link(box.path('shipflow/assessment.json')).createSync(target.path);
      await expectLater(box.publish(first), refused);
      expect(target.readAsStringSync(), 'ajeno');
      expect(
        FileSystemEntity.typeSync(
          box.path('shipflow/assessment.json'),
          followLinks: false,
        ),
        FileSystemEntityType.link,
      );
    },
  );

  test('a FIFO in place of the document is not opened', () async {
    await Process.run('mkfifo', [box.path('shipflow/assessment.json')]);
    await expectLater(
      box
          .withStore((store) => store.read())
          .timeout(const Duration(seconds: 5)),
      refused,
    );
  });

  test(
    'a staging directory swapped for a link writes nothing outside',
    () async {
      Link(
        box.path('shipflow/local/assessment-staging'),
      ).createSync(outside.path);
      await expectLater(box.publish(first), refused);
      expect(outside.listSync(), isEmpty);
      expect(box.document.existsSync(), isFalse);
    },
  );
}
