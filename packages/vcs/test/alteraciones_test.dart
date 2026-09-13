/// El parser de `diff-index --raw -z`, aislado.
///
/// Vive aparte de la suite que corre contra `git` porque acá está el caso que
/// esa suite no puede provocar: una letra que `git` podría emitir algún día
/// y que este control no previó. Descartarla en silencio sería leer un hueco
/// como un candidato intacto.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

/// Un registro tal como lo entrega `git`: la metadata, NUL, la ruta, NUL.
List<int> registro(String meta, String ruta) => [
  ...utf8.encode(meta),
  0,
  ...utf8.encode(ruta),
  0,
];

/// El segundo identificador siempre viene en ceros: `diff-index` no hashea el
/// árbol de trabajo. Es lo que obliga a leer el MODO para distinguir un cambio
/// de permisos de un cambio de contenido.
const ceros = '0000000000000000000000000000000000000000';
const sha = '5c1b14949828006ed75a3e8858957f86a2f7e2eb';

void main() {
  test('M con el mismo modo es modificada', () {
    final r = leerDiffRaw(
      registro(':100644 100644 $sha $ceros M', 'a.txt'),
      declaradas: const {},
    );
    expect(r.single.ruta, 'a.txt');
    expect(r.single.tipo, TipoDeAlteracion.modificada);
  });

  test('M con otro modo es cambioDeModo', () {
    final r = leerDiffRaw(
      registro(':100644 100755 $sha $ceros M', 'a.txt'),
      declaradas: const {},
    );
    expect(
      r.single.tipo,
      TipoDeAlteracion.cambioDeModo,
      reason:
          '`--name-status` plegaría esto en una M indistinguible de un '
          'cambio de contenido',
    );
  });

  test('D es borrada, T es cambioDeTipo', () {
    final bytes = [
      ...registro(':100644 000000 $sha $ceros D', 'x'),
      ...registro(':120000 100644 $sha $ceros T', 'd/rel'),
    ];
    final r = leerDiffRaw(bytes, declaradas: const {});
    expect(r.map((a) => a.tipo), [
      TipoDeAlteracion.borrada,
      TipoDeAlteracion.cambioDeTipo,
    ]);
  });

  test('una D sobre una ruta declarada no cuenta; una T sobre ella sí', () {
    final bytes = [
      ...registro(':120000 000000 $sha $ceros D', 'abs'),
      ...registro(':120000 100644 $sha $ceros T', 'up'),
    ];
    final r = leerDiffRaw(bytes, declaradas: const {'abs', 'up'});
    expect(r.single.ruta, 'up');
    expect(
      r.single.tipo,
      TipoDeAlteracion.cambioDeTipo,
      reason:
          'alguien escribió algo donde el candidato dejó un hueco a sabiendas',
    );
  });

  test('una letra que no sea M, D ni T falla cerrado', () {
    for (final letra in ['R100', 'A', 'C75', 'U', 'X']) {
      expect(
        () => leerDiffRaw(
          registro(':100644 100644 $sha $ceros $letra', 'a'),
          declaradas: const {},
        ),
        throwsA(isA<PromesaIncumplida>()),
        reason:
            'la letra «$letra» no se descarta: significa que git vio algo '
            'que este control no previó',
      );
    }
  });

  test('un registro sin su ruta falla cerrado', () {
    expect(
      () => leerDiffRaw([
        ...utf8.encode(':100644 100644 $sha $ceros M'),
        0,
      ], declaradas: const {}),
      throwsA(isA<PromesaIncumplida>()),
    );
  });

  test('una metadata que no tiene la forma esperada falla cerrado', () {
    expect(
      () => leerDiffRaw(registro('100644 100644 M', 'a'), declaradas: const {}),
      throwsA(isA<PromesaIncumplida>()),
    );
  });

  test('vacío es ninguna alteración', () {
    expect(leerDiffRaw(const [], declaradas: const {}), isEmpty);
  });

  test('una ruta con salto de línea sobrevive: los registros van por NUL', () {
    // `--name-status` sin `-z` partiría este registro en dos y el candidato
    // dejaría de representar el árbol que dice representar.
    final r = leerDiffRaw(
      registro(':100644 100644 $sha $ceros M', 'con\nsalto.txt'),
      declaradas: const {},
    );
    expect(r.single.ruta, 'con\nsalto.txt');
  });
}
