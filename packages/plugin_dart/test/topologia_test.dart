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

  test('un proyecto sin ningún paquete devuelve vacío, no falla', () async {
    // Es un resultado legítimo y distinto de «no pude mirar»: la diferencia la
    // sostiene que un manifiesto ilegible SÍ lanza.
    expect(await TopologiaDart(raiz).packages(), isEmpty);
  });
}
