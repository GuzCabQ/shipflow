import 'dart:io';

import 'package:test/test.dart';

import 'library_structure.dart';

void main() {
  late Directory lib;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('shipflow-estructura-');
    lib = Directory('${root.path}/lib')..createSync();
  });
  tearDown(() => lib.parent.delete(recursive: true));

  void put(String path, String text) => File('${lib.path}/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// Un árbol sano: el barrel exporta reconocimiento y assess, que dependen
  /// de observación; observación no depende de nadie.
  void healthy() {
    put(
      'plugin_dart.dart',
      "export 'src/recognition/r.dart';\nexport 'src/assessment/a.dart';\n",
    );
    put('src/recognition/r.dart', "import '../observation/o.dart';\n");
    put(
      'src/assessment/a.dart',
      "import 'package:plugin_dart/src/observation/o.dart';\n",
    );
    put(
      'src/observation/o.dart',
      "import 'dart:io';\nimport 'package:core/core.dart';\n",
    );
  }

  List<String> faults() => checkLibraryStructure(lib).faults;

  void expectFault(String reason) =>
      expect(faults(), contains(contains(reason)), reason: faults().join('\n'));

  group('the detector of the library structure', () {
    test('accepts a healthy tree and reports what it checked', () {
      healthy();
      final report = checkLibraryStructure(lib);
      expect(report.faults, isEmpty);
      expect(report.files, 4);
      expect(report.edges, 4);
    });

    test('S2 · a fact imported from its coordinator closes a cycle', () {
      healthy();
      put('src/recognition/facts.dart', "import 'scanner.dart';\n");
      put('src/recognition/scanner.dart', "import 'parser.dart';\n");
      put('src/recognition/parser.dart', "import 'facts.dart';\n");
      expectFault(
        'componente cíclico: src/recognition/facts.dart, '
        'src/recognition/parser.dart, src/recognition/scanner.dart',
      );
    });

    test('S3 · observation importing recognition', () {
      healthy();
      put('src/observation/o.dart', "import '../recognition/r.dart';\n");
      expectFault('dirección prohibida: observation → recognition');
    });

    test('a cycle closed only through an export', () {
      healthy();
      put('src/recognition/x.dart', "export 'y.dart';\n");
      put('src/recognition/y.dart', "import 'x.dart';\n");
      expectFault('componente cíclico: src/recognition/x.dart');
    });

    test('recognition and assessment in both directions', () {
      healthy();
      put('src/recognition/r.dart', "import '../assessment/a.dart';\n");
      expectFault('dirección prohibida: recognition → assessment');
      put('src/recognition/r.dart', '');
      put('src/assessment/a.dart', "import '../recognition/r.dart';\n");
      expectFault('dirección prohibida: assessment → recognition');
    });

    test('a library under src importing the public barrel', () {
      healthy();
      put(
        'src/recognition/r.dart',
        "import 'package:plugin_dart/plugin_dart.dart';\n",
      );
      expectFault('importa el barrel público');
      put('src/recognition/r.dart', "import '../../plugin_dart.dart';\n");
      expectFault('importa el barrel público');
    });

    test('a forbidden target hidden in a conditional alternative', () {
      healthy();
      put(
        'src/observation/o.dart',
        "import 'p.dart' if (dart.library.io) '../recognition/r.dart';\n",
      );
      put('src/observation/p.dart', '');
      expectFault('dirección prohibida: observation → recognition');
    });

    test('a cycle closed through a conditional alternative', () {
      healthy();
      put('src/recognition/x.dart', "import 'y.dart';\n");
      put(
        'src/recognition/y.dart',
        "import 'r.dart' if (dart.library.io) 'x.dart';\n",
      );
      expectFault('componente cíclico');
    });

    test('a local target that does not exist', () {
      healthy();
      put('src/recognition/r.dart', "import 'missing.dart';\n");
      expectFault('el destino «missing.dart» no existe');
    });

    test('a part directive', () {
      healthy();
      put('src/recognition/r.dart', "part 'r_part.dart';\n");
      put('src/recognition/r_part.dart', "part of 'r.dart';\n");
      expectFault('usa part/part of');
    });

    test('a library outside the three folders', () {
      healthy();
      put('src/loose.dart', '');
      expectFault(
        'src/loose.dart: fuera de recognition/, assessment/ y observation/',
      );
      File('${lib.path}/src/loose.dart').deleteSync();
      put('src/utilities/u.dart', '');
      expectFault('src/utilities/u.dart: fuera de');
    });

    test('an empty inventory is never healthy', () {
      expectFault('inventario vacío');
    });

    test('a library that does not parse', () {
      healthy();
      put(
        'src/recognition/r.dart',
        "import '../observation/o.dart'\nclass {\n",
      );
      expectFault('no se pudo parsear');
    });
  });
}
