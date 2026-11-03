import 'package:core/core.dart';

import '../context/context_shape.dart';

/// La forma del journal `shipflow/local/assessment-transaction.json`.
void shapeAssessmentTransaction(Object? value) {
  final json = shapeObject(value, '', {
    'schemaVersion',
    'kind',
    'projectId',
    'operationId',
    'before',
    'after',
    'candidatePath',
    'state',
    'baseContextDigest',
    'snapshotId',
  });
  shapeConstant(json['schemaVersion'], 1, '/schemaVersion');
  shapeConstant(json['kind'], assessmentTransactionKind, '/kind');
  shapeUuid(json['projectId'], '/projectId');
  shapeUuid(json['operationId'], '/operationId');
  shapeNullableSha256(json['before'], '/before');
  for (final key in ['after', 'baseContextDigest', 'snapshotId']) {
    shapeSha256(json[key], '/$key');
  }
  shapeText(
    json['candidatePath'],
    '/candidatePath',
    max: 4096,
    valid: isAssessmentPath,
  );
  shapeMember(json['state'], {'prepared', 'published'}, '/state');
}
