/// `forge` — por donde sale el pull request, y el único paquete que sabe quién
/// es la forja.
///
/// **Lanza su propio `git push`.** No puede usar `vcs`: las flechas entre
/// paquetes apuntan a `core` y solo `cli` ve a los adapters. Eso no es una
/// molestia del mapa — `vcs` es local y funciona sin red, `forge` es remoto y
/// necesita credencial, y confundirlos es lo que ADR-014 prohíbe.
library;

export 'src/composicion.dart';
export 'src/cuerpo.dart';
export 'src/empuje.dart';
export 'src/github.dart';
