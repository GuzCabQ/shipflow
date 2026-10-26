import 'dart:convert';

/// [value] como JSON canónico compacto en UTF-8, sin salto final: claves
/// en orden ordinal de unidades UTF-16, listas de objetos por `id`, si no
/// por `path`, si no por "", y después por los bytes de su forma canónica;
/// listas de textos en orden ordinal. Escapes mínimos, sin `/` escapado.
List<int> canonicalJson(Object? value) => utf8.encode(_encode(_order(value)));

String _encode(Object? value) => jsonEncode(value);

Object? _order(Object? value) => switch (value) {
  Map<String, Object?>() => {
    for (final key in value.keys.toList()..sort()) key: _order(value[key]),
  },
  List<Object?>() => _orderedList(value),
  _ => value,
};

List<Object?> _orderedList(List<Object?> list) {
  final ordered = [for (final item in list) _order(item)];
  final keyed =
      [
        for (final item in ordered)
          (item, _primary(item), utf8.encode(_encode(item))),
      ]..sort((a, b) {
        final primary = a.$2.compareTo(b.$2);
        return primary != 0 ? primary : _compareBytes(a.$3, b.$3);
      });
  return [for (final (item, _, _) in keyed) item];
}

/// La clave principal de orden de un elemento.
String _primary(Object? item) => switch (item) {
  Map<String, Object?>() =>
    (item.containsKey('id') ? item['id'] : item['path']) as String? ?? '',
  String() => item,
  _ => '',
};

int _compareBytes(List<int> a, List<int> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}
