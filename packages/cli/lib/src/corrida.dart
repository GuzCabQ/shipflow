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

  /// La ruta de un archivo de [runId] con [sufijo], **comprobando que caiga
  /// adentro del directorio de corridas**.
  ///
  /// **Se comprueba sobre la ruta NORMALIZADA y no sobre el identificador.**
  /// Mirar el identificador sería decidir sobre una representación más pobre
  /// que el criterio: lo que importa no es qué letras tiene, sino dónde
  /// termina el archivo. Con «../../fuera» concatenado tal cual, la ruta era
  /// `.shipflow/runs/../../fuera.json` — que el sistema de archivos resuelve
  /// a un archivo de otro lado, del que el reintento LEÍA y, si encontraba un
  /// documento válido, al que terminaba ESCRIBIENDO.
  ///
  /// **Hija DIRECTA, no descendiente.** Un identificador con una barra
  /// adentro no sale del directorio y, sin embargo, escribe en un
  /// subdirectorio que nadie declaró: el control que comprueba que los
  /// archivos de una corrida estén ignorados mira las rutas que esta clase
  /// nombra, y nada garantiza que una regla de exclusión escrita para el
  /// directorio cubra un nivel más abajo.
  ///
  /// **Lanza [ArgumentError] y no devuelve nulo** porque no es un hecho del
  /// dominio sobre el que quien llama tenga que poder ramificar: la frontera
  /// que interpreta la bandera ya rechaza todo lo que no tiene la forma de un
  /// identificador de corrida —ver `esRunIdDeCorrida`—, así que llegar acá
  /// con uno que se sale del directorio es un defecto de quien compone.
  String _archivoDe(String runId, String sufijo) {
    final directorio = rutas.normalize(_directorio.path);
    final propuesta = rutas.normalize(rutas.join(directorio, '$runId$sufijo'));
    if (rutas.dirname(propuesta) != directorio) {
      throw ArgumentError.value(
        runId,
        'runId',
        'El identificador de una corrida nombra un archivo HIJO DIRECTO del '
            'directorio de corridas. Con éste la ruta queda en «$propuesta», '
            'que está fuera de «$directorio»: leer ahí sería leer un archivo '
            'que ninguna corrida escribió, y sellar la corrida terminaría '
            'escribiéndolo.',
      );
    }
    return propuesta;
  }

  /// Dónde va el documento autoritativo de [runId].
  String documentoDe(String runId) => _archivoDe(runId, '.json');

  /// Dónde va la proyección local de la revisión de [runId].
  String proyeccionDe(String runId) => _archivoDe(runId, '.revision.json');

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
/// es [puertaDelReintento]. Filtra por rama, por destino y por estado ANTES de invocar
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

/// Los cuatro hechos de la revisión candidata que la reconciliación de los
/// cinco pasos necesita, **ya leídos**.
///
/// Nace vacía de lecturas a propósito: quien la construye leyó el repositorio
/// —el padre, el árbol y el mensaje de la revisión, más la comparación del
/// índice acotada a las rutas de la rebanada—, y [reconciliar] solo compara
/// estos cuatro valores contra lo que [DocumentoDeCorrida] ya afirmaba. Es la
/// misma partición que ya separa a [decidirRecuperacion] de quien le
/// consigue el `HEAD`: la lectura y la decisión no viven en el mismo lugar
/// porque la decisión es la que hay que poder probar sin montar un
/// repositorio, y son cinco pasos con más combinaciones que los tres casos de
/// esa comparación.
class HechosDeLaRevision {
  /// El padre de la revisión candidata, o nulo si no tiene ninguno. Nulo es
  /// un hecho —la primera revisión de un repositorio no tiene padre—, y por
  /// eso no se compara con una cadena vacía: una base real nunca es nula, así
  /// que un padre nulo ya es, por sí solo, un padre distinto.
  final String? padre;

