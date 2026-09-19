/// La lectura pura de la comparación del índice contra un árbol.
///
/// Acá vive solo la LECTURA de lo que `git diff-index` contestó, igual que en
/// el archivo donde vive [leerDiffRaw]: leer una salida ya obtenida no
/// necesita el lanzador saneado, así que puede vivir separado de la clase que
/// sí lo tiene. **Lanzar el proceso es de [RepositorioGit]**: es la única
/// costura contra `git` que este paquete se permite, y repetirla acá abriría
/// una segunda donde armar una invocación pudiera divergir de la real.
library;

import 'repositorio.dart';

/// Las rutas que un `diff-index --raw -z --cached <árbol> -- <rutas>` marcó
/// distintas, ordenadas.
///
/// **Envuelve a [leerDiffRaw]: no es un segundo parser del mismo formato.**
/// Dos lectores de la misma salida de `git` divergen tarde o temprano —uno
/// de los dos deja de enterarse el día que `git` cambia una letra, y nada lo
/// avisa hasta que el otro ya está mintiendo—, así que esta función se limita
/// a pedirle al parser que ya existe la lista de alteraciones y quedarse solo
/// con la ruta.
///
/// **[declaradas] de [leerDiffRaw] se le pasa vacío, a propósito.** Ese
/// descuento existe para el candidato, que materializa a propósito algunos
/// huecos en su árbol de trabajo aislado —enlaces absolutos, submódulos— y
/// necesita no contarlos como borrados. El índice real de quien corre
/// `ship` no tiene huecos declarados por nadie: lo que el árbol de trabajo no
/// tiene ahí es, sencillamente, una diferencia.
List<String> rutasDeDiffRaw(List<int> crudo) {
  final rutas = leerDiffRaw(
    crudo,
    declaradas: const {},
  ).map((alteracion) => alteracion.ruta).toList();
  rutas.sort();
  return rutas;
}
