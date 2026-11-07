import 'dart:convert';

import 'package:core/core.dart';

import '../cli_response.dart';
import 'basis_catalog.dart';
import 'basis_human.dart';

/// La respuesta de [result]: una línea JSON o la vista humana, ambas de la
/// misma respuesta acotada por [limits] y con los mismos efectos; mostrar
/// no ejecuta acciones.
CliResponse presentBasis(
  BasisResponse result, {
  required bool json,
  required BasisLimits limits,
}) {
  final fitted = fitBasisResponse(result, limits.maxResponseBytes);
  return CliResponse(
    exitCode: fitted.exitCode,
    channel: CliOutputChannel.stdout,
    payload: json
        ? '${jsonEncode(fitted.toJson())}\n'
        : renderBasisHuman(fitted),
  );
}

/// [result] si su JSON cabe en [maxBytes], targets de revisión incluidos;
/// si no, una respuesta no concluyente: sin registros ni historia, con
/// `selection.complete=false` y `budget_exceeded`, pero con los mismos
/// efectos, huellas, integridad y acciones. Nunca un conjunto truncado
/// que parezca completo.
BasisResponse fitBasisResponse(BasisResponse result, int maxBytes) {
  if (utf8.encode('${jsonEncode(result.toJson())}\n').length <= maxBytes) {
    return result;
  }
  final diagnostics = [
    ...result.diagnostics,
    basisDiagnostic(
      'budget_exceeded',
      message:
          'La respuesta completa no cabe en el presupuesto del perfil: no es '
          'concluyente. Repite con --report-budget=extended.',
    ),
  ];
  return _inconclusive(result, diagnostics);
}

BasisResponse _inconclusive(
  BasisResponse result,
  List<BasisDiagnostic> diagnostics,
) => BasisResponse(
  operation: result.operation,
  exitCode: basisExitCode(diagnostics),
  outcome: result.outcome,
  storageIntegrity: result.storageIntegrity,
  basisDigest: result.basisDigest,
  draftDigest: result.draftDigest,
  published: result.published,
  changedFiles: result.changedFiles,
  normativeCoverage: result.normativeCoverage,
  selected: const [],
  reviewTargets: const [],
  pending: const [],
  sourceStatus: const [],
  actor: result.actor,
  reason: result.reason,
  history: const [],
  selection: BasisSelectionSummary(
    scope: result.selection.scope,
    complete: false,
    excludedCount: result.selection.excludedCount,
  ),
  diagnostics: basisByPrecedence(diagnostics),
  nextActions: result.nextActions,
);
