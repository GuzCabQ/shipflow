/// INV-5: un secreto nunca se serializa ni aparece en traza, log o mensaje.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const secreto = 'valor-que-no-debe-aparecer';
  const credencial = Credential(secreto, label: 'token de la forja');

  test('toString devuelve la máscara', () {
    expect(credencial.toString(), equals('***'));
  });

  test('una interpolación no filtra el secreto', () {
    expect('$credencial'.contains(secreto), isFalse);
    expect('$credencial', equals('***'));
  });

  test('el mensaje de una excepción no filtra el secreto', () {
    // El caso real: alguien mete la credencial en un error y el error va al log.
    final mensaje = Exception('no pude usar $credencial').toString();
    expect(mensaje.contains(secreto), isFalse);
  });

  test('jsonEncode se niega, en vez de escribir el secreto', () {
    // Sin `toJson`, `jsonEncode` no tiene por dónde. Que LANCE en vez de
    // escribir algo es el comportamiento deseado: falla ruidosa, no silenciosa.
    expect(() => jsonEncode(credencial),
        throwsA(isA<JsonUnsupportedObjectError>()));
  });

  test('el secreto solo se alcanza dentro de use()', () {
    final encabezado = credencial.use((s) => 'Bearer $s');
    expect(encabezado, equals('Bearer $secreto'));
  });

  test('se puede preguntar si está vacía sin exponerla', () {
    expect(const Credential('', label: 'x').isEmpty, isTrue);
    expect(credencial.isEmpty, isFalse);
  });
}
