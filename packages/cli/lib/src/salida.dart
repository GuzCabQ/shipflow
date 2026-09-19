/// El protocolo de salida: el documento, los eventos y el código de proceso.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';

/// Versión del esquema de salida. **Va en cada documento y en cada evento.**
///
/// Un consumidor automático necesita saber contra qué está parseando. Es la
/// misma razón por la que el plugin exige la versión del esquema del
/// analizador: leer un formato nuevo con reglas viejas devuelve menos de lo
/// que hay, y en silencio.
///
/// **Subió a `2` con `runId`** (ver [EventEnvelope] y [ResultEnvelope]): un
/// consumidor que ya sabía leer el `1` no sabe que ahora hay una clave más, y
/// tiene que poder distinguir los dos formatos.
const esquemaDeSalida = 2;

var _corridas = 0;

/// Identifica una corrida de la cascada, para correlacionar sus eventos con
/// su resultado. **Nulo cuando no hubo corrida**: un error de uso o la ayuda
/// no llegan a componer ni a correr una [Cascada], así que no hay nada que
/// identificar — inventarle un id sería afirmar una corrida que no ocurrió.
String generarRunId() {
  _corridas += 1;
  return '${DateTime.now().toUtc().microsecondsSinceEpoch}-$_corridas';
}

/// Los códigos de proceso. **La precedencia no es una tabla: se deriva.**
///
/// Estaba escrita en prosa y una tabla en un documento no impide que alguien
/// devuelva `1` desde un `catch`. Acá el código sale de [deCorrida] y de
/// ningún otro lado.
abstract final class Codigo {
  static const exito = 0;
  static const fallaDeVerificacion = 1;
  static const noConcluyente = 2;

  /// Una detención por una precondición declarada que dejó de valer.
  ///
  /// **No es error de configuración** —nada está mal configurado—, **no es
  /// error interno** —nada se corrompió—, y no describe la verificación. Es la
  /// forma del circuit breaker.
  static const detencionDeclarada = 3;

  /// Falta configuración o credencial, y se dice cuál. **Cero escrituras.**
  ///
  /// Se clasifica por fase: una credencial ausente o rechazada en el preflight
  /// es `4`; expirada o rechazada después del commit es
  /// [entregaIncompleta], porque ahí sí hay trabajo local que quedó hecho.
  static const errorDeConfiguracion = 4;

  static const errorDeUso = 5;

  /// El trabajo local se completó y el efecto remoto no.
  ///
  /// Rama, commit y artefactos existen; **no hay un pull request abierto
  /// utilizable confirmado**.
  static const entregaIncompleta = 6;

  /// El arnés se rompió. **Nunca es un resultado del pipeline.**
  static const errorInterno = 70;

  /// El código que le corresponde a un estado de corrida. Es una función
  /// total: un estado nuevo no compila hasta que alguien decida su código.
  static int deCorrida(EstadoDeCorrida estado) => switch (estado) {
    EstadoDeCorrida.verde => exito,
    EstadoDeCorrida.rojo => fallaDeVerificacion,
    EstadoDeCorrida.noConcluyente => noConcluyente,
    EstadoDeCorrida.errorInterno => errorInterno,
  };

