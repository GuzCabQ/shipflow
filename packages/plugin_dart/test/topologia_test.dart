/// Pruebas de la implementación REAL de `ProjectTopology`.
///
/// Nivel unitario, no de contrato: acá se ejerce lo que solo esta
/// implementación hace —resolver rutas contra el disco, rechazar un manifiesto
/// ilegible—. El fake no tiene nada equivalente que hacer, así que meterlo en
/// la suite de contrato sería pedirle que finja.
library;

import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

late Directory raiz;

Directory paquete(String ruta, String manifiesto) {
  final d = Directory('${raiz.path}/$ruta')..createSync(recursive: true);
  File('${d.path}/pubspec.yaml').writeAsStringSync(manifiesto);
  return d;
}

void main() {
  setUp(() => raiz = Directory.systemTemp.createTempSync('topologia_'));
  tearDown(() => raiz.deleteSync(recursive: true));

  test('una dependencia por ruta hacia AFUERA no es topología', () async {
    // El bug que encontró un review: cualquier `path:` entraba a `dependsOn`
    // sin comprobar que apuntara adentro, y dejaba una arista colgante hacia
    // un paquete que `packages()` nunca devuelve.
    paquete(
        'proyecto/app',
        'name: app\n'
            'dependencies:\n  ajeno:\n    path: ../../afuera/ajeno\n');
    paquete('afuera/ajeno', 'name: ajeno\n');

    final ps =
        await TopologiaDart(Directory('${raiz.path}/proyecto')).packages();
    expect(ps.map((p) => p.name), equals(['app']));
    expect(ps.single.dependsOn, isEmpty,
        reason: 'la arista apuntaría a un paquete que packages() no devuelve');
  });

  test('una dependencia por ruta hacia adentro SÍ lo es', () async {
    paquete(
        'app',
        'name: app\n'
            'dependencies:\n  dominio:\n    path: ../dominio\n');
    paquete('dominio', 'name: dominio\n');

    final ps = await TopologiaDart(raiz).packages();
    expect(
        ps.firstWhere((p) => p.name == 'app').dependsOn, equals(['dominio']));
  });

  test('una ruta con «..» que vuelve adentro se resuelve', () async {
    // Sin canonicalizar, esta ruta no coincidiría con ningún directorio
    // descubierto y la flecha desaparecería en silencio.
    paquete(
        'a/app',
        'name: app\n'
            'dependencies:\n  dominio:\n    path: ../../b/../b/dominio\n');
    paquete('b/dominio', 'name: dominio\n');

    final ps = await TopologiaDart(raiz).packages();
    expect(
        ps.firstWhere((p) => p.name == 'app').dependsOn, equals(['dominio']));
  });

  test('el nombre lo da el manifiesto del destino, no la clave', () async {
    // Las dos pueden diferir, y la que manda es la del paquete real: si se
    // usara la clave, `dependsOn` nombraría algo que no existe.
    paquete(
        'app',
        'name: app\n'
            'dependencies:\n  alias_cualquiera:\n    path: ../real\n');
    paquete('real', 'name: nombre_real\n');

    final ps = await TopologiaDart(raiz).packages();
    expect(ps.firstWhere((p) => p.name == 'app').dependsOn,
        equals(['nombre_real']));
  });

  test('un manifiesto ilegible detiene la topología, no se saltea', () async {
    paquete('bueno', 'name: bueno\n');
    paquete('roto', ':::esto no es yaml:::\n  - [\n');

    expect(
        () => TopologiaDart(raiz).packages(), throwsA(isA<TopologiaIlegible>()),
        reason: 'saltarlo haría la topología más chica, y eso se lee igual '
            'que un proyecto con menos paquetes');
  });

  test('un manifiesto sin `name` también', () async {
    paquete('sin_nombre', 'dependencies:\n  x: ^1.0.0\n');
    expect(() => TopologiaDart(raiz).packages(),
        throwsA(isA<TopologiaIlegible>()));
  });

  group('no poder INTERPRETAR una arista no es que no HAYA arista', () {
    // El bug: `path: 42` se salteaba en silencio y la topología salía más
    // chica. Es el mismo modo de fallo que el archivo declara evitar, cometido
    // dentro del archivo que lo declara.
    for (final caso in {
      // La SECCIÓN entera, no solo una entrada. Se había arreglado el caso
      // que un review mostró —una entrada— y no la clase: `dependencies: 42`
      // seguía produciendo una topología vacía en silencio.
      '`dependencies` es una lista': 'name: app\ndependencies:\n  - local\n',
      '`dependencies` es un número': 'name: app\ndependencies: 42\n',
      '`dev_dependencies` es una lista':
          'name: app\ndev_dependencies:\n  - x\n',
      // Y un nivel más: el NOMBRE de la dependencia. No lo pidió ningún
      // review; salió de recorrer la estructura entera en vez del caso.
      'el nombre de una dependencia no es cadena':
          'name: app\ndependencies:\n  42:\n    path: ../x\n',
      '`path` numérico': 'name: app\ndependencies:\n  x:\n    path: 42\n',
      '`path` vacío': "name: app\ndependencies:\n  x:\n    path: ''\n",
      '`path` nulo': 'name: app\ndependencies:\n  x:\n    path:\n',
      'la dependencia es una lista':
          'name: app\ndependencies:\n  x:\n    - a\n',
    }.entries) {
      test(caso.key, () async {
        paquete('app', caso.value);
        expect(() => TopologiaDart(raiz).packages(),
            throwsA(isA<TopologiaIlegible>()));
      });
    }
  });

  group('lo que SÍ se saltea, porque es una conclusión y no una duda', () {
    for (final caso in {
      'restricción de versión': 'name: app\ndependencies:\n  x: ^1.0.0\n',
      'sin restricción': 'name: app\ndependencies:\n  x:\n',
      'mapa sin `path`': 'name: app\ndependencies:\n  x:\n    sdk: flutter\n',
      'sección ausente': 'name: app\n',
      'sección presente y vacía': 'name: app\ndependencies:\n',
    }.entries) {
      test(caso.key, () async {
        paquete('app', caso.value);
        final ps = await TopologiaDart(raiz).packages();
        expect(ps.single.dependsOn, isEmpty);
      });
    }
  });

  test('una lectura que falla de verdad también es TopologiaIlegible',
      () async {
    // El test de «manifiesto ilegible» usa YAML sintácticamente inválido, así
    // que no demuestra que un fallo de LECTURA —distinto de uno de parseo—
    // termine normalizado. Bytes que no son UTF-8 lo ejercen de verdad.
    final d = Directory('${raiz.path}/bytes')..createSync(recursive: true);
    File('${d.path}/pubspec.yaml').writeAsBytesSync([0xC3, 0x28, 0xA0, 0xA1]);
    expect(() => TopologiaDart(raiz).packages(),
        throwsA(isA<TopologiaIlegible>()));
  });

  test('un proyecto sin ningún paquete devuelve vacío, no falla', () async {
    // Es un resultado legítimo y distinto de «no pude mirar»: la diferencia la
    // sostiene que un manifiesto ilegible SÍ lanza.
    expect(await TopologiaDart(raiz).packages(), isEmpty);
  });
}
