/// El observador del stack. Son los casos que hoy vivían dentro del paso, más
/// los que la suite de contrato del puerto va a exigirle a cualquiera.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;
  late ObservadorDeAlcanceDart obs;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('alcance_');
    Directory('${raiz.path}/lib').createSync();
    File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
    obs = ObservadorDeAlcanceDart(directorio: raiz.path);
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  ObservedSubject unico(ScopeObservation o) => o.observed.single;

  test('un directorio con fuentes es del stack, con su conteo', () async {
    final o = await obs.observe(['lib']);
    expect(unico(o).ofStack, isTrue);
    expect(unico(o).files, 1);
    expect(o.usable(), ['lib']);
  });

  test('un archivo de fuente nombrado directo es del stack', () async {
    final o = await obs.observe(['lib/a.dart']);
    expect(unico(o).ofStack, isTrue);
    expect(unico(o).files, 1);
  });

  test('un archivo que no es del stack se descarta CON motivo', () async {
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
    final o = await obs.observe(['LEEME.md']);
    expect(unico(o).ofStack, isFalse);
    expect(unico(o).reason, isNotNull);
    expect(o.usable(), isEmpty);
  });

  test('un directorio real SIN fuentes es ajeno, no inobservable', () async {
    // El falso rojo simétrico: se pudo mirar, y no había nada suyo.
    Directory('${raiz.path}/prosa').createSync();
    File('${raiz.path}/prosa/LEEME.md').writeAsStringSync('# hola\n');
    final o = await obs.observe(['prosa']);
    expect(o.unobserved, isEmpty);
    expect(unico(o).ofStack, isFalse);
    expect(unico(o).files, 0);
  });

  test('una ruta que no existe es INOBSERVABLE, no ajena', () async {
    // «No pude mirar» no es «no había nada mío». Un review lo cobró.
    final o = await obs.observe(['no/existe']);
    expect(o.observed, isEmpty);
    expect(o.unobserved.single.cause, contains('no existe'));
  });

  test('un directorio sin permisos es inobservable', () async {
    final cerrado = Directory('${raiz.path}/cerrado')..createSync();
    File('${cerrado.path}/x.dart').writeAsStringSync('void main() {}\n');
    Process.runSync('chmod', ['000', cerrado.path]);
    addTearDown(() => Process.runSync('chmod', ['700', cerrado.path]));
    final o = await obs.observe(['cerrado']);
    expect(o.unobserved.single.cause, contains('no se pudo mirar'));
  }, onPlatform: const {'windows': Skip('los permisos POSIX no aplican')});

  test('lo que cuelga de una carpeta oculta no se cuenta', () async {
    // Está medido: la herramienta del stack salta los componentes ocultos al
    // recorrer. Contarlos haría que la reconciliación no cerrara nunca.
    Directory('${raiz.path}/lib/.oculto').createSync();
    File('${raiz.path}/lib/.oculto/c.dart').writeAsStringSync('void main() {}\n');
    final o = await obs.observe(['lib']);
    expect(unico(o).files, 1);
  });

  test('un alcance mixto se particiona entero', () async {
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
    final o = await obs.observe(['lib', 'LEEME.md', 'no/existe']);
    expect(o.requested, hasLength(3));
    expect(o.observed.map((e) => e.subject), containsAll(['lib', 'LEEME.md']));
    expect(o.unobserved.single.subject, 'no/existe');
    expect(o.usable(), ['lib']);
  });

  test('el sujeto vuelve TAL COMO SE PIDIÓ, aunque haya que canonizarlo',
      () async {
    // El observador canoniza para decidir el hecho; si además renombrara el
    // sujeto, la partición de `core` no cerraría.
    final o = await obs.observe(['./lib']);
    expect(o.observed.single.subject, './lib');
    expect(o.observed.single.ofStack, isTrue);
  });

  test('un alcance vacío da una observación vacía, no un error', () async {
    final o = await obs.observe(const []);
    expect(o.requested, isEmpty);
    expect(o.usable(), isEmpty);
  });
}
