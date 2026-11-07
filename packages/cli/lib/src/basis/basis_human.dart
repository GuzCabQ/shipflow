import 'package:core/core.dart';

import '../terminal_text.dart';
import 'basis_catalog.dart';
import 'basis_human_records.dart';

/// La vista humana de [result], derivada de los mismos datos que el JSON:
/// qué se consultó o hizo, las reglas vigentes, lo pendiente, las
/// decisiones históricas que esas revisiones citan, los soportes y los
/// límites de lo que Shipflow puede afirmar. El texto de los registros
/// nunca controla la terminal.
String renderBasisHuman(BasisResponse result) {
  final lines = <String>[
    _header(result),
    ?_declarer(result),
    ..._storage(result.storageIntegrity),
    if (_presents(result)) _coverage(result.normativeCoverage),
    ...recordSections(result),
    if (_presents(result)) ..._guarantees(),
    ..._problems(result.diagnostics),
    ..._actions(result.nextActions),
  ];
  return '${lines.join('\n')}\n';
}

bool _presents(BasisResponse r) =>
    r.selected.isNotEmpty ||
    r.pending.isNotEmpty ||
    r.history.isNotEmpty ||
    const {
      BasisOutcome.shown,
      BasisOutcome.published,
      BasisOutcome.draftPrepared,
    }.contains(r.outcome);

String _header(BasisResponse r) {
  final digest = r.draftDigest == null ? '' : '\nHuella: ${r.draftDigest}';
  return switch (r.outcome) {
    BasisOutcome.published => 'Base guardada en shipflow/basis.json.',
    BasisOutcome.shown when isDraftView(r) =>
      'Borrador guardado: todavía no está aceptado.$digest',
    BasisOutcome.shown => 'Base aceptada${_scope(r.selection.scope)}.',
    BasisOutcome.draftPrepared =>
      'Borrador preparado: todavía no está aceptado.$digest',
    BasisOutcome.discarded =>
      'Borrador descartado: la base aceptada no cambió.',
    BasisOutcome.abortedBeforePublication =>
      'Se abortó una publicación que no había ocurrido: la base aceptada no '
          'cambió.',
    BasisOutcome.alreadyApplied =>
      'Ese borrador ya estaba aceptado: no se creó otra revisión.',
    BasisOutcome.recovered => 'Publicación pendiente resuelta.',
    BasisOutcome.noChanges => 'No había nada que cambiar.',
    BasisOutcome.choiceRequired =>
      'Falta elegir una operación: sin terminal no se pregunta.',
    BasisOutcome.cancelled => 'Se canceló: nada se aceptó.',
    _ => 'No se completó la operación.',
  };
}

/// Quién declaró la propuesta o la aceptación de esta operación; nunca se
/// atribuye a las reglas que ya estaban aceptadas.
String? _declarer(BasisResponse r) {
  final actor = r.actor;
  if (actor == null) return null;
  final scope = actor.scope.kind == BasisScopeKind.project
      ? 'todo el proyecto'
      : actor.scope.paths.map(_text).join(', ');
  final what = isDraftView(r) ? 'Propuesta declarada' : 'Declarado';
  return '$what por ${_text(actor.label)} (${_text(actor.role)}) · ámbito '
      '$scope; autoridad local, sin autenticar.';
}

String _scope(BasisScope? scope) => scope == null
    ? ' · todo el proyecto'
    : ' · ámbito consultado: ${scope.paths.map(_text).join(', ')}';

String _text(String value) => singleLine(value, maxRunes: 200);

const _files = {
  'basis': 'shipflow/basis.json',
  'draft': 'shipflow/local/basis-draft.json',
  'transaction': 'shipflow/local/basis-transaction.json',
};

/// Un archivo propio que no se pudo usar se dice, aparte del código.
List<String> _storage(BasisStorageIntegrity integrity) => [
  for (final (key, state) in [
    ('basis', integrity.basis),
    ('draft', integrity.draft),
    ('transaction', integrity.transaction),
  ])
    if (state == BasisIntegrity.invalid)
      '${_files[key]} no cumple su formato: se conserva sin usarlo.'
    else if (state == BasisIntegrity.incompatible)
      '${_files[key]} tiene una versión que este binario no soporta.',
];

String _coverage(BasisCoverage coverage) => switch (coverage) {
  BasisCoverage.notEstablished =>
    'Cobertura normativa no establecida: que no haya decisiones vigentes '
        'no significa que el proyecto no tenga reglas.',
  BasisCoverage.declaredPartial =>
    'Cobertura normativa declarada y parcial: puede haber reglas que nadie '
        'registró.',
};

List<String> _guarantees() => const [
  '',
  'Aceptación local declarada: Shipflow no autentica quién la declara. No se '
      'comprobó automáticamente que el negocio sea correcto ni que todas las '
      'reglas estén registradas.',
];

List<String> _problems(List<BasisDiagnostic> diagnostics) => [
  if (diagnostics.isNotEmpty) ...['', 'Avisos:'],
  for (final d in diagnostics)
    '- ${_text(d.message)}${d.path == null ? '' : ' (${_text(d.path!)})'}'
        '${isBasisWarning(d.code) ? '' : ' [${d.code}]'}',
];

List<String> _actions(List<BasisAction> actions) => [
  if (actions.isNotEmpty) ...['', 'Siguientes pasos:'],
  for (final a in actions)
    '  shipflow ${a.command} ${a.arguments.map(_text).join(' ')}'
        '  # ${_text(a.purpose)}',
];
