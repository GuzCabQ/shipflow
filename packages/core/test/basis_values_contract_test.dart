import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Los bytes esperados son literales: un oráculo fijo, independiente de la
// serialización que se prueba.
const _scope = '{"kind":"paths","paths":["lib/b","lib/a"]}';
const _actor =
    '{"label":"Ana","role":"mantenimiento","authority":"local_declared",'
    '"scope":$_scope}';
const _ref = '{"ref":"source-1","version":3}';
const _review = '{"ref":"rule-1","version":2,"reviewer":null}';
const _rule =
    '{"kind":"rule","title":"Contratos","scope":{"kind":"project","paths":[]},'
    '"lifecycle":"active","replacementRef":null,"statement":"S.",'
    '"reason":"R.","ruleClass":"obligation","alternative":null,'
    '"exceptionPolicy":"requires_authority","support":"human_declaration",'
    '"sourceRefs":[$_ref],"evidenceLevel":"declared"}';
const _pending =
    '{"kind":"pending","title":"Revisión","scope":{"kind":"unknown","paths":[]},'
    '"status":"open","question":"¿Q?","reason":"R.","revisitWhen":"W.",'
    '"sourceRefs":[$_ref],"resolution":null,"decisionReview":$_review}';
const _document =
    '{"schemaVersion":1,"type":"shipflow.basis","projectId":"p","revision":1,'
    '"producerVersion":"0.0.0","validatorVersion":1,"queryVersion":1,'
    '"events":[{"revision":1,"operationId":"op-1","acceptedAt":"T",'
    '"actor":$_actor,"reason":"R.","draftDigest":"d",'
    '"previousEventDigest":null,"changes":['
    '{"id":"rule-1","version":1,"previousVersion":null,"payload":$_rule},'
    '{"id":"pending-1","version":1,"previousVersion":null,'
    '"payload":$_pending}],"eventDigest":"e"}],"digest":"g"}';

Map<String, Object?> _decoded(String text) =>
    jsonDecode(text) as Map<String, Object?>;

BasisScope _paths() =>
    BasisScope(kind: BasisScopeKind.paths, paths: ['lib/b', 'lib/a']);

BasisActor _actorOf() =>
    BasisActor(label: 'Ana', role: 'mantenimiento', scope: _paths());

BasisReference _refOf() => BasisReference(ref: 'source-1', version: 3);

BasisDecisionReview _reviewOf() =>
    BasisDecisionReview(ref: 'rule-1', version: 2, reviewer: null);

BasisRule _ruleOf() => BasisRule(
  title: 'Contratos',
  scope: BasisScope.project(),
  lifecycle: BasisRuleLifecycle.active,
  replacementRef: null,
  statement: 'S.',
  reason: 'R.',
  ruleClass: BasisRuleClass.obligation,
  alternative: null,
  exceptionPolicy: BasisExceptionPolicy.requiresAuthority,
  support: BasisSupport.humanDeclaration,
  sourceRefs: [_refOf()],
);

BasisPending _pendingOf() => BasisPending(
  title: 'Revisión',
  scope: BasisScope.unknown(),
  status: BasisPendingStatus.open,
  question: '¿Q?',
  reason: 'R.',
  revisitWhen: 'W.',
  sourceRefs: [_refOf()],
  resolution: null,
  decisionReview: _reviewOf(),
);

BasisRecordVersion _firstVersion(String id, BasisPayload payload) =>
    BasisRecordVersion(
      id: id,
      version: 1,
      previousVersion: null,
      payload: payload,
    );

BasisDocument _documentOf() => BasisDocument(
  projectId: 'p',
  revision: 1,
  producerVersion: '0.0.0',
  events: [
    BasisEvent(
      revision: 1,
      operationId: 'op-1',
      acceptedAt: 'T',
      actor: _actorOf(),
      reason: 'R.',
      draftDigest: 'd',
      previousEventDigest: null,
      changes: [
        _firstVersion('rule-1', _ruleOf()),
        _firstVersion('pending-1', _pendingOf()),
      ],
      eventDigest: 'e',
    ),
  ],
  digest: 'g',
);

