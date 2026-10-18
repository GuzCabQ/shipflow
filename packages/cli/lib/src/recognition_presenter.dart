import 'package:core/core.dart';

import 'cli_application.dart';
import 'cli_response.dart';
import 'terminal_text.dart';

const _recognitionType = 'init_dry_run';
const _unrecognizedExitCode = 65;
const _invalidRootExitCode = 66;
const _maxShownRunes = 240;

/// El código de salida de cada estado: un reconocimiento no verde sigue
/// siendo un reporte válido.
int recognitionExitCode(RecognitionStatus status) => switch (status) {
  RecognitionStatus.recognized => successExitCode,
  RecognitionStatus.ambiguous ||
  RecognitionStatus.unsupported => _unrecognizedExitCode,
  RecognitionStatus.invalidRoot => _invalidRootExitCode,
};

/// [report] como JSON de una línea o como vista humana, siempre en stdout.
CliResponse presentRecognition(RecognitionReport report, {required bool json}) {
  final exitCode = recognitionExitCode(report.status);
  if (json) {
    return jsonResponse(exitCode, {
      'schemaVersion': schemaVersion,
      'type': _recognitionType,
      ...report.toJson(),
      'exitCode': exitCode,
    });
  }
  return CliResponse(
    exitCode: exitCode,
    channel: CliOutputChannel.stdout,
    payload: '${_humanLines(report).join('\n')}\n',
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
