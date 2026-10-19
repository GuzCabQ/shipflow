import 'package:core/core.dart';

import 'bounded_recognition_json.dart';
import 'cli_command.dart';
import 'cli_response.dart';
import 'terminal_text.dart';

const _maxShownRunes = 240;

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
    payload: json ? encoded : '${_humanLines(effective).join('\n')}\n',
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

List<String> _humanLines(RecognitionReport report) => [
  ..._header(report),
  ..._section('Candidatos', [
    for (final c in report.candidates)
      _item([c.id, c.displayName, 'plugin ${c.pluginId}'], c.evidenceIds),
  ]),
  ..._section('Unidades', [
    for (final u in report.units)
      _item([u.id, u.name, u.kind, u.path], u.evidenceIds),
  ]),
  ..._section('Evidencia', [
    for (final e in report.evidence)
      _item([e.id, e.kind, e.path, e.value, e.fingerprint]),
  ]),
  ..._section('Conflictos', [
    for (final c in report.conflicts) _item([c.code, c.message], c.evidenceIds),
  ]),
  ..._section('Limitaciones', [
    for (final l in report.limitations)
      _item([
        l.code,
        'bloqueante: ${l.blocking ? 'sí' : 'no'}',
        l.path ?? 'sin ruta',
        l.message,
      ]),
  ]),
  ..._proposal(report.proposal),
  _effects(report.effects),
];

/// Estado, raíces y Git.
List<String> _header(RecognitionReport report) => [
  'Shipflow · reconocimiento',
  'Estado: ${report.status.toWireName()}',
  'Raíz solicitada: ${_safe(report.requestedRoot)}',
  'Raíz resuelta: ${report.resolvedRoot == null ? 'no disponible' : _safe(report.resolvedRoot!)}',
  'Git: ${_git(report.repository)}',
];

String _git(RepositoryContext repository) => switch (repository.status) {
  RepositoryStatus.detected =>
    'detected · ${repository.relation.toWireName()} · '
        '${_safe(repository.root ?? '')}',
  final status => status.toWireName(),
};

List<String> _section(String title, List<String> items) => [
  '$title:',
  if (items.isEmpty) '  ninguno' else ...items,
];

String _item(List<String> fields, [List<String>? evidenceIds]) => [
  '  - ${fields.map(_safe).join(' · ')}',
  if (evidenceIds != null) 'evidencia ${evidenceIds.map(_safe).join(', ')}',
].join(' · ');

List<String> _proposal(RecognitionProposal proposal) => [
  'Propuesta: ${proposal.eligible ? 'elegible' : 'no elegible'}',
  if (!proposal.eligible || proposal.actions.isEmpty)
    '  ninguna'
  else
    for (final a in proposal.actions) _item([a.code, a.description]),
];

String _effects(RecognitionEffects effects) =>
    'Efectos: ${effects.filesWritten} archivos, '
    '${effects.directoriesCreated} directorios, '
    '${effects.processesStarted} procesos, '
    '${effects.networkRequests} solicitudes de red.';

String _safe(String value) => singleLine(value, maxRunes: _maxShownRunes);
