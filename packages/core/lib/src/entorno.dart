/// El entorno con el que se lanza **todo** subproceso de este repositorio.
///
/// **Lista blanca, no lista negra.** Una lista negra promete sólo sobre lo
/// que alguien enumeró: cualquier variable secreta futura, o un `GIT_DIR` en
/// el shell de quien ejecuta, se filtra sola. La regla
/// `subprocesos-con-entorno-saneado` exige que ésta sea la única forma de
/// armar el entorno de un proceso.
///
/// **Es pura a propósito**: recibe el mapa del padre en vez de leerlo del
/// proceso, porque core no toca el mundo y porque así una prueba le pasa el
/// padre que quiere.
library;

/// Lo único que se hereda: `PATH` para que un hijo encuentre lo suyo y
/// `HOME` para la configuración del usuario, como sus reglas de ignore.
const listaBlanca = {'PATH', 'HOME', 'PUB_CACHE'};

/// La lista blanca tomada de [delPadre], más [propias]: lo que ESA
/// invocación necesita y su llamador decide.
///
/// Una propia no puede pisar la lista blanca: `PATH` decide qué binario
/// corre, y aceptarlo desde afuera reabriría lo que se cerró.
Map<String, String> entornoSaneado(
  Map<String, String> delPadre, {
  Map<String, String> propias = const {},
}) {
  final pisadas = propias.keys.where(listaBlanca.contains).toList()..sort();
  if (pisadas.isNotEmpty) {
    throw ArgumentError.value(
      pisadas,
      'propias',
      'Estas variables son de la lista blanca y se toman del padre, no de '
          'quien llama.',
    );
  }
  return Map.unmodifiable({
    for (final k in listaBlanca)
      if (delPadre.containsKey(k)) k: delPadre[k]!,
    ...propias,
  });
}