  /// El identificador del árbol de la revisión candidata. Se compara contra
  /// [CandidateIdentity.contentRevision] por igualdad de identificador, nunca
  /// por diferencias: un control que mirara si los dos árboles «se parecen»
  /// estaría decidiendo sobre una representación más pobre que su propio
  /// criterio, que es «es el mismo contenido», no «es un contenido parecido».
  final String arbol;

  /// El mensaje entero de la revisión candidata.
  final String mensaje;

  /// Las rutas, de entre las que la rebanada declaró, donde el índice de
  /// quien corre no coincide con el árbol de la revisión candidata. Vacía
  /// significa que coincide en todas.
  final List<String> rutasQueDifieren;

  const HechosDeLaRevision({
    required this.padre,
    required this.arbol,
    required this.mensaje,
    required this.rutasQueDifieren,
  });
}

/// Por qué los cinco pasos **no** alcanzan para confirmar que la revisión de
/// la rama es la del candidato. Cada valor nace con un `detalle` en el sitio
/// donde se construye [Ambigua] —ver ahí—, por la misma regla que ya sigue
/// [CausaDeNoReintento]: ninguna prohibición se instala sin decir qué hacer
/// en cambio.
enum CausaDeAmbiguedad {
  /// El padre de la revisión en la rama no es la base que este candidato
  /// declaró: la revisión no desciende de donde el candidato decía descender,
  /// y no hay ascendencia que reconstruir desde acá.
  padreDistinto,

  /// El árbol de la revisión en la rama no es, identificador contra
  /// identificador, el que este candidato produjo: el contenido no es el
  /// mismo, aunque el mensaje o el padre coincidan.
  contenidoDistinto,

  /// El mensaje de la revisión en la rama no es el que este candidato iba a
  /// commitear.
  mensajeDistinto,

  /// El índice de quien corre no coincide con el árbol de la revisión, en
  /// alguna de las rutas que esta rebanada declaró.
  indiceDistinto,
}

/// El resultado de la reconciliación de los cinco pasos: o bien no queda
/// ninguna duda sobre qué hacer, o bien queda alguna y hay que fallar cerrado.
///
/// **Sellada y con dos variantes, no un booleano con un mensaje al costado.**
/// Un booleano «¿es la misma revisión?» más un `String?` de motivo deja
/// construible el par imposible «no lo es, y no hay motivo»: acá, [Ambigua]
/// exige su [CausaDeAmbiguedad] y su `detalle` en el propio constructor, y
/// [Inequivoca] no puede llevar ninguno de los dos.
sealed class Reconciliacion {
  const Reconciliacion();
}

/// No queda ninguna ambigüedad: [queHacer] es la acción, tal cual la habría
/// dado la comparación de tres casos si nadie hubiera tenido que reconstruir
/// confianza en el candidato.
final class Inequivoca extends Reconciliacion {
  final QueHacerAlRecuperar queHacer;
  const Inequivoca(this.queHacer);
}

/// Fallar cerrado: no promover, no publicar. [causa] dice cuál de los cinco
/// pasos no cerró, y [detalle] nombra la acción precisa —nunca solo que no se
/// puede—, porque un reintento que adivina publica sobre un commit que nadie
/// verificó que sea el suyo.
final class Ambigua extends Reconciliacion {
  final CausaDeAmbiguedad causa;
  final String detalle;
  const Ambigua(this.causa, this.detalle);
}

