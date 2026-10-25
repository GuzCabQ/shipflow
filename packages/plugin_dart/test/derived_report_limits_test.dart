import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/src/dart_project_recognizer.dart';
import 'package:plugin_dart/src/derived_observation_budget.dart';
import 'package:plugin_dart/src/project_scanner.dart';
import 'package:test/test.dart';

import 'scan_support.dart';

Matcher exceeds(ReportLimitDimension dimension) => throwsA(
  isA<ReportLimitExceeded>().having((e) => e.dimension, 'dimension', dimension),
);

/// Un iterable que cuenta cuántos elementos se le piden: observa la
/// producción en vez de confiar en un contador que ella misma reporta.
final class CountingIterable extends Iterable<int> {
  CountingIterable(this.length);

  @override
  final int length;
  var pulled = 0;

  @override
  Iterator<int> get iterator => _Counting(this);
}

final class _Counting implements Iterator<int> {
  _Counting(this.source);

  final CountingIterable source;
  var _index = -1;

  @override
  int get current => _index;

  @override
  bool moveNext() {
    if (_index + 1 >= source.length) return false;
    _index++;
    source.pulled++;
    return true;
  }
}

void main() {
  final sandbox = ScanSandbox()..register();

  Future<RecognitionContribution> recognize(ReportLimits limits) =>
      recognizeDartProject(sandbox.root, reportLimits: limits);

  group('admitEach', () {
    test('se detiene en el que no cabe, sin construirlo ni pedir más', () {
      final source = CountingIterable(1000000);
      final built = <int>[];
      final budget = DerivedObservationBudget(
        const ReportLimits(maxDerivedItems: 10),
      );
      expect(
        () => budget
            .admitEach(source, textsOf: (_) => const [], build: built.add)
            .toList(),
        exceeds(ReportLimitDimension.items),
      );
      expect(source.pulled, 11);
      expect(built, hasLength(10));
    });
  });

  group('un manifiesto mínimo cobra exactamente lo que retiene', () {
    // name «añ»: una evidencia (21 + 12 + 3 + 71 bytes, rol identity 8 y
    // etiqueta 18, id 5), el candidato dart (4 + 4 + 11) y su referencia
    // (5), la unidad u0001 (5 + 3 + 12 + 1) y su referencia (5): 5 elementos
    // y 188 bytes. El ensamblador suma la propuesta y el alcance del reporte.
    setUp(() => sandbox.place('pubspec.yaml', 'name: añ\n'));

    test('5 elementos caben y 4 no', () async {
      await recognize(const ReportLimits(maxDerivedItems: 5));
      await expectLater(
        recognize(const ReportLimits(maxDerivedItems: 4)),
        exceeds(ReportLimitDimension.items),
      );
    });

    test('el ensamblador vuelve a contar lo mismo, más la propuesta', () async {
      final contribution = await recognize(const ReportLimits());
      RecognitionReport assemble(ReportLimits limits) =>
          _assemble(sandbox.root, contribution, limits);
      final proposalBytes = _proposalBytes();
      assemble(
        ReportLimits(
          maxDerivedItems: 7,
          maxDerivedTextBytes: 188 + proposalBytes + _scopeBytes,
        ),
      );
      expect(
        () => assemble(const ReportLimits(maxDerivedItems: 6)),
        exceeds(ReportLimitDimension.items),
      );
      expect(
        () => assemble(
          ReportLimits(maxDerivedTextBytes: 187 + proposalBytes + _scopeBytes),
        ),
        exceeds(ReportLimitDimension.textBytes),
      );
    });

    test('188 bytes caben y 187 no', () async {
      await recognize(const ReportLimits(maxDerivedTextBytes: 188));
      await expectLater(
        recognize(const ReportLimits(maxDerivedTextBytes: 187)),
        exceeds(ReportLimitDimension.textBytes),
      );
    });
  });

  test('una lista workspace repetida se corta al llenarse', () async {
    // 20.000 miembros de unos 104 bytes cada uno: el texto (1 MiB) se agota
    // antes que los 16.384 elementos.
    sandbox.place(
      'pubspec.yaml',
      'name: r\nworkspace:\n${'  - pkg\n' * 20000}',
    );
    await expectLater(
      recognize(const ReportLimits()),
      exceeds(ReportLimitDimension.textBytes),
    );
    await expectLater(
      recognize(const ReportLimits(maxDerivedTextBytes: 1 << 30)),
      exceeds(ReportLimitDimension.items),
    );
  });

  test('las dependencias locales también se cobran una por una', () async {
    sandbox.place('pubspec.yaml', '''
name: r
dependencies:
${[for (var i = 0; i < 40; i++) '  d$i: {path: d$i}'].join('\n')}
''');
    await expectLater(
      recognize(const ReportLimits(maxDerivedItems: 30)),
      exceeds(ReportLimitDimension.items),
    );
  });

  test('el escáner cobra sus limitaciones antes de crearlas', () async {
    for (var i = 0; i < 20; i++) {
      Link('${sandbox.root.path}/l$i').createSync(sandbox.root.path);
    }
    await expectLater(
      recognize(const ReportLimits(maxDerivedItems: 10)),
      exceeds(ReportLimitDimension.items),
    );
  });

  test('un nombre repetido referencia todas sus evidencias', () async {
    for (var i = 0; i < 12; i++) {
      sandbox.place('p$i/pubspec.yaml', 'name: igual\n');
    }
    // 12 evidencias, 12 unidades con una referencia cada una, el candidato
    // con 12 y el conflicto con otras 12: 12 + 24 + 13 + 13 = 62.
    await recognize(const ReportLimits(maxDerivedItems: 62));
    await expectLater(
      recognize(const ReportLimits(maxDerivedItems: 61)),
      exceeds(ReportLimitDimension.items),
    );
  });

  test('los conflictos de versiones se cobran antes de su mensaje', () async {
    sandbox.place('.fvmrc', '{"flutter": "3.0.0"}');
    for (var i = 0; i < 30; i++) {
      sandbox.place('p$i/pubspec.yaml', '''
name: p$i
environment:
  flutter: ">=9.$i.0"
''');
    }
    final full = await recognize(const ReportLimits());
    expect(full.conflicts, hasLength(30));
    await expectLater(
      recognize(const ReportLimits(maxDerivedItems: 100)),
      exceeds(ReportLimitDimension.items),
    );
  });

  test('un adelanto truncado cuenta sus 4096 bytes', () async {
    sandbox.place(
      'pubspec.yaml',
      'name: a\nenvironment:\n  sdk: "${'^' * 5000}"\n',
    );
    await expectLater(
      recognize(const ReportLimits(maxDerivedTextBytes: 4000)),
      exceeds(ReportLimitDimension.textBytes),
    );
  });

  test(
    'el orden en que el sistema lista no cambia la cota alcanzada',
    () async {
      // a pesa en texto (cinco miembros de 4000 bytes) y b en elementos
      // (sesenta miembros cortos): si b se recorriera primero se agotarían los
      // elementos; recorriendo en orden de ruta, a va primero y se agota el
      // texto, liste como liste el sistema.
      sandbox.place(
        'a/pubspec.yaml',
        'name: a\nworkspace:\n${'  - ${'w' * 4000}\n' * 5}',
      );
      sandbox.place('b/pubspec.yaml', 'name: b\nworkspace:\n${'  - m\n' * 60}');
      final dimensions = [
        await _exceededDimension(sandbox.root, listWithoutFollowing),
        await _exceededDimension(sandbox.root, (directory) async* {
          yield* Stream.fromIterable(
            (await listWithoutFollowing(directory).toList()).reversed,
          );
        }),
      ];
      expect(dimensions, [
        ReportLimitDimension.textBytes,
        ReportLimitDimension.textBytes,
      ]);
    },
  );
}

