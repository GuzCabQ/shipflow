/// La comparación del índice contra un árbol, acotada a rutas — contra `git`
/// de verdad.
///
/// **No hay doble de `git`, por el mismo motivo que en `repositorio_test`**:
/// es determinista, está instalado y es rápido, y lo que hay que comprobar es
/// justamente CÓMO responde la herramienta real ante mtimes tocados, rutas
/// ajenas, borrados del índice y conflictos sin resolver — un doble solo
/// repetiría lo que esta prueba ya supone.
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

  /// Un repositorio real con [archivos] commiteados como base, más los
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
    void Function(String ruta) borrarYCommitear,
    void Function(String ruta) dejarConflictoSinResolver,
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

    /// Borra [ruta] y la commitea: el árbol de la revisión resultante NO la
    /// tiene. Sirve para armar el escenario donde una ruta declarada está en
    /// el índice real de quien corre pero no en el árbol candidato —el que
    /// una revisión de borrado deja atrás—.
    void borrarYCommitear(String ruta) {
      git(['rm', '--quiet', '--', ruta]);
      git(['commit', '--quiet', '-m', 'borra $ruta']);
    }

    /// Deja [ruta] con un conflicto **sin resolver** en el índice real: la
    /// entrada queda sin fusionar, con sus tres etapas, que es lo que produce
    /// un `merge`, un `rebase` o un `cherry-pick` que no cerró.
    ///
    /// **Se arma con la herramienta de verdad y no escribiendo el índice a
    /// mano**, por lo mismo que el resto de esta suite: lo que hay que medir
    /// es cómo responde la herramienta real ante ese estado, y un índice
    /// fabricado solo repetiría lo que la prueba ya supone.
    ///
    /// El `merge` falla a propósito —ése es el punto—, así que es la única
    /// invocación de esta suite que no exige código cero.
    void dejarConflictoSinResolver(String ruta) {
      final contenido = File('${raiz.path}/$ruta').readAsStringSync();
      git(['switch', '--quiet', '-c', 'de-al-lado']);
      File('${raiz.path}/$ruta').writeAsStringSync('$contenido — de al lado\n');
      git(['commit', '--quiet', '-am', 'de al lado']);
      git(['switch', '--quiet', 'main']);
      File('${raiz.path}/$ruta').writeAsStringSync('$contenido — de acá\n');
      git(['commit', '--quiet', '-am', 'de acá']);
      Process.runSync('git', [
        'merge',
        'de-al-lado',
      ], workingDirectory: raiz.path);
    }

    return (
      repo: RepositorioGit(directorio: raiz.path, politica: politica),
      escribirYPreparar: escribirYPreparar,
      tocarSinCambiarContenido: tocarSinCambiarContenido,
      quitarDelIndice: quitarDelIndice,
      borrarYCommitear: borrarYCommitear,
      dejarConflictoSinResolver: dejarConflictoSinResolver,
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

    test(
      'un mtime tocado con el MISMO contenido no es una diferencia',
      () async {
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
      },
    );

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

    test('una ruta que el ÍNDICE tiene y el árbol candidato NO es una '
        'diferencia, no una excepción', () async {
      // El árbol candidato es el de una revisión que BORRÓ `a.txt`: ahí no
      // existe. Quien corre, después, la volvió a preparar en su índice
      // real —el caso de un verificador o un usuario que la restituye—.
      // Contra ese árbol, `diff-index --cached` reporta esto con la letra
      // `A` (agregada), que `leerDiffRaw` no conoce: su contrato es el del
      // índice AISLADO del candidato, leído del propio árbol que se le da,
      // donde esa letra es inalcanzable por construcción. Acá, con el
      // índice REAL y un árbol arbitrario, sí es alcanzable, y tratarla
      // como una `PromesaIncumplida` —el contrato pensado para lo
      // inalcanzable del candidato— confundiría una diferencia legítima
      // con «se rompió el arnés».
      final r = repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
      r.borrarYCommitear('a.txt');
      final arbolSinA = await r.repo.arbolDe(await r.repo.head);
      r.escribirYPreparar('a.txt', 'vuelve');
      expect(
        await r.repo.rutasQueDifierenDelArbol(
          arbol: arbolSinA,
          rutas: ['a.txt', 'b.txt'],
        ),
        ['a.txt'],
      );
    });

    test(
      'una entrada SIN FUSIONAR es una diferencia, no una excepción',
      () async {
        // **El conflicto sin resolver, con la herramienta de verdad.** Un
        // `merge`, un `rebase` o un `cherry-pick` que no cerró deja la entrada
        // con sus tres etapas, y la comparación del índice la marca con la
        // letra `U` — medido con la herramienta instalada, y declarado en su
        // manual de la salida cruda.
        //
        // Antes de esta prueba, esa letra llegaba al parser compartido, que
        // falla cerrado ante lo que no conoce: la excepción no es de la familia
        // que la composición atrapa, así que subía hasta la red de último
        // recurso y salía «se rompió el arnés, reportalo con la traza» sobre
        // una corrida donde lo único que pasa es que quien corre tiene un
        // conflicto sin resolver.
        //
        // Un índice sin fusionar **es** una diferencia: esa ruta no coincide
        // con ningún árbol, porque el índice todavía no decidió qué contiene.
        final r = repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
        r.dejarConflictoSinResolver('a.txt');
        final arbol = await r.repo.arbolDe(await r.repo.head);
        expect(
          await r.repo.rutasQueDifierenDelArbol(
            arbol: arbol,
            rutas: ['a.txt', 'b.txt'],
          ),
          ['a.txt'],
        );
      },
    );

    test('con más de una ruta distinta, el resultado sale ORDENADO y no en el '
        'orden en que se prepararon', () async {
      // Las seis pruebas de arriba nunca devuelven más de una ruta, así
      // que ninguna nota si el resultado se ordena o no. Acá se preparan
      // dos, a propósito en el orden CONTRARIO al alfabético.
      final r = repoConArchivos({'m.txt': 'uno', 'z.txt': 'dos'});
      final arbol = await r.repo.arbolDe(await r.repo.head);
      r.escribirYPreparar('z.txt', 'CAMBIADO');
      r.escribirYPreparar('m.txt', 'CAMBIADO');
      expect(
        await r.repo.rutasQueDifierenDelArbol(
          arbol: arbol,
          rutas: ['z.txt', 'm.txt'],
        ),
        ['m.txt', 'z.txt'],
      );
    });

    test('con rutas de las DOS fuentes —una fuera del árbol, otra dentro— el '
        'resultado sale ORDENADO igual', () async {
      // «a.txt» llega por la vía de `ls-files` —el árbol candidato la
      // borró y el índice real la volvió a preparar—; «z.txt» llega por
      // la vía de `diff-index` —el árbol la tiene, y el índice la
      // modificó—. El código arma primero las de `diff-index` y recién
      // DESPUÉS les suma las de `ls-files`; sin el ordenamiento final el
      // resultado saldría en ese orden de inserción, `['z.txt', 'a.txt']`,
      // y no en el alfabético. Ninguna de las pruebas de arriba mezcla las
      // dos fuentes, así que ninguna nota si el orden final depende de
      // CÓMO se llegó a cada ruta.
      final r = repoConArchivos({'a.txt': 'uno', 'z.txt': 'dos'});
      r.borrarYCommitear('a.txt');
      final arbolSinA = await r.repo.arbolDe(await r.repo.head);
      r.escribirYPreparar('a.txt', 'vuelve');
      r.escribirYPreparar('z.txt', 'CAMBIADO');
      expect(
        await r.repo.rutasQueDifierenDelArbol(
          arbol: arbolSinA,
          rutas: ['z.txt', 'a.txt'],
        ),
        ['a.txt', 'z.txt'],
      );
    });
  });
}
