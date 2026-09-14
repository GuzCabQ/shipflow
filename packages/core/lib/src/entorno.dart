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

import 'credencial.dart';

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

/// Las variables que llevan un secreto. **Declaradas, no adivinadas**: la
/// lista blanca de [entornoSaneado] ya protege a todo lanzador saneado, así
/// que esta enumeración solo gobierna el único sitio que NO sanea —la
/// excepción declarada de `vcs`— y la fuente que las lee.
const clavesDeCredencial = {'SHIPFLOW_GITHUB_TOKEN'};

/// El entorno del proceso, capturado una vez en la raíz de composición.
///
/// **Existe para que la credencial salga del mapa en UN solo sitio.** La
/// alternativa —excluirla en cada lanzamiento— es la lista negra otra vez:
/// promete solo sobre lo que alguien se acordó de enumerar, en cada llamada.
///
/// Lo que se inyecta hacia abajo es [paraHijos], y es un **derivado**: con un
/// campo asignable se construye un entorno «para hijos» que todavía lleva el
/// token, igual que con dos campos independientes se construye un artefacto no
/// concluyente marcado como completo.
///
/// **No expone el mapa crudo.** Un getter que lo devolviera volvería inútil
/// todo lo anterior, porque el llamador de al lado lo usaría por comodidad.
class EntornoDelProceso {
  final Map<String, String> _crudo;

  EntornoDelProceso(Map<String, String> crudo)
    : _crudo = Map.unmodifiable(Map<String, String>.of(crudo));

  /// El entorno con el que se lanza cualquier hijo. **Nunca lleva credencial.**
  Map<String, String> get paraHijos => Map.unmodifiable({
    for (final e in _crudo.entries)
      if (!clavesDeCredencial.contains(e.key)) e.key: e.value,
  });

  /// La credencial de [clave], opaca. Nula si no está o está vacía: las dos
  /// cosas significan lo mismo —no hay con qué autenticarse— y distinguirlas
  /// obligaría a cada llamador a tratar dos casos que tienen una sola salida.
  ///
  /// Pedir una clave que no está en [clavesDeCredencial] **falla**: si
  /// devolviera el valor, este método sería un lector del entorno crudo con
  /// otro nombre.
  Credential? credencial(String clave) {
    if (!clavesDeCredencial.contains(clave)) {
      throw ArgumentError.value(
        clave,
        'clave',
        'No está declarada en `clavesDeCredencial`. Este método no es un '
            'lector del entorno: solo entrega lo que el repositorio declaró '
            'secreto.',
      );
    }
    final valor = _crudo[clave];
    if (valor == null || valor.isEmpty) return null;
    return Credential(valor, label: clave);
  }
}
