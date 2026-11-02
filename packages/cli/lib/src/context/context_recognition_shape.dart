import 'package:core/core.dart';

import 'context_shape.dart';

/// El techo de elementos de cada colección del reconocimiento.
const maxRecognitionItems = 18432;

const _scopedKeys = {
  'status',
  'recognitionScope',
  'candidates',
  'units',
  'evidence',
  'conflicts',
  'limitations',
  'relations',
  'contextSources',
  'omissions',
};

// Los nombres de cable de core, fijados por sus pruebas de contrato, son
// los mismos enums del schema congelado.
final _roles = wireNames(EvidenceRole.values, (r) => r.toWireName());
final _relationKinds = wireNames(RelationKind.values, (k) => k.toWireName());
final _relationStatuses = wireNames(
  RelationStatus.values,
  (s) => s.toWireName(),
);
final _sourceKinds = wireNames(ContextSourceKind.values, (k) => k.toWireName());
final _entityTypes = wireNames(ContextEntityType.values, (t) => t.toWireName());
final _reasons = wireNames(ContextReason.values, (r) => r.toWireName());
final _rules = wireNames(OmissionRule.values, (r) => r.toWireName());

/// La forma de `$defs/recognition`: el subconjunto portable guardado.
void shapeRecognition(Object? value, String at) {
  final json = shapeObject(value, at, _scopedKeys);
  shapeConstant(json['status'], 'recognized', '$at/status');
  shapeScopedLists(json, at);
}

/// Las claves de un reconocimiento, para los schemas que lo extienden.
Set<String> get scopedRecognitionKeys => _scopedKeys;

/// El alcance y las ocho colecciones, comunes a recognition y dryRun.
void shapeScopedLists(Map<String, Object?> json, String at) {
  shapeConstant(
    json['recognitionScope'],
    'declared_project_recognition',
    '$at/recognitionScope',
  );
  for (final (key, item) in [
    ('candidates', _candidate),
    ('units', _unit),
    ('evidence', _evidence),
    ('conflicts', _conflict),
    ('limitations', _limitation),
    ('relations', _relation),
    ('contextSources', _source),
    ('omissions', _omission),
  ]) {
    shapeList(json[key], '$at/$key', item: item, max: maxRecognitionItems);
  }
}

void _candidate(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'displayName',
    'pluginId',
    'evidenceIds',
  });
  shapeText(json['id'], '$at/id', min: 1);
  shapeText(json['displayName'], '$at/displayName');
  shapeText(json['pluginId'], '$at/pluginId', min: 1, max: 256);
  shapeIds(json['evidenceIds'], '$at/evidenceIds');
}

void _unit(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'name',
    'kind',
    'path',
    'evidenceIds',
  });
  for (final key in ['id', 'name', 'kind']) {
    shapeText(json[key], '$at/$key', min: 1);
  }
  shapeLocation(json['path'], '$at/path');
  shapeIds(json['evidenceIds'], '$at/evidenceIds');
}

void _evidence(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'kind',
    'role',
    'label',
    'path',
    'value',
    'fingerprint',
  });
  for (final key in ['id', 'kind', 'fingerprint']) {
    shapeText(json[key], '$at/$key', min: 1);
  }
  shapeMember(json['role'], _roles, '$at/role');
  shapeText(json['label'], '$at/label');
  shapeLocation(json['path'], '$at/path');
  shapeText(json['value'], '$at/value');
}

void _conflict(Object? value, String at) {
  final json = shapeObject(value, at, {'code', 'message', 'evidenceIds'});
  shapeText(json['code'], '$at/code', min: 1);
  shapeText(json['message'], '$at/message');
  shapeIds(json['evidenceIds'], '$at/evidenceIds');
}

void _limitation(Object? value, String at) {
  final json = shapeObject(value, at, {'code', 'message', 'path', 'blocking'});
  shapeText(json['code'], '$at/code', min: 1);
  shapeText(json['message'], '$at/message');
  shapeNullableLocation(json['path'], '$at/path');
  shapeBoolean(json['blocking'], '$at/blocking');
}

void _relation(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'kind',
    'fromPath',
    'declaredName',
    'targetPath',
    'targetUnitId',
    'status',
    'evidenceIds',
  });
  shapeText(json['id'], '$at/id', min: 1);
  shapeMember(json['kind'], _relationKinds, '$at/kind');
  shapeLocation(json['fromPath'], '$at/fromPath');
  shapeNullableText(json['declaredName'], '$at/declaredName');
  _relationTarget(json, at);
  shapeIds(json['evidenceIds'], '$at/evidenceIds');
}

/// Una relación corroborada nombra su ruta y su unidad de destino.
void _relationTarget(Map<String, Object?> json, String at) {
  final target = shapeNullableLocation(json['targetPath'], '$at/targetPath');
  final unit = shapeNullableText(
    json['targetUnitId'],
    '$at/targetUnitId',
    min: 1,
  );
  final status = shapeMember(json['status'], _relationStatuses, '$at/status');
  if (status == 'corroborated' && (target == null || unit == null)) {
    throw shapeError('corroborated_target', at);
  }
}

void _source(Object? value, String at) {
  final json = shapeObject(value, at, {
    'scopePath',
    'path',
    'kind',
    'entityType',
    'reason',
    'contentStatus',
  });
  shapeLocation(json['scopePath'], '$at/scopePath');
  shapeLocation(json['path'], '$at/path');
  shapeMember(json['kind'], _sourceKinds, '$at/kind');
  final type = shapeMember(json['entityType'], _entityTypes, '$at/entityType');
  final reason = shapeMember(json['reason'], _reasons, '$at/reason');
  if (!_consistentSource(type, reason)) throw shapeError('source_reason', at);
  shapeConstant(json['contentStatus'], 'not_inspected', '$at/contentStatus');
}

bool _consistentSource(String type, String reason) => switch (reason) {
  'observed' => const {'file', 'directory', 'link', 'special'}.contains(type),
  'not_found' => type == 'missing',
  _ => type == 'unavailable',
};

void _omission(Object? value, String at) {
  final json = shapeObject(value, at, {'path', 'rule', 'evidenceIds'});
  final path = shapeLocation(json['path'], '$at/path');
  final rule = shapeMember(json['rule'], _rules, '$at/rule');
  shapeIds(json['evidenceIds'], '$at/evidenceIds');
  final evidence = json['evidenceIds']! as List<Object?>;
  final valid = switch (rule) {
    'tool_state' => path == 'shipflow' && evidence.isEmpty,
    'temporary_directory' || 'declared_resource' => evidence.isNotEmpty,
    _ => true,
  };
  if (!valid) throw shapeError('omission_rule', at);
}
