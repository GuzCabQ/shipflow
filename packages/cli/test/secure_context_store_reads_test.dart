@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'support/context_store_support.dart';

String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

void main() {
  late StoreSandbox box;
  setUp(() async => box = await StoreSandbox.create());
  tearDown(() => box.dispose());

  group('reads never change the tree', () {
    test('an absent record is not created by reading', () async {
      final store = await box.open();
      final before = box.snapshot();
      expect(
        await store.readRelative('shipflow/project.json', maxBytes: 9),
        isNull,
      );
      expect(
        await store.readRelative('shipflow/local/settings.json', maxBytes: 9),
        isNull,
      );
      expect(box.snapshot(), before);
    });

    test('a denied directory is an I/O failure, not absence', () async {
      box.file('shipflow/project.json', 'x');
      await Process.run('chmod', ['000', box.path('shipflow')]);
      addTearDown(() => Process.run('chmod', ['755', box.path('shipflow')]));
      final store = await box.open();
      await expectLater(
        store.readRelative('shipflow/project.json', maxBytes: 9),
        throwsA(storeFailure('io')),
      );
    });
  });

  group('directories and removal', () {
    test('creates nested directories once and refuses a link', () async {
      final store = await box.open();
      expect(await store.createDirectory('shipflow/local/locks'), [
        'shipflow',
        'shipflow/local',
        'shipflow/local/locks',
      ]);
      expect(await store.createDirectory('shipflow/local'), isEmpty);
      Link(box.path('otra')).createSync(box.outsideDirectory('x').path);
      await expectLater(
        store.createDirectory('otra'),
        throwsA(storeFailure('unsafe_path')),
      );
    });

    test('removes only the expected version', () async {
      box.file('shipflow/local/transaction.json', 'diario');
      final store = await box.open();
      await expectLater(
        store.removeRelative(
          'shipflow/local/transaction.json',
          expectedSha256: hashOf(utf8.encode('otro')),
        ),
        throwsA(storeFailure('concurrent_change')),
      );
      await store.removeRelative(
        'shipflow/local/transaction.json',
        expectedSha256: hashOf(utf8.encode('diario')),
      );
      expect(box.entriesOf('shipflow/local'), isEmpty);
    });

    test('unknownBootstrapTemporaryIsPreserved', () async {
      box.file('shipflow/.project.json.desconocido.tmp', 'resto');
      final store = await box.open();
      await store.publishRelative(
        'shipflow/project.json',
        utf8.encode('x'),
        expectedSha256: null,
      );
      await store.readRelative('shipflow/project.json', maxBytes: 9);
      expect(
        File(
          box.path('shipflow/.project.json.desconocido.tmp'),
        ).readAsStringSync(),
        'resto',
      );
    });
  });

  group('leases', () {
    test(
      'a second lease on the same resource is busy, release is idempotent',
      () async {
        box.directory('shipflow/local/locks');
        final store = await box.open();
        final lease = await store.acquirePublication([store.contextLock()]);
        final other = await box.open();
        await expectLater(
          other.acquirePublication([other.contextLock()]),
          throwsA(storeFailure('busy')),
        );
        await lease.release();
        await lease.release();
        final again = await other.acquirePublication([other.contextLock()]);
        await again.release();
        expect(box.entriesOf('shipflow/local/locks'), ['context.lock']);
      },
    );

    test('the lock file is opened without truncating it', () async {
      box.file('shipflow/local/locks/context.lock', 'no se trunca');
      final store = await box.open();
      final lease = await store.acquirePublication([store.contextLock()]);
      await lease.release();
      expect(
        File(box.path('shipflow/local/locks/context.lock')).readAsStringSync(),
        'no se trunca',
      );
    });
  });
}
