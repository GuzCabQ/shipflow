import 'package:core/core.dart';

import '../context/context_shape.dart';
import 'basis_document_shape.dart';
import 'basis_shape.dart';

/// La forma de `$defs/response`: lo que bootstrap emite y lo que un
/// consumidor puede validar antes de usarlo.
void _nonEmpty(Object? value, String at) => shapeText(value, at, min: 1);

Set<String> _names<T>(List<T> values, String Function(T) name) =>
    wireNames(values, name);

void _diagnostic(Object? value, String at) {
  final json = shapeObject(value, at, const {'code', 'message', 'path'});
  _nonEmpty(json['code'], '$at/code');
  _nonEmpty(json['message'], '$at/message');
  if (json['path'] != null) _nonEmpty(json['path'], '$at/path');
}

void _sourceStatus(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'sourceId',
    'sourceVersion',
    'status',
    'diagnostics',
  });
  shapeUuid(json['sourceId'], '$at/sourceId');
  shapeInteger(json['sourceVersion'], '$at/sourceVersion', min: 1);
  shapeMember(
    json['status'],
    _names(BasisSourceState.values, (v) => v.toWireName()),
    '$at/status',
  );
  shapeList(json['diagnostics'], '$at/diagnostics', item: _diagnostic);
}

void _action(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'command',
    'arguments',
    'purpose',
    'effect',
  });
  _nonEmpty(json['command'], '$at/command');
  shapeList(json['arguments'], '$at/arguments', item: _nonEmpty);
  _nonEmpty(json['purpose'], '$at/purpose');
  shapeMember(
    json['effect'],
    _names(BasisActionEffect.values, (v) => v.toWireName()),
    '$at/effect',
  );
}

void _integrity(Object? value, String at) {
  final json = shapeObject(value, at, const {'basis', 'draft', 'transaction'});
  final allowed = _names(BasisIntegrity.values, (v) => v.toWireName());
  for (final key in json.keys) {
    shapeMember(json[key], allowed, '$at/$key');
  }
}

void _selection(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'scope',
    'complete',
    'excludedCount',
  });
  if (json['scope'] != null) shapeBasisScope(json['scope'], '$at/scope');
  shapeBoolean(json['complete'], '$at/complete');
  shapeInteger(json['excludedCount'], '$at/excludedCount', min: 0);
}

const _responseKeys = {
  'schemaVersion',
  'type',
  'operation',
  'exitCode',
  'outcome',
  'storageIntegrity',
  'basisDigest',
  'draftDigest',
  'published',
  'changedFiles',
  'normativeCoverage',
  'selected',
  'reviewTargets',
  'pending',
  'sourceStatus',
  'actor',
  'reason',
  'history',
  'selection',
  'diagnostics',
  'nextActions',
};

void shapeBasisResponse(Object? value) {
  final json = shapeObject(value, '', _responseKeys);
  _status(json);
  _integrity(json['storageIntegrity'], 'storageIntegrity');
  shapeNullableDigest(json['basisDigest'], 'basisDigest');
  shapeNullableDigest(json['draftDigest'], 'draftDigest');
  shapeBoolean(json['published'], 'published');
  shapeList(json['changedFiles'], 'changedFiles', item: _nonEmpty);
  shapeMember(
    json['normativeCoverage'],
    _names(BasisCoverage.values, (v) => v.toWireName()),
    'normativeCoverage',
  );
  _records(json);
  if (json['actor'] != null) shapeBasisActor(json['actor'], 'actor');
  if (json['reason'] != null) _nonEmpty(json['reason'], 'reason');
  shapeList(json['history'], 'history', item: shapeBasisEvent);
  _selection(json['selection'], 'selection');
  shapeList(json['diagnostics'], 'diagnostics', item: _diagnostic);
  shapeList(json['nextActions'], 'nextActions', item: _action);
}

const _exitCodes = {'0', '64', '65', '66', '70', '74', '75', '130'};

/// Versión, tipo, operación, código y desenlace.
void _status(Map<String, Object?> json) {
  shapeConstant(json['schemaVersion'], 1, 'schemaVersion');
  shapeConstant(json['type'], 'bootstrap', 'type');
  shapeMember(
    json['operation'],
    _names(BasisOperation.values, (v) => v.toWireName()),
    'operation',
  );
  shapeInteger(json['exitCode'], 'exitCode');
  shapeMember('${json['exitCode']}', _exitCodes, 'exitCode');
  shapeMember(
    json['outcome'],
    _names(BasisOutcome.values, (v) => v.toWireName()),
    'outcome',
  );
}

void _records(Map<String, Object?> json) {
  for (final key in const ['selected', 'reviewTargets', 'pending']) {
    shapeList(json[key], key, item: shapeBasisVersion);
  }
  shapeList(json['sourceStatus'], 'sourceStatus', item: _sourceStatus);
}