  /// El código que le corresponde a un desenlace de `ship`. Es una función
  /// total: **una variante nueva no compila** hasta que alguien decida su
  /// código.
  ///
  /// Es el mismo criterio de [deCorrida], sobre un dominio cerrado más grande.
  static int deShip(ShipOutcome desenlace) => switch (desenlace) {
    NoIntentado(causa: CausaDeNoIntento.previewOnly) => exito,
    NoIntentado(causa: CausaDeNoIntento.confirmationMissing) => exito,
    NoIntentado(causa: CausaDeNoIntento.secretDetected) => fallaDeVerificacion,
    NoIntentado(
      causa: CausaDeNoIntento.verificationGate,
      :final verificacion,
    ) =>
      deCorrida(verificacion),
    NoAplicado() => detencionDeclarada,
    LocalInconsistente() => errorInterno,
    Publicado(:final verificacion) => deCorrida(verificacion.comoCorrida),
    // **`6` gana sobre el estado, y es deliberado.** Los dos códigos responden
    // preguntas distintas: `1` dice «el cambio no verificó» y `6` dice «el
    // efecto remoto no se completó», y la segunda es la que decide qué hacer
    // después. Un `1` acá mandaría a arreglar el código a alguien que además
    // tiene una rama empujada sin pull request, y el reintento que esa
    // situación pide no saldría de ningún lado. El precio: el estado de
    // verificación no viaja en el código de esta variante, solo en `verdict`
    // y en `data`.
    PublicacionIncompleta() => entregaIncompleta,
  };
}

/// Qué hacer después de un desenlace de `ship`.
///
/// **Se deriva, como el código.** Una acción escrita a mano en cada sitio de
/// retorno diverge del desenlace en cuanto alguien agrega una variante; acá la
/// exhaustividad del `switch` la ata.
///
/// **Nulo SOLO donde [Codigo.deShip] devuelve [Codigo.exito]**, que es una
/// implicación en un sentido y no un bicondicional: si el código no es cero,
/// hay acción. Es lo que [ResultEnvelope.nextAction] promete — toda salida que
/// no sea verde tiene que poder decir qué hacer. Al revés **es falso**, y no
/// tiene por qué valer: `confirmationMissing` sale `0` y devuelve igual el
/// mensaje de `--yes`. La promesa es que ninguna salida no-verde se quede
/// muda, no que ninguna verde hable.
String? accionDe(ShipOutcome desenlace) => switch (desenlace) {
  NoIntentado(causa: CausaDeNoIntento.previewOnly) => null,
  NoIntentado(causa: CausaDeNoIntento.confirmationMissing) =>
    'Volvé a correrlo con --yes para autorizar la escritura.',
  NoIntentado(causa: CausaDeNoIntento.secretDetected) =>
    'Sacá el secreto del cambio y leelo del entorno por el proveedor de '
        'configuración.',
  NoIntentado(causa: CausaDeNoIntento.verificationGate, :final verificacion)
      when verificacion == EstadoDeCorrida.errorInterno =>
    'Se rompió un paso del arnés, no la verificación del cambio. Revisá la '
        'corrida antes de volver a intentar; --allow-incomplete no autoriza '
        'esto.',
  NoIntentado(causa: CausaDeNoIntento.verificationGate) =>
    'Arreglá lo que la verificación señaló, o autorizá publicarla incompleta '
        'con --allow-incomplete.',
  // **Las dos causas de no aplicar se dicen distinto, y la segunda es la que
  // estaba mintiendo.** Con `ramaCambiada` la rama NO avanzó: no se intentó
  // mover ninguna referencia, y el `HEAD` observado es el de otra rama. El
  // consejo de «volvé a correr ship» era peor que inútil ahí —reconstruye el
  // candidato sobre esa otra rama y commitea ahí—, así que la alternativa
  // viaja con la advertencia y no después de ella.
  NoAplicado(causa: CausaDeNoAplicacion.baseMovida, :final headObservado) =>
    'La rama avanzó a $headObservado. Volvé a correr ship: el candidato se '
        'reconstruye sobre el HEAD nuevo. No sirve --retry-publication: no hay '
        'entrega que recuperar.',
  NoAplicado(causa: CausaDeNoAplicacion.ramaCambiada, :final headObservado) =>
    'La rama puesta dejó de ser la de la corrida, así que no se intentó mover '
        'ninguna referencia: $headObservado es el HEAD de la rama en la que '
        'estás ahora, no de aquella. Volvé a la rama sobre la que empezaste y '
        'corré ship de nuevo, y pasale --branch con ese nombre: así la corrida '
        'se detiene en el preflight en vez de commitear donde estés parado. '
        'Volver a correrlo sin más reconstruye el candidato sobre esta otra '
        'rama. No sirve --retry-publication: no hay entrega que recuperar.',
  LocalInconsistente(:final revision) =>
    'El commit $revision existe y el índice quedó sin sincronizar. Reparalo '
        'y después --retry-publication, que comprueba que el índice ya '
        'coincide antes de publicar.',
  Publicado(verificacion: EstadoPublicable.verde) => null,
  // **Publicar no es verificar.** `--allow-incomplete` autoriza publicar un
  // estado incompleto; no lo vuelve verde. Este desenlace sale `1` o `2` por
  // [Codigo.deShip] —lleva el código de su verificación— y hasta acá salía sin
  // acción siguiente: un código distinto de cero y nada que hacer. No sirve
  // `--retry-publication`, porque la publicación ya se completó; lo que queda
  // es lo que la verificación señaló, sobre un pull request que ya existe.
  Publicado(:final verificacion, :final pr) =>
    'El pull request ya existe en ${pr.url} y la verificación quedó en '
        '${verificacion.name}. --allow-incomplete autorizó publicarla así, no '
        'la declara verde: arreglá lo que la verificación señaló antes de '
        'integrarla. No sirve --retry-publication: la publicación se completó.',
  PublicacionIncompleta() =>
    'shipflow ship --retry-publication <runId>. No se creará otro commit ni '
        'un segundo pull request.',
};

