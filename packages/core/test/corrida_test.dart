import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('EstadoPublicable', () {
    test('errorInterno NO tiene equivalente publicable', () {
      expect(EstadoPublicable.desde(EstadoDeCorrida.errorInterno), isNull);
    });

    test('los otros tres sí, y conservan el nombre', () {
      for (final par in {
        EstadoDeCorrida.verde: EstadoPublicable.verde,
        EstadoDeCorrida.rojo: EstadoPublicable.rojo,
        EstadoDeCorrida.noConcluyente: EstadoPublicable.noConcluyente,
      }.entries) {
        expect(EstadoPublicable.desde(par.key), par.value);
        expect(par.value.name, par.key.name);
      }
    });

    test('la conversión cubre TODOS los estados de corrida', () {
      // Si alguien agrega un estado, esta prueba lo obliga a decidir si es
      // publicable. Sin esto, un estado nuevo caería en el `null` por omisión
      // y quedaría no publicable sin que nadie lo hubiera decidido.
      var publicables = 0;
      for (final e in EstadoDeCorrida.values) {
        if (EstadoPublicable.desde(e) != null) publicables += 1;
      }
      expect(publicables, EstadoPublicable.values.length);
    });
  });

  group('CausaDeNoIntento', () {
    test('son cuatro, y errorInterno NO es una de ellas', () {
      expect(CausaDeNoIntento.values, hasLength(4));
      expect(
        CausaDeNoIntento.values.map((c) => c.name),
        isNot(contains('errorInterno')),
        reason:
            'errorInterno es un ESTADO, no una causa: entra por '
            'verificationGate. Ver el ruling del plan.',
      );
    });
  });

  group('ShipOutcome', () {
    test('Publicado no acepta un estado que no sea publicable', () {
      // El tipo lo impide: `Publicado` lleva `EstadoPublicable`, que no tiene
      // errorInterno. Esta prueba fija que el campo sea de ese tipo y no de
      // `EstadoDeCorrida`, que es lo que lo volvería escribible.
      final publicado = ShipOutcome.publicadoParaLaPrueba(
        pr: PullRequestOpen(url: 'https://forja/pr/1'),
        verificacion: EstadoPublicable.verde,
      );
      expect(publicado.verificacion, isA<EstadoPublicable>());
    });

    test('NoIntentado sí lleva el estado ENTERO', () {
      // Es el camino por donde errorInterno sale, así que acá el tipo tiene
      // que ser el completo.
      final no = ShipOutcome.noIntentadoParaLaPrueba(
        causa: CausaDeNoIntento.verificationGate,
        verificacion: EstadoDeCorrida.errorInterno,
      );
      expect(no.verificacion, EstadoDeCorrida.errorInterno);
    });

    test('cada variante vuelve a ser ella misma por JSON', () {
      final casos = <ShipOutcome>[
        ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.previewOnly,
          verificacion: EstadoDeCorrida.verde,
        ),
        ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
        ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
        ShipOutcome.publicadoParaLaPrueba(
          pr: PullRequestMerged(url: 'https://forja/pr/2'),
          verificacion: EstadoPublicable.rojo,
        ),
        ShipOutcome.publicacionIncompletaParaLaPrueba(
          remoto: PushUnknown(causa: CausaDePublicacion.red),
          verificacion: EstadoPublicable.noConcluyente,
        ),
      ];
      for (final caso in casos) {
        final vuelta = ShipOutcome.fromJson(caso.toJson());
        expect(vuelta.toJson(), caso.toJson(), reason: caso.kind);
        expect(vuelta.runtimeType, caso.runtimeType);
      }
    });

    test('cada fromJson rechaza un discriminador ajeno: las CINCO', () {
      // Llamar solo a `ShipOutcome.fromJson` no prueba nada de las cinco
      // fábricas concretas: con un `kind` que no nombra ninguna variante, el
      // rechazo ocurre en el `switch` de la base, ANTES de que se ejecute el
      // `_exigirKind` de cualquier fábrica. Borrar `_exigirKind` de las cinco
      // dejaba una versión anterior de esta prueba en verde igual. Mismo
      // hueco, y mismo arreglo, que `publicacion_test.dart` ya cerró para
      // `PublicationOutcome` — «cada fromJson rechaza un discriminador
      // ajeno: las SIETE»: acá se llama a la fábrica de CADA variante por su
      // nombre, nunca al despachador de la base.
      final variantes = <String, ShipOutcome Function(Map<String, Object?>)>{
        'noIntentado': NoIntentado.fromJson,
        'noAplicado': NoAplicado.fromJson,
        'localInconsistente': LocalInconsistente.fromJson,
        'publicado': Publicado.fromJson,
        'publicacionIncompleta': PublicacionIncompleta.fromJson,
      };
      expect(
        variantes,
        hasLength(5),
        reason:
            'si nace una sexta variante y esta tabla no crece, la tabla '
            'vuelve a prometer «cada fromJson» cubriendo menos',
      );

      // El cuerpo legítimo de CADA variante, con su propio `kind`. Cada
      // fábrica exige su `kind` antes de mirar cualquier otro campo, así que
      // alcanza con que el cuerpo sea válido para SU PROPIA fromJson.
      final cuerpos = <String, Map<String, Object?>>{
        'noIntentado': ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.previewOnly,
          verificacion: EstadoDeCorrida.verde,
        ).toJson(),
        'noAplicado': ShipOutcome.noAplicadoParaLaPrueba(
          headObservado: 'a' * 40,
        ).toJson(),
        'localInconsistente': ShipOutcome.localInconsistenteParaLaPrueba(
          revision: 'b' * 40,
        ).toJson(),
        'publicado': ShipOutcome.publicadoParaLaPrueba(
          pr: PullRequestOpen(url: 'https://forja/pr/3'),
          verificacion: EstadoPublicable.verde,
        ).toJson(),
        'publicacionIncompleta': ShipOutcome.publicacionIncompletaParaLaPrueba(
          remoto: PushFailed(causa: CausaDePublicacion.permisos),
          verificacion: EstadoPublicable.verde,
        ).toJson(),
      };

      for (final entrada in variantes.entries) {
        final propio = entrada.key;
        // Un discriminador que es de OTRA variante, no uno inventado: el
        // caso inventado ya lo cubre «un kind desconocido no se adivina», y
        // el que de verdad confunde una variante con otra es éste.
        final ajeno = propio == 'noIntentado' ? 'noAplicado' : 'noIntentado';
        final cuerpoAjeno = Map<String, Object?>.from(cuerpos[propio]!)
          ..['kind'] = ajeno;

        expect(
          () => entrada.value(cuerpoAjeno),
          throwsFormatException,
          reason:
              'la fromJson de «$propio» aceptó el discriminador «$ajeno», '
              'que es de otra variante',
        );
        // Control positivo, en la misma vuelta: sin esto, una `fromJson` que
        // lanzara SIEMPRE pasaría la aserción de arriba.
        expect(entrada.value(cuerpos[propio]!).kind, propio);
      }
    });

    test('un kind desconocido no se adivina', () {
      expect(
        () => ShipOutcome.fromJson({'kind': 'inventado'}),
        throwsFormatException,
      );
    });
  });
}
