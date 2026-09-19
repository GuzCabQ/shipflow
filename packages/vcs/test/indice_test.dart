/// La comparación del índice contra un árbol, acotada a rutas — contra `git`
/// de verdad.
///
/// **No hay doble de `git`, por el mismo motivo que en `repositorio_test`**:
/// es determinista, está instalado y es rápido, y lo que hay que comprobar es
/// justamente CÓMO responde la herramienta real ante mtimes tocados, rutas
/// ajenas y borrados del índice — un doble solo repetiría lo que esta prueba
/// ya supone.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

/// Una política que declara todo editable: esta rebanada no ejercita
/// artefactos, y `RepositorioGit` la exige sin valor por defecto.
class _PoliticaQueAceptaTodo implements ArtifactPolicy {
  const _PoliticaQueAceptaTodo();

  @override
  bool isGenerated(String path) => false;

  @override
  bool isEditable(String path) => true;
}

void main() {
  const politica = _PoliticaQueAceptaTodo();

  /// Un repositorio real con [archivos] commiteados como base, más tres
  /// ayudantes que tocan el índice y el árbol de trabajo **por fuera** del
  /// adapter — con `git` de verdad, no con lo que se está probando — para que
  /// las pruebas puedan armar el estado que [RepositorioGit.rutasQueDifierenDelArbol]
  /// tiene que leer bien.
  ///
  /// **El temporal es propio de cada prueba y se borra solo.** Nunca se toca
  /// el checkout de este repositorio: `addTearDown` corre incluso si la
  /// prueba falla, así que no puede quedar un directorio de sobra fuera de
  /// `/tmp`.
  ({
    RepositorioGit repo,
    void Function(String ruta, String contenido) escribirYPreparar,
    void Function(String ruta) tocarSinCambiarContenido,
    void Function(String ruta) quitarDelIndice,
  })
  repoConArchivos(Map<String, String> archivos) {
    final raiz = Directory.systemTemp.createTempSync('indice_');
    addTearDown(() => raiz.deleteSync(recursive: true));

    void git(List<String> args) {
      final r = Process.runSync('git', args, workingDirectory: raiz.path);
      if (r.exitCode != 0) {
        fail('git ${args.join(" ")} falló: ${r.stdout}${r.stderr}');
      }
    }

    git(['init', '--quiet', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    for (final entrada in archivos.entries) {
      File('${raiz.path}/${entrada.key}').writeAsStringSync(entrada.value);
    }
    git(['add', '-A']);
    git(['commit', '--quiet', '-m', 'base']);

    void escribirYPreparar(String ruta, String contenido) {
      File('${raiz.path}/$ruta').writeAsStringSync(contenido);
      git(['add', '--', ruta]);
    }

    void tocarSinCambiarContenido(String ruta) {
      final archivo = File('${raiz.path}/$ruta');
      final contenido = archivo.readAsBytesSync();
      // **Un futuro lejano, no un `sleep`.** Lo que hace falta es un mtime
      // que el índice no tenga ya registrado; correr hacia adelante un mes es
      // instantáneo y no depende de la resolución del reloj del sistema de
      // archivos, que un `sleep` de un segundo sí podría no superar.
      final futuro = DateTime.now().add(const Duration(days: 30));
      archivo.writeAsBytesSync(contenido);
      archivo.setLastModifiedSync(futuro);
    }

    void quitarDelIndice(String ruta) {
      git(['rm', '--quiet', '--cached', '--', ruta]);
    }

    return (
      repo: RepositorioGit(directorio: raiz.path, politica: politica),
      escribirYPreparar: escribirYPreparar,
      tocarSinCambiarContenido: tocarSinCambiarContenido,
      quitarDelIndice: quitarDelIndice,
    );
  }

  group('rutasQueDifierenDelArbol', () {
    test('un índice que coincide devuelve la lista VACÍA', () async {
      final r = repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
      final arbol = await r.repo.arbolDe(await r.repo.head);
      expect(
        await r.repo.rutasQueDifierenDelArbol(
          arbol: arbol,
          rutas: ['a.txt', 'b.txt'],
        ),
        isEmpty,
      );
    });

    test('una ruta preparada con otro contenido sale en la lista', () async {
      final r = repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
      final arbol = await r.repo.arbolDe(await r.repo.head);
      r.escribirYPreparar('a.txt', 'CAMBIADO');
      expect(
        await r.repo.rutasQueDifierenDelArbol(
          arbol: arbol,
          rutas: ['a.txt', 'b.txt'],
        ),
        ['a.txt'],
      );
    });

    test(
      'un cambio preparado FUERA de las rutas NO se reporta: no es nuestro',
      () async {
        final r = repoConArchivos({'a.txt': 'uno', 'ajeno.txt': 'dos'});
        final arbol = await r.repo.arbolDe(await r.repo.head);
        r.escribirYPreparar('ajeno.txt', 'CAMBIADO');
        expect(
          await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt']),
          isEmpty,
          reason:
              'el reintento no es dueño del índice del usuario: opinar sobre '
              'una ruta ajena rechazaría lo que apply promete preservar',
        );
      },
    );

    test('un mtime tocado con el MISMO contenido no es una diferencia', () async {
      // **La razón NO es un refresco previo: acá no hay ninguno.** El brief
      // de esta tarea suponía que hacía falta `update-index --refresh` para
      // que este caso diera vacío, copiando el razonamiento de
      // `_CandidatoGit.alteraciones` —que compara el árbol de TRABAJO, donde
      // el `mtime` sí decide—. Medido: con `--cached` la comparación es
      // índice contra árbol, dos objetos que no requieren leer el disco, así
      // que el `mtime` nunca entra en juego. Sacar un refresco que nunca se
      // escribió no puede romper esta prueba; lo que la sostiene es que
      // `git add` nunca se volvió a correr sobre `a.txt`, así que el índice
      // sigue anotando el blob original.
      final r = repoConArchivos({'a.txt': 'uno'});
      final arbol = await r.repo.arbolDe(await r.repo.head);
      r.tocarSinCambiarContenido('a.txt');
      expect(
        await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt']),
        isEmpty,
        reason:
            'el índice sigue anotando el blob de "uno": --cached compara '
            'objetos de git, no el mtime del árbol de trabajo',
      );
    });

    test('una ruta borrada del índice también es una diferencia', () async {
      final r = repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
      final arbol = await r.repo.arbolDe(await r.repo.head);
      r.quitarDelIndice('a.txt');
      expect(
        await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt']),
        ['a.txt'],
      );
    });

    test('la lista de rutas VACÍA no significa «todas»', () async {
      final r = repoConArchivos({'a.txt': 'uno'});
      final arbol = await r.repo.arbolDe(await r.repo.head);
      r.escribirYPreparar('a.txt', 'CAMBIADO');
      expect(
        await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: const []),
        isEmpty,
        reason:
            'sin rutas no hay nada sobre lo que opinar; tratarlo como '
            '«todas» convertiría un alcance vacío en el más ancho posible',
      );
    });
  });
}
