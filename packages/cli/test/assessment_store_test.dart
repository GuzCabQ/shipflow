@Timeout(Duration(minutes: 2))
library;

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_store.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:test/test.dart';

import 'support/assessment_store_support.dart';

void main() {
  late AssessmentBox box;
  setUp(() async => box = await AssessmentBox.initialized());
  tearDown(() => box.dispose());

  test(
    'a first publication creates the document and leaves nothing else',
    () async {
      final (first, _) = await twoRevisions();
      final before = box.state();
      final publication = await box.publish(first);
      expect(publication.published, isTrue);
      expect(publication.created, ['shipflow/assessment.json']);
      final after = box.state()..removeWhere((k, _) => before.containsKey(k));
      expect(after.keys, ['shipflow/assessment.json']);
      final read = await box.withStore((s) => s.read());
      expect(read.document!.toJson(), first.toJson());
    },
  );

  test('a new revision replaces current and keeps it as previous', () async {
    final (first, second) = await twoRevisions();
    await box.publish(first);
    final expected = sha256Of(box.document.readAsBytesSync());
    final publication = await box.publish(
      second,
      expected: expected,
      operationId: operationB,
    );
    expect(publication.replaced, ['shipflow/assessment.json']);
    final read = await box.withStore((s) => s.read());
    expect(read.document!.previous!.snapshotId, first.current.snapshotId);
  });

  test('an unexpected current version is never overwritten', () async {
    final (first, second) = await twoRevisions();
    await box.publish(first);
    final bytes = box.document.readAsBytesSync();
    await expectLater(
      box.publish(second, expected: 'f' * 64, operationId: operationB),
      throwsA(
        isA<AssessmentAbort>().having(
          (a) => a.code,
          'code',
          'concurrent_change',
        ),
      ),
    );
    expect(box.document.readAsBytesSync(), bytes);
  });

  test(
    'S1: a source changed before the commit keeps the previous bytes',
    () async {
      final (first, second) = await twoRevisions();
      await box.publish(first);
      final bytes = box.document.readAsBytesSync();
      final before = box.state();
      await expectLater(
        box.publish(
          second,
          expected: sha256Of(bytes),
          operationId: operationB,
          revalidate: () async => throw const AssessmentAbort('source_changed'),
        ),
        throwsA(isA<AssessmentAbort>()),
      );
      expect(box.document.readAsBytesSync(), bytes);
      expect(box.state(), before);
    },
  );

  test('a second writer finds the shared lock busy', () async {
    final (first, _) = await twoRevisions();
    final other = await SecureContextStore.open(box.box.root);
    addTearDown(other.close);
    final lease = await other.acquirePublication([other.contextLock()]);
    addTearDown(lease.release);
    await expectLater(
      box.publish(first),
      throwsA(isA<ContextStoreFailure>().having((f) => f.code, 'code', 'busy')),
    );
    expect(box.document.existsSync(), isFalse);
  });
}
