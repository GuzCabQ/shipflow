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

  /// Dónde va el documento autoritativo de [runId].
  String documentoDe(String runId) =>
      rutas.join(_directorio.path, '$runId.json');

  /// Dónde va la proyección local de la revisión de [runId].
  String proyeccionDe(String runId) =>
      rutas.join(_directorio.path, '$runId.revision.json');

  /// **Cada archivo que una corrida deja en el disco.** Es lo que mira el
  /// control del paso 9, y por eso la lista vive acá y no en quien lo corre.
  ///
  /// El criterio de ese control es «ningún archivo de la corrida termina
  /// commiteado», y miraba una sola ruta mientras el paso 14 escribe dos: un
  /// control que decide sobre una representación más pobre que su criterio.
  /// Hoy no divergen porque el contenido del `.gitignore` ignora todo, pero
  /// eso es una coincidencia del contenido, no del mecanismo — y la próxima
  /// proyección que alguien agregue entra por acá o no la mira nadie.
  List<String> rutasDe(String runId) => [
    documentoDe(runId),
    proyeccionDe(runId),
  ];

  File _archivo(String runId) => File(documentoDe(runId));

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
/// **Asegurar la precondición es del llamador**, y ese llamador ya existe:
/// es [puertaDelReintento]. Filtra por rama y por estado ANTES de invocar
/// esta función, así que quien llega hasta acá ya la tiene asegurada. Lo que
/// corresponde acá sigue siendo declarar la precondición en vez de dejarla
/// implícita —no repetir adentro el filtro que [puertaDelReintento] ya hizo
/// una vez, sobre el mismo dato, con la misma respuesta.
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

/// Por qué el reintento **no** actúa. Cada valor nace con un `detalle` en el
/// sitio donde se construye [NoSeReintenta] —ver ahí— porque la regla de este
/// proyecto es que ninguna prohibición se instala sin decir qué hacer en
/// cambio, y acá hay tres prohibiciones distintas, cada una con su propia
/// alternativa.
enum CausaDeNoReintento {
  /// Quien corre no está parado en la rama de esta corrida. Reintentar
  /// movería la rama en la que está parado, no la de la corrida: no son la
  /// misma referencia solo porque hoy apunten al mismo commit.
  ramaDistinta,

  /// Ya hay un pull request utilizable: no queda nada que publicar de nuevo.
  yaPublicado,

  /// El compare-and-swap fue rechazado. Nunca hubo un commit propio en la
  /// rama, así que no hay ninguna entrega que recuperar.
  nadaQueEntregar,
}

/// Qué hace `--retry-publication` con una corrida interrumpida, **con la
/// rama y el estado del documento ya filtrados**.
///
/// Es la precondición que [decidirRecuperacion] declara como propia y no
/// asegura —ver su doc—: esta puerta es lo único que se interpone entre esa
/// función de tres casos y un documento en un estado para el que sus tres
/// respuestas no significan nada, o significan algo falso.
sealed class PuertaDelReintento {
  const PuertaDelReintento();
}

/// Hay que reconstruir la confianza en el candidato antes de publicar.
///
/// **Cuál de los dos caminos de reconciliación de §9** —los cinco pasos
/// desde `prepared`, o la comprobación del índice desde
/// `localInconsistent`— no viaja acá adentro: lo decide quien reciba esta
/// variante, volviendo a mirar [DocumentoDeCorrida.estado]. Cargar esa
/// elección como un campo de esta clase pondría el mismo hecho —qué estado
/// tiene el documento— en dos lugares que podrían llegar a discrepar entre
/// sí; esta puerta ya lo consultó una vez para decidir que tocaba
/// reconciliar, y con eso alcanza.
final class Reconciliar extends PuertaDelReintento {
  const Reconciliar();
}

/// El commit ya existe en la rama, verificado o no reconciliable de otra
/// forma: publicar directo, sin reconstruir nada.
final class PublicarDirecto extends PuertaDelReintento {
  const PublicarDirecto();
}

/// El reintento no actúa. [detalle] siempre nombra la alternativa: qué hacer
/// en cambio de reintentar, nunca solo que no se puede.
final class NoSeReintenta extends PuertaDelReintento {
  final CausaDeNoReintento causa;
  final String detalle;

  const NoSeReintenta({required this.causa, required this.detalle});
}

/// La URL del pull request que ya dejó esta corrida, o nula si este
/// documento no la tiene.
///
/// **Nula es un caso real, no un error de esta función.** El propio doc de
/// [DocumentoDeCorrida.estado] declara como residuo que un estado terminal
/// puede cargar un desenlace nulo cuando quien avanza no vuelve a pasarlo.
/// Ningún camino de producción de hoy deja `publicationComplete` así —el
/// sellado siempre pasa el desenlace que afirma ese estado—, pero esta
/// función no puede asumirlo por quien la llama mañana: lee lo que hay y
/// devuelve nulo en vez de forzar un cast que reventaría por la red de
/// último recurso, sobre una corrida donde no se rompió nada.
String? _urlYaPublicada(DocumentoDeCorrida documento) {
  final desenlace = documento.desenlace;
  return desenlace is Publicado ? desenlace.pr.url : null;
}

