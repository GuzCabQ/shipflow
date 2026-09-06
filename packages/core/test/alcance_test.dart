/// La observación del alcance es una PARTICIÓN de lo que se pidió.
///
/// Sin eso, un sujeto puede desaparecer entre lo pedido y lo utilizable y
/// ninguna guardia posterior lo ve: la corrida sale verde sobre un archivo que
/// nadie miró. Hoy la partición es cierta por construcción y nada la comprueba.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

ObservedSubject delStack(String s, {int archivos = 1}) =>
    ObservedSubject(subject: s, ofStack: true, files: archivos);

ObservedSubject ajeno(String s) => ObservedSubject(
    subject: s, ofStack: false, files: 0, reason: 'no es de este stack');

ScopeObservation obs({
  required List<String> pedidos,
  List<ObservedSubject> observados = const [],
  List<UnobservedSubject> noObservados = const [],
}) =>
    ScopeObservation(
      requested: pedidos,
      observed: observados,
      unobserved: noObservados,
      observedAt: DateTime.utc(2026),
    );

void main() {
  group('la partición es exacta', () {
    test('observados más no observados son exactamente lo pedido', () {
      final o = obs(
        pedidos: const ['lib', 'no/existe'],
        observados: [delStack('lib', archivos: 3)],
        noObservados: [
          UnobservedSubject(
              subject: 'no/existe', cause: 'no existe en el árbol')
        ],
      );
      expect(o.usable(), ['lib']);
    });

    test('un sujeto pedido que no aparece en ninguna lista se rechaza', () {
      // El agujero: desaparece antes de calcular lo utilizable y nadie lo ve.
      expect(
          () => obs(
              pedidos: const ['lib', 'test'], observados: [delStack('lib')]),
          throwsArgumentError);
    });

    test('un sujeto que aparece y no se pidió se rechaza', () {
      expect(
          () => obs(
              pedidos: const ['lib'],
              observados: [delStack('lib'), delStack('test')]),
          throwsArgumentError);
    });

    test('un sujeto en las dos listas se rechaza', () {
      expect(
          () => obs(
                pedidos: const ['lib'],
                observados: [delStack('lib')],
                noObservados: [
                  UnobservedSubject(subject: 'lib', cause: 'no se dejó leer')
                ],
              ),
          throwsArgumentError);
    });

    test('un sujeto repetido dentro de una lista se rechaza', () {
      expect(
          () => obs(
              pedidos: const ['lib'],
              observados: [delStack('lib'), delStack('lib')]),
          throwsArgumentError);
    });

    test('la identidad es la cadena TAL COMO SE PIDIÓ', () {
      // `core` no puede normalizar rutas: no importa nada. Si el observador
      // devolviera `lib` para un pedido `./lib`, la partición no cierra y el
      // rechazo es correcto — la canonización es asunto suyo, y no puede
      // renombrar el sujeto que devuelve.
      expect(() => obs(pedidos: const ['./lib'], observados: [delStack('lib')]),
          throwsArgumentError);
    });
  });

  group('un sujeto observado dice una sola cosa', () {
    test('ajeno al stack no puede traer archivos', () {
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: false, files: 2, reason: 'x'),
          throwsArgumentError);
    });

    test('ajeno al stack sin motivo no dice por qué', () {
      expect(() => ObservedSubject(subject: 'a', ofStack: false, files: 0),
          throwsArgumentError);
    });

    test('ajeno al stack con motivo en blanco tampoco', () {
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: false, files: 0, reason: '  '),
          throwsArgumentError);
    });

    test('del stack con cero archivos es una contradicción', () {
      expect(() => ObservedSubject(subject: 'a', ofStack: true, files: 0),
          throwsArgumentError);
    });

    test('del stack con motivo es una contradicción', () {
      // El motivo existe para explicar por qué NO era suyo.
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: true, files: 1, reason: 'x'),
          throwsArgumentError);
    });

    test('un sujeto en blanco no es un sujeto', () {
      expect(() => ObservedSubject(subject: '  ', ofStack: true, files: 1),
          throwsArgumentError);
    });
  });

  group('un sujeto no observado dice su causa', () {
    test('una causa en blanco no es una causa', () {
      expect(() => UnobservedSubject(subject: 'a', cause: ' '),
          throwsArgumentError);
    });
  });

  test('mutar las listas originales no cambia la observación', () {
    final pedidos = ['lib'];
    final observados = [delStack('lib')];
    final o = obs(pedidos: pedidos, observados: observados);
    pedidos.clear();
    observados.clear();
    expect(o.usable(), ['lib']);
    expect(() => o.observed.add(delStack('otro')), throwsUnsupportedError);
  });

  test('lo utilizable excluye lo ajeno al stack', () {
    final o = obs(
        pedidos: const ['lib', 'LEEME.md'],
        observados: [delStack('lib'), ajeno('LEEME.md')]);
    expect(o.usable(), ['lib']);
  });

  test('ida y vuelta por JSON', () {
    final o = obs(
      pedidos: const ['lib', 'no/existe'],
      observados: [delStack('lib', archivos: 3)],
      noObservados: [
        UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol')
      ],
    );
    final ida = ScopeObservation.fromJson(o.toJson());
    expect(ida.usable(), o.usable());
    expect(ida.unobserved.single.cause, 'no existe en el árbol');
    expect(ida.observed.single.files, 3);
  });
}
