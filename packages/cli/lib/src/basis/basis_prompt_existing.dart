import 'package:core/core.dart';

import '../context/context_prompt.dart';
import '../terminal_text.dart';
import 'basis_prompt_changes.dart';
import 'basis_prompt_questions.dart';

/// Revisa una decisión vigente: cada respuesta vacía conserva lo aceptado,
/// y cambiar su ámbito se elige expresamente. Ofrece registrar la revisión
/// de la versión nueva.
Future<List<BasisChange>> askRevision(
  ContextPromptIO io,
  GuideKeys keys,
  List<BasisRecordVersion> rules,
) async {
  final v = await _pick(io, '¿Qué decisión quieres revisar?', rules);
  final rule = v.payload as BasisRule;
  final statement = await _kept(io, 'Nuevo enunciado');
  final reason = await _kept(io, '¿Por qué, o de dónde viene ahora?');
  final scope = await _scopeOf(io, rule);
  final revised = _rule(
    rule,
    statement: statement,
    reason: reason,
    scope: scope,
  );
  return [
    _change(keys('revision'), v, revised),
    ...await askReview(
      io,
      keys,
      ref: v.id,
      version: v.version + 1,
      scope: scope,
    ),
  ];
}

/// La respuesta nueva, o null para conservar lo aceptado.
Future<String?> _kept(ContextPromptIO io, String question) async {
  final answer = await ask(
    io,
    '$question (vacío: se conserva)',
    optional: true,
  );
  return answer.isEmpty ? null : answer;
}

/// El ámbito que se conserva, salvo que se elija cambiarlo expresamente.
Future<BasisScope> _scopeOf(ContextPromptIO io, BasisRule rule) async =>
    await yesNo(io, '¿Cambia la parte a la que aplica?')
    ? await askScope(io, '¿A qué parte aplica ahora?', unknownAllowed: false)
    : rule.scope;

/// Retira una decisión vigente, sólo con confirmación; sigue en la historia.
Future<List<BasisChange>> askRetirement(
  ContextPromptIO io,
  GuideKeys keys,
  List<BasisRecordVersion> rules,
) async {
  final v = await _pick(io, '¿Qué decisión quieres retirar?', rules);
  final rule = v.payload as BasisRule;
  if (!await yesNo(
    io,
    '¿Retirar «${singleLine(rule.title, maxRunes: 200)}»? Seguirá visible en la historia.',
  )) {
    return const [];
  }
  final retired = _rule(rule, lifecycle: BasisRuleLifecycle.retired);
  return [_change(keys('retiro'), v, retired)];
}

/// Resuelve un pendiente abierto con lo que se decidió; una revisión
/// conserva la versión exacta que revisaba.
Future<List<BasisChange>> askResolution(
  ContextPromptIO io,
  GuideKeys keys,
  List<BasisRecordVersion> pending,
) async {
  final v = await _pick(io, '¿Qué asunto quieres resolver?', pending);
  final p = v.payload as BasisPending;
  final how = await ask(io, '¿Cómo se resolvió?');
  final resolved = BasisPending(
    title: p.title,
    scope: p.scope,
    status: BasisPendingStatus.resolved,
    question: p.question,
    reason: p.reason,
    revisitWhen: p.revisitWhen,
    sourceRefs: p.sourceRefs,
    resolution: 'disposition:$how',
    decisionReview: p.decisionReview,
  );
  return [_change(keys('resuelto'), v, resolved)];
}

Future<BasisRecordVersion> _pick(
  ContextPromptIO io,
  String question,
  List<BasisRecordVersion> records,
) => choose(io, question, [for (final v in records) (_label(v), v)]);

String _label(BasisRecordVersion v) {
  final detail = switch (v.payload) {
    BasisRule(:final statement) => statement,
    BasisPending(:final question) => question,
    _ => '',
  };
  return '«${singleLine(v.payload.title, maxRunes: 60)}» versión '
      '${v.version}: ${singleLine(detail, maxRunes: 80)}';
}

BasisChange _change(String key, BasisRecordVersion v, BasisPayload payload) =>
    BasisChange(
      key: key,
      targetId: v.id,
      expectedVersion: v.version,
      payload: payload,
    );

BasisRule _rule(
  BasisRule r, {
  String? statement,
  String? reason,
  BasisScope? scope,
  BasisRuleLifecycle? lifecycle,
}) => BasisRule(
  title: r.title,
  scope: scope ?? r.scope,
  lifecycle: lifecycle ?? r.lifecycle,
  replacementRef: r.replacementRef,
  statement: statement ?? r.statement,
  reason: reason ?? r.reason,
  ruleClass: r.ruleClass,
  alternative: r.alternative,
  exceptionPolicy: r.exceptionPolicy,
  support: r.support,
  sourceRefs: r.sourceRefs,
);
