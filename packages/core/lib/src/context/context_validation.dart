/// En qué capa se rechazó un documento de contexto.
enum ContextFormatLayer {
  /// No es JSON estricto: UTF-8, claves, profundidad o tamaño.
  parser,

  /// No tiene la forma del schema congelado.
  schema,

  /// Tiene la forma, pero contradice una regla que el schema no expresa.
  semantic,
}

/// Un documento de contexto que no se acepta. Sólo lleva un código acotado
/// y la ubicación según los nombres del schema: nunca el contenido leído.
final class ContextFormatException implements Exception {
  const ContextFormatException(this.layer, this.code, [this.at = '']);

  factory ContextFormatException.fromJson(Map<String, Object?> json) =>
      ContextFormatException(
        ContextFormatLayer.values.byName(json['layer']! as String),
        json['code']! as String,
        json['at']! as String,
      );

  final ContextFormatLayer layer;
  final String code;

  /// Puntero a la ubicación, con nombres de campo del schema e índices.
  final String at;

  Map<String, Object?> toJson() => {
    'layer': layer.name,
    'code': code,
    'at': at,
  };

  @override
  String toString() => 'ContextFormatException(${layer.name}, $code, $at)';
}

/// Lanza un rechazo semántico con [code] si no se cumple [condition].
void requireSemantic(bool condition, String code, [String at = '']) {
  if (!condition) {
    throw ContextFormatException(ContextFormatLayer.semantic, code, at);
  }
}

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _hex64 = RegExp(r'^[0-9a-f]{64}$');
final _timestamp = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$',
);

bool isUuidV4(String value) => _uuidV4.hasMatch(value);

bool isSha256Hex(String value) => _hex64.hasMatch(value);

/// Si [value] tiene la forma UTC del schema y nombra un instante real.
bool isUtcTimestamp(String value) {
  final match = _timestamp.firstMatch(value);
  if (match == null) return false;
  final [year, month, day, hour, minute, second] = [
    for (var i = 1; i <= 6; i++) int.parse(match[i]!),
  ];
  if (hour > 23 || minute > 59 || second > 59) return false;
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

/// Una ruta de ubicación relativa a la raíz: `.` o tramos separados por
/// `/`, sin absolutos, unidad, `\`, NUL, `.`, `..`, vacíos ni barra final.
bool isLocationPath(String path) {
  if (path == '.') return true;
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
    return false;
  }
  if (path.contains('\u0000') || RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    return false;
  }
  return path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');
}

/// Si [text] es UTF-16 bien formado: ningún sustituto suelto.
bool isWellFormedText(String text) {
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xDC00 && unit <= 0xDFFF) return false;
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= units.length) return false;
      final next = units[i + 1];
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    }
  }
  return true;
}