void main() {
  test('scope keeps its paths and compares them as a set', () {
    final input = ['lib/b', 'lib/a'];
    final scope = BasisScope(kind: BasisScopeKind.paths, paths: input);
    input.add('lib/c');
    final again = ['lib/a', 'lib/b', 'lib/a'];

    expect(jsonEncode(scope.toJson()), _scope);
    expect(() => scope.paths.add('x'), throwsUnsupportedError);
    expect(
      scope.sameAs(BasisScope(kind: BasisScopeKind.paths, paths: again)),
      isTrue,
    );
    expect(scope.sameAs(BasisScope.project()), isFalse);
    expect(
      jsonEncode(BasisScope.project().toJson()),
      '{"kind":"project","paths":[]}',
    );
    expect(
      jsonEncode(BasisScope.unknown().toJson()),
      '{"kind":"unknown","paths":[]}',
    );
    expect(jsonEncode(BasisScope.fromJson(_decoded(_scope)).toJson()), _scope);
  });

  test('actor declares local authority and rejects any other', () {
    final actor = _actorOf();
    final foreign = _decoded(_actor)..['authority'] = 'remote';

    expect(jsonEncode(actor.toJson()), _actor);
    expect(actor.authority, 'local_declared');
    expect(jsonEncode(BasisActor.fromJson(_decoded(_actor)).toJson()), _actor);
    expect(
      () => BasisActor.fromJson(foreign),
      throwsA(
        isA<ContextFormatException>()
            .having((e) => e.layer, 'layer', ContextFormatLayer.semantic)
            .having((e) => e.code, 'code', 'invalid_schema')
            .having((e) => e.at, 'at', ''),
      ),
    );
  });

  test('references and reviews keep their keys', () {
    const named = '{"ref":"rule-1","version":2,"reviewer":"Ana"}';
    final review = BasisDecisionReview(
      ref: 'rule-1',
      version: 2,
      reviewer: 'Ana',
    );

    expect(jsonEncode(_refOf().toJson()), _ref);
    expect(jsonEncode(_reviewOf().toJson()), _review);
    expect(jsonEncode(review.toJson()), named);
    expect(jsonEncode(BasisReference.fromJson(_decoded(_ref)).toJson()), _ref);
    for (final text in [_review, named]) {
      final back = BasisDecisionReview.fromJson(_decoded(text));
      expect(jsonEncode(back.toJson()), text);
    }
  });

  test('payloads embed scope and references unchanged', () {
    expect(jsonEncode(_ruleOf().toJson()), _rule);
    expect(jsonEncode(_pendingOf().toJson()), _pending);
    for (final text in [_rule, _pending]) {
      final back = BasisPayload.fromJson(_decoded(text));
      expect(jsonEncode(back.toJson()), text);
    }
  });

  test('a basis document keeps its bytes', () {
    final back = BasisDocument.fromJson(_decoded(_document));

    expect(jsonEncode(_documentOf().toJson()), _document);
    expect(jsonEncode(back.toJson()), _document);
    expect(basisType, 'shipflow.basis');
  });

  test('the barrel exposes the moved constructors', () {
    // Asignabilidad, no igualdad exacta: la igualdad la da el volcado de API.
    final BasisScope Function({
      required BasisScopeKind kind,
      required List<String> paths,
    })
    scopeNew = BasisScope.new;
    final BasisActor Function({
      required String label,
      required String role,
      required BasisScope scope,
    })
    actorNew = BasisActor.new;
    final BasisReference Function({required String ref, required int version})
    refNew = BasisReference.new;
    final BasisDecisionReview Function({
      required String ref,
      required int version,
      required String? reviewer,
    })
    reviewNew = BasisDecisionReview.new;

    expect([scopeNew, actorNew, refNew, reviewNew], hasLength(4));
  });

  test('the barrel exposes the named constructors and readers', () {
    final List<BasisScope Function()> named = [
      BasisScope.project,
      BasisScope.unknown,
    ];
    final List<Object Function(Map<String, Object?>)> readers = [
      BasisScope.fromJson,
      BasisActor.fromJson,
      BasisReference.fromJson,
      BasisDecisionReview.fromJson,
    ];

    expect([...named, ...readers], hasLength(6));
  });
}
