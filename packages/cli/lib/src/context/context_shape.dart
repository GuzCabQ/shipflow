import 'package:core/core.dart';

/// Los lectores de forma de los schemas V2 congelados. Cada fallo es de la
/// capa schema y lleva un puntero con nombres del schema, nunca el valor.
///
/// Replican sólo lo que esos schemas usan: objetos cerrados con todas sus
/// claves obligatorias, tipos, `const`, `enum`, longitudes en caracteres,
/// rangos, patrones de ruta y de huella, y `uniqueItems`.
ContextFormatException shapeError(String code, String at) =>
    ContextFormatException(ContextFormatLayer.schema, code, at);

/// [value] como objeto con exactamente las claves [keys].
Map<String, Object?> shapeObject(Object? value, String at, Set<String> keys) {
  if (value is! Map<String, Object?>) throw shapeError('type', at);
  for (final key in value.keys) {
    if (!keys.contains(key)) throw shapeError('unknown_field', at);
  }
  for (final key in keys) {
    if (!value.containsKey(key)) throw shapeError('missing_field', '$at/$key');
  }
  return value;
}

/// [value] como texto de [min] a [max] caracteres que cumple [valid].
String shapeText(
  Object? value,
  String at, {
  int min = 0,
  int? max,
  bool Function(String)? valid,
}) {
  if (value is! String) throw shapeError('type', at);
  final length = value.runes.length;
  if (length < min || (max != null && length > max)) {
    throw shapeError('length', at);
  }
  if (valid != null && !valid(value)) throw shapeError('pattern', at);
  return value;
}

/// [value] como texto con las mismas reglas, o null.
String? shapeNullableText(
  Object? value,
  String at, {
  int min = 0,
  bool Function(String)? valid,
}) => value == null ? null : shapeText(value, at, min: min, valid: valid);

int shapeInteger(Object? value, String at, {int? min, int? max}) {
  if (value is! int) throw shapeError('type', at);
  if ((min != null && value < min) || (max != null && value > max)) {
    throw shapeError('range', at);
  }
  return value;
}

bool shapeBoolean(Object? value, String at) =>
    value is bool ? value : throw shapeError('type', at);

void shapeConstant(Object? value, Object expected, String at) {
  if (value != expected || value.runtimeType != expected.runtimeType) {
    throw shapeError('const', at);
  }
}

/// Los nombres de cable de [values].
Set<String> wireNames<T>(List<T> values, String Function(T) name) => {
  for (final value in values) name(value),
};

/// [value] como uno de los textos de [allowed].
String shapeMember(Object? value, Set<String> allowed, String at) {
  if (value is! String) throw shapeError('type', at);
  if (!allowed.contains(value)) throw shapeError('enum', at);
  return value;
}

/// [value] como lista de [min] a [max] elementos, cada uno leído con [item].
List<Object?> shapeList(
  Object? value,
  String at, {
  required void Function(Object? item, String at) item,
  int min = 0,
  int? max,
  bool unique = false,
}) {
  if (value is! List<Object?>) throw shapeError('type', at);
  if (value.length < min || (max != null && value.length > max)) {
    throw shapeError('items', at);
  }
  for (final (index, element) in value.indexed) {
    item(element, '$at/$index');
  }
  if (unique && value.toSet().length != value.length) {
    throw shapeError('unique', at);
  }
  return value;
}

/// Una lista de textos de al menos un carácter: las referencias a IDs.
void shapeIds(Object? value, String at) =>
    shapeList(value, at, item: (id, at) => shapeText(id, at, min: 1));

/// Una lista de textos cualquiera.
void shapeTexts(Object? value, String at) =>
    shapeList(value, at, item: (text, at) => shapeText(text, at));

String shapeLocation(Object? value, String at) =>
    shapeText(value, at, valid: isLocationPath);

String? shapeNullableLocation(Object? value, String at) =>
    shapeNullableText(value, at, valid: isLocationPath);

String shapeUuid(Object? value, String at) =>
    shapeText(value, at, valid: isUuidV4);

String shapeSha256(Object? value, String at) =>
    shapeText(value, at, valid: isSha256Hex);

String? shapeNullableSha256(Object? value, String at) =>
    shapeNullableText(value, at, valid: isSha256Hex);

/// La forma de un instante UTC; que sea una fecha real es semántico.
String shapeTimestamp(Object? value, String at) => shapeText(
  value,
  at,
  valid: RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$',
  ).hasMatch,
);