/// El veredicto de un desenlace de `ship`, o **nulo donde no hay estado que
/// informar**.
///
/// Se deriva, como el código y como la acción. Los tres desenlaces que llevan
/// el estado de la verificación lo dicen; los otros dos —el compare-and-swap
/// rechazado y el índice sin sincronizar— **no lo llevan**, y ahí el nulo es
/// el dato: la corrida se detuvo por lo que pasó con el repositorio local, no
/// por lo que la verificación vio. Inventarles un veredicto sería afirmar algo
/// sobre un cambio que, en esos dos caminos, este desenlace no mira.
String? veredictoDeShip(ShipOutcome desenlace) => switch (desenlace) {
  NoIntentado(:final verificacion) => veredictoDe(verificacion),
  Publicado(:final verificacion) => veredictoDe(verificacion.comoCorrida),
  PublicacionIncompleta(:final verificacion) => veredictoDe(
    verificacion.comoCorrida,
  ),
  NoAplicado() || LocalInconsistente() => null,
};

/// El payload de máquina de `ship`: lo que un consumidor automático lee para
/// decidir qué hacer sin volver a correr nada.
///
/// **Versiona su propio formato y NO toca el del envelope.** ADR-019 fija
/// [esquemaDeSalida] en `2`; subirlo por un campo que solo `ship` produce haría
/// que `verify` emitiera `3` contra un ADR aceptado, y obligaría a todos sus
/// consumidores a releer un formato que para ellos no cambió. Por eso la
/// versión que viaja acá es [payloadVersionDeShip] —en `core`, para que este
/// payload y el cuerpo del pull request no lleven cada uno su copia del
/// número— y la clave `schema` no está: es del envelope y de nadie más.
///
/// **El cuerpo es el `toJson` del desenlace, y eso no es pereza.** Ese mismo
/// mapa es el que persiste el documento de la corrida. Dos serializaciones del
/// mismo hecho divergen, y la que alguien relee después de una interrupción
/// tendría que coincidir con la que se imprimió. Lo que se agrega son los
/// derivados del desenlace remoto —qué tan entregada quedó, si se reintenta, y
/// en qué fase quedó cada mitad— que un consumidor necesita y que `toJson` no
/// lleva porque son getters, no campos.
///
/// **No lleva `runId`.** Lo lleva [ResultEnvelope.runId], en el mismo
/// documento: repetirlo acá es el mismo hecho escrito dos veces, y dos
/// escrituras del mismo hecho divergen.
///
/// **Los cuatro campos del documento SE RELEEN, no se agregan al desenlace.**
/// `branch`, `base`, `revision` y `candidate` están en el diseño de este
/// payload y ninguno es un campo de ningún [ShipOutcome]. El documento de la
/// corrida es el registro de lo que pasó y ya los lleva todos —para eso lo
/// construyó la rebanada anterior, y es el mismo que va a releer
/// `--retry-publication`—, así que se leen de ahí. Meterlos en el desenlace
/// obligaría a la variante que no intentó a cargar cuatro nulos, que es
/// exactamente el dato inventado que este payload existe para no producir.
///
/// **Que falten cuando no hay documento NO es una inconsistencia.** Una
/// corrida que no intentó no TIENE revisión ni candidato: no llegó a
/// construirlos. La ausencia de la clave es el dato honesto; la clave presente
/// con nulo adentro afirmaría que se miró y no había, que es otra cosa. Las
/// dos corridas que no dejan documento son la previsualización y la que se
/// detiene antes del candidato — ver `DocumentoDeCorrida.estadoQueAfirma`, que
/// declara por qué [NoIntentado] no afirma ningún estado del documento.
///
/// **Y esa ausencia honesta no es la ÚNICA que deja a los cuatro campos
/// afuera — [documentoIlegible] existe para que no se confundan.** Un
/// documento que SÍ se escribió y que la relectura no pudo abrir después de
/// la publicación deja el mismo hueco que una corrida que nunca escribió nada, y
/// las dos cuentas son hechos distintos: la primera es la que
/// `DocumentoDeCorrida.estadoQueAfirma` ya declara, la segunda es que hubo
/// una corrida —con [ShipOutcome] publicado, lo más caro de esta tabla— y su
/// registro quedó ilegible. Un consumidor que lea la ausencia como la primera
/// cuando pasó la segunda concluye que la corrida no escribió nada, que es
/// falso justo después de que se abrió un pull request. `documentUnreadable`
/// sale en `true` únicamente en ese segundo caso — nunca en `false`, porque
/// una ausencia sin la clave YA dice «no hubo nada que releer», y agregarla en
/// `false` ahí repetiría el mismo hecho por dos caminos que pueden divergir.
///
/// **QUÉ CAUSA SECUNDARIA VIAJA, Y CUÁL NO.** La precedencia de
/// [ShipOutcome.derivar] devuelve UNA causa, y la del estado de verificación
/// sobrevive igual: [NoIntentado] lleva su `verificacion` entera, así que una
/// corrida detenida por un secreto que ADEMÁS tenía la cascada en rojo informa
/// las dos cosas. Los otros hechos que la fábrica recibió —hubo secreto, se
/// confirmó, era una previsualización— **no son campos de ningún desenlace**:
/// entran a `derivar` y no salen. Nadie los tiene cuando este payload se
/// escribe, así que un campo que los informara estaría inventando el dato en
/// vez de reportarlo. Cerrarlo pide que el desenlace conserve los hechos que
/// descartó, que es un cambio del tipo del dominio y no de esta función.
Map<String, Object?> payloadDeShip(
  ShipOutcome desenlace, {
  DocumentoDeCorrida? documento,
  bool documentoIlegible = false,
}) => {
  'payloadVersion': payloadVersionDeShip,
  ...desenlace.toJson(),
  ...?_publicacionDe(desenlace),
  ...?_deLaCorrida(documento, ilegible: documentoIlegible),
};

