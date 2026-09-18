/// `cli` — comandos y **composition root**.
///
/// Es el único paquete al que la arquitectura le permite ver los plugins y los
/// adapters, y por eso es el único que sabe qué pasos concretos existen. Todo
/// lo que arma un sistema a partir de las piezas se decide acá.
///
/// **Permitido no es declarado.** `arquitectura.json` le permite ver también
/// `vcs`, `rules` y `agents`; el pubspec declara solo lo que hoy se importa, así
/// que hoy `cli` no puede importarlos. Esta frase nombraba a `agents` de
/// ejemplo y quedó **falsa** el mismo día que se quitó esa dependencia: un
/// ejemplo elegido de lo permitido envejece con cualquier limpieza de lo usado.
library;

export 'src/comando.dart';
export 'src/corrida.dart';
export 'src/credenciales.dart';
export 'src/salida.dart';
export 'src/ship/entrada.dart';
export 'src/ship/gitignore.dart';
export 'src/ship/preflight.dart';
export 'src/ship/preview.dart';
export 'src/ship/ship.dart';
export 'src/uso.dart';
export 'src/verify.dart';
