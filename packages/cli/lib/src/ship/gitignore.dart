/// El `.gitignore` del directorio de corridas, y su comprobación.
///
/// **Dos operaciones, y las dos existen porque una sola no alcanza.**
/// [asegurarGitignore] pone el archivo; [corridasIgnoradas] pregunta si la
/// ruta queda protegida de verdad. Que el archivo EXISTA no dice que APLIQUE:
/// una regla de negación más abajo en el mismo `.gitignore`, o un
/// `core.excludesFile` que declare otro, lo dejarían sin efecto —y el fallo
/// sería el documento de la corrida terminando commiteado dentro del pull
/// request, que es exactamente lo contrario de lo que este mecanismo
/// promete—. Por eso la comprobación se la hace a `git`, con el mismo
/// lanzador saneado que usa el resto de esta clase, y no leyendo el archivo.
///
/// **El momento importa tanto como el mecanismo.** Las dos se llaman DESPUÉS
/// de la compuerta por estado y ANTES de persistir el documento `prepared` —
/// nunca en el preflight, que corre antes de que exista `.shipflow/runs` y
/// donde exigirlo impediría el primer uso. Quién las llama y cuándo es de la
/// orquestación de `ship`, no de este archivo.
library;

import 'dart:io';

import 'package:path/path.dart' as rutas;
import 'package:vcs/vcs.dart';

/// El contenido que este mecanismo escribe. **Es la línea sola, sin adornos**:
/// [asegurarGitignore] decide si pisa o no un archivo existente comparando
/// bytes contra este valor, y una cabecera o un comentario lo volverían
/// distinto de sí mismo entre una corrida y la siguiente, lo que rompería la
/// idempotencia que la segunda prueba de esta suite exige.
const _contenido = '*\n';

/// Se lanza cuando `$raizDeShipflow/.gitignore` ya existe con un contenido
/// que no es el que este mecanismo escribiría.
///
/// **No se pisa.** El contenido ajeno puede ser deliberado —alguien necesita
/// versionar algo puntual ahí— y sobrescribirlo en silencio sería la misma
/// clase de sorpresa que este mecanismo existe para evitar del otro lado: no
/// proteger de menos, tampoco de más.
class GitignoreAjeno implements Exception {
  final String ruta;

  const GitignoreAjeno(this.ruta);

  @override
  String toString() =>
      'GitignoreAjeno: $ruta ya existe con un contenido distinto del que '
      'este mecanismo escribiría. No se pisa: puede ser deliberado.';
}

/// Que exista `$raizDeShipflow/.gitignore` con `*`, sin pisar uno ajeno.
///
/// **Temporal y `rename`, el mismo mecanismo que [RegistroDeCorridas]** —en
/// `corrida.dart`— y el mismo límite: el `rename` es atómico dentro del mismo
/// sistema de archivos, así que el temporal se crea AL LADO del destino y no
/// en el temporal del sistema operativo. Cruzar sistemas de archivos
/// convertiría el `rename` en copiar y borrar, que no es atómico.
///
/// **Crea [raizDeShipflow] si no existe.** En el primer uso `.shipflow/`
/// todavía no está en el disco —por eso el preflight no puede exigir nada
/// acá—, y esta es la primera operación de la corrida que sí escribe ahí.
///
/// **No es un candado.** Entre comprobar que el destino no existe y renombrar
/// el temporal hay una ventana; dos corridas de `ship` empezando en el mismo
/// instante sobre el mismo `.shipflow` recién creado podrían pisarse una a la
/// otra. Nada en este diseño sostiene que `ship` corra concurrentemente sobre
/// el mismo repositorio, así que esa ventana queda declarada y no cerrada —el
/// mismo trato que [RegistroDeCorridas.escribir] les da a sus propios límites.
Future<void> asegurarGitignore(String raizDeShipflow) async {
  await Directory(raizDeShipflow).create(recursive: true);
  final destino = File(rutas.join(raizDeShipflow, '.gitignore'));
  if (await destino.exists()) {
    if (await destino.readAsString() == _contenido) return;
    throw GitignoreAjeno(destino.path);
  }
  // Al lado del destino, no en el temporal del sistema: ver el doc de arriba.
  final temporal = File('${destino.path}.tmp');
  await temporal.writeAsString(_contenido, flush: true);
  await temporal.rename(destino.path);
}

/// Si `git` ignora [rutaDeUnaCorrida]. **Le pregunta a `git`, no al disco.**
///
/// Delega en [RepositorioGit.rutaIgnorada], que corre `check-ignore` con el
/// lanzador saneado del adapter: esta función no lanza el proceso, solo
/// traduce la pregunta al vocabulario de `ship`.
Future<bool> corridasIgnoradas(RepositorioGit repo, String rutaDeUnaCorrida) =>
    repo.rutaIgnorada(rutaDeUnaCorrida);
