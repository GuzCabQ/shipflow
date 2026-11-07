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

/// [result] si su JSON cabe en [maxBytes], targets de revisión y cambios
/// propuestos incluidos; si no, una respuesta no concluyente: sin
/// registros, cambios ni historia, con `selection.complete=false` y
/// `budget_exceeded`, con los mismos efectos, huellas e integridad. Nunca
/// un conjunto truncado que parezca completo.
BasisResponse fitBasisResponse(BasisResponse result, int maxBytes) {
  if (utf8.encode('${jsonEncode(result.toJson())}\n').length <= maxBytes) {
    return result;
  }
  final cut = result.proposedChanges.length;
  final diagnostics = [
    ...result.diagnostics,
    basisDiagnostic(
      'budget_exceeded',
      message: cut == 0
          ? 'La respuesta completa no cabe en el presupuesto del perfil: no '
                'es concluyente. Repite con --report-budget=extended.'
          : 'Los $cut cambios propuestos no caben en el presupuesto del '
                'perfil y no se muestran: revísalos con --show --draft '
                '--report-budget=extended antes de aceptar.',
    ),
  ];
  return _inconclusive(result, diagnostics, _actionsWithout(result, cut));
}

/// Sin poder mostrar los cambios propuestos no se ofrece aceptarlos: se
/// ofrece revisarlos con el presupuesto ampliado.
List<BasisAction> _actionsWithout(BasisResponse result, int cut) => cut == 0
    ? result.nextActions
    : [
        showDraftExtendedAction,
        for (final a in result.nextActions)
          if (a.arguments.first != '--accept') a,
      ];

BasisResponse _inconclusive(
  BasisResponse result,
  List<BasisDiagnostic> diagnostics,
  List<BasisAction> actions,
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
  proposedChanges: const [],
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
  nextActions: actions,
);
