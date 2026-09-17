/// §8 de la propuesta de entorno: **lista blanca, no lista negra**. Una
/// variable secreta futura no puede filtrarse sola.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const padre = {
    'PATH': '/usr/bin',
    'HOME': '/home/u',
    'PUB_CACHE': '/home/u/.cache-de-paquetes',
    'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
    'GIT_DIR': '/otro/repo/.git',
    'XDG_CONFIG_HOME': '/home/u/.config',
  };

  test('deja pasar exactamente PATH, HOME y PUB_CACHE', () {
    expect(entornoSaneado(padre), {
      'PATH': '/usr/bin',
      'HOME': '/home/u',
      'PUB_CACHE': '/home/u/.cache-de-paquetes',
    });
  });

  test(
    'una variable que no está en la lista no pasa, se llame como se llame',
    () {
      final s = entornoSaneado(padre);
      expect(s.containsKey('SHIPFLOW_GITHUB_TOKEN'), isFalse);
      expect(s.containsKey('GIT_DIR'), isFalse);
      expect(s.containsKey('XDG_CONFIG_HOME'), isFalse);
    },
  );

  test('PUB_CACHE solo viaja si el padre la tiene', () {
    expect(entornoSaneado({'PATH': '/bin'}), {'PATH': '/bin'});
  });

  test('las propias se suman tal cual', () {
    final s = entornoSaneado(padre, propias: {'GIT_INDEX_FILE': '/tmp/i'});
    expect(s['GIT_INDEX_FILE'], '/tmp/i');
    expect(s['PATH'], '/usr/bin');
  });

  test('una propia no puede pisar la lista blanca', () {
    expect(
      () => entornoSaneado(padre, propias: {'PATH': '/donde-sea'}),
      throwsArgumentError,
    );
  });

  test('el resultado es inmodificable', () {
    expect(() => entornoSaneado(padre)['X'] = 'y', throwsUnsupportedError);
  });

  group('los tipos del entorno', () {
    final cita = QuotedText('Unable to satisfy', source: 'resolver');

    test('un rechazo o un aborto no se construyen sin evidencia', () {
      expect(
        () => CandidatoRechazado(
          causa: CausaDeRechazo.pubRechazoLaResolucion,
          evidencia: const QuotedText('', source: 'resolver'),
        ),
        throwsArgumentError,
      );
      expect(
        () => DerivacionAbortada(
          terminacion: Termination.herramientaAusente,
          causa: CausaDeAborto.laHerramientaNoRespondio,
          evidencia: const QuotedText('   ', source: 'x'),
        ),
        throwsArgumentError,
      );
    });

    test('la terminación y la causa del aborto tienen que concordar', () {
      // Una herramienta que corrió del todo y falló al decir su versión SÍ es
      // un aborto —no llegamos a medir— pero por una causa distinta de la de
      // una herramienta que no respondió. Cruzarlas describiría mal el hecho.
      expect(
        () => DerivacionAbortada(
          terminacion: Termination.completa,
          causa: CausaDeAborto.laHerramientaNoRespondio,
          evidencia: cita,
        ),
        throwsArgumentError,
      );
      expect(
        () => DerivacionAbortada(
          terminacion: Termination.herramientaAusente,
          causa: CausaDeAborto.laToolchainNoSeIdentifico,
          evidencia: cita,
        ),
        throwsArgumentError,
      );
      expect(
        DerivacionAbortada(
          terminacion: Termination.completa,
          causa: CausaDeAborto.laToolchainNoSeIdentifico,
          evidencia: cita,
        ).causa,
        CausaDeAborto.laToolchainNoSeIdentifico,
      );
    });

    test(
      'un entorno derivado no admite cifras negativas ni toolchain muda',
      () {
        final tc = IdentidadDeToolchain(
          version: QuotedText('SDK version: 3.12.0', source: 'toolchain'),
        );
        expect(
          () => EntornoDerivado(paquetes: -1, raices: 1, toolchain: tc),
          throwsArgumentError,
        );
        expect(
          () => EntornoDerivado(paquetes: 3, raices: -1, toolchain: tc),
          throwsArgumentError,
        );
        expect(
          () =>
              IdentidadDeToolchain(version: const QuotedText('', source: 'x')),
          throwsArgumentError,
        );
        // Cero raíces SÍ se admite: un candidato sin nada que derivar no es un
        // candidato defectuoso.
        expect(
          EntornoDerivado(paquetes: 0, raices: 0, toolchain: tc).raices,
          0,
        );
      },
    );

    test('una alteración sin ruta no nombra nada', () {
      expect(
        () => AlteracionDelCandidato(ruta: ' ', tipo: TipoDeAlteracion.borrada),
        throwsArgumentError,
      );
    });

    test(
      'ResultadoDeEntorno es cerrado: un switch sin default cubre las tres',
      () {
        // Si alguien agrega una variante, esto deja de COMPILAR. Es la prueba: la
        // exhaustividad es una propiedad del tipo, no una aserción que corre.
        String nombre(ResultadoDeEntorno r) => switch (r) {
          EntornoDerivado() => 'derivado',
          CandidatoRechazado() => 'rechazado',
          DerivacionAbortada() => 'abortada',
        };
        expect(
          nombre(
            CandidatoRechazado(
              causa: CausaDeRechazo.dependenciaPathQueEscapa,
              evidencia: cita,
            ),
          ),
          'rechazado',
        );
      },
    );
  });

  group('EntornoDelProceso', () {
    test('lo que va a los hijos no lleva la credencial', () {
      final e = EntornoDelProceso(const {
        'PATH': '/bin',
        'HOME': '/casa',
        'SHIPFLOW_GITHUB_TOKEN': 'ghp_secreto',
      });
      expect(e.paraHijos.containsKey('SHIPFLOW_GITHUB_TOKEN'), isFalse);
      expect(e.paraHijos['PATH'], '/bin');
      expect(e.paraHijos['HOME'], '/casa');
    });

    test('lo que va a los hijos es inmodificable', () {
      final e = EntornoDelProceso(const {'PATH': '/bin'});
      expect(() => e.paraHijos['X'] = 'y', throwsUnsupportedError);
    });

    test('la credencial sale como Credential, nunca como cadena', () {
      final e = EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': 'ghp_x'});
      final c = e.credencial('SHIPFLOW_GITHUB_TOKEN');
      expect(c, isNotNull);
      expect(c.toString(), '***');
      expect(c!.use((secreto) => secreto), 'ghp_x');
    });

    test('ausente y vacía son la misma respuesta: no hay credencial', () {
      expect(
        EntornoDelProceso(const {}).credencial('SHIPFLOW_GITHUB_TOKEN'),
        isNull,
      );
      expect(
        EntornoDelProceso(const {
          'SHIPFLOW_GITHUB_TOKEN': '',
        }).credencial('SHIPFLOW_GITHUB_TOKEN'),
        isNull,
      );
    });

    test('pedir una clave que no está declarada como credencial no compila '
        'un secreto: falla', () {
      final e = EntornoDelProceso(const {'PATH': '/bin'});
      expect(() => e.credencial('PATH'), throwsArgumentError);
    });

    test('`paraHijos` no reenvía el valor de una clave declarada como '
        'credencial', () {
      // **El título dice lo que la prueba afirma, y nada más.** Se llamaba
      // «el mapa crudo que se le pasó no se puede leer entero desde afuera»,
      // y eso no es lo que mira: mira `paraHijos`. En este lenguaje no se
      // puede probar la AUSENCIA de un getter sin reflexión, así que ese control
      // no existe —y un título que promete cobertura que no hay es lo que le
      // dice al próximo revisor que eso ya está mirado—.
      //
      // **Lo que sí lo sostiene, y no es esta prueba:** que `_crudo` sea
      // privado lo comprueba el compilador en cada llamador de fuera de la
      // biblioteca, y que la clase no lo serialice lo comprueba la regla
      // `opacidad-declarada`. Agregar un getter público que devuelva el
      // crudo no lo caza nada de eso: queda declarado acá como residuo, y
      // como revisión humana.
      final e = EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': 'ghp_x'});
      expect(e.paraHijos.values.contains('ghp_x'), isFalse);
    });
  });
}
