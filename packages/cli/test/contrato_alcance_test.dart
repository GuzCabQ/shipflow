/// Suite de contrato de `ScopeObserver`, contra las DOS implementaciones.
///
/// Lo que se prueba acá vale para cualquier stack. Los formatos y los sufijos
/// son del plugin y no aparecen: cada caso trae su propio escenario.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

/// Cada implementación arma su escenario: un sujeto del stack, uno ajeno y uno
/// que no se puede mirar.
typedef Escenario = ({
  ScopeObserver observador,
  String delStack,
  String ajeno,
  String inobservable,
});

void main() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('contrato_alcance_');
    Directory('${raiz.path}/lib').createSync();
    File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  final implementaciones = <String, Escenario Function()>{
    'real · stack': () => (
          observador: ObservadorDeAlcanceDart(directorio: raiz.path),
          delStack: 'lib',
          ajeno: 'LEEME.md',
          inobservable: 'no/existe',
        ),
    'falso · en memoria': () => (
          observador: ObservadorDeAlcanceFalso(
            observados: {
              'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
              'LEEME.md': ObservedSubject(
                  subject: 'LEEME.md',
                  ofStack: false,
                  files: 0,
                  reason: 'no es de este stack'),
            },
            noObservados: const {'no/existe': 'no existe en el árbol'},
          ),
          delStack: 'lib',
          ajeno: 'LEEME.md',
          inobservable: 'no/existe',
        ),
  };

  test('la suite corre contra DOS implementaciones', () {
    expect(implementaciones, hasLength(2));
  });

  implementaciones.forEach((nombre, armar) {
    group(nombre, () {
      test('cláusula 1 · la observación particiona lo pedido', () async {
        final e = armar();
        final o = await e.observador
            .observe([e.delStack, e.ajeno, e.inobservable]);
        final clasificados = {
          ...o.observed.map((x) => x.subject),
          ...o.unobserved.map((x) => x.subject),
        };
        expect(clasificados, {e.delStack, e.ajeno, e.inobservable});
      });

      test('cláusula 2 · el sujeto vuelve tal como se pidió', () async {
        final e = armar();
        final o = await e.observador.observe([e.delStack]);
        expect(o.observed.single.subject, e.delStack);
      });

      test('cláusula 3 · no pude mirar y no era mío son distintos', () async {
        final e = armar();
        final o = await e.observador.observe([e.ajeno, e.inobservable]);
        expect(o.unobserved.single.subject, e.inobservable,
            reason: 'lo que no se pudo mirar no puede presentarse como ajeno');
        expect(o.observed.single.subject, e.ajeno);
        expect(o.observed.single.ofStack, isFalse);
        expect(o.observed.single.reason, isNotNull);
      });

      test('y sin embargo SÍ reconoce lo que es del stack', () async {
        // Sin esto, un observador que devolviera todo como inobservable
        // pasaría las tres cláusulas por la vía de no funcionar.
        final e = armar();
        final o = await e.observador.observe([e.delStack]);
        expect(o.usable(), [e.delStack]);
        expect(o.observed.single.files, greaterThan(0));
      });

      test('un alcance vacío no es un error', () async {
        final e = armar();
        final o = await e.observador.observe(const []);
        expect(o.usable(), isEmpty);
      });
    });
  });
}
