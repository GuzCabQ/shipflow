import 'package:core/core.dart';

import '../context/context_shape.dart';
import 'assessment_shape.dart';

const _responseKeys = {
  'schemaVersion',
  'kind',
  'command',
  'operation',
  'exitCode',
  'outcome',
  'freshness',
  'coverage',
  'snapshot',
  'diagnostics',
  'effects',
  'nextActions',
  'comparison',
  'retiredRevision',
};

/// La forma de una respuesta de assess, con el snapshot elegido o null.
void shapeAssessmentResponse(Object? value) {
  final json = shapeObject(value, '', _responseKeys);
  shapeConstant(json['schemaVersion'], 2, '/schemaVersion');
  shapeConstant(json['kind'], assessmentResponseKind, '/kind');
  shapeConstant(json['command'], 'assess', '/command');
  shapeMember(json['operation'], {'observe', 'show', 'recover'}, '/operation');
  final code = shapeInteger(json['exitCode'], '/exitCode');
  if (!const {0, 64, 65, 66, 70, 74, 75, 130}.contains(code)) {
    throw shapeError('enum', '/exitCode');
  }
  _members(json);
  if (json['snapshot'] != null) shapeSnapshot(json['snapshot'], '/snapshot');
  shapeList(
    json['diagnostics'],
    '/diagnostics',
    item: shapeAssessmentDiagnostic,
    max: 256,
  );
  _effects(json['effects']);
  shapeList(json['nextActions'], '/nextActions', item: _action, max: 10);
  if (json['comparison'] != null) _comparison(json['comparison']);
  if (json['retiredRevision'] != null) {
    shapeInteger(json['retiredRevision'], '/retiredRevision', min: 1);
  }
}

void _members(Map<String, Object?> json) {
  shapeMember(
    json['outcome'],
    wireNames(AssessmentOutcome.values, (o) => o.toWireName()),
    '/outcome',
  );
  shapeMember(
    json['freshness'],
    wireNames(AssessmentFreshness.values, (f) => f.toWireName()),
    '/freshness',
  );
  shapeMember(
    json['coverage'],
    wireNames(AssessmentCoverage.values, (c) => c.toWireName()),
    '/coverage',
  );
}

void _effects(Object? value) {
  final json = shapeObject(value, '/effects', {
    'created',
    'replaced',
    'removed',
    'published',
    'gitQueries',
    'network',
    'productWrites',
  });
  for (final key in ['created', 'replaced', 'removed']) {
    shapeList(
      json[key],
      '/effects/$key',
      item: (path, at) =>
          shapeText(path, at, max: 4096, valid: isAssessmentPath),
      max: 128,
    );
  }
  shapeBoolean(json['published'], '/effects/published');
  shapeInteger(json['gitQueries'], '/effects/gitQueries', min: 0);
  shapeConstant(json['network'], 0, '/effects/network');
  shapeConstant(json['productWrites'], 0, '/effects/productWrites');
}

void _action(Object? value, String at) {
  final json = shapeObject(value, at, {'argv', 'purpose', 'effect'});
  shapeList(
    json['argv'],
    '$at/argv',
    item: (arg, at) => shapeText(arg, at, max: 4096),
    max: 12,
  );
  shapeText(json['purpose'], '$at/purpose', min: 1, max: 128);
  shapeMember(
    json['effect'],
    wireNames(AssessmentActionEffect.values, (e) => e.toWireName()),
    '$at/effect',
  );
}

void _comparison(Object? value) {
  final json = shapeObject(value, '/comparison', {
    'addedReferences',
    'repeatedReferences',
    'notObservedNow',
  });
  for (final key in json.keys) {
    shapeInteger(json[key], '/comparison/$key', min: 0);
  }
}
