/// La costura por donde el plugin invoca herramientas del sistema.
///
/// **No es un puerto de `core` y no debe serlo.** El dominio no habla de
/// procesos: habla de verificaciones y testigos. Esto es un detalle interno de
/// cómo ESTE plugin cumple sus puertos, y meterlo en `core` agrandaría la
/// superficie de puertos con algo que ningún otro paquete necesita.
///
/// Existe por una sola razón: **para poder probar las terminaciones que no se
/// pueden provocar de verdad.** Una herramienta ausente y un presupuesto
/// agotado son los dos casos que ADR-011 nombra, y sin esta costura habría que
/// desinstalar la toolchain para probar el primero.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// Lo que salió de una invocación, y **cómo terminó**.
///
/// La terminación la decide quien lanzó el proceso, que es el único que sabe
/// si el binario estaba. Nadie la deduce después del código de salida: esa
/// deducción es exactamente el agujero que [Termination] existe para cerrar.
class ResultadoDeProceso {
  final Termination terminacion;

  /// El código que devolvió el proceso, o `-1` si no llegó a devolver
  /// ninguno. **`-1` no es un código de la herramienta**: es la marca de que
  /// no hubo. Lo que significa el resultado lo dice [terminacion].
  final int codigo;

  final String salidaEstandar;
  final String salidaDeError;

  const ResultadoDeProceso({
    required this.terminacion,
    required this.codigo,
    required this.salidaEstandar,
    required this.salidaDeError,
  });
}

abstract interface class EjecutorDeProceso {
  Future<ResultadoDeProceso> correr(
    String ejecutable,
    List<String> argumentos, {
    required String directorio,
    required Duration presupuesto,
  });
}

/// Corre procesos de verdad.
///
/// **Residuo declarado: no rastrea descendientes.** Al agotarse el presupuesto
/// mata el proceso que lanzó, y `Process.start` no permite crear un grupo de
/// procesos de forma portable desde Dart. Un hijo que ese proceso haya dejado
/// atrás sigue vivo. Está medido: un `sh` que lanza otro `sh` y muere por
/// presupuesto deja al hijo escribiendo archivos después de que este ejecutor
/// ya devolvió. Los pasos lo declaran en su testigo cuando la terminación es
/// [Termination.tiempoAgotado], para que quede en la evidencia y no acá.
class EjecutorDelSistema implements EjecutorDeProceso {
  const EjecutorDelSistema();

  /// Cuánto se espera, como mucho, a que el proceso muera y sus corrientes
  /// cierren después del disparo. Limpiar no puede colgar la corrida.
  static const _limpieza = Duration(seconds: 5);

  /// **Decodificación estricta, a propósito.** Toleraba bytes inválidos
  /// reemplazándolos, y eso contradice a [QuotedText], que promete el texto
  /// «tal cual llegó». Una salida que no se puede decodificar no es una salida
  /// degradada: es una que no se puede leer, y eso vuelve la corrida no
  /// concluyente en vez de producir un texto que nadie escribió.
  ///
  /// **El invariante que sostiene esto es el del tipo, no INV-6.** Un review
  /// citó INV-6, y INV-6 dice otra cosa: «todo texto de fuente externa se
  /// encapsula», que es contra la inyección —`ASI01`— y no sobre fidelidad de
  /// bytes. La exigencia de fidelidad la puso `QuotedText` en la fase 1.
  ///
  /// **Costo declarado:** una ruta con bytes que no son UTF-8 vuelve NO
  /// CONCLUYENTE el paso entero, no solo ese archivo. Es el lado caro de la
  /// elección, y se toma igual porque el lado barato es fabricar un texto que
  /// la herramienta no escribió.
  static const _texto = Utf8Decoder();

  @override
  Future<ResultadoDeProceso> correr(
    String ejecutable,
    List<String> argumentos, {
    required String directorio,
    required Duration presupuesto,
  }) async {
    final Process proceso;
    try {
      proceso = await Process.start(ejecutable, argumentos,
          workingDirectory: directorio);
    } on ProcessException catch (e) {
      // El caso que ADR-011 nombra primero. Un verde acá sería «no encontró
      // nada» cuando nadie miró.
      return ResultadoDeProceso(
        terminacion: Termination.herramientaAusente,
        codigo: -1,
        salidaEstandar: '',
        salidaDeError: '${e.message} (${e.executable})',
      );
    }

    final salida = StringBuffer();
    final error = StringBuffer();

    // **El fallo de una corriente se guarda, no se traga.** Se tragaba, y con
    // eso una lectura rota producía una terminación «completa» con la salida
    // cortada — que es exactamente el falso verde que este archivo existe para
    // no fabricar. Después del disparo por presupuesto SÍ se ignora, porque
    // ahí el fallo es la consecuencia esperada de haber matado al proceso.
    Object? falloDeCorriente;
    Future<void> drenar(Stream<List<int>> s, StringBuffer destino) async {
      try {
        await s.transform(_texto).forEach(destino.write);
      } on Object catch (e) {
        falloDeCorriente ??= e;
      }
    }

    final corrientes = Future.wait(
        [drenar(proceso.stdout, salida), drenar(proceso.stderr, error)]);

    try {
      final codigo = await proceso.exitCode.timeout(presupuesto);
      await corrientes;
      if (falloDeCorriente != null) {
        return ResultadoDeProceso(
          terminacion: Termination.interrumpida,
          codigo: codigo,
          salidaEstandar: salida.toString(),
          salidaDeError: 'No se pudo leer la salida del proceso: '
              '$falloDeCorriente',
        );
      }
      return ResultadoDeProceso(
        terminacion: Termination.completa,
        codigo: codigo,
        salidaEstandar: salida.toString(),
        salidaDeError: error.toString(),
      );
    } on TimeoutException {
      // Se dispara Y se espera. Devolver sin esperar dejaba el proceso y sus
      // lecturas vivos después de que el resultado ya decía «tiempo agotado»,
      // así que la evidencia adelantaba un hecho que todavía no había pasado.
      final disparo = proceso.kill(ProcessSignal.sigkill);
      final codigo =
          await proceso.exitCode.timeout(_limpieza, onTimeout: () => -1);
      await corrientes.timeout(_limpieza, onTimeout: () => <void>[]);
      return ResultadoDeProceso(
        terminacion: Termination.tiempoAgotado,
        codigo: -1,
        salidaEstandar: salida.toString(),
        salidaDeError: disparo
            ? 'Presupuesto agotado; el proceso se detuvo con código $codigo.'
            : 'Presupuesto agotado y la señal no llegó a entregarse: el '
                'proceso pudo haber terminado solo, o pudo seguir vivo.',
      );
    }
  }
}

/// Un ejecutor al que se le declara qué devolver, para probar las
/// terminaciones que no se pueden provocar de verdad.
class EjecutorDeclarado implements EjecutorDeProceso {
  final ResultadoDeProceso respuesta;

  /// Qué se le pidió, para poder comprobar que el paso invocó lo que dice
  /// haber invocado. Sin esto, el testigo podría nombrar una invocación que
  /// nunca ocurrió y nada lo notaría.
  final List<String> invocaciones = [];

  EjecutorDeclarado(this.respuesta);

  @override
  Future<ResultadoDeProceso> correr(
    String ejecutable,
    List<String> argumentos, {
    required String directorio,
    required Duration presupuesto,
  }) async {
    invocaciones.add([ejecutable, ...argumentos].join(' '));
    return respuesta;
  }
}
