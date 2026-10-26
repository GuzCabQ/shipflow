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

  group('S03: a write never lands on a foreign destination', () {
    test(
      'a target swapped for a link after the guard keeps the outside bytes',
      () async {
        box.file('shipflow/project.json', 'propio');
        final outside = box.outsideFile('ajeno', 'bytes ajenos');
        final store = await box.open(
          api: SwapBeforeRename(() {
            File(box.path('shipflow/project.json')).deleteSync();
            Link(box.path('shipflow/project.json')).createSync(outside.path);
          }),
        );
        await expectLater(
          store.publishRelative(
            'shipflow/project.json',
            utf8.encode('nuevo'),
            expectedSha256: hashOf(utf8.encode('propio')),
          ),
          completes,
        );
        expect(outside.readAsStringSync(), 'bytes ajenos');
        expect(
          FileSystemEntity.isLinkSync(box.path('shipflow/project.json')),
          isFalse,
        );
      },
    );

    test('a target that already is a link is refused, untouched', () async {
      final outside = box.outsideFile('ajeno', 'bytes ajenos');
      box.directory('shipflow');
      Link(box.path('shipflow/project.json')).createSync(outside.path);
      final store = await box.open();
      await expectLater(
        store.publishRelative(
          'shipflow/project.json',
          utf8.encode('nuevo'),
          expectedSha256: null,
        ),
        throwsA(storeFailure('unsafe_path')),
      );
      await expectLater(
        store.readRelative('shipflow/project.json', maxBytes: 99),
        throwsA(storeFailure('unsafe_path')),
      );
      expect(outside.readAsStringSync(), 'bytes ajenos');
      expect(
        Link(box.path('shipflow/project.json')).targetSync(),
        outside.path,
      );
    });

    test(
      'a FIFO is refused without blocking, for reading or writing',
      () async {
        box.directory('shipflow');
        await Process.run('mkfifo', [box.path('shipflow/project.json')]);
        final store = await box.open();
        await expectLater(
          store.readRelative('shipflow/project.json', maxBytes: 99),
          throwsA(storeFailure('unsafe_path')),
        );
        await expectLater(
          store.publishRelative(
            'shipflow/project.json',
            utf8.encode('x'),
            expectedSha256: null,
          ),
          throwsA(storeFailure('unsafe_path')),
        );
      },
    );

    test(
      'a path outside the root is refused before touching anything',
      () async {
        final store = await box.open();
        final before = box.snapshot();
        for (final path in [
          '../fuera',
          '/etc/passwd',
          'a/../b',
          'a//b',
          '',
          '.',
        ]) {
          await expectLater(
            store.publishRelative(path, utf8.encode('x'), expectedSha256: null),
            throwsA(storeFailure('unsafe_path')),
            reason: path,
          );
        }
        expect(box.snapshot(), before);
      },
    );

    test(
      'an intermediate link to outside is refused, outside unchanged',
      () async {
        final outside = box.outsideDirectory('ajena');
        Link(box.path('shipflow')).createSync(outside.path);
        final store = await box.open();
        await expectLater(
          store.publishRelative(
            'shipflow/project.json',
            utf8.encode('x'),
            expectedSha256: null,
          ),
          throwsA(storeFailure('unsafe_path')),
        );
        expect(outside.listSync(), isEmpty);
      },
    );

    test(
      'a hardlinked target is replaced without truncating its twin',
      () async {
        final outside = box.outsideFile('gemelo', 'compartido');
        box.directory('shipflow');
        await Process.run('ln', [
          outside.path,
          box.path('shipflow/project.json'),
        ]);
        final store = await box.open();
        await store.publishRelative(
          'shipflow/project.json',
          utf8.encode('nuevo'),
          expectedSha256: hashOf(utf8.encode('compartido')),
        );
        expect(outside.readAsStringSync(), 'compartido');
        expect(
          File(box.path('shipflow/project.json')).readAsStringSync(),
          'nuevo',
        );
      },
    );
  });

  group('publication follows the expected fingerprint', () {
    test('creates and reads a new version', () async {
      box.directory('shipflow');
      final store = await box.open();
      await store.publishRelative(
        'shipflow/project.json',
        utf8.encode('uno'),
        expectedSha256: null,
      );
      final read = await store.readRelative(
        'shipflow/project.json',
        maxBytes: 99,
      );
      expect(utf8.decode(read!), 'uno');
    });

    test('replaces only from the expected version', () async {
      box.file('shipflow/project.json', 'uno');
      final store = await box.open();
      for (final expected in [hashOf(utf8.encode('otro')), null]) {
        await expectLater(
          store.publishRelative(
            'shipflow/project.json',
            utf8.encode('dos'),
            expectedSha256: expected,
          ),
          throwsA(storeFailure('concurrent_change')),
        );
      }
      expect(File(box.path('shipflow/project.json')).readAsStringSync(), 'uno');
      expect(box.entriesOf('shipflow'), ['project.json']);
    });

    test('a failed flush is not success and leaves no temporary', () async {
      box.file('shipflow/project.json', 'vigente');
      final store = await box.open(api: FailingFlush());
      await expectLater(
        store.publishRelative(
          'shipflow/project.json',
          utf8.encode('nuevo'),
          expectedSha256: hashOf(utf8.encode('vigente')),
        ),
        throwsA(storeFailure('io')),
      );
      expect(
        File(box.path('shipflow/project.json')).readAsStringSync(),
        'vigente',
      );
      expect(box.entriesOf('shipflow'), ['project.json']);
    });

    test('reading at most the limit plus one byte', () async {
      box.file('shipflow/project.json', 'x' * 50);
      final store = await box.open();
      final bytes = await store.readRelative(
        'shipflow/project.json',
        maxBytes: 9,
      );
      expect(bytes, hasLength(10));
    });
  });
}
