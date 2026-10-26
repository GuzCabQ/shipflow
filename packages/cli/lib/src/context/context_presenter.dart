import 'package:core/core.dart';

import '../cli_response.dart';
import '../terminal_text.dart';
import 'bounded_context_json.dart';
import 'state_layout.dart';

const _maxRunes = 160;
const _maxListed = 5;

/// La respuesta de [result]: JSON acotado de una línea, o la vista humana.
/// Ambas salen del mismo resultado; no se vuelve a inspeccionar.
CliResponse presentContext(
  ContextOperationResult result, {
  required bool json,
  required String root,
}) => CliResponse(
  exitCode: result.exitCode,
  channel: CliOutputChannel.stdout,
  payload: json ? encodeContextWithinLimit(result) : _human(result, root),
);

String _human(ContextOperationResult r, String root) {
  final lines = [
    'Shipflow · contexto del proyecto',
    _headline(r),
    'Carpeta: ${_shown(root)}',
    '',
    ..._context(r),
    ..._sharing(r),
    ..._findings(r),
    ..._effects(r),
    ..._next(r),
    'No se comprobó si el proyecto compila, si sus pruebas pasan, si respeta '
        'su arquitectura ni si el SDK está instalado.',
    '',
    'Para el detalle estructurado: shipflow '
        '${r.command == ContextCommand.doctor ? 'doctor' : 'init'} --json',
  ];
  return '${lines.join('\n')}\n';
}

/// Primero la consecuencia para la persona.
String _headline(ContextOperationResult r) => switch (r.outcome) {
  ContextOutcome.cancelled => 'Cancelado: no se escribió nada.',
  ContextOutcome.initialized => 'Contexto inicializado',
  ContextOutcome.refreshed => 'Contexto actualizado',
  ContextOutcome.recovered => 'Operación recuperada',
  ContextOutcome.available || ContextOutcome.unchanged => 'Contexto disponible',
  _ when r.contextState == ContextState.recoveryRequired =>
    'Hay una operación por recuperar',
  _ when r.freshness == ContextFreshness.stale => 'Necesita actualizarse',
  _
      when r.contextState == ContextState.absent &&
          r.exitCode == 65 &&
          r.diagnostics.any((d) => d.code == 'context_absent') =>
    'Todavía no hay contexto guardado',
  _ => 'No se pudo comprobar',
};

List<String> _context(ContextOperationResult r) {
  final context = r.context;
  if (context == null) return const [];
  final names = [for (final u in context.units) _shown(u.name)];
  final description = context.evidence
      .where((e) => e.role == EvidenceRole.description)
      .firstOrNull;
  return [
    'Contexto guardado: $projectPath',
    '  ${names.length == 1 ? '1 paquete' : '${names.length} paquetes'}: '
        '${names.take(_maxListed).join(', ')}'
        '${names.length > _maxListed ? ' y ${names.length - _maxListed} más' : ''}',
    if (description != null) '  Descripción: «${_shown(description.value)}»',
    '  ${_freshness(r.freshness)}',
    '',
  ];
}

String _freshness(ContextFreshness freshness) => switch (freshness) {
  ContextFreshness.current =>
    'Coincide con lo observado ahora, dentro de la misma cobertura.',
  ContextFreshness.stale => 'Lo observado ahora difiere de lo guardado.',
  ContextFreshness.unverified => 'No se pudo comparar con lo observado ahora.',
  ContextFreshness.notApplicable => 'Sin comparación.',
};

List<String> _sharing(ContextOperationResult r) => [
  'Conservación: ${switch ((r.sharing.choice, r.sharing.effective)) {
    (_, SharingEffective.shareReady) => 'listo para versionarlo con el proyecto; todavía tienes que incluirlo al guardar los cambios.',
    (_, SharingEffective.localExcluded) => 'sólo en esta copia; no se incluye al compartir cambios y necesita respaldo.',
    (_, SharingEffective.conflict) => 'la elección no está aplicada; revisa el motivo indicado.',
    (SharingChoice.pending, _) when r.sharing.gitState != GitState.available => 'sólo en esta copia; Shipflow no versiona ni comparte el contexto sin Git.',
    (SharingChoice.pending, _) => 'todavía no se eligió cómo conservarlo.',
    _ => 'no se pudo comprobar si la elección está aplicada.',
  }}',
  '',
];

List<String> _findings(ContextOperationResult r) {
  if (r.diagnostics.isEmpty) return const [];
  return [
    'Observaciones:',
    for (final d in r.diagnostics)
      '  - ${_shown(d.message)}${d.path == null ? '' : ' · ${_shown(d.path!)}'}',
    '',
  ];
}

List<String> _effects(ContextOperationResult r) {
  final e = r.effects;
  final lines = [
    for (final (label, paths) in [
      ('Creado', e.filesCreated),
      ('Reemplazado', e.filesReplaced),
      ('Eliminado', e.filesRemoved),
      ('Carpeta creada', e.directoriesCreated),
    ])
      for (final path in paths) '  $label: ${_shown(path)}',
    if (e.excludeModified) '  Se modificó el exclude local de Git.',
  ];
  return [
    'Cambios en disco:',
    if (lines.isEmpty) '  No se modificó ningún archivo.' else ...lines,
    '',
  ];
}

List<String> _next(ContextOperationResult r) {
  if (r.nextActions.isEmpty) return const [];
  return [
    'Siguiente acción:',
    for (final a in r.nextActions)
      '  shipflow ${a.command.toWireName()}'
          '${a.arguments.isEmpty ? '' : ' ${a.arguments.map(_shown).join(' ')}'}'
          ' — ${_shown(a.purpose)}',
    '',
  ];
}

String _shown(String value) => singleLine(value, maxRunes: _maxRunes);
