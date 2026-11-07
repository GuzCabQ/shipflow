import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_codec.dart';
import 'package:cli/src/basis/basis_preflight.dart';
import 'package:cli/src/basis/basis_service.dart';
import 'package:cli/src/basis/basis_sources.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:cli/src/context/state_layout.dart';
import 'package:core/core.dart';

import 'context_service_support.dart';

/// Un proyecto inicializado con V2 y el servicio de la base sobre el
/// almacén anclado real, con IDs y reloj deterministas.
final class BasisBox {
  BasisBox._(this.box);

  static Future<BasisBox> initialized() async {
    final box = ServiceSandbox.create()..project();
    final result = await box.run(ContextOperation.init);
    if (result.exitCode != 0) throw StateError('init: ${result.exitCode}');
    return BasisBox._(box);
  }

  /// Sobre un proyecto ya inicializado por otra caja.
  factory BasisBox.on(ServiceSandbox box) => BasisBox._(box);

  final ServiceSandbox box;
  var clock = DateTime.utc(2026, 11, 6, 12);
  var _ids = 0;
  BasisLimits limits = BasisLimits.forProfile(BasisProfile.standard);

  /// Una envoltura del almacén, para provocar fallos y carreras.
  ContextStore Function(ContextStore real)? storeWrap;

  String newId() =>
      'bbbbbbbb-0000-4000-8000-${(++_ids).toRadixString(16).padLeft(12, '0')}';

  String path(String relative) => box.path(relative);
  File get basis => File(path('shipflow/basis.json'));
  File get draft => File(path('shipflow/local/basis-draft.json'));
  File get journal => File(path('shipflow/local/basis-transaction.json'));

  String get projectId =>
      (jsonDecode(File(path('shipflow/project.json')).readAsStringSync())
              as Map<String, Object?>)['projectId']!
          as String;

  BasisDocument get document =>
      decodeBasis(basis.readAsBytesSync(), limits: limits);

  Future<T> using<T>(Future<T> Function(BasisService service) body) async {
    final real = await SecureContextStore.open(box.root);
    final store = storeWrap?.call(real) ?? real;
    try {
      return await body(
        BasisService(
          store: store,
          reader: BasisSourceReader(store),
          readProject: () => readBasisEnvironment(store),
          newId: newId,
          now: () => clock,
          limits: limits,
          version: '0.0.0-prueba',
          observeLayout: () => observeStateLayout(box.root),
        ),
      );
    } finally {
      await real.close();
    }
  }

  Future<BasisResponse> prepare(BasisInput input) =>
      using((s) => s.prepare(input));

  Future<BasisResponse> accept(String digest) => using((s) => s.accept(digest));

  Future<BasisResponse> discard(String digest) =>
      using((s) => s.discard(digest));

  Future<BasisResponse> recover() => using((s) => s.recover());

  Future<BasisResponse> show({
    String? path,
    bool history = false,
    bool draft = false,
  }) => using((s) => s.show(path: path, history: history, draft: draft));

  /// Prepara y acepta [input]; falla la prueba si no se publica.
  Future<BasisResponse> publish(BasisInput input) async {
    final prepared = await prepare(input);
    if (prepared.draftDigest == null) {
      throw StateError('prepare: ${codesOf(prepared)}');
    }
    final accepted = await accept(prepared.draftDigest!);
    if (!accepted.published) throw StateError('accept: ${codesOf(accepted)}');
    return accepted;
  }

  BasisInput input(
    List<BasisChange> changes, {
    String? expected,
    BasisActor? actor,
    bool currentBase = true,
  }) => BasisInput(
    projectId: projectId,
    expectedBasisDigest:
        expected ??
        (currentBase && basis.existsSync() ? document.digest : null),
    actor: actor ?? actorOf(),
    reason: 'Propuesta de prueba.',
    changes: changes,
  );

  Map<String, String> snapshot() => box.snapshot();

  void dispose() => box.dispose();
}

List<String> codesOf(BasisResponse r) => [
  for (final d in r.diagnostics) d.code,
];

BasisActor actorOf([BasisScope? scope]) => BasisActor(
  label: 'Ana',
  role: 'mantenimiento',
  scope: scope ?? BasisScope.project(),
);

BasisScope at(List<String> prefixes) =>
    BasisScope(kind: BasisScopeKind.paths, paths: prefixes);

BasisChange create(String key, BasisPayload payload) => BasisChange(
  key: key,
  targetId: null,
  expectedVersion: null,
  payload: payload,
);

BasisChange revise(String id, int expected, BasisPayload payload) =>
    BasisChange(
      key: 'k${id.substring(0, 8)}',
      targetId: id,
      expectedVersion: expected,
      payload: payload,
    );

BasisRule ruleOf({
  BasisScope? scope,
  BasisRuleLifecycle lifecycle = BasisRuleLifecycle.active,
  String? replacementRef,
  BasisSupport support = BasisSupport.humanDeclaration,
  List<BasisReference> sourceRefs = const [],
  String statement = 'Los contratos públicos se revisan.',
}) => BasisRule(
  title: 'Contratos',
  scope: scope ?? BasisScope.project(),
  lifecycle: lifecycle,
  replacementRef: replacementRef,
  statement: statement,
  reason: 'Compatibilidad.',
  ruleClass: BasisRuleClass.obligation,
  alternative: null,
  exceptionPolicy: BasisExceptionPolicy.requiresAuthority,
  support: support,
  sourceRefs: sourceRefs,
);

BasisPending pendingOf({
  BasisScope? scope,
  BasisDecisionReview? review,
  BasisPendingStatus status = BasisPendingStatus.open,
  String? resolution,
}) => BasisPending(
  title: 'Revisión',
  scope: scope ?? BasisScope.project(),
  status: status,
  question: '¿Sigue valiendo?',
  reason: 'Falta confirmar consumidores.',
  revisitWhen: 'Al integrar el segundo consumidor.',
  sourceRefs: const [],
  resolution: resolution,
  decisionReview: review,
);

BasisSource localSource(String locator) => BasisSource(
  title: 'Política',
  scope: BasisScope.project(),
  lifecycle: BasisSourceLifecycle.active,
  sourceType: BasisSourceType.local,
  locator: locator,
  purpose: 'Referencia.',
  contentDigest: null,
  observation: BasisObservation.unverified,
);

/// Una regla sustentada en la fuente nueva `new:doc`.
List<BasisChange> ruleWithSource(String locator) => [
  create('doc', localSource(locator)),
  create(
    'rule',
    ruleOf(
      support: BasisSupport.sourceSupported,
      sourceRefs: [BasisReference(ref: 'new:doc', version: 1)],
    ),
  ),
];

/// La versión actual del primer registro de [kind] en la base publicada.
BasisRecordVersion currentOf(BasisBox box, String kind) =>
    replayBasis(box.document).values.firstWhere((v) => v.payload.kind == kind);

/// Prepara [changes] y muere justo antes del rename: queda un journal de
/// bootstrap preparado y la base como estaba.
Future<String> interruptBasis(BasisBox box, List<BasisChange> changes) async {
  final prepared = await box.prepare(box.input(changes));
  box.storeWrap = (real) => CrashingStore(real, 2);
  try {
    await box.accept(prepared.draftDigest!);
    throw StateError('accept no murió');
  } on SimulatedCrash {
    // La muerte del proceso deja el journal y el candidato.
  } finally {
    box.storeWrap = null;
  }
  return prepared.draftDigest!;
}