/// [argumento], citado para que un shell POSIX lo parsee como **un solo
/// argumento igual a esta misma cadena**, sea cual sea lo que lleve adentro.
///
/// **Existe porque envolver entre apóstrofos NO alcanza, y el agujero estaba
/// abierto.** Adentro de un par de apóstrofos el shell no interpreta nada
/// —ni el espacio, ni el salto de línea, ni el dólar, ni la comilla doble, ni
/// la barra invertida— salvo el apóstrofo mismo, que CIERRA la cita. Una ruta
/// como `it` seguida de apóstrofo y de `s` es un nombre de archivo
/// perfectamente válido, y envuelta a mano produce un comando con una cita
/// sin cerrar: quien lo pega en su terminal no repara nada y encima se queda
/// con el intérprete esperando el resto de la línea. Peor: una ruta armada a
/// propósito puede cerrar la cita, meter otro comando y volver a abrirla, y
/// ese comando lo va a pegar una persona porque se lo recomendamos nosotros.
///
/// **El escape es el de POSIX y no tiene variantes**: se cierra la cita, se
/// escapa el apóstrofo con una barra invertida —afuera de toda cita, que es
/// el único lugar donde esa barra lo escapa— y se reabre la cita. Todo lo
/// demás viaja literal.
///
/// **Una cadena vacía también se cita**, y por eso no hay caso especial: un
/// par de apóstrofos vacío es un argumento vacío, que es exactamente lo que
/// hay que producir; dejarla sin citar la haría desaparecer del comando.
///
/// **Función propia y probada, nunca una interpolación en el sitio de uso.**
/// Escrita inline, cada sitio que arma un comando repite la regla y la
/// primera copia que se olvide del apóstrofo no la delata nadie: acá hay una
/// sola definición, y su suite la mide contra el parser del shell de verdad.
String citarParaShell(String argumento) =>
    "'${argumento.replaceAll("'", r"'\''")}'";

/// La reparación concreta para un índice que no coincide con [revision] en
/// [rutas], como una frase que se puede pegar entera adentro de un mensaje.
///
/// **Un solo lugar para las dos reconciliaciones de §9 que se topan con esto**
/// —la de los cinco pasos, más abajo, y la de [comprobarIndice] desde
/// `localInconsistent`—: las dos reparan exactamente lo mismo, con el mismo
/// comando, y escribir el texto dos veces las deja libres para divergir la
/// primera vez que alguien corrija una sin acordarse de la otra.
///
/// **Cada ruta va citada, y no es un detalle de estilo.** Medido: sin
/// comillas, una ruta con un espacio se parte en dos argumentos apenas
/// alguien pega el comando en una terminal —«ruta con espacio.txt» se
/// convierte en tres pathspecs, dos de los cuales no existen—, `git` sale
/// con código cero de todos modos, y el índice queda exactamente tan
/// desincronizado como antes de correrlo: un consejo que no repara es peor
/// que no darlo.
///
/// **Y citar es [citarParaShell], nunca envolver entre apóstrofos acá.** Ver
/// el doc de esa función: envolver a mano rompe el comando ante una ruta que
/// lleve un apóstrofo, que es un carácter perfectamente válido en un nombre
/// de archivo.
///
/// **Se cita CADA argumento, incluida [revision], y eso es una regla y no una
/// evaluación caso por caso.** Lo que impide que una revisión imposible
/// llegue hasta acá es que se la rechaza al leer el documento —ver
/// `DocumentoDeCorrida.fromJson`—, y ésa es la protección de verdad. Citarla
/// igual es lo que hace TOTAL la regla de armar un comando recomendado:
/// «éste no hace falta porque lo valida otro» es un acoplamiento que se rompe
/// el día que el otro cambia, y acá el precio de romperse es un comando que
/// una persona pega en su terminal porque se lo recomendamos nosotros. Cuesta
/// una llamada y sobre un OID válido no cambia nada de lo que el comando
/// hace.
String _reparacionDelIndice({
  required String revision,
  required List<String> rutas,
}) {
  final citadas = rutas.map(citarParaShell).join(' ');
  return 'corré `git reset ${citarParaShell(revision)} -- $citadas`, que '
      'reescribe el índice en esas rutas sin tocar el árbol de trabajo, y '
      'reintentá';
}

