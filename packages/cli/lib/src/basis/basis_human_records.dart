import 'package:core/core.dart';

import '../terminal_text.dart';

/// Las secciones de registros de la vista humana. Las reglas vigentes, lo
/// pendiente y las decisiones históricas que citan las revisiones van por
/// separado: una revisión no convierte su versión en regla vigente.
List<String> recordSections(BasisResponse r) {
  final draft = isDraftView(r);
  final rules = [
    for (final v in r.selected)
      if (v.payload is BasisRule) v,
  ];
  return [
    if (rules.isNotEmpty) ...['', 'Reglas vigentes:'],
    for (final v in rules) ..._rule(v, r.actor, draft: draft),
    if (r.pending.isNotEmpty) ...['', 'Pendientes:'],
    for (final v in r.pending) ..._pending(v, r.reviewTargets),
    if (r.reviewTargets.isNotEmpty) ...[
      '',
      'Decisión a la que corresponde esta revisión:',
    ],
    for (final v in r.reviewTargets) ..._target(v),
    if (r.sourceStatus.isNotEmpty) ...['', 'Fuentes:'],
    for (final s in r.sourceStatus) _source(s, r.selected),
    if (r.selection.excludedCount > 0)
      '${r.selection.excludedCount} registro(s) quedaron fuera del ámbito '
          'consultado.',
    if (r.history.isNotEmpty) ...['', 'Historia:'],
    ..._history(r.history),
  ];
}

/// Si [r] presenta un borrador: su estado sólo cuenta como aceptado al
/// aceptar su huella exacta.
bool isDraftView(BasisResponse r) =>
    r.outcome == BasisOutcome.draftPrepared ||
    (r.outcome == BasisOutcome.shown &&
        r.draftDigest != null &&
        r.history.isEmpty);

String _t(String value, [int max = 200]) => singleLine(value, maxRunes: max);

String _scope(BasisScope scope) => switch (scope.kind) {
  BasisScopeKind.project => 'todo el proyecto',
  BasisScopeKind.unknown => 'ámbito todavía desconocido',
  BasisScopeKind.paths => scope.paths.map(_t).join(', '),
};

List<String> _rule(
  BasisRecordVersion v,
  BasisActor? actor, {
  required bool draft,
}) {
  final rule = v.payload as BasisRule;
  return [
    '• «${_t(rule.title)}» · versión ${v.version} · ${_scope(rule.scope)}',
    '  ${_t(rule.statement, 600)}',
    '  Motivo: ${_t(rule.reason, 400)}',
    if (rule.ruleClass == BasisRuleClass.prohibition)
      '  Alternativa: ${_t(rule.alternative ?? 'sin definir')} · '
          'Excepciones: ${_policy(rule.exceptionPolicy)}',
    if (rule.lifecycle == BasisRuleLifecycle.active && draft)
      '  Decisión del borrador${_declared(actor)}: no cuenta como aceptado '
          'hasta aceptar su huella.'
    else if (rule.lifecycle == BasisRuleLifecycle.active)
      '  Decisión aceptada por el usuario${_declared(actor)}.'
    else
      '  Propuesta: todavía no es una decisión vigente.',
    if (rule.support == BasisSupport.sourceSupported)
      '  Se sustenta en fuentes: su estado está en «Fuentes».',
  ];
}

String _declared(BasisActor? actor) => actor == null
    ? ' (autoridad local declarada)'
    : ' (declaró ${_t(actor.label)}, ${_t(actor.role)}; autoridad local)';

String _policy(BasisExceptionPolicy policy) => switch (policy) {
  BasisExceptionPolicy.notAllowed => 'no se admiten',
  BasisExceptionPolicy.requiresAuthority => 'requieren autorización',
  BasisExceptionPolicy.unspecified => 'sin definir',
};

List<String> _pending(BasisRecordVersion v, List<BasisRecordVersion> targets) {
  final payload = v.payload;
  if (payload is BasisRule) {
    return [
      '• Propuesta «${_t(payload.title)}»: ${_t(payload.statement, 400)}',
    ];
  }
  final p = payload as BasisPending;
  final link = p.decisionReview;
  return [
    '• Este aspecto sigue pendiente: ${_t(p.question, 400)}',
    '  Motivo: ${_t(p.reason, 400)}',
    '  Volver a mirarlo: ${_t(p.revisitWhen, 400)}',
    if (link != null) ...[
      '  Revisa ${_titleOf(link, targets)} versión ${link.version}.',
      '  ${link.reviewer == null ? 'Responsable por definir' : 'Responsable: ${_t(link.reviewer!)}'}.',
    ] else if (p.scope.kind == BasisScopeKind.unknown)
      '  Ámbito todavía desconocido: no se da por aplicable ni por excluido.',
  ];
}

String _titleOf(BasisDecisionReview link, List<BasisRecordVersion> targets) {
  for (final t in targets) {
    if (t.id == link.ref && t.version == link.version) {
      return 'la decisión «${_t(t.payload.title)}»';
    }
  }
  return 'una decisión';
}

List<String> _target(BasisRecordVersion v) => [
  '• «${_t(v.payload.title)}» versión ${v.version}: es la versión que motivó '
      'la revisión, no necesariamente la regla vigente.',
  if (v.payload.citedSources.isNotEmpty)
    '  Soportes de la decisión histórica no revalidados.',
];

String _source(BasisSourceStatus s, List<BasisRecordVersion> selected) {
  final version = selected
      .where((v) => v.id == s.sourceId && v.version == s.sourceVersion)
      .firstOrNull;
  final name = version == null
      ? 'Fuente'
      : '«${_t(version.payload.title)}» '
            '(${_t((version.payload as BasisSource).locator)})';
  final detail = s.diagnostics.isEmpty
      ? ''
      : ' ${_t(s.diagnostics.first.message)}';
  return switch (s.status) {
    BasisSourceState.current =>
      '• $name: La fuente no cambió desde su registro. Eso no certifica la '
          'decisión ni que su premisa siga vigente.',
    BasisSourceState.stale =>
      '• $name: La fuente cambió desde su registro: su soporte no está '
          'vigente.',
    BasisSourceState.unverified => '• $name: no se pudo comprobar.$detail',
    BasisSourceState.excluded => '• $name: excluida.$detail',
  };
}

/// Cada revisión con sus cambios; una revisión pendiente nombra la versión
/// exacta que revisa, con el título que esa regla tenía en la historia.
List<String> _history(List<BasisEvent> events) {
  final titles = <String, String>{};
  final lines = <String>[];
  for (final e in events) {
    for (final c in e.changes) {
      titles[c.id] = c.payload.title;
    }
    lines
      ..add(_event(e))
      ..addAll(e.changes.map((c) => _change(c, titles)));
  }
  return lines;
}

String _change(BasisRecordVersion c, Map<String, String> titles) {
  final kind = switch (c.payload) {
    BasisRule() => 'regla',
    BasisSource() => 'fuente',
    _ => 'pendiente',
  };
  final head = '  «${_t(c.payload.title)}» $kind · versión ${c.version}';
  return switch (c.payload) {
    BasisPending(:final decisionReview?) =>
      '$head · revisa la versión ${decisionReview.version} de '
          '«${_t(titles[decisionReview.ref] ?? decisionReview.ref)}»',
    _ => head,
  };
}

String _event(BasisEvent e) =>
    '• Revisión ${e.revision} · ${_t(e.acceptedAt)} · ${_t(e.actor.label)} '
    '(${_t(e.actor.role)}) · ${e.changes.length} cambio(s) · '
    '${_t(e.reason, 300)}';
