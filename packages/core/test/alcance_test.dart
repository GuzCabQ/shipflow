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

    test('un sujeto PEDIDO dos veces se rechaza: no hay denominador', () {
      // Distinto del caso de arriba: ahí lo repetido está en `observed`. Acá
      // lo repetido está en `requested` mismo, así que `unicos` (una sola
      // 'lib') y `vistos` calzan y ese primer chequeo no dispara — el que
      // tiene que atajarlo es el que compara el tamaño de `requested` contra
      // su propio `toSet()`. Un revisor lo ejercitó a mano; sin esta prueba,
      // la guardia se podía quitar en una refactorización sin que nada lo
      // note.
      expect(
          () =>
              obs(pedidos: const ['lib', 'lib'], observados: [delStack('lib')]),
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

  group('VerificationScope · lo único que ve un verificador', () {
    // **Este grupo no existía.** El tipo entró con cuatro invariantes en su
    // constructor y ninguna prueba: la única cobertura era el caso de ida y
    // vuelta que el check de serialización exige por su cuenta. Lo encontró un
    // review, junto con el invariante que además faltaba.

    test('un sujeto utilizable con cero archivos no se construye', () {
      // **El estado imposible.** Un sujeto solo llega a `usable()` desde un
      // `ObservedSubject(ofStack: true)`, y ése exige al menos un archivo: si
      // no hay archivos, no es del stack. Así que este alcance afirma dos
      // cosas incompatibles a la vez, y ninguna observación real lo produce.
      expect(() => VerificationScope(subjects: const ['lib'], files: 0),
          throwsArgumentError);
    });

    test('dos sujetos con un solo archivo tampoco', () {
      // Cada sujeto utilizable aporta uno como mínimo, así que el total no
      // puede ser menor que la cantidad de sujetos. Es el caso que un
      // `files >= 1` a secas dejaría pasar.
      expect(() => VerificationScope(subjects: const ['lib', 'test'], files: 1),
          throwsArgumentError);
    });

    test('y tampoco entrando por fromJson', () {
      // `fromJson` delega en el constructor, y esta prueba es lo que impide
      // que alguien lo «optimice» construyendo los campos directamente: un
      // documento de afuera es justo por donde entra un estado que el resto
      // del programa no puede fabricar.
      expect(
          () => VerificationScope.fromJson(const {
                'subjects': ['lib', 'test'],
                'files': 1,
              }),
          throwsArgumentError);
    });

    test('control negativo: dos sujetos y dos archivos sí se construye', () {
      // Sin esto, un constructor que lanzara SIEMPRE pasaría las tres pruebas
      // de arriba por la vía de no funcionar.
      final a = VerificationScope(subjects: const ['lib', 'test'], files: 2);
      expect(a.subjects, ['lib', 'test']);
      expect(a.files, 2);
    });

    test('un alcance vacío no se construye', () {
      // La precondición que vivía adentro de `run` y se mudó acá.
      expect(() => VerificationScope(subjects: const [], files: 0),
          throwsArgumentError);
    });

    test('un sujeto en blanco no se construye', () {
      expect(() => VerificationScope(subjects: const ['  '], files: 1),
          throwsArgumentError);
    });

    test('un sujeto repetido no se construye', () {
      // El libro de obligaciones cuenta por par paso-sujeto: un repetido
      // pediría cuenta dos veces de lo mismo.
      expect(() => VerificationScope(subjects: const ['lib', 'lib'], files: 2),
          throwsArgumentError);
    });

    test('un conteo negativo no se construye', () {
      expect(() => VerificationScope(subjects: const ['lib'], files: -1),
          throwsArgumentError);
    });

    test('sale de la observación con lo utilizable y su conteo', () {
      final o = ScopeObservation(
        requested: const ['lib', 'test', 'LEEME.md', 'no/existe'],
        observed: [
          ObservedSubject(subject: 'lib', ofStack: true, files: 3),
          ObservedSubject(subject: 'test', ofStack: true, files: 2),
          ObservedSubject(
              subject: 'LEEME.md',
              ofStack: false,
              files: 0,
              reason: 'no es de este stack'),
        ],
        unobserved: [
          UnobservedSubject(
              subject: 'no/existe', cause: 'no existe en el árbol')
        ],
        observedAt: DateTime.utc(2026),
      );
      final a = VerificationScope.de(o);
      expect(a.subjects, ['lib', 'test'],
          reason: 'ni el ajeno ni el que no se pudo mirar llegan al paso');
      expect(a.files, 5, reason: 'solo cuentan los archivos del stack');
    });

    test('y una observación sin nada utilizable no produce alcance', () {
      // Quien compone no llega a armarlo, que es exactamente lo que debe
      // pasar: decidir qué significa eso es de la orquestación.
      final o = ScopeObservation(
        requested: const ['LEEME.md'],
        observed: [
          ObservedSubject(
              subject: 'LEEME.md',
              ofStack: false,
              files: 0,
              reason: 'no es de este stack'),
        ],
        unobserved: const [],
        observedAt: DateTime.utc(2026),
      );
      expect(() => VerificationScope.de(o), throwsArgumentError);
    });
  });
}
