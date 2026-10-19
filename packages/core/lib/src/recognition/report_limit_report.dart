import 'recognition_enums.dart';
import 'recognition_findings.dart';
import 'recognition_proposal.dart';
import 'recognition_report.dart';
import 'repository_context.dart';
import 'report_budget.dart';

const reportLimitReachedCode = 'report_limit_reached';

const _dimensionNames = {
  ReportLimitDimension.items: 'elementos del reporte',
  ReportLimitDimension.textBytes: 'texto del reporte',
  ReportLimitDimension.jsonBytes: 'tamaño JSON del reporte',
};

const _widen =
    'Puedes repetir con shipflow init --dry-run --report-budget=extended. '
    'El perfil ampliado puede consumir más recursos.';

const _ceiling =
    'Se alcanzó el máximo disponible en esta versión. Inspecciona una raíz '
    'tecnológica más acotada; esto cambia el alcance de la inspección.';

/// El reporte compacto que sustituye a uno que excedió su perfil: conserva
/// raíces y repositorio, descarta todo el inventario y no es elegible. Se
/// construye fuera del presupuesto agotado y no cita evidencia descartada.
RecognitionReport reportLimitReached({
  required String requestedRoot,
  required String resolvedRoot,
  required RepositoryContext repository,
  required ReportLimitDimension dimension,
  required bool extended,
}) => RecognitionReport(
  status: RecognitionStatus.ambiguous,
  requestedRoot: requestedRoot,
  resolvedRoot: resolvedRoot,
  repository: repository,
  candidates: const [],
  units: const [],
  evidence: const [],
  conflicts: const [],
  limitations: [
    RecognitionLimitation(
      code: reportLimitReachedCode,
      message: _limitMessage(dimension, extended: extended),
      path: null,
      blocking: true,
    ),
  ],
  proposal: RecognitionProposal(
    eligible: false,
    pluginIds: const [],
    actions: const [],
  ),
  effects: RecognitionEffects.none,
);

String _limitMessage(
  ReportLimitDimension dimension, {
  required bool extended,
}) =>
    'El reconocimiento alcanzó el límite de ${_dimensionNames[dimension]} '
    'del perfil ${extended ? 'ampliado' : 'normal'}; no se publica un '
    'inventario parcial. ${extended ? _ceiling : _widen}';
