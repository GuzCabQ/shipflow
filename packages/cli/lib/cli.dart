/// `cli` — comandos y **composition root**.
///
/// Es el único paquete que puede ver a `plugin_dart` y a `agents`, y por eso
/// es el único que sabe qué pasos concretos existen. Todo lo que arma un
/// sistema a partir de las piezas se decide acá.
library;

export 'src/comando.dart';
export 'src/salida.dart';
export 'src/uso.dart';
export 'src/verify.dart';
