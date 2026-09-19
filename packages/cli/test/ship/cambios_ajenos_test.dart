/// Los cambios ajenos del árbol de trabajo: **lo que la previsualización le
/// muestra a quien está por confirmar la publicación**.
///
/// **El repositorio es de verdad.** Lo que estas pruebas miden es cómo la
/// herramienta ESCRIBE su salida de estado —qué rutas cita, cómo escribe un
/// renombrado— y eso no lo puede producir ningún doble sin reimplementar la
/// herramienta: un doble que devolviera lo que creemos que devuelve mediría
/// nuestra creencia.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:test/test.dart';

/// Un repositorio con un primer commit, listo para ensuciar.
Directory _repo() {
  final raiz = Directory.systemTemp.createTempSync('ship_ajenos_');
  addTearDown(() => raiz.deleteSync(recursive: true));
  String git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: raiz.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
    return (r.stdout as String).trim();
  }

  git(['init', '--initial-branch=main', '.']);
  git(['config', 'user.email', 'p@p']);
  git(['config', 'user.name', 'prueba']);
  // La configuración que hace que la herramienta CITE las rutas no ASCII es
  // la de por omisión; se fija explícita para que una configuración global de
  // quien corre estas pruebas no las vuelva verdes por el motivo equivocado.
  git(['config', 'core.quotePath', 'true']);
  return raiz;
}

void _escribir(Directory raiz, String ruta, String contenido) {
  File('${raiz.path}/$ruta')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(contenido);
}

String _git(Directory raiz, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: raiz.path);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
  }
  return (r.stdout as String).trim();
}