/// La reconciliación de los cinco pasos de §9, desde un documento en
/// `prepared`.
///
/// **Los cinco pasos solo se evalúan cuando la comparación de tres casos dice
/// que hay una revisión propia que promover.** Si [headActual] está en la
/// base o en otra cosa, no hay ninguna revisión nuestra en la rama sobre la
/// que reconstruir confianza: por eso esta función empieza delegando en
/// [decidirRecuperacion], y solo sigue de largo cuando esa respuesta es
/// [QueHacerAlRecuperar.promoverACommitted]. Evaluarlos antes —o sin mirar esa
/// respuesta— confundiría «el CAS nunca corrió» con «corrió y hay que
/// dudar de lo que dejó», que son hechos distintos con acciones distintas.
///
/// **Y cuando esa comparación dice promover, la ambigüedad gana.** Los tres
/// casos no vieron el contenido de la revisión: solo compararon
/// identificadores contra el documento. Los cinco pasos sí miran ese
/// contenido, y si encuentran algo que no cierra, esa duda pesa más que el
/// «promoverACommitted» que los tres casos ya habían adelantado —promoverlo
/// igual publicaría sobre un commit que nadie verificó que sea el nuestro.
///
/// **Pura, sin excepción: no lee el repositorio.** Los cuatro hechos de
/// [hechos] ya vienen leídos —ver su doc—, y esta función solo los compara
/// contra lo que [documento] afirma. Es la misma propiedad que ya declara
/// [decidirRecuperacion], sostenida acá con más motivo: son cinco pasos con
/// más combinaciones que esos tres casos, así que probarlos sin montar un
/// repositorio por cada uno vale más, no menos.
///
/// **El orden de los cuatro chequeos no es intercambiable, y acá está el
/// motivo.** Cuando UN SOLO hecho falla, el orden no se nota: cualquiera de
/// los cuatro que se evaluara primero iba a fallar cerrado igual. Pero
/// cuando fallan DOS a la vez —un padre ajeno sobre un árbol que además es
/// otro, digamos— el orden deja de ser cosmético: decide cuál
/// [CausaDeAmbiguedad] se reporta.
///
/// **Entre padre, árbol y mensaje, lo que el orden cambia es cuál hecho se
/// NOMBRA, no la acción.** Medido: los tres `detalle` de esas causas
/// terminan en la misma recomendación —volver a correr `ship` desde el
/// principio—, y nada fuera de esta función distingue una de otra para
/// actuar distinto. Lo que el orden compra ahí es precisión diagnóstica:
/// nombrar primero el hecho más estructural evita mandar a investigar un
/// síntoma —el mensaje— cuando hay una causa más profunda —la ascendencia—
/// y las dos fallan a la vez. Alcanza con eso para justificar el orden
/// entre estas tres; no hace falta inventarle una diferencia de acción que
/// hoy no tiene. Y si algún día esas tres causas ganan acciones distintas
/// entre sí, esta premisa se vuelve MÁS fuerte, no más débil.
///
/// **Con el índice, la acción SÍ cambia, y ahí el argumento es más fuerte
/// todavía.** Si el índice se comprobara antes que los tres estructurales y
/// los dos fallaran a la vez, la acción que saldría sería «sincronizá el
/// índice» sobre un commit que, por el padre, el árbol o el mensaje
/// distintos, hay que reconstruir desde cero de todos modos: un consejo que
/// no sirve para la conclusión real. Comprobarlo último es lo que evita dar
/// ese consejo.
///
/// El orden de abajo va de lo más estructural a lo más circunstancial:
///
/// 1. **El padre primero.** Habla del lugar del objeto en el grafo de
///    commits, no de lo que contiene. Si la revisión no desciende de la
///    base que este candidato declaró, ningún otro hecho —el contenido, el
///    mensaje, el índice— puede rescatar esa conclusión: no es nuestra
///    ascendencia, y ninguna coincidencia más abajo cambia eso.
/// 2. **El árbol segundo.** Sigue siendo estructural —identidad de objeto,
///    no ascendencia—, pero un padre correcto con un árbol distinto ya no
///    es nuestro contenido, sin importar qué diga el mensaje: cualquier
///    padre puede parir cualquier árbol.
/// 3. **El mensaje tercero, y es el más débil de los tres hechos DE LA
///    REVISIÓN.** Es el único que se puede reescribir —un nuevo commit con
///    el mismo árbol y el mismo padre, pero otro texto— sin que ningún
///    objeto de contenido cambie: que coincida no prueba nada que el árbol
///    y el padre no prueben ya con más fuerza, y por eso solo importa
///    cuando los dos anteriores ya cerraron.
/// 4. **El índice último, y no porque sea el hecho más débil de los
///    cuatro: porque es el único que no describe la revisión.** Los tres
///    anteriores hablan del commit que ya quedó en la rama; este habla del
///    estado LOCAL de quien corre el reintento, y puede fallar aunque el
///    commit sea, byte a byte, el nuestro. Reportarlo antes que los tres
///    estructurales confundiría «esto no es nuestro commit» —que exige
///    reconstruir desde cero— con «esto sí es nuestro commit, pero tu
///    copia de trabajo no coincide» —que exige sincronizar el índice—, y
///    son remedios distintos para hechos de naturaleza distinta.
Reconciliacion reconciliar({
  required DocumentoDeCorrida documento,
  required String headActual,
  required HechosDeLaRevision hechos,
}) {
  final tresCasos = decidirRecuperacion(
    documento: documento,
    headActual: headActual,
  );
  if (tresCasos != QueHacerAlRecuperar.promoverACommitted) {
    return Inequivoca(tresCasos);
  }

  final candidato = documento.draft.artefacto.candidato;

  // Paso 1: el padre de la revisión candidata es la base. Primero por ser
  // el hecho más estructural — ver el orden argumentado en el doc de esta
  // función.
  if (hechos.padre != candidato.baseRevision) {
    return Ambigua(
      CausaDeAmbiguedad.padreDistinto,
      'El padre de la revisión en la rama es «${hechos.padre}», y este '
      'candidato se preparó sobre la base «${candidato.baseRevision}»: no '
      'desciende de donde decía descender. No se puede confirmar que sea '
      'nuestra: la acción es volver a correr `ship` desde el principio.',
    );
  }

  // Paso 2: el árbol de la revisión es EXACTAMENTE el del candidato —
  // igualdad de identificador, nunca una comparación de diferencias. Segundo
  // porque, con el padre ya asegurado, sigue siendo un hecho de identidad de
  // objeto, no de descripción.
  if (hechos.arbol != candidato.contentRevision) {
    return Ambigua(
      CausaDeAmbiguedad.contenidoDistinto,
      'El árbol de la revisión en la rama es «${hechos.arbol}», y este '
      'candidato produjo «${candidato.contentRevision}»: el contenido no es '
      'el mismo. No se puede confirmar que sea nuestra: la acción es volver '
      'a correr `ship` desde el principio.',
    );
  }

  // Paso 3: el mensaje coincide con el esperado. Tercero: es el hecho más
  // débil de los tres que hablan de la revisión, porque es el único que se
  // reescribe sin tocar ningún objeto de contenido.
  final intentEsperado = documento.draft.artefacto.intent;
  if (hechos.mensaje != intentEsperado) {
    return const Ambigua(
      CausaDeAmbiguedad.mensajeDistinto,
      'El mensaje de la revisión en la rama no es el que este candidato iba '
      'a commitear. No se puede confirmar que sea nuestra: la acción es '
      'volver a correr `ship` desde el principio.',
    );
  }

  // Paso 4: el índice coincide, solo en las rutas de la rebanada. Último
  // porque no es un hecho MÁS DÉBIL de la revisión: es el único que no habla
  // de la revisión, sino del estado local de quien corre.
  if (hechos.rutasQueDifieren.isNotEmpty) {
    return Ambigua(
      CausaDeAmbiguedad.indiceDistinto,
      'El índice de quien corre no coincide con esta revisión en: '
      '${hechos.rutasQueDifieren.join(", ")}. No se puede promover con el '
      'índice desincronizado: '
      '${_reparacionDelIndice(revision: documento.revision, rutas: hechos.rutasQueDifieren)}.',
    );
  }

  // Paso 5: inequívoco en los cinco pasos → promover. Cualquier otra
  // combinación ya salió antes por alguna de las cuatro ambigüedades.
  return const Inequivoca(QueHacerAlRecuperar.promoverACommitted);
}

