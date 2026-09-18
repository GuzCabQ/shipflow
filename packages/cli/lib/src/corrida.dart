import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;

/// Dónde viven los documentos de las corridas.
///
/// **Se escribe a un temporal y se renombra.** El `rename` es atómico dentro
/// del mismo sistema de archivos, así que el nombre final aparece con el
/// contenido entero o no aparece: nadie lee un documento a medio escribir. Ese
/// es todo el mecanismo.
///
/// **Límite declarado:** la atomicidad es *dentro del mismo sistema de
/// archivos*. El temporal se crea al lado del destino justamente por eso; si
/// `.shipflow/` viviera en otro sistema de archivos que el temporal, la
/// garantía no valdría. Como los dos salen de [raiz], no puede pasar sin que
/// alguien cambie esta clase.
///
/// **Segundo límite declarado: `flush: true` no lo sostiene ninguna prueba.**
/// La escritura pide vaciar el búfer del sistema operativo antes de renombrar,
/// para que el documento esté en el disco y no solo en la caché cuando el
/// nombre final aparece. Sacarlo no pone roja ninguna prueba de esta suite, y
/// no es un descuido: observar la diferencia pide un corte de energía o una
/// caída del kernel entre las dos llamadas, que desde el proceso de pruebas no
/// se simula. Queda declarado en vez de disimulado con una prueba que pasaría
/// igual con el mecanismo roto.
class RegistroDeCorridas {
  final String raiz;

  const RegistroDeCorridas({required this.raiz});

  Directory get _directorio => Directory(rutas.join(raiz, 'runs'));

  File _archivo(String runId) =>
      File(rutas.join(_directorio.path, '$runId.json'));

  Future<void> escribir(String runId, DocumentoDeCorrida documento) async {
    await _directorio.create(recursive: true);
    final destino = _archivo(runId);
    // Al lado del destino, no en el temporal del sistema: cruzar sistemas de
    // archivos convertiría el `rename` en copiar y borrar, que no es atómico.
    final temporal = File('${destino.path}.tmp');
    await temporal.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(documento.toJson())}\n',
      flush: true,
    );
    await temporal.rename(destino.path);
  }

  /// El documento de [runId], o nulo si no hay ninguno.
  ///
  /// **Nulo es un hecho, no un fallo:** significa que el proceso murió antes
  /// de persistir `prepared`, y entonces lo único que quedó es un objeto
  /// commit inalcanzable que el `gc` recoge. La recuperación tiene que poder
  /// ramificar sobre eso.
  ///
  /// **Un temporal huérfano no se lee y no se borra.** No se lee porque sería
  /// leer un documento a medio escribir; no se borra porque esta clase no sabe
  /// si alguien lo está escribiendo ahora mismo.
  Future<DocumentoDeCorrida?> leer(String runId) async {
    final archivo = _archivo(runId);
    if (!await archivo.exists()) return null;
    return DocumentoDeCorrida.fromJson(
      Map<String, Object?>.from(
        jsonDecode(await archivo.readAsString()) as Map,
      ),
    );
  }
}

/// Qué hacer con una corrida interrumpida.
enum QueHacerAlRecuperar {
  /// Nada se movió: el CAS se puede reintentar tal cual.
  reintentarElCas,

  /// El CAS sí corrió antes de morir. El commit está en la rama.
  promoverACommitted,

  /// La rama avanzó a otra cosa. El candidato hay que reconstruirlo.
  alguienMasAvanzo,
}

/// La comparación de §9. **Es una función de tres casos, no una búsqueda.**
///
/// Con [documento] llevando ya la revisión, los tres datos que hacen falta
/// —la base, la revisión candidata y el `HEAD` observado— están todos sobre la
/// mesa. Antes, sin la revisión persistida, esto tenía que salir a buscar qué
/// commit podía ser el candidato.
///
/// **No lee el repositorio**: quien la llama ya leyó el `HEAD`. Así se puede
/// probar los tres casos sin montar un repositorio por cada uno.
///
/// **Tampoco lee `documento.estado`, y eso es una PRECONDICIÓN, no una
/// omisión benigna.** Supone un documento en `prepared`, que es el único
/// estado donde las tres respuestas significan algo: son «el CAS no llegó a
/// correr», «el CAS corrió antes de morir» y «otra cosa avanzó la rama». Sobre
/// un documento en otro estado devuelve igual una de las tres, y puede ser
/// falsa: [leer] reconstruye cualquier estado —correctamente, porque un
/// documento persistido se relee entero—, así que una corrida que murió en
/// `publicationComplete` con `headActual == documento.revision` sale de acá
/// como [QueHacerAlRecuperar.promoverACommitted], que es una arista que el
/// grafo del documento no tiene.
///
/// **Asegurar la precondición es del llamador**, y ese llamador es
/// `--retry-publication`, que todavía no existe: filtrar por estado es una
/// decisión de esa rebanada, no de esta. Lo que corresponde acá es declarar la
/// ausencia en vez de dejarla implícita.
///
/// Si `base` y `revision` fueran iguales, el primer caso ganaría y se
/// reintentaría un CAS que ya corrió. No puede pasar: una revisión es hija de
/// su base, así que sus OIDs difieren siempre.
QueHacerAlRecuperar decidirRecuperacion({
  required DocumentoDeCorrida documento,
  required String headActual,
}) {
  final base = documento.draft.artefacto.candidato.baseRevision;
  if (headActual == base) return QueHacerAlRecuperar.reintentarElCas;
  if (headActual == documento.revision) {
    return QueHacerAlRecuperar.promoverACommitted;
  }
  return QueHacerAlRecuperar.alguienMasAvanzo;
}
