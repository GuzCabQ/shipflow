import 'package:test/test.dart';

import '../../tool/src/options.dart';

void main() {
  const names = {'--a', '--b'};

  test('lee pares nombre y valor en cualquier orden', () {
    expect(parseNamedOptions(['--b', '2', '--a', '1'], names), {
      '--a': '1',
      '--b': '2',
    });
  });

  test('una opción puede faltar: cada herramienta decide si la exige', () {
    expect(parseNamedOptions(['--a', '1'], names), {'--a': '1'});
    expect(parseNamedOptions(const [], names), isEmpty);
  });

  test('el valor se toma tal cual, aunque parezca una opción', () {
    expect(parseNamedOptions(['--a', '--b'], names), {'--a': '--b'});
  });

  for (final (name, arguments) in [
    ('una opción desconocida', ['--a', '1', '--c', '3']),
    ('una opción repetida', ['--a', '1', '--a', '2']),
    ('una opción sin valor', ['--a', '1', '--b']),
    ('un valor suelto', ['1']),
  ]) {
    test('$name es inválida', () {
      expect(parseNamedOptions(arguments, names), isNull);
    });
  }
}
