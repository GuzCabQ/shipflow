import 'package:core/core.dart';

import 'cli_command.dart';
import 'recognition_human_context.dart';
import 'recognition_human_findings.dart';
import 'recognition_human_support.dart';

const _scope =
    '  No se comprobó si el proyecto compila, si sus pruebas pasan, si '
    'respeta su arquitectura, si sus recursos existen ni si el SDK está '
    'instalado.';
const _effects =
    '  No se modificó el proyecto. Shipflow no guardó este reporte ni creó un '
    'expediente.';
const _reviewSources =
    '  Revisa las fuentes indicadas y repite la inspección después de '
    'decidir su corrección.';
const _reviewLimitations =
    '  Revisa las causas indicadas; el reconocimiento está incompleto. Si una '
    'causa depende del alcance de esta versión y no del proyecto, esta '
    'versión no puede resolverla.';

/// La ficha humana de [report]: identidad, unidades y relaciones, entorno
/// declarado, fuentes candidatas, cobertura, y el resultado con lo que
/// impide continuar, lo que no se comprobó, lo que no se guardó y el
/// siguiente paso. Pura: no inspecciona nada ni consulta modelos, y no
/// muestra IDs ni hashes. La misma clasificación gobierna JSON y código.
String recognitionHumanText(
  RecognitionReport report, {
  ReportBudgetProfile budgetProfile = ReportBudgetProfile.standard,
}) {
  final limit = report.limitations
      .where((l) => l.code == reportLimitReachedCode)
      .firstOrNull;
  final findings = Findings(report);
  final inventory =
      limit == null && report.status != RecognitionStatus.invalidRoot;
  final extended = budgetProfile == ReportBudgetProfile.extended;
  final lines = [
    'Shipflow · reconocimiento del proyecto',
    _headline(report.status),
    ..._place(report),
    ?findings.summary,
    if (inventory) ...scopedBlocks(report),
    '',
    'Resultado',
    ..._result(report, findings),
    ..._actions(report, limit, findings),
    '',
    'Para repetir la inspección con detalle estructurado:',
    '  shipflow init --dry-run --json${extended ? ' --report-budget=extended' : ''}',
  ];
  return '${lines.join('\n')}\n';
}

String _headline(RecognitionStatus status) => switch (status) {
  RecognitionStatus.recognized =>
    'Identidad reconocida dentro del alcance indicado',
  RecognitionStatus.ambiguous => 'Reconocimiento no concluyente',
  RecognitionStatus.unsupported => 'Proyecto no soportado',
  RecognitionStatus.invalidRoot => 'No se pudo inspeccionar la carpeta',
};

/// La carpeta inspeccionada y el alias corroborado, si lo hay.
List<String> _place(RecognitionReport report) {
  final resolved = report.resolvedRoot;
  return [
    'Carpeta: ${shown(resolved ?? report.requestedRoot)}',
    if (resolved != null && report.requestedRoot != resolved)
      'Alias: ${shown(report.requestedRoot)}',
  ];
}

List<String> _result(RecognitionReport report, Findings findings) => [
  if (findings.empty)
    '  No se detectaron conflictos ni límites en este reconocimiento.',
  ...findings.lines(),
  ?_proposal(report, findings),
  _scope,
  _effects,
];

/// Nunca llama conflicto a una limitación.
String? _proposal(RecognitionReport report, Findings findings) {
  if (report.status == RecognitionStatus.invalidRoot) return null;
  final contradictions = report.conflicts.isNotEmpty;
  final limits = report.limitations.any((l) => l.blocking);
  if (findings.blocked) {
    return '  La propuesta no puede aplicarse: hay '
        '${[if (contradictions) 'contradicciones entre declaraciones', if (limits) 'limitaciones bloqueantes'].join(' y ')}.';
  }
  return report.proposal.eligible
      ? '  La propuesta es elegible, pero no se aplicó.'
      : null;
}

List<String> _actions(
  RecognitionReport report,
  RecognitionLimitation? limit,
  Findings findings,
) => switch (report.status) {
  RecognitionStatus.recognized => const [
    '  La inspección terminó. Esta versión sólo entrega esta ficha: no '
        'aplica la inicialización ni inicia tareas.',
  ],
  RecognitionStatus.unsupported => const [
    '  Esta versión reconoce proyectos Dart y Flutter mediante sus '
        'manifiestos y marcadores.',
  ],
  RecognitionStatus.invalidRoot => const [
    '  Comprueba que la carpeta exista y que tengas permiso para leerla.',
  ],
  RecognitionStatus.ambiguous when limit != null => [
    '  ${splitLimitMessage(limit.message).action}',
  ],
  RecognitionStatus.ambiguous => _ambiguousActions(report),
};

/// Ante contradicciones, revisar sus fuentes; ante límites, saber que el
/// reconocimiento está incompleto. Nunca se elige una versión.
List<String> _ambiguousActions(RecognitionReport report) {
  final limits = report.limitations.any((l) => l.blocking);
  return [
    if (report.conflicts.isNotEmpty || !limits) _reviewSources,
    if (limits) _reviewLimitations,
  ];
}
