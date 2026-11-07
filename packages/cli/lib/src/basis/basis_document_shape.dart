import 'package:core/core.dart';

import '../context/context_shape.dart';
import 'basis_shape.dart';

/// La forma de los documentos de bootstrap: input, basis, draft, journal
/// y respuesta, según sus schemas.
void _nonEmpty(Object? value, String at) => shapeText(value, at, min: 1);

void _header(Map<String, Object?> json, String type) {
  shapeConstant(json['schemaVersion'], 1, 'schemaVersion');
  shapeConstant(json['type'], type, 'type');
}

void _versions(Object? value, String at) =>
    shapeList(value, at, item: shapeBasisVersion);

void _readings(Object? value, String at) =>
    shapeList(value, at, item: shapeBasisReading);

void _change(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'key',
    'targetId',
    'expectedVersion',
    'payload',
  });
  _nonEmpty(json['key'], '$at/key');
  if (json['targetId'] != null) shapeUuid(json['targetId'], '$at/targetId');
  if (json['expectedVersion'] != null) {
    shapeInteger(json['expectedVersion'], '$at/expectedVersion', min: 1);
  }
  shapeBasisPayload(json['payload'], '$at/payload');
}

void shapeBasisInput(Object? value, [String at = '']) {
  final json = shapeObject(value, at, const {
    'schemaVersion',
    'type',
    'projectId',
    'expectedBasisDigest',
    'actor',
    'reason',
    'changes',
  });
  _header(json, basisInputType);
  shapeUuid(json['projectId'], '$at/projectId');
  shapeNullableDigest(json['expectedBasisDigest'], '$at/expectedBasisDigest');
  shapeBasisActor(json['actor'], '$at/actor');
  _nonEmpty(json['reason'], '$at/reason');
  shapeList(json['changes'], '$at/changes', item: _change);
}

void _event(Object? value, String at) {
  final json = shapeObject(value, at, const {
    'revision',
    'operationId',
    'acceptedAt',
    'actor',
    'reason',
    'draftDigest',
    'previousEventDigest',
    'changes',
    'eventDigest',
  });
  shapeInteger(json['revision'], '$at/revision', min: 1);
  shapeUuid(json['operationId'], '$at/operationId');
  shapeTimestamp(json['acceptedAt'], '$at/acceptedAt');
  shapeBasisActor(json['actor'], '$at/actor');
  _nonEmpty(json['reason'], '$at/reason');
  shapeDigest(json['draftDigest'], '$at/draftDigest');
  shapeNullableDigest(json['previousEventDigest'], '$at/previousEventDigest');
  _versions(json['changes'], '$at/changes');
  shapeDigest(json['eventDigest'], '$at/eventDigest');
}

void shapeBasisDocument(Object? value) {
  final json = shapeObject(value, '', const {
    'schemaVersion',
    'type',
    'projectId',
    'revision',
    'producerVersion',
    'validatorVersion',
    'queryVersion',
    'events',
    'digest',
  });
  _header(json, basisType);
  shapeUuid(json['projectId'], 'projectId');
  shapeInteger(json['revision'], 'revision', min: 1);
  _nonEmpty(json['producerVersion'], 'producerVersion');
  shapeConstant(json['validatorVersion'], 1, 'validatorVersion');
  shapeConstant(json['queryVersion'], 1, 'queryVersion');
  shapeList(json['events'], 'events', item: _event, min: 1);
  shapeDigest(json['digest'], 'digest');
}

void shapeBasisDraft(Object? value) {
  final json = shapeObject(value, '', const {
    'schemaVersion',
    'type',
    'projectId',
    'operationId',
    'createdAt',
    'expectedBasisDigest',
    'contextProjectDigest',
    'input',
    'preparedChanges',
    'sourceReads',
    'digest',
  });
  _header(json, basisDraftType);
  shapeUuid(json['projectId'], 'projectId');
  shapeUuid(json['operationId'], 'operationId');
  shapeTimestamp(json['createdAt'], 'createdAt');
  shapeNullableDigest(json['expectedBasisDigest'], 'expectedBasisDigest');
  shapeDigest(json['contextProjectDigest'], 'contextProjectDigest');
  shapeBasisInput(json['input'], 'input');
  _versions(json['preparedChanges'], 'preparedChanges');
  _readings(json['sourceReads'], 'sourceReads');
  shapeDigest(json['digest'], 'digest');
}

const _transactionKeys = {
  'schemaVersion',
  'type',
  'projectId',
  'operationId',
  'phase',
  'before',
  'after',
  'acceptedDraftDigest',
  'acceptedAt',
  'actor',
  'contextProjectDigest',
  'sourceReads',
  'candidatePath',
  'digest',
};

void shapeBasisTransaction(Object? value) {
  final json = shapeObject(value, '', _transactionKeys);
  _header(json, basisTransactionType);
  shapeUuid(json['projectId'], 'projectId');
  shapeUuid(json['operationId'], 'operationId');
  shapeMember(
    json['phase'],
    wireNames(BasisTransactionPhase.values, (v) => v.toWireName()),
    'phase',
  );
  shapeNullableDigest(json['before'], 'before');
  shapeDigest(json['after'], 'after');
  shapeDigest(json['acceptedDraftDigest'], 'acceptedDraftDigest');
  shapeTimestamp(json['acceptedAt'], 'acceptedAt');
  shapeBasisActor(json['actor'], 'actor');
  shapeDigest(json['contextProjectDigest'], 'contextProjectDigest');
  _readings(json['sourceReads'], 'sourceReads');
  _nonEmpty(json['candidatePath'], 'candidatePath');
  shapeDigest(json['digest'], 'digest');
}

/// `$defs/event` para la historia de una respuesta.
void shapeBasisEvent(Object? value, String at) => _event(value, at);
