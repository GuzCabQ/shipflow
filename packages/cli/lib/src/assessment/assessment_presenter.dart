import 'dart:convert';

import 'package:core/core.dart';

import '../cli_response.dart';
import 'assessment_human.dart';

/// La respuesta de [result]: una línea JSON o la vista humana, ambas del
/// mismo resultado y sin volver a observar. Un JSON que no cabe entero sale
/// compacto, sin snapshot y con los efectos verdaderos.
CliResponse presentAssessment(
  AssessmentResult result, {
  required bool json,
  required String root,
  int maxJsonBytes = maxAssessmentResponseBytes,
}) {
  if (!json) {
    return CliResponse(
      exitCode: result.exitCode,
      channel: CliOutputChannel.stdout,
      payload: humanAssessment(result, root: root),
    );
  }
  final full = '${jsonEncode(result.toJson())}\n';
  final payload = utf8.encode(full).length <= maxJsonBytes
      ? full
      : '${jsonEncode(compactAssessment(result).toJson())}\n';
  return CliResponse(
    exitCode: result.exitCode,
    channel: CliOutputChannel.stdout,
    payload: payload,
  );
}

/// [result] sin su snapshot: el mismo resultado, vigencia, cobertura,
/// diagnósticos, efectos y acciones.
AssessmentResult compactAssessment(AssessmentResult result) => AssessmentResult(
  operation: result.operation,
  exitCode: result.exitCode,
  outcome: result.outcome,
  freshness: result.freshness,
  coverage: result.coverage,
  snapshot: null,
  diagnostics: result.diagnostics,
  effects: result.effects,
  nextActions: result.nextActions,
  comparison: result.comparison,
  retiredRevision: result.retiredRevision,
);
