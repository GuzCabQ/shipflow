import 'package:core/core.dart';

import '../context/context_shape.dart';

/// La forma de los `$defs` compartidos por los cinco schemas de bootstrap.
/// Sólo forma: las cotas de texto y las reglas cruzadas son semánticas.
final _digest = RegExp(r'^sha256:[0-9a-f]{64}$');

String shapeDigest(Object? value, String at) =>
    shapeText(value, at, valid: _digest.hasMatch);

String? shapeNullableDigest(Object? value, String at) =>
    value == null ? null : shapeDigest(value, at);

void _nonEmpty(Object? value, String at) => shapeText(value, at, min: 1);

void _nullableNonEmpty(Object? value, String at) {
  if (value != null) _nonEmpty(value, at);
}

Set<String> _names<T>(List<T> values, String Function(T) name) =>
    wireNames(values, name);

void shapeBasisScope(Object? value, String at) {
  final json = shapeObject(value, at, const {'kind', 'paths'});
  final kind = shapeMember(
    json['kind'],
    _names(BasisScopeKind.values, (k) => k.toWireName()),
    '$at/kind',
  );
  shapeList(
    json['paths'],
    '$at/paths',
    item: _nonEmpty,
    min: kind == 'paths' ? 1 : 0,
    max: kind == 'paths' ? null : 0,
    unique: true,
  );
}

void shapeBasisActor(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'label',
    'role',
    'authority',
    'scope',
  });
  _nonEmpty(json['label'], '$at/label');
  _nonEmpty(json['role'], '$at/role');
  shapeConstant(json['authority'], 'local_declared', '$at/authority');
  shapeBasisScope(json['scope'], '$at/scope');
}

void _references(Object? value, String at) => shapeList(
  value,
  at,
  item: (item, at) {
    final json = shapeObject(item, at, const {'ref', 'version'});
    _nonEmpty(json['ref'], '$at/ref');
    shapeInteger(json['version'], '$at/version', min: 1);
  },
);

const _sourceKeys = {
  'kind',
  'title',
  'scope',
  'lifecycle',
  'sourceType',
  'locator',
  'purpose',
  'contentDigest',
  'observation',
};

void _source(Map<String, Object?> json, String at) {
  shapeObject(json, at, _sourceKeys);
  shapeMember(
    json['lifecycle'],
    _names(BasisSourceLifecycle.values, (v) => v.toWireName()),
    '$at/lifecycle',
  );
  shapeMember(
    json['sourceType'],
    _names(BasisSourceType.values, (v) => v.toWireName()),
    '$at/sourceType',
  );
  _nonEmpty(json['locator'], '$at/locator');
  _nonEmpty(json['purpose'], '$at/purpose');
  shapeNullableDigest(json['contentDigest'], '$at/contentDigest');
  shapeMember(
    json['observation'],
    _names(BasisObservation.values, (v) => v.toWireName()),
    '$at/observation',
  );
}

const _ruleKeys = {
  'kind',
  'title',
  'scope',
  'lifecycle',
  'replacementRef',
  'statement',
  'reason',
  'ruleClass',
  'alternative',
  'exceptionPolicy',
  'support',
  'sourceRefs',
  'evidenceLevel',
};

void _rule(Map<String, Object?> json, String at) {
  shapeObject(json, at, _ruleKeys);
  shapeMember(
    json['lifecycle'],
    _names(BasisRuleLifecycle.values, (v) => v.toWireName()),
    '$at/lifecycle',
  );
  _nullableNonEmpty(json['replacementRef'], '$at/replacementRef');
  _nonEmpty(json['statement'], '$at/statement');
  _nonEmpty(json['reason'], '$at/reason');
  shapeMember(
    json['ruleClass'],
    _names(BasisRuleClass.values, (v) => v.toWireName()),
    '$at/ruleClass',
  );
  _nullableNonEmpty(json['alternative'], '$at/alternative');
  shapeMember(
    json['exceptionPolicy'],
    _names(BasisExceptionPolicy.values, (v) => v.toWireName()),
    '$at/exceptionPolicy',
  );
  shapeMember(
    json['support'],
    _names(BasisSupport.values, (v) => v.toWireName()),
    '$at/support',
  );
  _references(json['sourceRefs'], '$at/sourceRefs');
  shapeConstant(json['evidenceLevel'], 'declared', '$at/evidenceLevel');
}

const _pendingKeys = {
  'kind',
  'title',
  'scope',
  'status',
  'question',
  'reason',
  'revisitWhen',
  'sourceRefs',
  'resolution',
  'decisionReview',
};

void _pending(Map<String, Object?> json, String at) {
  shapeObject(json, at, _pendingKeys);
  shapeMember(
    json['status'],
    _names(BasisPendingStatus.values, (v) => v.toWireName()),
    '$at/status',
  );
  _nonEmpty(json['question'], '$at/question');
  _nonEmpty(json['reason'], '$at/reason');
  _nonEmpty(json['revisitWhen'], '$at/revisitWhen');
  _references(json['sourceRefs'], '$at/sourceRefs');
  _nullableNonEmpty(json['resolution'], '$at/resolution');
  final review = json['decisionReview'];
  if (review == null) return;
  final link = shapeObject(review, '$at/decisionReview', const {
    'ref',
    'version',
    'reviewer',
  });
  _nonEmpty(link['ref'], '$at/decisionReview/ref');
  shapeInteger(link['version'], '$at/decisionReview/version', min: 1);
  _nullableNonEmpty(link['reviewer'], '$at/decisionReview/reviewer');
}

void shapeBasisPayload(Object? value, String at) {
  if (value is! Map<String, Object?>) throw shapeError('type', at);
  _nonEmpty(value['title'], '$at/title');
  shapeBasisScope(value['scope'], '$at/scope');
  switch (value['kind']) {
    case 'source':
      _source(value, at);
    case 'rule':
      _rule(value, at);
    case 'pending':
      _pending(value, at);
    default:
      throw shapeError('one_of', '$at/kind');
  }
}

/// `$defs/version`: una versión de registro con ID UUID.
void shapeBasisVersion(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'id',
    'version',
    'previousVersion',
    'payload',
  });
  shapeUuid(json['id'], '$at/id');
  shapeInteger(json['version'], '$at/version', min: 1);
  if (json['previousVersion'] != null) {
    shapeInteger(json['previousVersion'], '$at/previousVersion', min: 1);
  }
  shapeBasisPayload(json['payload'], '$at/payload');
}

/// `$defs/reading`: una lectura de fuente local.
void shapeBasisReading(Object? value, String at) {
  final json = shapeObject(value, at, const {'path', 'digest'});
  _nonEmpty(json['path'], '$at/path');
  shapeDigest(json['digest'], '$at/digest');
}
