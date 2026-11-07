import 'dart:convert';

import 'package:crypto/crypto.dart';

/// [value] en la forma canónica basis-v1, en UTF-8 sin BOM ni salto final:
/// claves de objeto en orden de unidades UTF-16, listas en su orden,
/// enteros decimales y los escapes mínimos de JSON. A diferencia del
/// canónico de contexto, nunca reordena una lista.
List<int> canonicalBasisJson(Object? value) => utf8.encode(_encode(value));

String _encode(Object? value) => switch (value) {
  Map<String, Object?>() => _object(value),
  List<Object?>() => '[${value.map(_encode).join(',')}]',
  _ => jsonEncode(value),
};

String _object(Map<String, Object?> value) {
  final keys = value.keys.toList()..sort();
  return '{${[for (final k in keys) '${jsonEncode(k)}:${_encode(value[k])}'].join(',')}}';
}

/// `sha256:<hex>` de la forma canónica de [value].
String basisDigest(Object? value) =>
    'sha256:${sha256.convert(canonicalBasisJson(value))}';

/// La huella que sella [json] excluyendo sólo su propio campo [field].
String sealedDigest(Map<String, Object?> json, String field) =>
    basisDigest({...json}..remove(field));

/// `sha256:<hex>` de bytes tal cual están en disco.
String bytesDigest(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';
