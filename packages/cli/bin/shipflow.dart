import 'dart:io';

import 'package:cli/cli.dart';

/// El punto de entrada. **Lo único que hace es traducir**: argumentos a
/// opciones, y el código de la corrida al código del proceso.
Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    stdout.writeln(_ayuda);
    // Una invocación sin acción no es un éxito: no hizo nada.
    exit(args.isEmpty ? Codigo.errorDeUso : Codigo.exito);
  }

  final comando = args.first;
  if (comando != nombreDelComando) {
    stdout.writeln('shipflow: no conozco el comando «$comando».\n'
        '  → Hoy solo existe `verify`. El resto llega con su fase.');
    exit(Codigo.errorDeUso);
  }

  exit(await correrVerify(
    args.skip(1).toList(),
    directorio: Directory.current.path,
    destino: stdout,
  ));
}

const _ayuda = '''
shipflow — arnés de desarrollo asistido por agentes

  verify [rutas...]   Corre la cascada de verificación y reporta con testigo.

Banderas de verify:
  --json              Protocolo de salida para consumo automático.
  --verbose           Incluye el testigo de cada paso: qué corrió, sobre qué,
                      y qué omitió.
  --quiet, -q         Solo lo que no sea verde.

Códigos: 0 verde · 1 diagnósticos bloqueantes · 2 no concluyente ·
         5 error de uso · 70 error interno del arnés.
''';
