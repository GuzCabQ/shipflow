/// La lectura pura de la comparación del índice contra un árbol.
///
/// Vive en el mismo library que [RepositorioGit] —por eso es un `part`—,
/// siguiendo al archivo donde vive [leerDiffRaw] y al del candidato: **acá
/// vive solo la LECTURA** de lo que `git diff-index` contestó, y lanzar el
/// proceso es de la clase que tiene el lanzador saneado. Una library propia
/// que necesitara llamar de vuelta a [leerDiffRaw] tendría que importar esta
/// misma library, y ese ciclo es justo lo que la forma de `part` evita.
part of 'repositorio.dart';

/// Las rutas que un `diff-index --raw -z --cached <árbol> -- <rutas>`
/// —acotado a rutas que EL ÁRBOL YA TIENE— marcó distintas.
///
/// **Sin ordenar, a propósito.** [RepositorioGit.rutasQueDifierenDelArbol]
/// junta esto con lo que encuentra por otra vía —una ruta que el árbol no
/// tiene— y ordena recién al final, sobre el conjunto completo. Ordenar acá
/// también sería trabajo que ninguna prueba puede notar —el orden final ya
/// queda garantizado del otro lado— y una promesa que esta función no
/// necesita sostener por su cuenta.
///
/// **Envuelve a [leerDiffRaw]: no es un segundo parser del mismo formato.**
/// Dos lectores de la misma salida de `git` divergen tarde o temprano —uno
/// de los dos deja de enterarse el día que `git` cambia una letra, y nada lo
/// avisa hasta que el otro ya está mintiendo—, así que esta función se limita
/// a pedirle al parser que ya existe la lista de alteraciones y quedarse solo
/// con la ruta.
///
/// **Por qué el pathspec tiene que estar acotado al árbol, y no es un
/// detalle de quien llama.** `leerDiffRaw` falla cerrado ante una letra que
/// no sea `M`, `D` o `T` a propósito: contra el índice AISLADO del
/// candidato —su único llamador hasta que existió esta función— una ruta
/// ausente del árbol es inalcanzable, porque ese índice se lee del mismo
/// árbol que se compara. Con el índice REAL y un árbol arbitrario, esa
/// ausencia SÍ es alcanzable —una revisión candidata que borró la ruta, y
/// quien corre la volvió a preparar— y `git` la marca con `A` (agregada),
/// que el parser no conoce y rechaza con `PromesaIncumplida`. Ensanchar el
/// parser compartido para admitirla aflojaría, del lado del candidato, una
/// garantía que ahí sí vale; por eso [RepositorioGit.rutasQueDifierenDelArbol]
/// nunca le pide `diff-index` por una ruta que el árbol no tiene, y resuelve
/// esas por su cuenta, sin pasar por acá.
///
/// **[declaradas] de [leerDiffRaw] se le pasa vacío, a propósito.** Ese
/// descuento existe para el candidato, que materializa a propósito algunos
/// huecos en su árbol de trabajo aislado —enlaces absolutos, submódulos— y
/// necesita no contarlos como borrados. El índice real de quien corre no
/// tiene huecos declarados por nadie: lo que falta ahí es, sencillamente,
/// una diferencia.
List<String> rutasDeDiffRaw(List<int> crudo) => leerDiffRaw(
  crudo,
  declaradas: const {},
).map((alteracion) => alteracion.ruta).toList();
