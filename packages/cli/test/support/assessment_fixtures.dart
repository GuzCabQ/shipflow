import 'dart:convert';
import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import '../init_process_support.dart';

/// Los schemas y fixtures V3, copiados byte a byte del paquete revisión 2.
Future<String> v3Root() async => '${(await cliRoot()).path}/test/fixtures/v3';

Future<List<int>> v3Bytes(String name) async =>
    File('${await v3Root()}/$name').readAsBytes();

Future<Object?> v3Json(String name) async =>
    jsonDecode(utf8.decode(await v3Bytes(name)));

/// Un documento del paquete, leído por el codec del producto.
Future<AssessmentDocument> loadAssessmentFixture(String name) async =>
    decodeAssessment(await v3Bytes(name));

/// Rechaza con [code] en la capa [layer].
Matcher rejectsAssessment(String code, [ContextFormatLayer? layer]) => throwsA(
  isA<ContextFormatException>()
      .having((e) => e.code, 'code', code)
      .having((e) => layer == null || e.layer == layer, 'layer', isTrue),
);