void main() {
  test(
    'un archivo declarado con un nombre NO ASCII no es un cambio ajeno',
    () async {
      // **La reproducción del P1-3 de la revisión humana.** Con la salida
      // citada, «á.txt» vuelve de la herramienta como una cadena entre
      // comillas dobles con sus bytes en octal, no coincide con la ruta
      // declarada, y la previsualización lo pone bajo «NO se publica y NO
      // está en el artefacto» — falso, y es el texto con el que una persona
      // confirma la publicación.
      final raiz = _repo();
      _escribir(raiz, 'á.txt', 'de la rebanada\n');
      expect(
        _git(raiz, ['status', '--porcelain', '--untracked-files=all']),
        contains(r'\303\241'),
        reason:
            'si la herramienta dejara de citar, esta prueba pasaría por el '
            'motivo equivocado: lo que mide es que NO nos engañe el citado',
      );

      final ajenos = await cambiosAjenosDelArbol(
        directorio: raiz.path,
        deLaRebanada: const ['á.txt'],
      );
      expect(
        ajenos,
        isEmpty,
        reason:
            'está declarado: es de la rebanada, y decir lo contrario vuelve '
            'falsa la evidencia con la que se confirma la publicación',
      );
    },
  );

  test('un archivo NO declarado con nombre no ASCII sí es ajeno', () async {
    final raiz = _repo();
    _escribir(raiz, 'ñ.txt', 'de otra persona\n');
    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const ['otro.txt'],
    );
    expect(
      ajenos,
      ['ñ.txt'],
      reason: 'sin citar, y con la ruta tal como la escribiría una persona',
    );
  });

  test('un renombrado declarado de punta a punta no es ajeno', () async {
    final raiz = _repo();
    _escribir(raiz, 'viejo.txt', 'contenido\n');
    _git(raiz, ['add', '-A']);
    _git(raiz, ['commit', '-m', 'base']);
    _git(raiz, ['mv', 'viejo.txt', 'nuevo.txt']);

    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const ['viejo.txt', 'nuevo.txt'],
    );
    expect(
      ajenos,
      isEmpty,
      reason:
          'las DOS rutas del renombrado están declaradas; sin decodificar el '
          'registro de origen, la ruta vieja se leía como un registro suelto',
    );
  });

  test('un renombrado ajeno vuelve con sus dos rutas, legible', () async {
    final raiz = _repo();
    _escribir(raiz, 'viejo.txt', 'contenido\n');
    _escribir(raiz, 'lib/a.txt', 'de la rebanada\n');
    _git(raiz, ['add', '-A']);
    _git(raiz, ['commit', '-m', 'base']);
    _git(raiz, ['mv', 'viejo.txt', 'nuevo.txt']);
    _escribir(raiz, 'lib/a.txt', 'cambiado\n');

    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const ['lib/a.txt'],
    );
    expect(ajenos, ['viejo.txt -> nuevo.txt']);
  });

  test(
    'un renombrado donde solo el destino está declarado sigue siendo ajeno',
    () async {
      // El origen NO es de la rebanada: mover un archivo que la rebanada no
      // nombró es exactamente lo que esta sección existe para mostrar.
      final raiz = _repo();
      _escribir(raiz, 'viejo.txt', 'contenido\n');
      _git(raiz, ['add', '-A']);
      _git(raiz, ['commit', '-m', 'base']);
      _git(raiz, ['mv', 'viejo.txt', 'nuevo.txt']);

      final ajenos = await cambiosAjenosDelArbol(
        directorio: raiz.path,
        deLaRebanada: const ['nuevo.txt'],
      );
      expect(ajenos, ['viejo.txt -> nuevo.txt']);
    },
  );

  test('un archivo declarado con un salto de línea NO es ajeno', () async {
    // **El ancla de la cuarta forma que la revisión nombró.** Un salto de
    // línea adentro de un nombre de archivo es la que parte en dos un
    // registro leído por líneas: sin el delimitador nulo, esa ruta llega
    // partida y ninguna de las dos mitades coincide con lo declarado.
    final raiz = _repo();
    const conSalto = 'con\nsalto.txt';
    _escribir(raiz, conSalto, 'de la rebanada\n');
    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const [conSalto],
    );
    expect(ajenos, isEmpty);
  });

  test('un archivo NO declarado con un salto de línea vuelve entero', () async {
    final raiz = _repo();
    _escribir(raiz, 'con\nsalto.txt', 'de otra persona\n');
    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const ['lib/a.txt'],
    );
    expect(ajenos, [
      'con\nsalto.txt',
    ], reason: 'una sola entrada, con el salto adentro y no partida en dos');
  });

  test('un archivo declarado en otra forma unicode tampoco es ajeno', () async {
    // **El residuo de la misma clase que quedaba abierto, cerrado.** En un
    // sistema de archivos que guarda los nombres descompuestos, la
    // herramienta los precompone al imprimirlos: la ruta declarada tal como
    // el disco la guarda NO coincide, carácter por carácter, con la misma
    // ruta tal como el estado la escribe, y el archivo terminaba bajo «no se
    // publica y no está en el artefacto».
    final raiz = _repo();
    const descompuesto = 'a\u0301.txt';
    const compuesto = '\u00e1.txt';
    _escribir(raiz, descompuesto, 'de la rebanada\n');

    // La premisa de la prueba, medida y no supuesta: si en este sistema las
    // dos formas coincidieran, lo de abajo pasaría por el motivo
    // equivocado. Se declara lo que el disco guarda; el estado puede
    // imprimir eso mismo o la otra forma, y las dos son correctas.
    expect(descompuesto, isNot(compuesto));

    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const [descompuesto],
    );
    expect(
      ajenos,
      isEmpty,
      reason:
          'está declarado: quien compara tiene que ser la herramienta, que '
          'es la que decide cuándo dos rutas son la misma',
    );
  });

  test('una ruta con comillas y espacios vuelve sin citar', () async {
    final raiz = _repo();
    _escribir(raiz, 'con "comillas" y espacio.txt', 'ajeno\n');
    final ajenos = await cambiosAjenosDelArbol(
      directorio: raiz.path,
      deLaRebanada: const ['lib/a.txt'],
    );
    expect(ajenos, ['con "comillas" y espacio.txt']);
  });
}
