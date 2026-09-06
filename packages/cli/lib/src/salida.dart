/// El protocolo de salida: el documento, los eventos y el código de proceso.
library;

import 'dart:convert';

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
  static const errorDeUso = 5;

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
}

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
  /// **Hueco de la superficie, declarado.** La lista de veredictos cubre los
  /// códigos `0`, `1`, `2`, `3` y `70`, pero no el `5`: un error de uso no
  /// alcanzó el dominio, así que no tiene veredicto que dar. Inventarle uno
  /// sería afirmar algo sobre un cambio que nadie miró. El código de salida
  /// lleva ese dato, y va en el mismo documento.
  final String? verdict;

  /// Qué hacer a continuación. Toda salida que no sea verde tiene que poder
  /// decirlo: es la misma exigencia que INV-8 le hace a una regla que bloquea.
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
          'último, y un consumidor que ya cerró su lectura no vería esto.');
    }
    if (silencioso && e.type == 'progress') return;
    _paraEventos.writeln(json ? jsonEncode(e.toJson()) : humano);
  }

  /// Emite el resultado. **Uno solo, y último.**
  void resultado(ResultEnvelope d, String humano) {
    _resultados++;
    if (_resultados > 1) {
      throw ProtocoloRoto('Se emitió un segundo resultado para «${d.command}». '
          'El protocolo promete exactamente uno.');
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
          'exactamente uno.');
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