/// El resultado de comprobar el índice desde el estado inconsistente: o
/// coincide con la revisión y se puede promover, o no coincide y hay que
/// decir con qué comando repararlo.
///
/// **Sellada y con dos variantes, no un booleano.** Un booleano «¿coincide?»
/// más una lista de rutas al costado deja construible el par imposible «no
/// coincide, y no hay ninguna ruta que nombrar»: acá, [IndiceNoCoincide]
/// exige sus rutas en el propio constructor, y [IndiceCoincide] no lleva
/// ninguna.
sealed class IndiceDelReintento {
  const IndiceDelReintento();
}

/// El índice de quien corre ya coincide con la revisión, en todas las rutas
/// que esta rebanada declaró: se puede promover a `committed` y publicar.
final class IndiceCoincide extends IndiceDelReintento {
  const IndiceCoincide();
}

/// El índice no coincide, y [detalle] nombra la reparación concreta —nunca
/// solo que hace falta una—, porque promover sobre un índice desincronizado
/// dejaría `git status` mintiendo sobre lo que se acaba de commitear.
final class IndiceNoCoincide extends IndiceDelReintento {
  /// Las rutas donde el índice no coincide con el árbol de la revisión.
  final List<String> rutas;

  /// El texto que se le muestra a quien reintenta: nombra [rutas] y el
  /// comando que las sincroniza.
  final String detalle;

