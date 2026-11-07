import 'package:core/core.dart';

import '../context/context_prompt.dart';
import 'basis_prompt_questions.dart';

/// Una clave nueva del lote para [prefix].
typedef GuideKeys = String Function(String prefix);

BasisChange _create(String key, BasisPayload payload) => BasisChange(
  key: key,
  targetId: null,
  expectedVersion: null,
  payload: payload,
);

/// Una decisión en lenguaje corriente: qué respetar, por qué, a qué aplica
/// y, si prohíbe, su alternativa y sus excepciones. Si falta algo para
/// activarla, queda como propuesta. Ofrece registrar su revisión pendiente.
Future<List<BasisChange>> askDecision(
  ContextPromptIO io,
  GuideKeys keys,
) async {
  final title = await ask(io, 'Título breve de la decisión:');
  final statement = await ask(io, '¿Qué se debe respetar?');
  final reason = await ask(io, '¿Por qué, o de dónde viene?');
  final scope = await askScope(
    io,
    '¿A qué parte aplica?',
    unknownAllowed: true,
  );
  final (cls, alternative, policy) = await _prohibition(io);
  final active =
      scope.kind != BasisScopeKind.unknown &&
      (cls != BasisRuleClass.prohibition ||
          (alternative != null && policy != BasisExceptionPolicy.unspecified));
  if (!active) {
    io.show('Queda como propuesta: le falta ámbito, alternativa o política.\n');
  }
  final key = keys('decision');
  final rule = _rule(title, statement, reason, scope, active, (
    cls,
    alternative,
    policy,
  ));
  return [
    _create(key, rule),
    if (active) ...await _review(io, keys, key, rule),
  ];
}

BasisRule _rule(
  String title,
  String statement,
  String reason,
  BasisScope scope,
  bool active,
  (BasisRuleClass, String?, BasisExceptionPolicy) kind,
) => BasisRule(
  title: title,
  scope: scope,
  lifecycle: active ? BasisRuleLifecycle.active : BasisRuleLifecycle.proposed,
  replacementRef: null,
  statement: statement,
  reason: reason,
  ruleClass: kind.$1,
  alternative: kind.$2,
  exceptionPolicy: kind.$3,
  support: BasisSupport.humanDeclaration,
  sourceRefs: const [],
);

Future<(BasisRuleClass, String?, BasisExceptionPolicy)> _prohibition(
  ContextPromptIO io,
) async {
  if (!await yesNo(io, '¿Prohíbe algo?')) {
    return (BasisRuleClass.obligation, null, BasisExceptionPolicy.unspecified);
  }
  final alternative = await ask(
    io,
    '¿Qué alternativa está permitida? (vacío si todavía no se sabe)',
    optional: true,
  );
  final policy = await choose(io, '¿Admite excepciones?', const [
    ('No', BasisExceptionPolicy.notAllowed),
    ('Sólo con autorización', BasisExceptionPolicy.requiresAuthority),
    ('Todavía no se sabe', BasisExceptionPolicy.unspecified),
  ]);
  return (
    BasisRuleClass.prohibition,
    alternative.isEmpty ? null : alternative,
    policy,
  );
}

/// La revisión pendiente de la decisión recién preparada, si la hay: el
/// mismo ámbito y la versión 1 de esa regla; el responsable es opcional.
Future<List<BasisChange>> _review(
  ContextPromptIO io,
  GuideKeys keys,
  String ruleKey,
  BasisRule rule,
) async {
  if (!await yesNo(
    io,
    '¿Queda algo por revisar de esta decisión más adelante?',
  )) {
    return const [];
  }
  final question = await ask(io, '¿Qué falta confirmar?');
  final reason = await ask(io, '¿Por qué sigue pendiente?');
  final when = await ask(
    io,
    '¿Cuándo volver a mirarlo? (una fecha o un acontecimiento)',
  );
  final reviewer = await ask(
    io,
    '¿Quién lo revisará? (vacío: por definir)',
    optional: true,
  );
  if (reviewer.isEmpty) {
    io.show('Responsable por definir: no impide guardar.\n');
  }
  return [
    _create(
      keys('review'),
      _reviewPending(rule.scope, (question, reason, when), ruleKey, reviewer),
    ),
  ];
}

BasisPending _reviewPending(
  BasisScope scope,
  (String, String, String) asked,
  String ruleKey,
  String reviewer,
) => BasisPending(
  title: 'Revisión pendiente',
  scope: scope,
  status: BasisPendingStatus.open,
  question: asked.$1,
  reason: asked.$2,
  revisitWhen: asked.$3,
  sourceRefs: const [],
  resolution: null,
  decisionReview: BasisDecisionReview(
    ref: 'new:$ruleKey',
    version: 1,
    reviewer: reviewer.isEmpty ? null : reviewer,
  ),
);

/// Una fuente señalada: registrarla no adopta su contenido como reglas.
Future<List<BasisChange>> askSource(ContextPromptIO io, GuideKeys keys) async {
  final title = await ask(io, 'Título de la fuente:');
  final locator = await ask(
    io,
    'Ubicación (una ruta del proyecto o https://…):',
  );
  final purpose = await ask(io, '¿Para qué sirve como referencia?');
  final scope = await askScope(
    io,
    '¿A qué parte aplica?',
    unknownAllowed: true,
  );
  final external = locator.startsWith('https://');
  return [
    _create(
      keys('source'),
      BasisSource(
        title: title,
        scope: scope,
        lifecycle: BasisSourceLifecycle.active,
        sourceType: external ? BasisSourceType.external : BasisSourceType.local,
        locator: locator,
        purpose: purpose,
        contentDigest: null,
        observation: BasisObservation.unverified,
      ),
    ),
  ];
}

/// Un asunto por aclarar: se conserva sin forzar una aceptación.
Future<List<BasisChange>> askPending(ContextPromptIO io, GuideKeys keys) async {
  final title = await ask(io, 'Título breve del asunto:');
  final question = await ask(io, '¿Qué falta aclarar?');
  final reason = await ask(io, '¿Por qué está pendiente?');
  final when = await ask(
    io,
    '¿Cuándo volver a mirarlo? (una fecha o un acontecimiento)',
  );
  final scope = await askScope(
    io,
    '¿A qué parte aplica?',
    unknownAllowed: true,
  );
  return [
    _create(
      keys('pending'),
      BasisPending(
        title: title,
        scope: scope,
        status: BasisPendingStatus.open,
        question: question,
        reason: reason,
        revisitWhen: when,
        sourceRefs: const [],
        resolution: null,
        decisionReview: null,
      ),
    ),
  ];
}
