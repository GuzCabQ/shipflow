import 'package:core/core.dart';

import '../context/context_shape.dart';

/// Los lectores de forma de los schemas V3 congelados: documento,
/// respuesta y journal comparten las definiciones del snapshot. Cada fallo
/// es de la capa schema y lleva un puntero, nunca el valor leído.
const _maxText = 4096;
const _maxId = 128;
const _coverages = {'complete', 'partial', 'failed'};

Set<String> _names<T extends Enum>(List<T> values, String Function(T) name) =>
    wireNames(values, name);

String _id(Object? value, String at) =>
    shapeText(value, at, min: 1, max: _maxId);

String? _nullableId(Object? value, String at) =>
    value == null ? null : _id(value, at);

String _path(Object? value, String at, {bool root = false}) => shapeText(
  value,
  at,
  max: _maxText,
  valid: (p) => isAssessmentPath(p, allowRoot: root),
);

String? _nullableText(Object? value, String at) =>
    value == null ? null : shapeText(value, at, max: _maxText);

/// La forma de `shipflow/assessment.json`.
void shapeAssessmentDocument(Object? value) {
  final json = shapeObject(value, '', {
    'schemaVersion',
    'kind',
    'projectId',
    'revision',
    'current',
    'previous',
  });
  shapeConstant(json['schemaVersion'], 1, '/schemaVersion');
  shapeConstant(json['kind'], assessmentKind, '/kind');
  shapeUuid(json['projectId'], '/projectId');
  shapeInteger(json['revision'], '/revision', min: 1);
  shapeSnapshot(json['current'], '/current');
  if (json['previous'] != null) shapeSnapshot(json['previous'], '/previous');
}

const _snapshotKeys = {
  'snapshotId',
  'observedAt',
  'producer',
  'contextDigest',
  'profile',
  'coverage',
  'inventoryComplete',
  'units',
  'inputs',
  'files',
  'claims',
  'witnesses',
  'contextLinks',
  'diagnostics',
};

/// Cada colección del snapshot, su máximo y el lector de sus elementos.
const _collections = <(String, int, void Function(Object?, String))>[
  ('units', 4096, _unit),
  ('inputs', 400000, _input),
  ('files', 16384, _file),
  ('claims', 131072, _claim),
  ('witnesses', 5, _witness),
  ('contextLinks', 18432, _link),
  ('diagnostics', 256, shapeAssessmentDiagnostic),
];

/// La forma de `$defs/snapshot`.
void shapeSnapshot(Object? value, String at) {
  final json = shapeObject(value, at, _snapshotKeys);
  shapeSha256(json['snapshotId'], '$at/snapshotId');
  shapeTimestamp(json['observedAt'], '$at/observedAt');
  _producer(json['producer'], '$at/producer');
  shapeSha256(json['contextDigest'], '$at/contextDigest');
  shapeMember(json['profile'], {'standard', 'extended'}, '$at/profile');
  shapeMember(json['coverage'], _coverages, '$at/coverage');
  shapeBoolean(json['inventoryComplete'], '$at/inventoryComplete');
  for (final (key, max, item) in _collections) {
    shapeList(json[key], '$at/$key', item: item, max: max);
  }
}

void _producer(Object? value, String at) {
  final json = shapeObject(value, at, {
    'version',
    'contract',
    'pluginId',
    'parserVersion',
  });
  for (final key in json.keys) {
    _id(json[key], '$at/$key');
  }
}

void _unit(Object? value, String at) {
  final json = shapeObject(value, at, {'id', 'path', 'label'});
  _id(json['id'], '$at/id');
  _path(json['path'], '$at/path', root: true);
  shapeText(json['label'], '$at/label', max: _maxText);
}

void _input(Object? value, String at) {
  final json = shapeObject(value, at, {
    'path',
    'kind',
    'state',
    'sha256',
    'reason',
  });
  _path(json['path'], '$at/path', root: true);
  shapeMember(
    json['kind'],
    _names(AssessmentInputKind.values, (k) => k.toWireName()),
    '$at/kind',
  );
  shapeMember(
    json['state'],
    _names(AssessmentInputState.values, (s) => s.toWireName()),
    '$at/state',
  );
  shapeNullableSha256(json['sha256'], '$at/sha256');
  _nullableId(json['reason'], '$at/reason');
}