NoSeReintenta _yaPublicado(DocumentoDeCorrida documento) {
  final url = _urlYaPublicada(documento);
  return NoSeReintenta(
    causa: CausaDeNoReintento.yaPublicado,
    detalle: url == null
        ? 'Esta corrida ya publicó, y el documento no registra dónde. No '
              'hace falta reintentar nada: ya está hecho.'
        : 'Esta corrida ya publicó: $url. No hace falta reintentar nada: ya '
              'está hecho.',
  );
}

const _nadaQueEntregar = NoSeReintenta(
  causa: CausaDeNoReintento.nadaQueEntregar,
  detalle:
      'El compare-and-swap fue rechazado y nunca hubo un commit propio en '
      'la rama: no hay ninguna entrega que recuperar. La forma de seguir es '
      'volver a correr `ship` desde el principio.',
);

/// La puerta de `--retry-publication`: filtra por rama y por estado antes de
/// dejar pasar a [decidirRecuperacion] o a los caminos de reconciliación que
/// arrancan desde ella.
///
/// **Por qué llega temprano, medido.** En cinco de los seis estados de
/// [DocumentoDeCorrida], la respuesta de la comparación de tres casos es
/// inútil o falsa, y en cuatro de esos cinco obedecerla termina en una
/// transición que [DocumentoDeCorrida.avanzarA] rechaza —un `StateError` que
/// sale por la red de último recurso del CLI diciendo que se rompió el
/// arnés, sobre una corrida donde no se rompió nada—.
///
/// **Por qué la rama se comprueba ANTES que el estado.** No es solo que
/// reintentar mueva la rama equivocada —esa lectura alcanza para `prepared`
/// y `committed`, pero no dice nada de los tres estados terminales, que ya
/// no tocan ninguna rama—. El motivo que vale para los SEIS es más simple:
/// si quien corre está parado en otra rama, lo que [documento] afirma **no
/// es sobre el repositorio que se está mirando**. `documento.estado` describe
/// una corrida hecha sobre la rama del propio documento, no sobre
/// [ramaActual]; leer ese estado con la rama puesta equivocada es leer una
/// respuesta cierta, pero sobre otra pregunta —así que cualquier cosa que
/// diga es irrelevante, sea cual sea el estado—. Los casos concretos son
/// consecuencia de esto y no el motivo en sí: alguien parado en OTRA rama
/// cuyo `HEAD` casualmente coincida con la base de esta corrida recibiría
/// «reintentá el compare-and-swap» si el estado fuera `prepared` —y
/// reintentarlo movería la rama en la que está parado, no la de la
/// corrida; es la misma precedencia que respeta la operación que aplica la
/// revisión candidata—, y esa misma persona frente a un documento
/// `publicationComplete` recibiría «ya está publicado, no hay nada que
/// hacer» sobre una corrida que no tiene nada que ver con la rama en la que
/// está parada.
///
/// **El `switch` sobre [EstadoDelDocumento] es exhaustivo y sin `default`.**
/// Es el mismo criterio que ya instaló la compuerta por estado de la
/// cascada, después de que una comparación con `!=` dejara compilar un
/// estado nuevo entero y reventara recién después de commitear y abrir el
/// pull request: acá, un estado nuevo no compila hasta que alguien decida
/// qué hace el reintento con él. Agregarle una rama `default` volvería a
/// abrir exactamente ese agujero, y no lo delataría ninguna prueba de esta
/// suite —los seis valores de hoy siguen cayendo en su propio `case`, y el
/// `default` queda muerto sin que nada lo ejercite—: lo único que fuerza la
/// decisión es el compilador, no el arnés de pruebas.
PuertaDelReintento puertaDelReintento({
  required DocumentoDeCorrida documento,
  required String ramaActual,
}) {
  final ramaDeLaCorrida = documento.draft.branch;
  if (ramaActual != ramaDeLaCorrida) {
    return NoSeReintenta(
      causa: CausaDeNoReintento.ramaDistinta,
      detalle:
          'Estás parado en «$ramaActual», pero esta corrida se preparó y '
          'commiteó en «$ramaDeLaCorrida». Reintentar acá movería la rama '
          'equivocada: cambiá a «$ramaDeLaCorrida» antes de reintentar.',
    );
  }
  return switch (documento.estado) {
    EstadoDelDocumento.prepared => const Reconciliar(),
    EstadoDelDocumento.committed => const PublicarDirecto(),
    EstadoDelDocumento.publicationIncomplete => const PublicarDirecto(),
    EstadoDelDocumento.publicationComplete => _yaPublicado(documento),
    EstadoDelDocumento.notApplied => _nadaQueEntregar,
    EstadoDelDocumento.localInconsistent => const Reconciliar(),
  };
}
