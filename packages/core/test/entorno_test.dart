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
}
