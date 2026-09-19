import 'dart:convert';
import 'dart:io' show FileSystemException;

import 'package:cli/cli.dart';
import 'package:test/test.dart';

/// Un identificador con la forma EXACTA que emite este árbol: los
/// microsegundos de un instante, un guion y el número de corrida. Las pruebas
/// del reintento lo usan en vez de un nombre inventado porque la bandera
/// ahora comprueba esa gramática — y una prueba que pasara con un
/// identificador que ninguna corrida puede producir estaría midiendo otra
/// cosa.
const _unRunId = '1758240000000000-1';

void main() {
  test('sin archivos no se infiere nada: falla', () {
    // El default que barre el árbol es el falso verde en la ENTRADA.
    expect(
      () => interpretarShip(['--intent', 'x']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('--file y --slice son excluyentes', () {
    expect(
      () => interpretarShip(['--file', 'a.txt', '--slice', 'e.json']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('--file exige --intent, y --slice lo rechaza', () {
    expect(
      () => interpretarShip(['--file', 'a.txt']),
      throwsA(isA<UsoInvalido>()),
    );
    expect(
      () => interpretarShip(['--slice', 'e.json', '--intent', 'x']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('un archivo repetido falla, y el mensaje lo nombra', () {
    // Repetir una ruta no es ambiguo: es una rebanada mal declarada, y
    // `apply` exige igualdad LITERAL con los archivos de la rebanada.
    try {
      interpretarShip(['--intent', 'x', '--file', 'a.txt', '--file', 'a.txt']);
      fail('se esperaba UsoInvalido');
    } on UsoInvalido catch (e) {
      expect(e.reason, contains('a.txt'));
      expect(e.queHacer, isNotEmpty);
    }
  });

  test('la forma válida se interpreta entera', () {
    final e = interpretarShip([
      '--intent',
      'medir',
      '--file',
      'lib/a.txt',
      '--file',
      'test/a_test.txt',
      '--base',
      'main',
      '--branch',
      'feature/x',
      '--yes',
    ]);
    expect(e.intent, 'medir');
    expect(e.archivos, ['lib/a.txt', 'test/a_test.txt']);
    expect(e.base, 'main');
    expect(e.branch, 'feature/x');
    expect(e.yes, isTrue);
    expect(e.dryRun, isFalse);
    expect(e.allowIncomplete, isFalse);
  });

  test('las banderas sin valor no se comen el argumento siguiente', () {
    // `--yes --intent x` no puede interpretar «--intent» como el valor de
    // `--yes`. Es el error clásico de un intérprete escrito a mano.
    final e = interpretarShip(['--yes', '--intent', 'x', '--file', 'a.txt']);
    expect(e.intent, 'x');
    expect(e.yes, isTrue);
  });

  test('una bandera desconocida falla en vez de ignorarse', () {
    expect(
      () =>
          interpretarShip(['--intent', 'x', '--file', 'a.txt', '--inventada']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('una bandera con valor tampoco se come la bandera siguiente', () {
    // El mismo agujero que la prueba anterior cierra para las booleanas
    // —no comerse el argumento siguiente— hacía falta acá: sin la guardia,
    // `--file` se tragaba a `--branch` como nombre de archivo y `--branch`
    // se quedaba sin valor, las dos cosas en silencio.
    expect(
      () => interpretarShip(['--intent', '--file', 'a.txt']),
      throwsA(
        isA<UsoInvalido>().having(
          (e) => e.reason,
          'reason',
          contains('--intent'),
        ),
      ),
      reason:
          'el mensaje tiene que nombrar la bandera sin valor, no culpar '
          'al valor que se le escapó',
    );
    expect(
      () => interpretarShip(['--file', '--branch', '--intent', 'x']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('--slice deja la ruta y no los archivos; --file, al revés', () {
    final porSlice = interpretarShip(['--slice', 'e.json']);
    expect(porSlice.rutaDeLaRebanada, 'e.json');
    expect(porSlice.archivos, isEmpty);

    final porFile = interpretarShip(['--intent', 'x', '--file', 'a.txt']);
    expect(porFile.rutaDeLaRebanada, isNull);
    expect(porFile.archivos, ['a.txt']);
  });

  group('--retry-publication', () {
    // **La reproducción del P1-2 de la revisión humana.** La bandera aceptaba
    // CUALQUIER cadena y el registro la concatenaba directo como ruta:
    // `.shipflow/runs/../../fuera.json`. El reintento leía esa ruta y, si
    // encontraba un documento válido, terminaba escribiéndola.
    const noSonIdentificadores = {
      'sube dos niveles': '../../fuera',
      'sube uno': '../vecino',
      'es absoluta': '/tmp/ajeno',
      'nombra un subdirectorio': 'adentro/otro',
      'no tiene la forma que emite este árbol': 'r-1',
      'coincide con el prefijo y sigue de largo': '1-1/../../fuera',
      'está vacío': '',
    };
    noSonIdentificadores.forEach((porQue, valor) {
      test('«$valor» ($porQue) se rechaza como uso inválido', () {
        expect(
          () => interpretarShip(['--retry-publication', valor]),
          throwsA(
            isA<UsoInvalido>()
                .having(
                  (e) => e.reason,
                  'reason',
                  contains('no es un identificador de corrida'),
                )
                // Ninguna prohibición sin su alternativa: el mensaje tiene
                // que decir dónde encontrar el identificador de verdad.
                .having((e) => e.queHacer, 'queHacer', contains('runs')),
          ),
        );
      });
    });

    test('la bandera lleva el identificador de la corrida', () {
      final e = interpretarShip(['--retry-publication', _unRunId]);
      expect(e.reintentarPublicacion, _unRunId);
    });

    test('sin valor, falla nombrando la bandera', () {
      expect(
        () => interpretarShip(['--retry-publication']),
        throwsA(
          isA<UsoInvalido>().having(
            (e) => e.reason,
            'reason',
            contains('--retry-publication'),
          ),
        ),
      );
    });

    test('un valor que es otra bandera no es un identificador', () {
      expect(
        () => interpretarShip(['--retry-publication', '--yes']),
        throwsA(isA<UsoInvalido>()),
      );
    });

    for (final ajena in [
      '--file',
      '--slice',
      '--intent',
      '--branch',
      '--base',
    ]) {
      test(
        '$ajena con el reintento es una CONTRADICCIÓN, no una preferencia',
        () {
          expect(
            () =>
                interpretarShip(['--retry-publication', _unRunId, ajena, 'x']),
            throwsA(
              isA<UsoInvalido>()
                  .having(
                    (e) => e.reason,
                    'reason',
                    contains('--retry-publication'),
                  )
                  .having((e) => e.reason, 'reason', contains(ajena)),
            ),
            reason:
                'la rebanada está en el documento; declararla otra vez afirma '
                'dos cosas sobre el mismo hecho',
          );
        },
      );

      test('$ajena con el reintento contradice SIN IMPORTAR el orden en que se '
          'pasen', () {
        // Los chequeos corren DESPUÉS de que el `for` de `interpretarShip`
        // terminó de parsear todo: a ninguno le importa si
        // `--retry-publication` vino antes o después de la bandera con la
        // que contradice, y el mensaje sigue nombrando a las dos.
        expect(
          () => interpretarShip([ajena, 'x', '--retry-publication', _unRunId]),
          throwsA(
            isA<UsoInvalido>()
                .having(
                  (e) => e.reason,
                  'reason',
                  contains('--retry-publication'),
                )
                .having((e) => e.reason, 'reason', contains(ajena)),
          ),
        );
      });
    }

    for (final ajena in ['--yes', '--allow-incomplete']) {
      test('$ajena con el reintento se rechaza: la compuerta ya pasó', () {
        expect(
          () => interpretarShip(['--retry-publication', _unRunId, ajena]),
          throwsA(isA<UsoInvalido>()),
        );
      });
    }

    test('--dry-run SÍ convive: un ensayo del reintento no escribe nada', () {
      final e = interpretarShip(['--retry-publication', _unRunId, '--dry-run']);
      expect(e.reintentarPublicacion, _unRunId);
      expect(e.dryRun, isTrue);
    });

    test(
      'sin la bandera, el campo es nulo y ship se interpreta como siempre',
      () {
        final e = interpretarShip(['--intent', 'x', '--file', 'a.txt']);
        expect(e.reintentarPublicacion, isNull);
      },
    );
  });

  group('ArchivoDeRebanada.desdeJson', () {
    test('el archivo de rebanada NO lleva identificador', () {
      // Si lo llevara, habría dos fuentes de la identidad: la del archivo y la
      // que asigna la corrida. Dos fuentes del mismo hecho divergen siempre.
      expect(
        () => ArchivoDeRebanada.desdeJson({
          'id': 'r-1',
          'intent': 'x',
          'files': ['a.txt'],
        }),
        throwsFormatException,
        reason: 'una clave que el formato no declara no se ignora en silencio',
      );
    });

    test('un archivo de rebanada válido se interpreta entero', () {
      final a = ArchivoDeRebanada.desdeJson({
        'intent': 'medir',
        'files': ['lib/a.txt'],
        'branch': 'feature/x',
        'base': 'main',
      });
      expect(a.intent, 'medir');
      expect(a.files, ['lib/a.txt']);
      expect(a.branch, 'feature/x');
      expect(a.base, 'main');
    });

    test('sin intención o sin archivos, el archivo se rechaza', () {
      expect(
        () => ArchivoDeRebanada.desdeJson({
          'files': ['a.txt'],
        }),
        throwsFormatException,
      );
      expect(
        () => ArchivoDeRebanada.desdeJson({'intent': 'x', 'files': <String>[]}),
        throwsFormatException,
      );
    });
  });

  group('resolverRebanada', () {
    test('sin ruta de rebanada, no hay nada que resolver', () async {
      final entrada = interpretarShip(['--intent', 'x', '--file', 'a.txt']);
      final resuelta = await resolverRebanada(
        entrada,
        // Si esto se llamara, la prueba fallaría: `--file` no señala ningún
        // archivo de rebanada, así que no hay nada que leer.
        leer: (_) async => fail('no debería leer nada'),
      );
      expect(resuelta, same(entrada));
    });

    test('--slice produce la misma EntradaDeShip que --file', () async {
      final entrada = interpretarShip(['--slice', 'e.json']);
      final resuelta = await resolverRebanada(
        entrada,
        leer: (ruta) async {
          expect(ruta, 'e.json');
          return jsonEncode({
            'intent': 'medir',
            'files': ['lib/a.txt', 'test/a_test.txt'],
            'branch': 'feature/x',
            'base': 'main',
          });
        },
      );
      expect(resuelta.intent, 'medir');
      expect(resuelta.archivos, ['lib/a.txt', 'test/a_test.txt']);
      expect(resuelta.branch, 'feature/x');
      expect(resuelta.base, 'main');
      expect(resuelta.rutaDeLaRebanada, 'e.json');
    });

    test(
      '--base explícito gana sobre el de la rebanada, que rellena',
      () async {
        final entrada = interpretarShip([
          '--slice',
          'e.json',
          '--base',
          'develop',
        ]);
        final resuelta = await resolverRebanada(
          entrada,
          leer: (_) async => jsonEncode({
            'intent': 'medir',
            'files': ['a.txt'],
            'base': 'main',
          }),
        );
        // `--base` no es una aserción sobre un hecho observable como
        // `--branch`: es la cadena de precedencia de tres fuentes que ya tiene
        // en el diseño, y la rebanada es una fuente más de esa cadena.
        expect(resuelta.base, 'develop');
      },
    );

    test('--branch que coincide con el de la rebanada no falla: son la misma '
        'aserción', () async {
      final entrada = interpretarShip([
        '--slice',
        'e.json',
        '--branch',
        'feature/x',
      ]);
      final resuelta = await resolverRebanada(
        entrada,
        leer: (_) async => jsonEncode({
          'intent': 'medir',
          'files': ['a.txt'],
          'branch': 'feature/x',
        }),
      );
      expect(resuelta.branch, 'feature/x');
    });

    test('--branch que difiere del de la rebanada falla: son dos aserciones '
        'contradictorias, no una preferencia', () async {
      final entrada = interpretarShip([
        '--slice',
        'e.json',
        '--branch',
        'feature/de-la-linea-de-comandos',
      ]);
      expect(
        () => resolverRebanada(
          entrada,
          leer: (_) async => jsonEncode({
            'intent': 'medir',
            'files': ['a.txt'],
            'branch': 'feature/de-la-rebanada',
          }),
        ),
        throwsA(isA<UsoInvalido>()),
      );
    });

    test('un archivo de rebanada con archivos repetidos falla, igual que '
        '--file', () async {
      final entrada = interpretarShip(['--slice', 'e.json']);
      expect(
        () => resolverRebanada(
          entrada,
          leer: (_) async => jsonEncode({
            'intent': 'medir',
            'files': ['a.txt', 'a.txt'],
          }),
        ),
        throwsA(isA<UsoInvalido>()),
      );
    });

    test(
      'un archivo que no se puede leer sale por UsoInvalido, no crudo',
      () async {
        final entrada = interpretarShip(['--slice', 'e.json']);
        expect(
          () => resolverRebanada(
            entrada,
            leer: (_) async =>
                throw const FileSystemException('no existe', 'e.json'),
          ),
          throwsA(isA<UsoInvalido>()),
        );
      },
    );

    test('un contenido que no es JSON sale por UsoInvalido', () async {
      final entrada = interpretarShip(['--slice', 'e.json']);
      expect(
        () => resolverRebanada(entrada, leer: (_) async => 'no es json'),
        throwsA(isA<UsoInvalido>()),
      );
    });

    test('un archivo de rebanada con una clave desconocida sale por '
        'UsoInvalido, no por la FormatException cruda', () async {
      final entrada = interpretarShip(['--slice', 'e.json']);
      expect(
        () => resolverRebanada(
          entrada,
          leer: (_) async => jsonEncode({
            'id': 'r-1',
            'intent': 'x',
            'files': ['a.txt'],
          }),
        ),
        throwsA(isA<UsoInvalido>()),
      );
    });
  });
}