/// Lo que solo el documento de la corrida sabe, o **nulo cuando no hay nada
/// que decir de él**.
///
/// Va DESPUÉS del `toJson` del desenlace a propósito: [LocalInconsistente]
/// escribe su propia `revision`, y las dos son el mismo commit —el documento
/// lo persiste desde que existe el objeto—. Que la del documento gane deja una
/// sola procedencia para esa clave en vez de dos que pueden divergir.
///
/// **[ilegible] es la otra ausencia, y la única que este mapa distingue de la
/// honesta.** Con [documento] nulo y [ilegible] en falso no hay nada que
/// agregar —es la corrida que nunca escribió, y ese nulo ya lo dice todo—;
/// con [ilegible] en verdad hay algo que agregar aunque [documento] siga
/// nulo: que hubo uno y no se dejó leer. Las dos ausencias no pueden
/// coincidir a la vez —`documento` gana si está— así que no hace falta un
/// tercer caso para «los dos a la vez».
Map<String, Object?>? _deLaCorrida(
  DocumentoDeCorrida? documento, {
  required bool ilegible,
}) {
  if (documento != null) {
    return {
      'branch': documento.draft.branch,
      'base': documento.draft.base,
      'revision': documento.revision,
      'candidate': documento.draft.artefacto.candidato.toJson(),
    };
  }
  if (ilegible) return {'documentUnreadable': true};
  return null;
}

