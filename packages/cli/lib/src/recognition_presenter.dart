import 'package:core/core.dart';

import 'bounded_recognition_json.dart';
import 'cli_command.dart';
import 'cli_response.dart';
import 'recognition_human.dart';

/// La única tabla que une cada perfil con sus tres cotas.
ReportLimits reportLimitsOf(ReportBudgetProfile profile) => switch (profile) {
  ReportBudgetProfile.standard => const ReportLimits(),
  ReportBudgetProfile.extended => const ReportLimits.extended(),
};

/// [report] como JSON de una línea o como vista humana, siempre en stdout.
/// El JSON se mide contra [budgetProfile] también cuando se pide la vista
/// humana: si no cabe, ambas salen del mismo reporte compacto.
CliResponse presentRecognition(
  RecognitionReport report, {
  required bool json,
  ReportBudgetProfile budgetProfile = ReportBudgetProfile.standard,
}) {
  final (:effective, :encoded) = _withinJsonLimit(report, budgetProfile);
  return CliResponse(
    exitCode: recognitionExitCode(effective.status),
    channel: CliOutputChannel.stdout,
    payload: json
        ? encoded
        : recognitionHumanText(effective, budgetProfile: budgetProfile),
  );
}

/// [report] y su JSON si caben en el perfil; si no, el reporte compacto y
/// el suyo. Que tampoco el compacto quepa es un defecto, no otro límite.
({RecognitionReport effective, String encoded}) _withinJsonLimit(
  RecognitionReport report,
  ReportBudgetProfile profile,
) {
  final maxBytes = reportLimitsOf(profile).maxReportJsonBytes;
  final encoded = encodeRecognitionWithinLimit(report, maxBytes: maxBytes);
  if (encoded != null) return (effective: report, encoded: encoded);
  final resolvedRoot = report.resolvedRoot;
  if (resolvedRoot == null) {
    throw StateError('una raíz inválida excedió su JSON');
  }
  final compact = reportLimitReached(
    requestedRoot: report.requestedRoot,
    resolvedRoot: resolvedRoot,
    repository: report.repository,
    dimension: ReportLimitDimension.jsonBytes,
    extended: profile == ReportBudgetProfile.extended,
  );
  return (
    effective: compact,
    encoded:
        encodeRecognitionWithinLimit(compact, maxBytes: maxBytes) ??
        (throw StateError('el reporte compacto no cabe en su perfil')),
  );
}
