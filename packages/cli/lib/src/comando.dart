/// **La única frontera.** Todo lo que sale del proceso pasa por acá.
///
/// El ruteo y el `main` tenían salidas propias: imprimían la ayuda, el comando
/// desconocido y su red de último recurso escribiendo texto directo, sin pasar
/// por la impresora. Con `--json` eso rompía el protocolo en tres invocaciones
/// distintas —sin comando, con un comando que no existe, y con `--help`— y
/// cada una había que arreglarla por separado.
///
/// Una sola frontera lo cierra de una vez: si el único camino de salida
/// construye envelopes, ningún camino puede no construirlos.
library;

import 'package:orchestration/orchestration.dart';

import 'salida.dart';
import 'verify.dart';

/// Lo que un comando decidió, antes de saber cómo se va a imprimir.
class Desenlace {
  final int codigo;
  final String? verdict;
  final String? queHacer;
  final Map<String, Object?> datos;

  /// Cómo se lee cuando lo lee una persona.
  final String humano;

  const Desenlace({
    required this.codigo,
    required this.verdict,
    required this.humano,
    this.queHacer,
    this.datos = const {},
  });
}

const _ayuda = r'''
shipflow — arnés de desarrollo asistido por agentes

  verify [rutas...]   Corre la cascada de verificación y reporta con testigo.

Banderas globales (valen antes o después del comando):
  --json              Protocolo de salida: eventos y resultado en JSON Lines
                      por la salida estándar.
  --verbose           Incluye el testigo de cada paso.
  --quiet, -q         Solo lo que bloquea.
  --help, -h          Esto.

Códigos: 0 verde · 1 diagnósticos bloqueantes · 2 no concluyente ·
         5 error de uso · 70 error interno del arnés.''';

/// Ejecuta la invocación entera y devuelve el código de proceso.
///
/// **Nada sale de este método sin haber emitido su resultado**, y la única
/// excepción es la red de [Impresora.ultimoRecurso], que existe para cuando ni
/// siquiera se puede serializar.
Future<int> ejecutar(
  List<String> args, {
  required String directorio,
  required StringSink salida,
  required StringSink error,
  Cascada Function(String directorio)? construirCascada,
}) async {
  // `--json` se detecta antes que nada, porque hasta un error de ruteo tiene
  // que salir como envelope. Su presencia no es ambigua.
  final json = args.contains('--json');
  final silencioso = args.contains('--quiet') || args.contains('-q');
  final imp = Impresora(
      salida: salida, error: error, json: json, silencioso: silencioso);

  try {
    // **Las banderas globales valen antes o después del comando.** El comando
    // es el primer argumento que no empieza con guion.
    final i = args.indexWhere((a) => !a.startsWith('-'));

    if (i < 0) {
      final pidioAyuda = args.contains('--help') || args.contains('-h');
      final d = pidioAyuda
          ? const Desenlace(
              codigo: Codigo.exito,
              verdict: 'ok',
              humano: _ayuda,
              datos: {'help': _ayuda})
          // Una invocación vacía no cumplió ningún contrato: no hizo nada.
          : const Desenlace(
              codigo: Codigo.errorDeUso,
              verdict: null,
              humano: _ayuda,
              queHacer: 'Elegí un comando. Hoy existe `verify`.',
              datos: {'error': 'invocación sin acción', 'help': _ayuda});
      return _emitir(imp, 'shipflow', d);
    }

    final comando = args[i];
    if (comando != nombreDelComando) {
      return _emitir(
        imp,
        'shipflow',
        Desenlace(
          codigo: Codigo.errorDeUso,
          verdict: null,
          humano: 'shipflow: no conozco el comando «$comando».',
          queHacer: 'Hoy solo existe `verify`. El resto llega con su fase.',
          datos: {'error': 'comando desconocido: $comando'},
        ),
      );
    }

    return await correrVerify(
      [...args.sublist(0, i), ...args.sublist(i + 1)],
      directorio: directorio,
      impresora: imp,
      construirCascada: construirCascada,
    );
  } on Object catch (e, pila) {
    return _rescatar(imp, e, pila);
  }
}

int _emitir(Impresora imp, String comando, Desenlace d) {
  imp.resultado(
    ResultEnvelope(
      command: comando,
      exitCode: d.codigo,
      verdict: d.verdict,
      nextAction: d.queHacer,
      data: d.datos,
    ),
    d.queHacer == null ? d.humano : '${d.humano}\n  → ${d.queHacer}',
  );
  imp.cerrar();
  return d.codigo;
}

/// Convierte cualquier excepción en un `70` **con su acción siguiente**.
///
/// Si el resultado ya salió, no se emite un segundo —el protocolo promete uno
/// solo— y queda la red de la corriente de error, que no serializa nada.
int _rescatar(Impresora imp, Object e, StackTrace pila) {
  const queHacer = 'Se rompió el arnés, no la verificación del cambio. '
      'Reportalo con esta traza y volvé a correr; si se repite, es del arnés.';
  if (imp.resultadosEmitidos == 0) {
    try {
      return _emitir(
        imp,
        nombreDelComando,
        Desenlace(
          codigo: Codigo.errorInterno,
          verdict: veredictoDe(EstadoDeCorrida.errorInterno),
          humano: 'shipflow: error interno del arnés — $e',
          queHacer: queHacer,
          datos: {'error': '$e', 'stack': '$pila'},
        ),
      );
    } on Object {
      // Falló hasta emitir el resultado. Es literalmente el caso que la
      // corriente de error tiene reservado.
    }
  }
  imp.ultimoRecurso('error interno del arnés — $e', queHacer);
  return Codigo.errorInterno;
}
