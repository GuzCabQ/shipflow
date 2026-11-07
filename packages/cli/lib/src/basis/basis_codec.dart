import 'dart:convert';

import 'package:core/core.dart';

import '../context/strict_json.dart';
import 'basis_canonical.dart';
import 'basis_document_shape.dart';
import 'basis_response_shape.dart';

/// Los lectores y escritores de los documentos de bootstrap. Cada lector
/// cobra los bytes antes de interpretar, exige JSON estricto, comprueba la
/// versión mayor antes de consumir, valida la forma, verifica las huellas
/// y después las reglas de core. Cada rechazo lleva un código del catálogo.
BasisDocument decodeBasis(List<int> bytes, {required BasisLimits limits}) =>
    _decode(() {
      final json = _json(bytes, limits.maxBasisBytes);
      shapeBasisDocument(json);
      _sealed(json, 'digest');
      for (final event in json['events']! as List<Object?>) {
        _sealed(event! as Map<String, Object?>, 'eventDigest');
      }
      final document = BasisDocument.fromJson(json);
      requireBasisWithin(replayBasisLedger(document), limits);
      return document;
    });

BasisInput decodeBasisInput(List<int> bytes, {required BasisLimits limits}) =>
    _decode(() {
      final json = _json(bytes, limits.maxDraftBytes);
      shapeBasisInput(json);
      final input = BasisInput.fromJson(json);
      _changes(input.changes.length, limits);
      validateBasisInput(input);
      return input;
    });

BasisDraft decodeBasisDraft(List<int> bytes, {required BasisLimits limits}) =>
    _decode(() {
      final json = _json(bytes, limits.maxDraftBytes);
      shapeBasisDraft(json);
      _sealed(json, 'digest');
      final draft = BasisDraft.fromJson(json);
      _changes(draft.preparedChanges.length, limits);
      validateBasisDraft(draft);
      return draft;
    });

BasisTransaction decodeBasisTransaction(
  List<int> bytes, {
  required BasisLimits limits,
}) => _decode(() {
  final json = _json(bytes, limits.maxDraftBytes);
  shapeBasisTransaction(json);
  _sealed(json, 'digest');
  final transaction = BasisTransaction.fromJson(json);
  validateBasisTransaction(transaction);
  return transaction;
});

BasisResponse decodeBasisResponse(
  List<int> bytes, {
  required BasisLimits limits,
}) => _decode(() {
  final json = _json(bytes, limits.maxResponseBytes);
  shapeBasisResponse(json);
  final response = BasisResponse.fromJson(json);
  validateBasisResponse(response);
  return response;
});

/// Los bytes de disco: JSON legible con dos espacios y salto final. La
/// huella se calcula sobre la forma canónica, no sobre estos bytes.
List<int> encodeBasis(BasisDocument value) => _pretty(value.toJson());

List<int> encodeBasisInput(BasisInput value) => _pretty(value.toJson());

List<int> encodeBasisDraft(BasisDraft value) => _pretty(value.toJson());

List<int> encodeBasisTransaction(BasisTransaction value) =>
    _pretty(value.toJson());

List<int> encodeBasisResponse(BasisResponse value) =>
    utf8.encode('${jsonEncode(value.toJson())}\n');

List<int> _pretty(Map<String, Object?> json) =>
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(json)}\n');

/// [read] con cada rechazo traducido al catálogo: el parser y la forma son
/// `invalid_schema` (salvo el exceso de bytes); lo semántico ya lo es.
T _decode<T>(T Function() read) {
  try {
    return read();
  } on ContextFormatException catch (e) {
    throw ContextFormatException(e.layer, _catalog(e), e.at);
  } on TypeError {
    throw const ContextFormatException(
      ContextFormatLayer.schema,
      'invalid_schema',
    );
  } on ArgumentError {
    throw const ContextFormatException(
      ContextFormatLayer.schema,
      'invalid_schema',
    );
  }
}

String _catalog(ContextFormatException e) => switch (e.layer) {
  ContextFormatLayer.semantic => e.code,
  ContextFormatLayer.parser =>
    e.code == 'too_large' ? 'budget_exceeded' : 'invalid_schema',
  ContextFormatLayer.schema => 'invalid_schema',
};

/// JSON estricto dentro de [maxBytes] y, si declara otra versión mayor,
/// `incompatible_version` antes de mirar su forma.
Map<String, Object?> _json(List<int> bytes, int maxBytes) {
  final json = decodeStrictJson(
    bytes,
    maxBytes: maxBytes,
    maxDepth: maxBasisJsonDepth,
  );
  if (json is Map<String, Object?>) {
    final version = json['schemaVersion'];
    requireBasis(
      version is! int || version == 1,
      'incompatible_version',
      'schemaVersion',
    );
    return json;
  }
  throw const ContextFormatException(ContextFormatLayer.schema, 'type');
}

void _sealed(Map<String, Object?> json, String field) => requireBasis(
  json[field] == sealedDigest(json, field),
  'digest_mismatch',
  field,
);

void _changes(int count, BasisLimits limits) =>
    requireBasis(count <= limits.maxChanges, 'budget_exceeded', 'changes');