/// Los derivados del desenlace remoto, o nulo cuando no hubo ninguno.
///
/// Nulo y no un mapa con ceros: una corrida que no intentó publicar no tiene
/// estado de entrega que informar, y un `retryable: false` ahí se leería como
/// «se intentó y no se puede reintentar».
Map<String, Object?>? _publicacionDe(ShipOutcome desenlace) {
  final PublicationOutcome? remoto = switch (desenlace) {
    Publicado(:final pr) => pr,
    PublicacionIncompleta(:final remoto) => remoto,
    NoIntentado() || NoAplicado() || LocalInconsistente() => null,
  };
  if (remoto == null) return null;
  final fases = _fasesDe(remoto);
  return {
    'deliveryStatus': remoto.deliveryStatus.name,
    'retryable': remoto.retryable,
    'remoteNextAction': remoto.nextAction.name,
    'push': fases.push,
    'pullRequest': fases.pullRequest,
  };
}

/// En qué quedó cada mitad de la publicación. **Se DERIVA de la variante**, y
/// esa es toda la diferencia con los dos enums independientes que el tipo
/// sellado vino a reemplazar: aquéllos admitían el producto cartesiano —«el
/// empuje falló y el pull request salió bien»— porque cada uno se asignaba por
/// su cuenta. Acá no hay nada que asignar: un `switch` exhaustivo sobre las
/// siete variantes, y una octava no compila hasta que alguien diga en qué fase
/// deja a cada mitad.
///
/// **`notAttempted` no es un eufemismo de «falló».** Si el empuje falló o no se
/// supo, el pull request no se llegó a pedir: decir `failed` ahí afirmaría un
/// intento remoto que no ocurrió, y es justo la distinción que hace que un
/// reintento no abra un segundo pull request.
({String push, String pullRequest}) _fasesDe(PublicationOutcome remoto) =>
    switch (remoto) {
      PullRequestOpen() => (push: 'succeeded', pullRequest: 'open'),
      PullRequestMerged() => (push: 'succeeded', pullRequest: 'merged'),
      PullRequestClosed() => (push: 'succeeded', pullRequest: 'closed'),
      PushFailed() => (push: 'failed', pullRequest: 'notAttempted'),
      PushUnknown() => (push: 'unknown', pullRequest: 'notAttempted'),
      PullRequestFailed() => (push: 'succeeded', pullRequest: 'failed'),
      PullRequestUnknown() => (push: 'succeeded', pullRequest: 'unknown'),
    };

/// El veredicto tal como lo lee un consumidor automático.
///
/// `internalError` es un veredicto propio y no una ausencia: la superficie lo
/// declara junto a los otros, y un consumidor tiene que poder distinguir «el
/// arnés se rompió» de «no hay dato» sin mirar el código de salida.
String veredictoDe(EstadoDeCorrida estado) => switch (estado) {
  EstadoDeCorrida.verde => 'ok',
  EstadoDeCorrida.rojo => 'failed',
  EstadoDeCorrida.noConcluyente => 'inconclusive',
  EstadoDeCorrida.errorInterno => 'internalError',
};

