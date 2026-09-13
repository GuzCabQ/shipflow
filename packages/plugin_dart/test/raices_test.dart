/// Qué raíces de resolución toca una rebanada, sobre un fixture **con la forma
/// exacta de este repositorio**.
///
/// Raíz de workspace con miembros, `tool/analisis` que no es miembro y tiene
/// lockfile propio, y `fixtures/app-minima/{dominio,app}` con `app` sobre el SDK
/// de Flutter. Un fixture de un solo manifiesto jamás habría encontrado el
/// defecto que la aprobación del diseño encontró: la versión anterior exigía un
/// único workspace con raíz en el candidato, y con eso `shipflow` no podía
/// verificarse a sí mismo.
///
/// **Se calculan sin correr nada.** Es lo que permite fijar esta forma sin
/// depender de dónde vive la toolchain en la máquina que corre la suite — el
/// error que ya se cometió tres veces en este diseño.
library;

import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;

  void escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  /// La forma de `shipflow`, con los mismos nombres.
  void comoShipflow() {
    escribir(
      'pubspec.yaml',
      'name: shipflow\n'
          'environment:\n  sdk: ^3.11.0\n'
          'workspace:\n  - packages/core\n  - packages/vcs\n',
    );
    escribir('pubspec.lock', 'packages: {}\n');
    escribir(
      'packages/core/pubspec.yaml',
      'name: core\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\n',
    );
    escribir('packages/core/lib/valores.dart', 'class A {}\n');
    escribir(
      'packages/vcs/pubspec.yaml',
      'name: vcs\n'
          'environment:\n  sdk: ^3.11.0\n'
          'resolution: workspace\n'
          'dependencies:\n  core:\n    path: ../core\n',
    );
    escribir('packages/vcs/lib/repo.dart', 'class R {}\n');
    escribir(
      'tool/analisis/pubspec.yaml',
      'name: analisis\nenvironment:\n  sdk: ^3.11.0\n',
    );
    escribir('tool/analisis/pubspec.lock', 'packages: {}\n');
    escribir('tool/analisis/bin/check.dart', 'void main() {}\n');
    escribir(
      'fixtures/app-minima/dominio/pubspec.yaml',
      'name: dominio\nenvironment:\n  sdk: ^3.11.0\n',
    );
    escribir('fixtures/app-minima/dominio/lib/dominio.dart', 'class D {}\n');
    escribir(
      'fixtures/app-minima/app/pubspec.yaml',
      'name: app\n'
          'environment:\n  sdk: ^3.11.0\n  flutter: ">=3.18.0"\n'
          'dependencies:\n'
          '  flutter:\n    sdk: flutter\n'
          '  dominio:\n    path: ../dominio\n',
    );
    escribir('fixtures/app-minima/app/lib/main.dart', 'void main() {}\n');
    escribir('README.md', '# el arnés\n');
    escribir('.github/workflows/checks.yml', 'name: checks\n');
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('raices_');
    comoShipflow();
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  List<String> raices(List<String> archivos) =>
      raicesDeResolucion(raiz.path, archivos);

  test(
    'una rebanada que solo toca packages/ deriva UNA raíz: el workspace',
    () {
      expect(raices(['packages/core/lib/valores.dart']), ['.']);
      expect(
        raices([
          'packages/core/lib/valores.dart',
          'packages/vcs/lib/repo.dart',
        ]),
        ['.'],
      );
    },
  );

  test('packages/ y tool/analisis derivan DOS raíces', () {
    expect(
      raices([
        'packages/core/lib/valores.dart',
        'tool/analisis/bin/check.dart',
      ]),
      ['.', 'tool/analisis'],
    );
  });

  test('el fixture con otra toolchain solo aparece cuando se lo toca', () {
    expect(raices(['fixtures/app-minima/app/lib/main.dart']), [
      'fixtures/app-minima/app',
    ]);
    expect(
      raices(['packages/core/lib/valores.dart']),
      isNot(contains('fixtures/app-minima/app')),
      reason:
          'derivar una raíz que la rebanada no necesita es pagar por nada el '
          'riesgo de una toolchain que acá está y en el runner no',
    );
  });

  test(
    'un archivo de la raíz que no es de ningún paquete cae en el workspace',
    () {
      expect(raices(['README.md', '.github/workflows/checks.yml']), ['.']);
    },
  );

  test(
    'un miembro que se declara del workspace y nadie lista es raíz propia',
    () {
      escribir(
        'packages/suelto/pubspec.yaml',
        'name: suelto\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\n',
      );
      escribir('packages/suelto/lib/s.dart', '');
      expect(raices(['packages/suelto/lib/s.dart']), ['packages/suelto']);
    },
  );

  test('sin ningún manifiesto hacia arriba no hay raíz', () {
    // Cero raíces es legítimo: un candidato cuyos archivos no cuelgan de ningún
    // manifiesto no tiene nada que derivar, y eso no lo vuelve defectuoso.
    final vacio = Directory.systemTemp.createTempSync('sin_manifiesto_');
    try {
      File('${vacio.path}/a.txt').writeAsStringSync('x');
      expect(raicesDeResolucion(vacio.path, ['a.txt']), isEmpty);
    } finally {
      vacio.deleteSync(recursive: true);
    }
  });

  test('un manifiesto que no se puede leer es raíz propia: el resolvedor dirá '
      'por qué', () {
    // Acá NO se falla cerrado, y es a propósito: la evidencia del defecto la
    // produce la herramienta que resuelve, con su propio mensaje citado. Decidir
    // acá que el manifiesto está roto sería adivinar por ella.
    escribir('tool/roto/pubspec.yaml', 'name: [\n');
    escribir('tool/roto/bin/x.dart', '');
    expect(raices(['tool/roto/bin/x.dart']), ['tool/roto']);
  });

  test('un archivo fuera del candidato no se acepta', () {
    expect(() => raices(['../afuera.dart']), throwsArgumentError);
    expect(() => raices(['/etc/hosts']), throwsArgumentError);
  });
}
