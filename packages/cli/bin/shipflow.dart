import 'dart:io';

import 'package:cli/cli.dart';

/// El punto de entrada. **No imprime nada por su cuenta.**
///
/// Tenía su propia salida —la ayuda, el comando desconocido, su red de último
/// recurso— y con `--json` eso rompía el protocolo en tres invocaciones
/// distintas. Ahora todo pasa por la frontera de `ejecutar`, y acá solo queda
/// traducir su código al del proceso.
Future<void> main(List<String> args) async {
  exitCode = await ejecutar(
    args,
    directorio: Directory.current.path,
    salida: stdout,
    error: stderr,
  );
  // **`exitCode` y no `exit()`.** `exit()` corta el proceso sin dejar drenar
  // las corrientes, y una salida larga —un `--json` con muchos diagnósticos—
  // se trunca sin que nadie se entere.
  await stdout.flush();
  await stderr.flush();
}