  const IndiceNoCoincide({required this.rutas, required this.detalle});
}

/// La comprobación de §9 desde `localInconsistent`: el reintento **no vuelve
/// a aplicar la revisión** —esa operación ya corrió, y volver a correrla
/// obligaría a distinguir «ya aplicada» de «el plan estaba mal declarado»,
/// una distinción que esa operación no puede hacer sin marcar el commit—.
/// Lo que sí puede hacer es comprobar si el problema que dejó la corrida
/// original ya no existe: si el índice de quien corre coincide con la
/// revisión que el commit ya tiene, no queda nada que reparar.
///
/// **Recibe [rutasQueDifieren] ya calculadas, y no lee ningún repositorio.**
/// Es la misma partición que ya separa la comparación de los tres casos, y
/// la de los cinco pasos, de quien les consigue los hechos: la decisión se
/// prueba sin montar un repositorio por cada caso, y quien sí lo lee es la
/// composición que llama a esta función.
///
/// **Precondición: [documento] tiene que estar en `localInconsistent`.**
/// Fuera de ese estado, las dos respuestas de esta función no significan
/// nada —o significan algo falso—: es la puerta de UN solo estado, la misma
/// idea que ya declara [decidirRecuperacion] al dejar la comprobación de
/// estado y de rama en manos de quien la llama.
///
/// **Y acá SÍ se comprueba adentro, aunque el llamador ya la asegure.** La
/// razón escrita era que no había ningún llamador que la asegurara todavía, y
/// eso venció: la composición del reintento entra acá solo desde la rama que
/// ya comparó el estado con `localInconsistent`. La guarda se queda igual, y
/// el motivo que la sostiene es otro: es defensa en profundidad sobre la
/// única precondición cuyo incumplimiento no se nota mirando la salida
/// —promovería por una arista que ese estado no tiene, y lo haría en
/// silencio—. Lanza en vez de devolver un caso porque no es un hecho del
/// dominio sobre el que quien llama tenga que poder ramificar: es un defecto
/// de quien la invocó.
IndiceDelReintento comprobarIndice({
  required DocumentoDeCorrida documento,
  required List<String> rutasQueDifieren,
}) {
  if (documento.estado != EstadoDelDocumento.localInconsistent) {
    throw StateError(
      'comprobarIndice es la puerta de un solo estado: '
      '«${EstadoDelDocumento.localInconsistent.name}». Este documento está '
      'en «${documento.estado.name}»: usarla acá promovería por una arista '
      'que ese estado no tiene.',
    );
  }
  if (rutasQueDifieren.isEmpty) return const IndiceCoincide();
  return IndiceNoCoincide(
    rutas: rutasQueDifieren,
    detalle:
        'El índice de quien corre no coincide con la revisión '
        '«${documento.revision}» en: ${rutasQueDifieren.join(", ")}. No se '
        'puede promover con el índice desincronizado: '
        '${_reparacionDelIndice(revision: documento.revision, rutas: rutasQueDifieren)}.',
  );
}