/// Lo que la propuesta de un reconocimiento Dart agrega en bytes.
int _proposalBytes() => [
  recordProjectIdentity.code,
  recordProjectIdentity.description,
  enableStackPlugin.code,
  enableStackPlugin.description,
  'plugin_dart',
].fold(0, (sum, text) => sum + utf8.encode(text).length);

RecognitionReport _assemble(
  Directory root,
  RecognitionContribution contribution,
  ReportLimits limits,
) => assembleRecognition(
  requestedRoot: root.path,
  resolvedRoot: root.path,
  repository: const RepositoryContext(
    status: RepositoryStatus.absent,
    root: null,
    relation: RepositoryRelation.none,
  ),
  contributions: [contribution],
  limits: limits,
);

/// La cota que corta el reconocimiento de [root] cuando se lista con [list].
Future<ReportLimitDimension> _exceededDimension(
  Directory root,
  DirectoryLister list,
) async {
  try {
    await recognizeListing(
      root,
      reportLimits: const ReportLimits(
        maxDerivedItems: 50,
        maxDerivedTextBytes: 20000,
      ),
      list: list,
    );
  } on ReportLimitExceeded catch (e) {
    return e.dimension;
  }
  throw StateError('debía exceder');
}

final _scopeBytes = utf8Length(declaredProjectRecognition);