/// Un evento emitido durante la ejecución. Cero o más por comando.
class EventEnvelope {
  final String command;
  final String type;
  final Map<String, Object?> data;
  final DateTime timestamp;

  /// La corrida que lo produjo, o `null` si no vino de ninguna.
  final String? runId;

  EventEnvelope({
    required this.command,
    required this.type,
    required this.data,
    this.runId,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  Map<String, Object?> toJson() => {
    'schema': esquemaDeSalida,
    'command': command,
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'runId': runId,
    'data': data,
  };
}

/// El resultado. **Exactamente uno por comando, y siempre el último.**
class ResultEnvelope {
  final String command;
  final int exitCode;

  /// El veredicto del dominio, o `null` cuando el comando no llegó a
  /// producir uno.
  ///
  /// **Hueco de la superficie, declarado.** Los cuatro veredictos de
  /// [veredictoDe] cubren los códigos que salen de [Codigo.deCorrida] —`0`,
  /// `1`, `2` y `70`— pero no el `5`: un error de uso no alcanzó el dominio,
  /// así que no tiene veredicto que dar. Inventarle uno sería afirmar algo
  /// sobre un cambio que nadie miró. El código de salida lleva ese dato, y va
  /// en el mismo documento.
  ///
  /// **Para un [ShipOutcome] lo arma [veredictoDeShip], y no cubre las cinco
  /// variantes.** La frase anterior decía que nadie armaba todavía ninguno;
  /// desde que el comando existe, sí. Lo que cambió es dónde queda el hueco:
  /// ya no es «el `3` y el `6` no tienen veredicto» —el `6` sale de
  /// [PublicacionIncompleta], que lleva su estado de verificación y por lo
  /// tanto SÍ lo tiene—, sino que son [NoAplicado] y [LocalInconsistente] los
  /// que salen sin veredicto, porque ninguno de los dos lleva estado de
  /// verificación que informar: se detuvieron por lo que pasó con el
  /// repositorio local. Un consumidor que reciba cualquiera de los dos lo sabe
  /// por el código de salida y por `data`, no por `verdict`.
  ///
  /// Enumerar variantes acá **vence con cada una nueva** —esta oración ya
  /// nació incompleta una vez, con el `6` recién estrenado—, así que quien
  /// agregue una fila a [Codigo.deShip] la agrega también a [veredictoDeShip],
  /// que es un `switch` exhaustivo y no compila hasta que lo haga, y después
  /// reescribe este párrafo.
  final String? verdict;

  /// Qué hacer a continuación. Toda salida que no sea verde tiene que poder
  /// decirlo: es la misma exigencia que INV-8 le hace a una regla que bloquea.
  ///
  /// Para un [ShipOutcome] eso lo cumple [accionDe], y lo cumple entero: es
  /// nulo **solo donde** [Codigo.deShip] devuelve [Codigo.exito]. **Solo
  /// donde, no exactamente donde**: la implicación va en un sentido —si el
  /// código no es cero, hay acción— y el otro sentido es falso, porque
  /// `confirmationMissing` sale `0` y devuelve igual el mensaje de `--yes`.
  /// Afirmar el bicondicional sería prometer más de lo que el control tiene, y
  /// es lo único que la suite puede comprobar. La versión anterior no cumplía
  /// ni la implicación y no lo decía — un [Publicado] con la verificación en
  /// rojo salía `1` sin acción siguiente.
  final String? nextAction;

  final Map<String, Object?> data;

  /// La corrida que lo produjo, o `null` si el comando no llegó a componer
  /// ni a correr una cascada.
  final String? runId;

  const ResultEnvelope({
    required this.command,
    required this.exitCode,
    required this.verdict,
    required this.data,
    this.nextAction,
    this.runId,
  });

  Map<String, Object?> toJson() => {
    'schema': esquemaDeSalida,
    'command': command,
    'type': 'result',
    'exitCode': exitCode,
    'verdict': verdict,
    'nextAction': nextAction,
    'runId': runId,
    'data': data,
  };
}

/// Se lanza cuando el protocolo de salida se incumple. **No se degrada a un
/// mensaje**: un consumidor que recibe una salida que no cumple el contrato no
/// tiene forma de saberlo, así que el incumplimiento tiene que romper acá.
class ProtocoloRoto implements Exception {
  final String reason;
  const ProtocoloRoto(this.reason);

  @override
  String toString() => 'ProtocoloRoto: $reason';
}

/// Por dónde sale cada cosa.
///
/// **Todo va a la salida estándar**, incluidos los diagnósticos: un consumidor
/// automático los necesita, y mandarlos por la corriente de error lo obligaría
/// a leer dos. La de error **queda reservada** para un fallo que impida
/// siquiera serializar el resultado.
///
/// Ese ruteo está acá y en ningún otro lado.
class Impresora {
  final StringSink salida;
  final StringSink error;
  final bool json;
  final bool silencioso;

  var _resultados = 0;

  Impresora({
    required this.salida,
    required this.error,
    this.json = false,
    this.silencioso = false,
  });

  /// Los eventos salen por donde sale todo: la estándar.
  StringSink get _paraEventos => salida;

  /// Emite un evento.
  ///
  /// **`--quiet` calla el progreso, no los hallazgos.** La bandera dice «solo
  /// errores», y callar un diagnóstico bloqueante dejaba un resumen que
  /// afirmaba que había errores sin decir cuáles: eso no es silencio, es un
  /// reporte inservible.
  ///
  /// QUÉ diagnósticos se muestran no se decide acá: depende de su severidad,
  /// y la severidad la conoce quien los tiene. Filtrar por el TIPO del evento
  /// es lo que hacía esto antes, y con eso `--quiet` mostraba lo informativo
  /// e incluso lo que `Severity.silencia` declara que no se muestra.
  void evento(EventEnvelope e, String humano) {
    if (_resultados > 0) {
      throw const ProtocoloRoto(
        'Se emitió un evento DESPUÉS del resultado. El resultado es el '
        'último, y un consumidor que ya cerró su lectura no vería esto.',
      );
    }
    if (silencioso && e.type == 'progress') return;
    _paraEventos.writeln(json ? jsonEncode(e.toJson()) : humano);
  }

  /// Emite el resultado. **Uno solo, y último.**
  void resultado(ResultEnvelope d, String humano) {
    _resultados++;
    if (_resultados > 1) {
      throw ProtocoloRoto(
        'Se emitió un segundo resultado para «${d.command}». '
        'El protocolo promete exactamente uno.',
      );
    }
    if (json) {
      salida.writeln(jsonEncode(d.toJson()));
    } else if (!silencioso || d.exitCode != Codigo.exito) {
      salida.writeln(humano);
    }
  }

  /// Cierra la impresión. **Cero resultados también incumple el contrato**, y
  /// era el lado que nadie miraba: la comprobación de «uno solo» no dice nada
  /// sobre «al menos uno», y un comando que no emite ninguno deja al
  /// consumidor esperando algo que no llega.
  void cerrar() {
    if (_resultados == 0) {
      throw const ProtocoloRoto(
        'El comando terminó sin emitir su resultado. El protocolo promete '
        'exactamente uno.',
      );
    }
  }

  int get resultadosEmitidos => _resultados;

  /// La última salida posible. **Va por la corriente de error y no serializa
  /// nada.**
  ///
  /// El contrato reserva esa corriente para «un fallo que impida incluso
  /// serializar el resultado», y hasta acá nadie escribía en ella: el rescate
  /// reintentaba sobre la misma salida que acababa de fallar. Esto no arma un
  /// envelope, no codifica JSON y no toca el estado de la impresora — si algo
  /// de eso fuera posible, no estaríamos acá.
  void ultimoRecurso(String mensaje, String queHacer) {
    error.writeln('shipflow: $mensaje');
    error.writeln('  → $queHacer');
  }
}
