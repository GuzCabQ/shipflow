import 'package:core/core.dart';

import 'context_recognition_shape.dart';
import 'context_shape.dart';

final _outcomes = wireNames(ContextOutcome.values, (o) => o.toWireName());
final _states = wireNames(ContextState.values, (s) => s.toWireName());
final _freshness = wireNames(ContextFreshness.values, (f) => f.toWireName());
final _choices = wireNames(SharingChoice.values, (c) => c.toWireName());
final _gitStates = wireNames(GitState.values, (g) => g.toWireName());
final _effective = wireNames(SharingEffective.values, (e) => e.toWireName());
final _checkIds = wireNames(ContextCheckId.values, (c) => c.toWireName());
final _checkStatuses = wireNames(
  ContextCheckStatus.values,
  (s) => s.toWireName(),
);

/// La forma de `$defs/response`: la salida schema 3 de init y doctor.
void shapeResponse(Object? value) {
  final json = shapeObject(value, '', {
    'schemaVersion',
    'command',
    'operation',
    'outcome',
    'exitCode',
    'contextState',
    'freshness',
    'sharing',
    'checks',
    'diagnostics',
    'context',
    'effects',
    'nextActions',
  });
  shapeConstant(json['schemaVersion'], 3, '/schemaVersion');
  _command(json);
  shapeMember(json['outcome'], _outcomes, '/outcome');
  _exitCode(json['exitCode'], contextExitCodes);
  shapeMember(json['contextState'], _states, '/contextState');
  shapeMember(json['freshness'], _freshness, '/freshness');
  _sharing(json['sharing']);
  _findings(json);
}

/// Comprobaciones, diagnósticos, contexto, efectos y siguientes acciones.
void _findings(Map<String, Object?> json) {
  shapeList(json['checks'], '/checks', item: _check, max: 6);
  shapeList(json['diagnostics'], '/diagnostics', item: _diagnostic);
  if (json['context'] != null) shapeRecognition(json['context'], '/context');
  _effects(json['effects']);
  shapeList(json['nextActions'], '/nextActions', item: _action);
}

void _command(Map<String, Object?> json) {
  final command = shapeMember(
    json['command'],
    wireNames(ContextCommand.values, (c) => c.toWireName()),
    '/command',
  );
  final operation = shapeMember(
    json['operation'],
    wireNames(ContextOperation.values, (o) => o.toWireName()),
    '/operation',
  );
  if ((command == 'doctor') != (operation == 'doctor')) {
    throw shapeError('command_operation', '/operation');
  }
}

void _exitCode(Object? value, Set<int> allowed) {
  final code = shapeInteger(value, '/exitCode');
  if (!allowed.contains(code)) throw shapeError('enum', '/exitCode');
}

void _sharing(Object? value) {
  final json = shapeObject(value, '/sharing', {
    'choice',
    'gitState',
    'effective',
  });
  shapeMember(json['choice'], _choices, '/sharing/choice');
  shapeMember(json['gitState'], _gitStates, '/sharing/gitState');
  shapeMember(json['effective'], _effective, '/sharing/effective');
}

void _check(Object? value, String at) {
  final json = shapeObject(value, at, {
    'id',
    'status',
    'code',
    'scope',
    'message',
  });
  shapeMember(json['id'], _checkIds, '$at/id');
  shapeMember(json['status'], _checkStatuses, '$at/status');
  shapeText(json['code'], '$at/code', min: 1);
  shapeText(json['scope'], '$at/scope');
  shapeText(json['message'], '$at/message');
}

void _diagnostic(Object? value, String at) {
  final json = shapeObject(value, at, {'code', 'message', 'path'});
  shapeText(json['code'], '$at/code', min: 1);
  shapeText(json['message'], '$at/message');
  shapeNullableText(json['path'], '$at/path');
}

void _effects(Object? value) {
  final json = shapeObject(value, '/effects', {
    'filesCreated',
    'filesReplaced',
    'filesRemoved',
    'directoriesCreated',
    'processesStarted',
    'excludeModified',
    'networkRequests',
  });
  for (final key in [
    'filesCreated',
    'filesReplaced',
    'filesRemoved',
    'directoriesCreated',
  ]) {
    shapeTexts(json[key], '/effects/$key');
  }
  shapeInteger(
    json['processesStarted'],
    '/effects/processesStarted',
    min: 0,
    max: 12,
  );
  shapeBoolean(json['excludeModified'], '/effects/excludeModified');
  shapeConstant(json['networkRequests'], 0, '/effects/networkRequests');
}

void _action(Object? value, String at) {
  final json = shapeObject(value, at, {
    'command',
    'arguments',
    'purpose',
    'effect',
  });
  shapeMember(json['command'], {'init', 'doctor'}, '$at/command');
  shapeTexts(json['arguments'], '$at/arguments');
  shapeText(json['purpose'], '$at/purpose');
  shapeText(json['effect'], '$at/effect');
}

/// La forma de `$defs/dryRun`: el reconocimiento schema 3 sin efectos.
void shapeDryRun(Object? value) {
  final json = shapeObject(value, '', {
    ...scopedRecognitionKeys,
    'schemaVersion',
    'type',
    'command',
    'operation',
    'exitCode',
    'requestedRoot',
    'resolvedRoot',
    'repository',
    'proposal',
    'effects',
  });
  shapeMember(
    json['status'],
    wireNames(RecognitionStatus.values, (s) => s.toWireName()),
    '/status',
  );
  shapeScopedLists(json, '');
  _dryRunEnvelope(json);
  _repository(json['repository']);
  _proposal(json['proposal']);
  _dryRunEffects(json['effects']);
}

void _dryRunEnvelope(Map<String, Object?> json) {
  shapeConstant(json['schemaVersion'], 3, '/schemaVersion');
  shapeConstant(json['type'], 'init_dry_run', '/type');
  shapeConstant(json['command'], 'init', '/command');
  shapeConstant(json['operation'], 'dry_run', '/operation');
  _exitCode(json['exitCode'], const {0, 65, 66});
  shapeText(json['requestedRoot'], '/requestedRoot');
  shapeNullableText(json['resolvedRoot'], '/resolvedRoot');
}

/// Un reconocimiento no escribe, no crea, no lanza procesos ni usa red.
void _dryRunEffects(Object? value) {
  final effects = shapeObject(value, '/effects', {
    'filesWritten',
    'directoriesCreated',
    'processesStarted',
    'networkRequests',
  });
  for (final key in effects.keys) {
    shapeConstant(effects[key], 0, '/effects/$key');
  }
}

void _repository(Object? value) {
  final json = shapeObject(value, '/repository', {
    'status',
    'root',
    'relation',
  });
  shapeMember(
    json['status'],
    wireNames(RepositoryStatus.values, (s) => s.toWireName()),
    '/repository/status',
  );
  shapeNullableText(json['root'], '/repository/root');
  shapeMember(
    json['relation'],
    wireNames(RepositoryRelation.values, (r) => r.toWireName()),
    '/repository/relation',
  );
}

void _proposal(Object? value) {
  final json = shapeObject(value, '/proposal', {
    'eligible',
    'pluginIds',
    'actions',
  });
  shapeBoolean(json['eligible'], '/proposal/eligible');
  shapeList(
    json['pluginIds'],
    '/proposal/pluginIds',
    item: (id, at) => shapeText(id, at, min: 1, max: 256),
  );
  shapeList(
    json['actions'],
    '/proposal/actions',
    item: (action, at) {
      final entry = shapeObject(action, at, {'code', 'description'});
      shapeText(entry['code'], '$at/code', min: 1);
      shapeText(entry['description'], '$at/description');
    },
  );
}
