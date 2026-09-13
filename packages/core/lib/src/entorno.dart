/// El entorno con el que se lanza **todo** subproceso de este repositorio.
///
/// **Lista blanca, no lista negra** (§8 de la propuesta de entorno de
/// verificación). Una lista negra promete solo sobre lo que alguien enumeró:
/// cualquier variable secreta futura se filtra sola. Esta función promete lo
/// contrario, y la regla `subprocesos-con-entorno-saneado` exige que sea la
/// única forma de armar el entorno de un proceso.
///
/// **Es pura a propósito**: recibe el mapa del padre en vez de leerlo del
/// proceso, porque este paquete no puede tocar el mundo —lo prohíbe
/// `nucleo-sin-entrada-salida`— y porque así la prueba le pasa el padre que
/// quiere, que es la única forma de comprobar qué llega y qué no sin depender
/// del shell de quien corre la suite.
library;

/// Lo único que se hereda. Medido variable por variable: el analizador
/// estático necesita **solo** `PATH` —el mapa de paquetes resuelto lleva rutas
/// absolutas al cache—; el resolvedor de dependencias necesita encontrar ese
/// cache; `git` necesita `HOME`.
const listaBlanca = {'PATH', 'HOME', 'PUB_CACHE'};

/// Arma el entorno saneado: la lista blanca tomada de [delPadre], más
/// [propias] —las variables que ESA invocación necesita y que el llamador
/// decide, como `GIT_INDEX_FILE` o la identidad capturada—.
///
/// Una propia no puede pisar la lista blanca: `PATH` decide qué binario corre,
/// y aceptarlo desde afuera sería reabrir por otra puerta lo que se cerró.
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
