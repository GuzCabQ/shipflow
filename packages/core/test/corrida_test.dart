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

    test('cada fromJson rechaza un discriminador ajeno', () {
      final ajenos = <String, ShipOutcome>{
        for (final caso in <ShipOutcome>[
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.previewOnly,
            verificacion: EstadoDeCorrida.verde,
          ),
          ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
          ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
          ShipOutcome.publicadoParaLaPrueba(
            pr: PullRequestOpen(url: 'https://forja/pr/3'),
            verificacion: EstadoPublicable.verde,
          ),
          ShipOutcome.publicacionIncompletaParaLaPrueba(
            remoto: PushFailed(causa: CausaDePublicacion.permisos),
            verificacion: EstadoPublicable.verde,
          ),
        ])
          caso.kind: caso,
      };
      expect(ajenos, hasLength(5), reason: 'los kind tienen que ser distintos');
      for (final entrada in ajenos.entries) {
        final impostor = Map<String, Object?>.from(entrada.value.toJson())
          ..['kind'] = 'otro-kind';
        expect(
          () => ShipOutcome.fromJson(impostor),
          throwsFormatException,
          reason: entrada.key,
        );
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
