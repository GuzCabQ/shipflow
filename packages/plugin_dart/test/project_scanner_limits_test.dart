import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

void main() {
  final sandbox = ScanSandbox()..register();

  Future<ScanResult> scan(ScanLimits limits) =>
      scanProject(sandbox.root, limits: limits);

  group('profundidad', () {
    test('la raíz es la profundidad cero y el máximo es inclusivo', () async {
      sandbox.place('a/pubspec.yaml');
      final result = await scan(const ScanLimits(maxDepth: 2));
      expect(sourcePaths(result), ['a/pubspec.yaml']);
      expect(result.limitations, isEmpty);
    });

    test('lo que la excede corta esa rama y bloquea', () async {
      sandbox.place('a/pubspec.yaml');
      sandbox.place('a/b/pubspec.yaml');
      sandbox.place('z/pubspec.yaml');
      final result = await scan(const ScanLimits(maxDepth: 2));
      expect(sourcePaths(result), ['a/pubspec.yaml', 'z/pubspec.yaml']);
      expect(limitationsOf(result), ['scan_limit_reached:a/b:true']);
    });

    test('un directorio vacío en el máximo no bloquea', () async {
      sandbox.directory('a/b');
      expect((await scan(const ScanLimits(maxDepth: 2))).limitations, isEmpty);
    });
  });

  group('entradas', () {
    setUp(() {
      // a y build, más a/pubspec.yaml: tres entidades observadas. build se
      // cuenta aunque se excluya; lo que tiene dentro no se observa.
      sandbox.place('a/pubspec.yaml');
      sandbox.place('build/x');
    });

    test('las excluidas cuentan y el máximo es inclusivo', () async {
      final result = await scan(const ScanLimits(maxEntries: 3));
      expect(result.limitations, isEmpty);
      expect(sourcePaths(result), ['a/pubspec.yaml']);
    });

    test('el directorio que no cabe corta todo y bloquea', () async {
      final result = await scan(const ScanLimits(maxEntries: 2));
      expect(limitationsOf(result), ['scan_limit_reached:a:true']);
      expect(sourcePaths(result), isEmpty);
    });

    test('de un directorio que no cabe no se toma un subconjunto', () async {
      sandbox.place('pubspec.yaml');
      final result = await scan(const ScanLimits(maxEntries: 2));
      expect(limitationsOf(result), ['scan_limit_reached:.:true']);
      expect(sourcePaths(result), isEmpty);
    });

    test('la enumeración se detiene al agotar el presupuesto', () async {
      for (var i = 0; i < 1200; i++) {
        sandbox.place('f$i', '');
      }
      var pulled = 0;
      final result = await scanProject(
        sandbox.root,
        limits: const ScanLimits(maxEntries: 1),
        list: (directory) => listWithoutFollowing(directory).map((entity) {
          pulled++;
          return entity;
        }),
      );
      expect(pulled, lessThanOrEqualTo(2));
      expect(limitationsOf(result), ['scan_limit_reached:.:true']);
    });
  });

  group('manifiestos', () {
    setUp(() {
      sandbox.place('a/pubspec.yaml');
      sandbox.place('b/pubspec.yaml');
    });

    test('el máximo es inclusivo', () async {
      final result = await scan(const ScanLimits(maxManifests: 2));
      expect(sourcePaths(result), ['a/pubspec.yaml', 'b/pubspec.yaml']);
      expect(result.limitations, isEmpty);
    });

    test('el siguiente corta y conserva lo observado', () async {
      final result = await scan(const ScanLimits(maxManifests: 1));
      expect(sourcePaths(result), ['a/pubspec.yaml']);
      expect(limitationsOf(result), ['scan_limit_reached:b/pubspec.yaml:true']);
    });
  });

  group('bytes', () {
    setUp(() {
      sandbox.place('a/pubspec.yaml', 'name: a\n');
      sandbox.place('b/pubspec.yaml', 'name: bb\n');
    });

    test('cada fuente se cuenta una vez aunque se lea dos', () async {
      final result = await scan(const ScanLimits(maxTotalSourceBytes: 17));
      expect(sourcePaths(result), ['a/pubspec.yaml', 'b/pubspec.yaml']);
      expect(result.limitations, isEmpty);
    });

    test('la fuente que excede el total corta y bloquea', () async {
      final result = await scan(const ScanLimits(maxTotalSourceBytes: 16));
      expect(sourcePaths(result), ['a/pubspec.yaml']);
      expect(limitationsOf(result), ['scan_limit_reached:b/pubspec.yaml:true']);
    });

    test('un manifiesto sobredimensionado se informa y no se lee', () async {
      final result = await scan(const ScanLimits(maxManifestBytes: 8));
      expect(sourcePaths(result), ['a/pubspec.yaml']);
      expect(limitationsOf(result), ['source_too_large:b/pubspec.yaml:true']);
    });

    test('un marcador sobredimensionado también', () async {
      sandbox.place('.fvmrc', '{"flutter": "3.0.0"}');
      final result = await scan(const ScanLimits(maxMarkerBytes: 4));
      expect(limitationsOf(result), ['source_too_large:.fvmrc:true']);
    });
  });
}
