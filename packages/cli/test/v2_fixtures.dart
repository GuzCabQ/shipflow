import 'dart:convert';
import 'dart:io';

import 'package:cli/src/context/strict_json.dart';
import 'package:core/core.dart';

import 'init_process_support.dart';

/// El directorio de schemas y fixtures V2, copiados por hash del paquete.
Future<String> v2Root() async => '${(await cliRoot()).path}/test/fixtures/v2';

Future<List<int>> v2Bytes(String relative) async =>
    File('${await v2Root()}/$relative').readAsBytes();

Future<Map<String, Object?>> v2Json(String relative) async =>
    jsonDecode(utf8.decode(await v2Bytes(relative))) as Map<String, Object?>;

/// Cada caso del índice: ruta, schema y capa esperada (`valid` si pasa).
Future<List<({String path, String schema, String layer})>> v2Cases() async {
  final index =
      jsonDecode(utf8.decode(await v2Bytes('fixtures/index.json')))
          as List<Object?>;
  return [
    for (final item in index.cast<Map<String, Object?>>())
      (
        path: (item['path']! as String),
        schema: item['schema']! as String,
        layer: (item['layer'] as String?) ?? 'valid',
      ),
  ];
}

/// [bytes] con el major de respuesta vigente: V4 subió el major de la
/// respuesta contextual (3 → 4) y de la de assess (1 → 2) sin cambiar su
/// forma, sólo ampliando valores. Lo que no es JSON estricto queda igual.
List<int> currentMajor(List<int> bytes, {required int from, required int to}) {
  final Object? json;
  try {
    json = decodeStrictJson(bytes, maxBytes: bytes.length);
  } on ContextFormatException {
    return bytes;
  }
  if (json is! Map<String, Object?> || json['schemaVersion'] != from) {
    return bytes;
  }
  return utf8.encode(jsonEncode({...json, 'schemaVersion': to}));
}
