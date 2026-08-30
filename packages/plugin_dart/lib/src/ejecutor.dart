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
class EjecutorDelSistema implements EjecutorDeProceso {
  const EjecutorDelSistema();

  /// `allowMalformed` a propósito: la salida de una herramienta puede traer
  /// bytes que no son UTF-8 y eso no es motivo para que el paso se caiga con
  /// una excepción que nadie espera. Se degrada el carácter, no la corrida —
  /// y queda escrito para que no parezca un descuido.
  static const _texto = Utf8Decoder(allowMalformed: true);

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
    // Las corrientes mueren con el proceso cuando se lo mata por presupuesto.
    // Que la lectura falle DESPUÉS de un SIGKILL no es información: es la
    // consecuencia esperada. Se absorbe acá y en ningún otro lado.
    Future<void> drenar(Stream<List<int>> s, StringBuffer destino) async {
      try {
        await s.transform(_texto).forEach(destino.write);
      } on Object {
        // El proceso ya no está; lo que se alcanzó a leer está en el buffer.
      }
    }

    final corrientes = Future.wait(
        [drenar(proceso.stdout, salida), drenar(proceso.stderr, error)]);

    try {
      final codigo = await proceso.exitCode.timeout(presupuesto);
      await corrientes;
      return ResultadoDeProceso(
        terminacion: Termination.completa,
        codigo: codigo,
        salidaEstandar: salida.toString(),
        salidaDeError: error.toString(),
      );
    } on TimeoutException {
      proceso.kill(ProcessSignal.sigkill);
      return ResultadoDeProceso(
        terminacion: Termination.tiempoAgotado,
        codigo: -1,
        salidaEstandar: salida.toString(),
        salidaDeError: error.toString(),
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
