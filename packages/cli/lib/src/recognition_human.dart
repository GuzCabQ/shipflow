import 'package:core/core.dart';

import 'cli_command.dart';
import 'terminal_text.dart';

const _maxShownRunes = 240;
const _maxPackages = 20;
const _maxFindings = 10;
const _maxSources = 5;

const _scope =
    'No se comprobó si el proyecto compila, si sus pruebas pasan, si respeta '
    'su arquitectura ni si el SDK está instalado.';
const _effects =
    'No se modificó el proyecto. Shipflow no guardó este reporte ni creó un '
    'expediente.';
const _blocked =
    'La propuesta no puede aplicarse: hay conflictos o limitaciones '
    'bloqueantes.';
const _reviewSources =
    'Revisa las fuentes indicadas y repite la inspección después de decidir '
    'su corrección.';
const _reviewLimitations =
    'Revisa las limitaciones indicadas; el reconocimiento está incompleto.';

/// La vista humana de [report]: qué se observó, qué impide continuar, qué no
/// se comprobó, qué se cambió o guardó y qué se puede hacer. Pura: no
/// inspecciona nada ni consulta modelos, y no muestra IDs ni hashes.
String recognitionHumanText(
  RecognitionReport report, {
  ReportBudgetProfile budgetProfile = ReportBudgetProfile.standard,
}) {
  final limit = report.limitations
      .where((l) => l.code == reportLimitReachedCode)
      .firstOrNull;
  final extended = budgetProfile == ReportBudgetProfile.extended;
  final lines = [
    'Shipflow · reconocimiento del proyecto',
    _headline(report.status),
    ..._observed(report, discarded: limit != null),
    '',
    ..._findings(report, limit),
    ..._proposal(report),
    _scope,
    '',
    _effects,
    ..._actions(report, limit),
    'Para repetir la inspección con detalle estructurado:',
    '  shipflow init --dry-run --json${extended ? ' --report-budget=extended' : ''}',
  ];
  return '${lines.join('\n')}\n';
}

String _headline(RecognitionStatus status) => switch (status) {
  RecognitionStatus.recognized => 'Proyecto reconocido',
  RecognitionStatus.ambiguous => 'Reconocimiento no concluyente',
  RecognitionStatus.unsupported => 'Proyecto no soportado',
  RecognitionStatus.invalidRoot => 'No se pudo inspeccionar la carpeta',
};

/// Carpeta, alias corroborado, tecnología y paquetes observados. Un reporte
/// descartado por su tamaño no tiene inventario que contar.
List<String> _observed(RecognitionReport report, {required bool discarded}) {
  final resolved = report.resolvedRoot;
  return [
    'Carpeta: ${_safe(resolved ?? report.requestedRoot)}',
    if (resolved != null && report.requestedRoot != resolved)
      'Alias: ${_safe(report.requestedRoot)}',
    if (report.candidates.isNotEmpty)
      'Tecnología: ${report.candidates.map((c) => _safe(c.displayName)).join(', ')}',
    if (!discarded && report.status != RecognitionStatus.invalidRoot) ...[
      'Paquetes observados: ${report.units.length}',
      for (final u in report.units.take(_maxPackages))
        '  ${_safe(u.name)} · ${_safe(u.path)}',
      ?_more(report.units.length - _maxPackages, 'paquete', 'paquetes'),
    ],
  ];
}

List<String> _findings(RecognitionReport report, RecognitionLimitation? limit) {
  if (report.conflicts.isEmpty && report.limitations.isEmpty) {
    return const [
      'No se detectaron conflictos ni límites en este reconocimiento.',
    ];
  }
  final evidence = {for (final e in report.evidence) e.id: e};
  return [
    if (report.conflicts.isNotEmpty) ...[
      'Conflictos:',
      for (final c in report.conflicts.take(_maxFindings))
        '  - ${_safe(c.message)}${_sources(c.evidenceIds, evidence)}',
      ?_more(report.conflicts.length - _maxFindings, 'conflicto', 'conflictos'),
    ],
    if (report.limitations.isNotEmpty) ...[
      'Limitaciones:',
      for (final l in report.limitations.take(_maxFindings)) _limitation(l),
      ?_more(
        report.limitations.length - _maxFindings,
        'limitación',
        'limitaciones',
      ),
    ],
  ];
}

/// Las fuentes de un conflicto, con su valor, hasta [_maxSources].
String _sources(List<String> ids, Map<String, RecognitionEvidence> evidence) {
  if (ids.isEmpty) return '';
  final shown = [
    for (final id in ids.take(_maxSources))
      if (evidence[id] case final e?) '${_safe(e.path)} (${_safe(e.value)})',
  ];
  final rest = ids.length - _maxSources;
  return ' · fuentes: ${shown.join(', ')}${rest > 0 ? ' y $rest más' : ''}';
}

String _limitation(RecognitionLimitation l) {
  final message = l.code == reportLimitReachedCode
      ? _split(l.message).finding
      : l.message;
  return '  - ${_safe(message)}'
      '${l.path == null ? '' : ' · ${_safe(l.path!)}'}'
      '${l.blocking ? '' : ' (no bloquea)'}';
}

List<String> _proposal(RecognitionReport report) {
  if (report.status == RecognitionStatus.invalidRoot) return const [];
  if (report.conflicts.isNotEmpty ||
      report.limitations.any((l) => l.blocking)) {
    return const [_blocked];
  }
  if (report.proposal.eligible) {
    return const ['La propuesta es elegible, pero no se aplicó.'];
  }
  return const [];
}

List<String> _actions(RecognitionReport report, RecognitionLimitation? limit) =>
    switch (report.status) {
      RecognitionStatus.recognized => const [
        'La inspección terminó. Esta versión todavía no aplica la '
            'inicialización ni inicia tareas.',
      ],
      RecognitionStatus.unsupported => const [
        'Esta versión reconoce proyectos Dart y Flutter mediante sus '
            'manifiestos y marcadores.',
      ],
      RecognitionStatus.invalidRoot => const [
        'Comprueba que la carpeta exista y que tengas permiso para leerla.',
      ],
      RecognitionStatus.ambiguous when limit != null => [
        _split(limit.message).action,
      ],
      RecognitionStatus.ambiguous => _ambiguousActions(report),
    };

/// Ante conflictos, revisar sus fuentes; ante límites de lectura, saber que
/// el reconocimiento está incompleto. Nunca se elige una versión.
List<String> _ambiguousActions(RecognitionReport report) {
  final readLimits = report.limitations.any((l) => l.blocking);
  return [
    if (report.conflicts.isNotEmpty || !readLimits) _reviewSources,
    if (readLimits) _reviewLimitations,
  ];
}

/// El mensaje del límite de reporte en lo que pasó y lo que se puede hacer:
/// su primera oración, y el resto.
({String finding, String action}) _split(String message) {
  final cut = message.indexOf('. ');
  if (cut < 0) return (finding: message, action: '');
  return (
    finding: message.substring(0, cut + 1),
    action: message.substring(cut + 2),
  );
}

String? _more(int extra, String singular, String plural) => extra <= 0
    ? null
    : extra == 1
    ? '  Hay 1 $singular adicional; consulta la salida JSON.'
    : '  Hay $extra $plural adicionales; consulta la salida JSON.';

String _safe(String value) => singleLine(value, maxRunes: _maxShownRunes);
