/// El protocolo de salida: los dos envelopes y el código de proceso.
library;

import 'dart:convert';

import 'package:orchestration/orchestration.dart';

/// Versión del esquema de salida. **Va en cada envelope.**
///
/// Un consumidor automático necesita saber contra qué está parseando. Es la
/// misma razón por la que el plugin exige la versión del esquema del
/// analizador: leer un formato nuevo con reglas viejas devuelve menos de lo
/// que hay, y en silencio.
const esquemaDeSalida = 1;

/// Los códigos de proceso. **La precedencia no es una tabla: se deriva.**
///
/// Estaba escrita en prosa —`70 > 2 > 1 > 3 > 0`— y una tabla en un documento
/// no impide que alguien devuelva `1` desde un `catch`. Acá el código sale de
/// [deCorrida] y de ningún otro lado.
abstract final class Codigo {
  /// La etapa cumplió su contrato.
  static const exito = 0;

  /// La cascada encontró diagnósticos bloqueantes.
  static const fallaDeVerificacion = 1;

  /// Algo no se pudo observar. **Se trata como rojo**, y gana sobre el rojo.
  static const noConcluyente = 2;

  /// Error de uso: comando o bandera inválida, combinación incompatible.
  static const errorDeUso = 5;

  /// El arnés se rompió. **Nunca es un resultado del pipeline**: distingue
  /// «esto se rompió» de «el cambio no verificó».
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
  final String verdict;

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

/// Por dónde sale todo. **Todo va a la salida estándar**, incluidos los
/// diagnósticos: un consumidor automático los necesita, y mandarlos por la
/// corriente de error lo obligaría a leer dos.
class Impresora {
  final StringSink destino;
  final bool json;
  final bool silencioso;
  final bool detallado;

  var _resultados = 0;

  Impresora(this.destino,
      {this.json = false, this.silencioso = false, this.detallado = false});

  void evento(EventEnvelope e, String humano) {
    if (json) {
      destino.writeln(jsonEncode(e.toJson()));
    } else if (!silencioso) {
      destino.writeln(humano);
    }
  }

  /// Emite el resultado. **Se lleva la cuenta de cuántos van**, porque «uno
  /// solo, y último» es una promesa del protocolo y una promesa que nada
  /// comprueba es una promesa que se rompe.
  void resultado(ResultEnvelope r, String humano) {
    _resultados++;
    if (_resultados > 1) {
      throw StateError(
          'Se emitió más de un ResultEnvelope para «${r.command}». '
          'El protocolo promete exactamente uno, y último.');
    }
    if (json) {
      destino.writeln(jsonEncode(r.toJson()));
    } else if (!silencioso || r.exitCode != Codigo.exito) {
      destino.writeln(humano);
    }
  }

  /// Cuántos resultados se emitieron. Lo usa la prueba del protocolo.
  int get resultadosEmitidos => _resultados;
}
