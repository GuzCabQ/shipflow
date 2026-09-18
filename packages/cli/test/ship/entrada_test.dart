import 'package:cli/cli.dart';
import 'package:test/test.dart';

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
}
