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
const esquemaDeSalida = 1;

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

  EventEnvelope({
    required this.command,
    required this.type,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  Map<String, Object?> toJson() => {
        'schema': esquemaDeSalida,
        'command': command,
        'type': type,
        'timestamp': timestamp.toIso8601String(),
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

  const ResultEnvelope({
    required this.command,
    required this.exitCode,
    required this.verdict,
    required this.data,
    this.nextAction,
  });

  Map<String, Object?> toJson() => {
        'schema': esquemaDeSalida,
        'command': command,
        'type': 'result',
        'exitCode': exitCode,
        'verdict': verdict,
        'nextAction': nextAction,
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
  final bool detallado;

  var _resultados = 0;

  Impresora({
    required this.salida,
    required this.error,
    this.json = false,
    this.silencioso = false,
    this.detallado = false,
  });

  /// Los eventos salen por donde sale todo: la estándar.
  StringSink get _paraEventos => salida;

  /// Emite un evento.
  ///
  /// **`--quiet` calla el progreso, no los hallazgos.** La bandera dice «solo
  /// errores», y callar un diagnóstico bloqueante dejaba un resumen que
  /// afirmaba que había errores sin decir cuáles: eso no es silencio, es un
  /// reporte inservible.
  void evento(EventEnvelope e, String humano) {
    if (_resultados > 0) {
      throw const ProtocoloRoto(
          'Se emitió un evento DESPUÉS del resultado. El resultado es el '
          'último, y un consumidor que ya cerró su lectura no vería esto.');
    }
    if (silencioso && e.type != 'diagnostic') return;
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
}
