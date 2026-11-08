/// El parser de YAML es recursivo y agota la pila con unos miles de niveles,
/// de flujo o de bloque. Antes de parsear se acotan ambos: los corchetes y
/// llaves abiertos, y el prefijo estructural de cada línea (sangría más
/// indicadores `- ` y `? `), que crece al menos uno por nivel de bloque.
const maxYamlNesting = 64;

/// Si [text] anida más de [maxYamlNesting] niveles de flujo, o su prefijo
/// estructural más ancho pasa del doble: entonces no se parsea.
bool nestsTooDeep(String text) =>
    _flowNesting(text) > maxYamlNesting ||
    _blockPrefix(text) > 2 * maxYamlNesting;

/// La mayor profundidad de `[` y `{`, contando también los que estén dentro
/// de cadenas: sobreestimar sólo convierte un manifiesto raro en limitación.
int _flowNesting(String text) {
  var depth = 0;
  var deepest = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0x5B || unit == 0x7B) {
      depth++;
      if (depth > deepest) deepest = depth;
    } else if ((unit == 0x5D || unit == 0x7D) && depth > 0) {
      depth--;
    }
  }
  return deepest;
}

/// El mayor prefijo estructural de una línea: su sangría más dos por cada
/// indicador `- ` o `? ` que la abre.
int _blockPrefix(String text) {
  var widest = 0;
  for (final line in text.split('\n')) {
    var index = 0;
    while (index < line.length && (line[index] == ' ' || line[index] == '\t')) {
      index++;
    }
    var prefix = index;
    while (index + 1 < line.length &&
        (line[index] == '-' || line[index] == '?') &&
        (line[index + 1] == ' ' || line[index + 1] == '\t')) {
      index += 2;
      prefix += 2;
      while (index < line.length && line[index] == ' ') {
        index++;
      }
    }
    if (prefix > widest) widest = prefix;
  }
  return widest;
}