/// Por qué el reintento **no** actúa. Cada valor nace con un `detalle` en el
/// sitio donde se construye [NoSeReintenta] —ver ahí— porque la regla de este
/// proyecto es que ninguna prohibición se instala sin decir qué hacer en
/// cambio, y acá hay CUATRO prohibiciones distintas —contadas sobre los
/// valores de abajo, uno por uno—, cada una con su propia alternativa.
enum CausaDeNoReintento {
  /// Quien corre no está parado en la rama de esta corrida. Reintentar
  /// movería la rama en la que está parado, no la de la corrida: no son la
  /// misma referencia solo porque hoy apunten al mismo commit.
  ramaDistinta,

  /// El remoto de este repositorio ya no nombra el destino donde esta corrida
  /// iba a publicar. Publicar acá abriría un pull request en otro
  /// repositorio, y la búsqueda que impide abrir un SEGUNDO correría contra
  /// un destino donde el primero no está.
  ///
  /// **Solo sale por los caminos que PUBLICAN.** Una corrida que ya publicó,
  /// o cuyo compare-and-swap fue rechazado, contesta lo suyo con el remoto
  /// movido o sin él: ahí no hay ninguna publicación que esta causa pueda
  /// guardar, y taparlas con ella cambiaría un hecho cierto por un fallo.
  destinoDistinto,

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

/// **El aviso que acompaña a la URL cuando el remoto ya no es el de aquella
/// corrida**, o vacío cuando sí lo es.
///
/// **Existe para no tener que elegir entre mentir y callar.** El riesgo real
/// de dar la URL con el remoto movido es que quien la lea la tome por un pull
/// request del destino de AHORA; la respuesta a eso es decir de dónde es, no
/// convertir en fallo una información verdadera. Quien movió el remoto por un
/// motivo ajeno a esta corrida sigue necesitando saber dónde quedó, y sin la
/// URL pierde la única forma de preguntarlo.
String _avisoDeDestinoMovido(
  DocumentoDeCorrida documento,
  String? destinoActual,
) {
  if (destinoActual == documento.destino) return '';
  return ' Ojo: esa publicación es en «${documento.destino}», y el remoto de '
      'este repositorio apunta ahora a '
      '${destinoActual == null ? "ningún destino que se pueda nombrar" : "«$destinoActual»"}: '
      'la URL de arriba NO es del destino que tenés configurado.';
}

NoSeReintenta _yaPublicado(
  DocumentoDeCorrida documento, {
  required String? destinoActual,
}) {
  final url = _urlYaPublicada(documento);
  final aviso = _avisoDeDestinoMovido(documento, destinoActual);
  return NoSeReintenta(
    causa: CausaDeNoReintento.yaPublicado,
    detalle: url == null
        ? 'Esta corrida ya publicó, y el documento no registra dónde. No '
              'hace falta reintentar nada: ya está hecho.$aviso'
        : 'Esta corrida ya publicó: $url. No hace falta reintentar nada: ya '
              'está hecho.$aviso',
  );
}

const _nadaQueEntregar = NoSeReintenta(
  causa: CausaDeNoReintento.nadaQueEntregar,
  detalle:
      'El compare-and-swap fue rechazado y nunca hubo un commit propio en '
      'la rama: no hay ninguna entrega que recuperar. La forma de seguir es '
      'volver a correr `ship` desde el principio.',
);

/// La puerta de `--retry-publication`: filtra por rama, por destino y por
/// estado antes de dejar pasar a [decidirRecuperacion] o a los caminos de
/// reconciliación que arrancan desde ella.
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
/// **Por qué el DESTINO gana sobre el estado, pero SOLO en los caminos que
/// publican.** Lo que esta comparación guarda es una publicación: la búsqueda
/// idempotente que impide abrir un SEGUNDO pull request es una búsqueda EN EL
/// DESTINO, así que contra un destino nuevo no encuentra nada —correctamente:
/// ahí no hay nada— y se publica otra vez, en un repositorio que nadie
/// eligió. Por eso, cuando el estado despacha a [Reconciliar] o a
/// [PublicarDirecto], el destino manda: esas dos respuestas describen una
/// corrida hecha contra OTRO destino y obedecerlas publicaría acá.
///
/// **Y por eso NO gana sobre las respuestas que ya son [NoSeReintenta].**
/// Ahí no hay ninguna publicación que guardar —ni se lee el repositorio, ni se
/// le pide nada a la forja—, así que comparar destinos solo puede cambiar una
/// respuesta verdadera por un fallo. El caso concreto es el más caro de los
/// dos: sobre una corrida ya publicada, la respuesta lleva la URL del pull
/// request, y quien movió el remoto por un motivo ajeno a esta corrida sigue
/// necesitando esa URL para preguntar qué pasó. El riesgo de darla —que se la
/// lea como si fuera del remoto de ahora— se cubre con un aviso al lado, ver
/// [_avisoDeDestinoMovido], y no convirtiendo en fallo un hecho cierto.
///
/// **La rama, en cambio, gana sobre los SEIS.** No es una inconsistencia: la
/// rama decide si lo que [documento] afirma es sobre el repositorio que se
/// está mirando, así que ahí ni siquiera la URL de una publicación anterior es
/// una respuesta a la pregunta que se hizo.
///
/// **[destinoActual] es nulo cuando el remoto de hoy no nombra ningún
/// destino** —no hay remoto, o el que hay no se puede leer como uno—. Nulo
/// nunca es igual al destino de un documento, así que ese caso entra por la
/// misma puerta y con el mismo texto.
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
  required String? destinoActual,
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
  final porElEstado = switch (documento.estado) {
    EstadoDelDocumento.prepared => const Reconciliar(),
    EstadoDelDocumento.committed => const PublicarDirecto(),
    EstadoDelDocumento.publicationIncomplete => const PublicarDirecto(),
    EstadoDelDocumento.publicationComplete => _yaPublicado(
      documento,
      destinoActual: destinoActual,
    ),
    EstadoDelDocumento.notApplied => _nadaQueEntregar,
    EstadoDelDocumento.localInconsistent => const Reconciliar(),
  };
  // **El destino gobierna los caminos que PUBLICAN, y solo ésos.** Ver el
  // doc de esta función: sobre una respuesta que ya es «no se reintenta» no
  // hay ninguna publicación que guardar, y convertirla en otro rechazo cambia
  // una respuesta verdadera por un fallo.
  if (porElEstado is! NoSeReintenta && destinoActual != documento.destino) {
    return NoSeReintenta(
      causa: CausaDeNoReintento.destinoDistinto,
      detalle:
          'Esta corrida se preparó para publicar en «${documento.destino}», y '
          'el remoto de este repositorio apunta ahora a '
          '${destinoActual == null ? "ningún destino que se pueda nombrar" : "«$destinoActual»"}. '
          'Reintentar acá NO terminaría aquella publicación: la búsqueda que '
          'impide abrir un segundo pull request corre contra el destino de '
          'ahora, donde el de aquella corrida no está ni puede estar, así que '
          'se abriría uno nuevo en otro repositorio. Devolvé el remoto a '
          '«${documento.destino}» y reintentá, o volvé a correr `ship` desde '
          'el principio si lo que querés es publicar en el destino de ahora.',
    );
  }
  return porElEstado;
}
