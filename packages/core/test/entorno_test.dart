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
          evidencia: const QuotedText('   ', source: 'x'),
        ),
        throwsArgumentError,
      );
    });

    test('una derivación abortada no puede decir que terminó completa', () {
      // `completa` es «la herramienta corrió y dijo algo»: eso es un rechazo o
      // un entorno derivado, nunca un aborto.
      expect(
        () => DerivacionAbortada(
          terminacion: Termination.completa,
          evidencia: cita,
        ),
        throwsArgumentError,
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
}
