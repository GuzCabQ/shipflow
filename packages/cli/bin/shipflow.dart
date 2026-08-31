import 'dart:io';

import 'package:cli/cli.dart';

/// El punto de entrada. **Lo único que hace es enrutar**: separa el comando de
/// sus argumentos y traduce el código de la corrida al del proceso.
Future<void> main(List<String> args) async {
  try {
    exitCode = await _enrutar(args);
  } on Object catch (e) {
    // Última red. Una excepción acá dejaría al proceso con el código 255 del
    // runtime, que no significa nada en esta superficie.
    stdout.writeln('shipflow: error interno del arnés — $e');
    exitCode = Codigo.errorInterno;
  }
  // **`exitCode` y no `exit()`.** `exit()` corta el proceso sin dejar drenar
  // las corrientes, y una salida larga —un `--json` con muchos diagnósticos—
  // se trunca sin que nadie se entere. Que el `main` termine solo es lo que
  // garantiza que lo escrito salga.
  await stdout.flush();
  await stderr.flush();
}

Future<int> _enrutar(List<String> args) async {
  // **Las banderas globales valen antes o después del comando.** `--json`
  // antes del comando se leía como un comando desconocido, que es lo contrario
  // de lo que «global» significa. El comando es el primer argumento que no
  // empieza con guion.
  final i = args.indexWhere((a) => !a.startsWith('-'));

  if (i < 0) {
    // Sin comando. `--help` explícito es un éxito: pediste ayuda y la tuviste.
    // Una invocación vacía no: no hizo nada, y nada no es haber cumplido.
    final pidioAyuda = args.contains('--help') || args.contains('-h');
    stdout.writeln(_ayuda);
    return pidioAyuda ? Codigo.exito : Codigo.errorDeUso;
  }

  final comando = args[i];
  final resto = [...args.sublist(0, i), ...args.sublist(i + 1)];

  if (comando != nombreDelComando) {
    stdout.writeln('shipflow: no conozco el comando «$comando».\n'
        '  → Hoy solo existe `verify`. El resto llega con su fase.');
    return Codigo.errorDeUso;
  }

  return correrVerify(
    resto,
    directorio: Directory.current.path,
    salida: stdout,
    error: stderr,
  );
}

const _ayuda = r'''
shipflow — arnés de desarrollo asistido por agentes

  verify [rutas...]   Corre la cascada de verificación y reporta con testigo.

Banderas globales (valen antes o después del comando):
  --json              Protocolo de salida: eventos y resultado en JSON Lines
                      por la salida estándar.
  --verbose           Incluye el testigo de cada paso.
  --quiet, -q         Calla el progreso. NO calla los diagnósticos.
  --help, -h          Esto.

Códigos: 0 verde · 1 diagnósticos bloqueantes · 2 no concluyente ·
         5 error de uso · 70 error interno del arnés.''';
