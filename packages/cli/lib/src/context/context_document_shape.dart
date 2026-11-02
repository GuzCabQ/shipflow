import 'package:core/core.dart';

import 'context_recognition_shape.dart';
import 'context_shape.dart';

final _choices = wireNames(SharingChoice.values, (c) => c.toWireName());

/// La forma de `$defs/project`: `shipflow/project.json`.
void shapeProject(Object? value) {
  final json = shapeObject(value, '', {
    'schemaVersion',
    'kind',
    'projectId',
    'root',
    'revision',
    'producer',
    'observedAt',
    'recognition',
    'observationDigest',
  });
  shapeConstant(json['schemaVersion'], 1, '/schemaVersion');
  shapeConstant(json['kind'], 'shipflow.project-context', '/kind');
  shapeUuid(json['projectId'], '/projectId');
  shapeConstant(json['root'], '.', '/root');
  shapeInteger(json['revision'], '/revision', min: 1);
  _producer(json['producer']);
  shapeTimestamp(json['observedAt'], '/observedAt');
  shapeRecognition(json['recognition'], '/recognition');
  shapeSha256(json['observationDigest'], '/observationDigest');
}

void _producer(Object? value) {
  final json = shapeObject(value, '/producer', {
    'version',
    'recognitionContract',
    'pluginIds',
  });
  for (final key in ['version', 'recognitionContract']) {
    shapeText(json[key], '/producer/$key', min: 1, max: 256);
  }
  shapeList(
    json['pluginIds'],
    '/producer/pluginIds',
    item: (id, at) => shapeText(id, at, min: 1, max: 256),
    min: 1,
    unique: true,
  );
}

/// La forma de `$defs/settings`: `shipflow/local/settings.json`.
void shapeSettings(Object? value) {
  final json = shapeObject(value, '', {
    'schemaVersion',
    'projectId',
    'choice',
    'binding',
    'applied',
    'managedExclude',
  });
  shapeConstant(json['schemaVersion'], 1, '/schemaVersion');
  shapeUuid(json['projectId'], '/projectId');
  final choice = shapeMember(json['choice'], _choices, '/choice');
  if (json['binding'] != null) _binding(json['binding']);
  final applied = shapeBoolean(json['applied'], '/applied');
  final exclude = json['managedExclude'];
  if (exclude != null) _managedExclude(exclude);
  if (choice == 'pending' && (applied || exclude != null)) {
    throw shapeError('pending_applied', '');
  }
  if (choice == 'local' &&
      applied &&
      (json['binding'] == null || exclude == null)) {
    throw shapeError('local_applied', '');
  }
}

void _binding(Object? value) {
  final json = shapeObject(value, '/binding', {
    'repositoryRoot',
    'gitDir',
    'commonDir',
    'prefix',
  });
  for (final key in ['repositoryRoot', 'gitDir', 'commonDir']) {
    shapeText(json[key], '/binding/$key', min: 1);
  }
  shapeText(json['prefix'], '/binding/prefix');
}

void _managedExclude(Object? value) {
  final json = shapeObject(value, '/managedExclude', {
    'path',
    'blockId',
    'sha256',
  });
  shapeText(json['path'], '/managedExclude/path', min: 1);
  for (final key in ['blockId', 'sha256']) {
    shapeSha256(json[key], '/managedExclude/$key');
  }
}

/// La forma de `$defs/journal`: `shipflow/local/transaction.json`.
void shapeTransaction(Object? value) {
  final json = shapeObject(value, '', {
    'schemaVersion',
    'operationId',
    'projectId',
    'operation',
    'choice',
    'phase',
    'targets',
    'staging',
    'exclude',
  });
  shapeConstant(json['schemaVersion'], 1, '/schemaVersion');
  shapeUuid(json['operationId'], '/operationId');
  shapeUuid(json['projectId'], '/projectId');
  shapeMember(
    json['operation'],
    wireNames(TransactionOperation.values, (o) => o.toWireName()),
    '/operation',
  );
  shapeMember(json['choice'], _choices, '/choice');
  shapeMember(
    json['phase'],
    wireNames(TransactionPhase.values, (p) => p.toWireName()),
    '/phase',
  );
  shapeList(json['targets'], '/targets', item: _target, min: 1, max: 3);
  _staging(json['staging']);
  _exclude(json['exclude']);
}

void _target(Object? value, String at) {
  final json = shapeObject(value, at, {'resource', 'before', 'after'});
  shapeMember(
    json['resource'],
    wireNames(TransactionResource.values, (r) => r.toWireName()),
    '$at/resource',
  );
  shapeNullableSha256(json['before'], '$at/before');
  shapeNullableSha256(json['after'], '$at/after');
}

void _staging(Object? value) {
  const keys = {'project', 'settingsBefore', 'settingsAfter'};
  final json = shapeObject(value, '/staging', keys);
  for (final key in keys) {
    shapeNullableLocation(json[key], '/staging/$key');
  }
}

void _exclude(Object? value) {
  final json = shapeObject(value, '/exclude', {
    'blockId',
    'beforeBlock',
    'afterBlock',
  });
  shapeNullableSha256(json['blockId'], '/exclude/blockId');
  shapeNullableText(json['beforeBlock'], '/exclude/beforeBlock');
  shapeNullableText(json['afterBlock'], '/exclude/afterBlock');
}
