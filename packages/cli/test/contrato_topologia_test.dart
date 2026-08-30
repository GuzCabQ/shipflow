/// Suite de contrato de `ProjectTopology`, contra las DOS implementaciones.
///
/// `docs/08` §2 lo dice sin rodeos: *un fake solo es sustituto válido si
/// cumple el mismo contrato que el real. Sin eso se testea contra un fake que
/// miente y la suite queda verde por construcción.*
///
/// El sujeto es el fixture: un proyecto de verdad, con dos paquetes y una
/// flecha entre ellos. La implementación real lo lee del disco; la falsa se
/// configura para describir el mismo proyecto.
///
/// LO QUE PRUEBA Y LO QUE NO
///     Prueba que las dos respondan lo mismo ante el mismo sujeto. **No**
///     prueba que la real esté bien: para eso está el fixture, que es un
///     proyecto que compila de verdad y se verifica en su propio job.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

/// La raíz del repositorio, encontrada subiendo hasta el registro de reglas.
///
/// NO se usa una ruta relativa ni `Platform.script`. La relativa depende de
/// desde dónde se invoque `dart test`, y `Platform.script` bajo el corredor de
/// pruebas apunta a un kernel temporal en `/var/folders/...` — las dos harían
/// que la implementación real leyera un directorio inexistente y devolviera
/// una lista vacía, **que se lee igual que un proyecto sin paquetes**.
///
/// Y si no la encuentra, LANZA. Un fixture ausente que se degradara a «no hay
/// paquetes» pondría de acuerdo a las dos implementaciones en la nada.
Directory get raizDelRepo {
  var d = Directory.current.absolute;
  for (var i = 0; i < 8; i++) {
    if (File('${d.path}/arquitectura.json').existsSync()) return d;
    if (d.parent.path == d.path) break;
    d = d.parent;
  }
  throw StateError('no encontré la raíz del repositorio subiendo desde '
      '${Directory.current.path}. Sin ella no hay sujeto que comparar.');
}

Directory get fixture => Directory('${raizDelRepo.path}/fixtures/app-minima');

/// Lo que el fixture ES. Las dos implementaciones tienen que decir esto.
List<Package> get esperado => [
      Package(name: 'app', path: 'app', dependsOn: const ['dominio']),
      Package(name: 'dominio', path: 'dominio', dependsOn: const []),
    ];

/// Las dos implementaciones, con nombre. **Que sean dos no es un detalle: es
/// la condición para que esta suite signifique algo.**
final implementaciones = <String, ProjectTopology Function()>{
  'real · lee el fixture del disco': () => TopologiaDart(fixture),
  'falsa · se le declara la topología': () => TopologiaFalsa(esperado),
};

void main() {
  test('la suite corre contra DOS implementaciones, no una', () {
    // Sin esto, quitar la real —porque tarda, porque necesita disco, porque
    // falló una vez— dejaría la suite verde probando el fake contra sí mismo.
    // Es el modo de fallo que `docs/08` §2 nombra, y no lo vería nadie.
    expect(implementaciones, hasLength(2));
    expect(
        implementaciones.keys.where((k) => k.startsWith('real')), hasLength(1),
        reason: 'sin la implementación real esto no es una suite de contrato');
    expect(
        implementaciones.keys.where((k) => k.startsWith('falsa')), hasLength(1),
        reason: 'sin el fake no hay segunda implementación que la contradiga');
  });

  test('el fixture existe donde la suite lo busca', () {
    // Si no estuviera, la real devolvería una lista vacía y las comparaciones
    // fallarían por la razón equivocada — o peor, coincidirían en vacío.
    expect(fixture.existsSync(), isTrue,
        reason: 'el sujeto de esta suite es ${fixture.path}');
  });

  for (final entrada in implementaciones.entries) {
    group(entrada.key, () {
      late ProjectTopology puerto;
      setUp(() => puerto = entrada.value());

      test('encuentra los dos paquetes del proyecto', () async {
        final paquetes = await puerto.packages();
        expect(paquetes.map((p) => p.name), equals(['app', 'dominio']));
      });

      test('reporta la flecha entre paquetes locales', () async {
        final paquetes = await puerto.packages();
        final app = paquetes.firstWhere((p) => p.name == 'app');
        expect(app.dependsOn, equals(['dominio']),
            reason: 'una dependencia por ruta ES topología');
      });

      test('NO reporta las externas como topología', () async {
        // `app` depende de un framework y de un paquete de lints. Eso es
        // resolución, y pertenece a otro puerto: `DependencyResolver`.
        final paquetes = await puerto.packages();
        for (final p in paquetes) {
          expect(
              p.dependsOn.every((d) => ['app', 'dominio'].contains(d)), isTrue,
              reason: '${p.name} reporta «${p.dependsOn}», que no son paquetes '
                  'de este proyecto');
        }
      });

      test('la lista que devuelve no se puede mutar desde afuera', () async {
        final paquetes = await puerto.packages();
        expect(() => paquetes.first.dependsOn.add('x'), throwsUnsupportedError);
      });
    });
  }
}
