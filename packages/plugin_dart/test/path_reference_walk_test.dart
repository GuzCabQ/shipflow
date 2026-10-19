import 'dart:async';
import 'dart:io';

import 'package:plugin_dart/src/path_dependency_boundary.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

/// Lo que devuelve [placeReference] y cada ruta cuyo tipo consultó. Un
/// tramo sólo se da por inexistente después de consultar su tipo, así que
/// esta lista cubre cada ruta que el trayecto mira.
(ReferencePlacement, List<String>) placeSpying(
  Directory root,
  String declared, {
  String? Function(String path)? omittedTree,
}) {
  final queried = <String>[];
  final outer = Zone.current;
  final placement = IOOverrides.runZoned(
    () => placeReference(
      root,
      '.',
      declared,
      omittedTree: omittedTree ?? (_) => null,
    ),
    fseGetTypeSync: (path, followLinks) {
      queried.add(path);
      return outer.run(
        () => FileSystemEntity.typeSync(path, followLinks: followLinks),
      );
    },
  );
  return (placement, queried);
}

void main() {
  final sandbox = ScanSandbox()..register();
  late Directory outside;

  setUp(() {
    final made = Directory.systemTemp.createTempSync('shipflow-fuera-');
    outside = Directory(made.resolveSymbolicLinksSync());
    Directory('${outside.path}/present').createSync();
  });
  tearDown(() => outside.deleteSync(recursive: true));

  String inRoot(String path) => '${sandbox.root.path}/$path';

  group('the walk stops at its first boundary', () {
    test('a link, whatever its target, without looking past it', () {
      final alias = Link(inRoot('alias'))..createSync(outside.path);
      final (live, liveQueries) = placeSpying(sandbox.root, 'alias/present/x');
      alias
        ..deleteSync()
        ..createSync('${outside.path}/missing');
      final (broken, brokenQueries) = placeSpying(
        sandbox.root,
        'alias/present/x',
      );
      expect(live, isA<ReferenceLinked>());
      expect(broken, isA<ReferenceLinked>());
      expect(liveQueries, [inRoot('alias')]);
      expect(brokenQueries, [inRoot('alias')]);
    });

    test('leaving the root, whatever comes after', () {
      final parent = sandbox.root.parent.path;
      final name = outside.path.split('/').last;
      for (final declared in [
        '../$name/present',
        '../$name/missing/../present',
      ]) {
        final (placement, queries) = placeSpying(sandbox.root, declared);
        expect(placement, isA<ReferenceOutside>(), reason: declared);
        expect(queries, isEmpty, reason: '$declared in $parent');
      }
    });

    test('an absolute path elsewhere is outside without looking', () {
      final (placement, queries) = placeSpying(
        sandbox.root,
        '${outside.path}/present',
      );
      expect(placement, isA<ReferenceOutside>());
      expect(queries, isEmpty);
    });

    test('an absolute path under the root is walked from the root', () {
      sandbox.directory('b');
      final (placement, queries) = placeSpying(sandbox.root, inRoot('b'));
      expect((placement as ReferenceInside).path, 'b');
      expect(placement.exists, isTrue);
      expect(queries, [inRoot('b')]);
    });

    test('a file, before climbing out of it', () {
      sandbox.place('archivo', '');
      sandbox.directory('b');
      final (placement, queries) = placeSpying(sandbox.root, 'archivo/../b');
      expect(placement, isA<ReferenceUnresolved>());
      expect(queries, [inRoot('archivo')]);
    });

    test('an omitted tree, without looking at it', () {
      final (placement, queries) = placeSpying(
        sandbox.root,
        'build/../b',
        omittedTree: (path) => path == 'build' ? 'build' : null,
      );
      expect((placement as ReferenceExcluded).tree, 'build');
      expect(queries, isEmpty);
    });
  });

  test('ordinary directories inside the root are walked', () {
    sandbox.directory('a/c');
    sandbox.directory('b');
    final (placement, queries) = placeSpying(sandbox.root, 'a/c/../../b');
    expect((placement as ReferenceInside).path, 'b');
    expect(placement.exists, isTrue);
    expect(queries, [inRoot('a'), inRoot('a/c'), inRoot('b')]);
  });
}
