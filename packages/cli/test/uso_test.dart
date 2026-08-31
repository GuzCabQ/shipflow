/// La interpretación de la línea de comandos, en la frontera.
///
/// Estos casos existen porque **comprobar la presencia de una bandera no es
/// interpretarla**. La frontera usaba `contains` y resolvía la ayuda sin haber
/// mirado el resto: `--inventada --help` salía con `0`.
library;

import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

Future<(int, String)> invocar(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final c = await ejecutar(args,
      directorio: '.',
      salida: out,
      error: err,
      construirCascada: (_) => Cascada(const []));
  return (c, out.toString());
}

void main() {
  group('el intérprete global', () {
    test('reconoce solo las banderas que existen de verdad', () {
      // `--no-color`, `--config` y `--version` están en el documento y NO
      // implementadas. Aceptarlas sin hacer nada sería prometer algo que no
      // hay, así que caen como desconocidas hasta que existan.
      expect(banderasGlobales,
          {'--json', '--quiet', '-q', '--verbose', '--help', '-h'});
    });

    test('el comando es el primer argumento sin guion', () {
      final g = interpretarGlobales(const ['--json', 'verify', 'lib', 'test']);
      expect(g.comando, 'verify');
      expect(g.restantes, ['lib', 'test']);
      expect(g.json, isTrue);
    });

    test('una bandera desconocida CON comando le toca al subcomando', () {
      // Un subcomando puede tener banderas propias. Hoy `verify` no tiene
      // ninguna y las rechaza, pero rechazarlas acá cerraría esa puerta.
      final g = interpretarGlobales(const ['verify', '--dry-run']);
      expect(g.restantes, ['--dry-run']);
    });

    test('sin comando, una bandera desconocida no la puede aceptar nadie', () {
      expect(() => interpretarGlobales(const ['--inventada']),
          throwsA(isA<UsoInvalido>()));
    });

    test('la contradicción se rechaza ANTES que la ayuda', () {
      // `--quiet --verbose --help` salía con 0 mostrando nada. SC-17 exige 5,
      // y no hay forma de honrar las dos banderas: elegir una es adivinar.
      expect(
          () => interpretarGlobales(const ['--quiet', '--verbose', '--help']),
          throwsA(isA<UsoInvalido>()));
    });
  });

  group('la frontera, caso por caso', () {
    final esperado = <String, int>{
      '--inventada': 5,
      '--inventada --help': 5,
      '--quiet --verbose': 5,
      '--quiet --verbose --help': 5,
      '--quiet --help': 0,
      'verify --quiet --help': 0,
      '--help': 0,
      '': 5,
    };

    esperado.forEach((linea, codigo) {
      final args = linea.isEmpty ? <String>[] : linea.split(' ');
      test('«shipflow $linea» → $codigo', () async {
        expect((await invocar(args)).$1, codigo);
      });

      test('«shipflow --json $linea» → un solo envelope', () async {
        final (c, out) = await invocar(['--json', ...args]);
        final lineas = out.trim().split('\n');
        expect(lineas, hasLength(1),
            reason: 'con --json no se cuela texto suelto (SC-10)');
        final r = jsonDecode(lineas.single) as Map<String, Object?>;
        expect(r['type'], 'result');
        expect(r['exitCode'], c, reason: 'el envelope dice el mismo código');
      });
    });

    test('`--help` gana sobre `--quiet`: si se pidió, se muestra', () async {
      // Salía con 0 y sin nada. Callar lo que alguien pidió explícitamente no
      // es silencio: es no hacerlo.
      final (c, out) = await invocar(const ['--quiet', '--help']);
      expect(c, 0);
      expect(out, contains('verify'));
    });
  });
}
