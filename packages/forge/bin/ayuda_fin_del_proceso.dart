/// **Un instrumento de medición de la suite, no un comando del producto.**
///
/// Vive en `bin/` y no en `test/` por dos motivos, los dos del arnés: un
/// archivo de `test/` que ninguna suite importa es un huérfano para el grafo,
/// y nombrar su ruta desde la suite obliga a escribir la extensión de los
/// archivos fuente, que la regla que acota el nombre del lenguaje a su plugin
/// y al composition root caza con razón. Como ejecutable del paquete se corre
/// por su NOMBRE, sin ruta ni extensión, y el grafo lo alcanza porque todo
/// ejecutable de `bin/` es un punto de entrada por convención.
///
/// Nadie lo compone en ningún flujo: lo único que lo invoca es la suite del
/// empuje, bajo `packages/forge/test/`.
///
/// Corre UN `empujar` contra el programa que se le pase y **vuelve de `main`
/// sin llamar a `exit`**, igual que el ejecutable del comando bajo
/// `packages/cli/bin/`, que fija `exitCode` y vuelve a propósito. Esa es toda la gracia: un proceso
/// que vuelve de `main` sigue vivo mientras le quede trabajo pendiente —una
/// suscripción a una tubería, por ejemplo—, así que CUÁNDO TERMINA ESTE
/// PROCESO es la medición que la suite no puede hacer desde adentro de sí
/// misma.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';

Future<void> main(List<String> argumentos) async {
  final [directorio, programa, revision, urlDelRemoto] = argumentos;

  final empuje = EmpujeAislado(
    directorio: directorio,
    entornoDelPadre: EntornoDelProceso({
      'PATH': Platform.environment['PATH'] ?? '',
    }),
    programa: programa,
    presupuesto: const Duration(milliseconds: 300),
  );

  final comienzo = DateTime.now();
  final desenlace = await empuje.empujar(
    urlDelRemoto: urlDelRemoto,
    credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
    revision: revision,
    rama: 'rebanada-1',
  );
  final tardanza = DateTime.now().difference(comienzo);

  // El tipo del desenlace y los milisegundos que tardó en computarse. No sale
  // nada más: lo que se mide afuera es cuánto tarda este proceso en terminar
  // DESPUÉS de esta línea.
  stdout.writeln('desenlace=${desenlace.runtimeType}');
  stdout.writeln('computado_en_ms=${tardanza.inMilliseconds}');
}