void _file(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'path',
    'unitId',
    'inputPath',
    'role',
    'parseState',
    'witnessId',
    'editable',
  });
  for (final key in ['id', 'unitId', 'witnessId']) {
    _id(json[key], '$at/$key');
  }
  _path(json['path'], '$at/path');
  _path(json['inputPath'], '$at/inputPath');
  shapeMember(json['role'], {'source', 'test'}, '$at/role');
  shapeMember(json['parseState'], {
    'parsed',
    'failed',
    'not_run',
  }, '$at/parseState');
  shapeConstant(json['editable'], 'unknown', '$at/editable');
}

const _claimKeys = {
  'id',
  'witnessId',
  'sourceFileId',
  'targetFileId',
  'targetUnitId',
  'targetLabel',
  'relation',
  'resolution',
  'reason',
  'condition',
  'groupId',
  'evidence',
  'sourceMetadata',
};

void _claim(Object? value, String at) {
  final json = shapeObject(value, at, _claimKeys);
  for (final key in ['id', 'witnessId', 'sourceFileId', 'groupId']) {
    _id(json[key], '$at/$key');
  }
  for (final key in ['targetFileId', 'targetUnitId', 'reason']) {
    _nullableId(json[key], '$at/$key');
  }
  _nullableText(json['targetLabel'], '$at/targetLabel');
  shapeMember(json['relation'], {
    'source_reference',
    'source_attachment',
  }, '$at/relation');
  shapeMember(json['resolution'], {
    'local',
    'external',
    'unresolved',
  }, '$at/resolution');
  shapeMember(json['condition'], {
    'always',
    'conditional',
    'fallback',
    'unknown',
  }, '$at/condition');
  _evidence(json['evidence'], '$at/evidence');
  _metadata(json['sourceMetadata'], '$at/sourceMetadata');
}

void _evidence(Object? value, String at) {
  final json = shapeObject(value, at, {'offset', 'length', 'line', 'column'});
  shapeInteger(json['offset'], '$at/offset', min: 0);
  for (final key in ['length', 'line', 'column']) {
    shapeInteger(json[key], '$at/$key', min: 1);
  }
}

void _metadata(Object? value, String at) {
  final json = shapeObject(value, at, {'directive', 'conditionText'});
  _id(json['directive'], '$at/directive');
  _nullableText(json['conditionText'], '$at/conditionText');
}

void _witness(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'capability',
    'producerVersion',
    'state',
    'expected',
    'processed',
    'failed',
    'omitted',
  });
  _id(json['id'], '$at/id');
  _id(json['producerVersion'], '$at/producerVersion');
  shapeMember(
    json['capability'],
    _names(AssessmentCapability.values, (c) => c.toWireName()),
    '$at/capability',
  );
  shapeMember(json['state'], {
    'complete',
    'partial',
    'failed',
    'not_run',
  }, '$at/state');
  for (final key in ['expected', 'processed', 'failed', 'omitted']) {
    shapeInteger(json[key], '$at/$key', min: 0);
  }
}

void _link(Object? value, String at) {
  final json = shapeObject(value, at, {
    'kind',
    'sourceId',
    'sourcePath',
    'label',
    'targetUnitId',
  });
  shapeMember(json['kind'], {
    'declared_dependency',
    'candidate_source',
  }, '$at/kind');
  _id(json['sourceId'], '$at/sourceId');
  _path(json['sourcePath'], '$at/sourcePath');
  shapeText(json['label'], '$at/label', max: _maxText);
  _nullableId(json['targetUnitId'], '$at/targetUnitId');
}

/// La forma de `$defs/diagnostic`, también usada por la respuesta.
void shapeAssessmentDiagnostic(Object? value, String at) {
  final json = shapeObject(value, at, {
    'code',
    'path',
    'consequence',
    'actionCode',
    'count',
    'examples',
  });
  for (final key in ['code', 'consequence', 'actionCode']) {
    _id(json[key], '$at/$key');
  }
  if (json['path'] != null) _path(json['path'], '$at/path');
  shapeInteger(json['count'], '$at/count', min: 1);
  shapeList(
    json['examples'],
    '$at/examples',
    item: (path, at) => _path(path, at),
    max: 5,
  );
}
