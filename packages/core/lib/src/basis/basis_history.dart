import '../context/context_validation.dart';
import 'basis_enums.dart';
import 'basis_limits.dart';
import 'basis_model.dart';
import 'basis_payload.dart';
import 'basis_response_parts.dart';
import 'basis_references.dart';
import 'basis_validation.dart';

/// Las versiones aceptadas hasta un punto de la historia: todas, por ID y
/// versión, y la actual de cada ID.
final class BasisLedger {
  final _versions = <String, BasisRecordVersion>{};
  final _current = <String, BasisRecordVersion>{};
  final _operations = <String>{};
  String? _lastEventDigest;
  var _revision = 0;

  int get revision => _revision;

  String? get lastEventDigest => _lastEventDigest;

  /// La versión actual de cada ID, en orden de primera aparición.
  Map<String, BasisRecordVersion> get current => Map.unmodifiable(_current);

  BasisRecordVersion? versionOf(String id, int version) =>
      _versions['$id@$version'];

  BasisRecordVersion? currentOf(String id) => _current[id];

  bool hasOperation(String operationId) => _operations.contains(operationId);

  void _apply(BasisEvent event) {
    for (final change in event.changes) {
      _versions['${change.id}@${change.version}'] = change;
      _current[change.id] = change;
    }
    _operations.add(event.operationId);
    _lastEventDigest = event.eventDigest;
    _revision = event.revision;
  }
}

/// Valida [event] sobre [ledger] y lo incorpora. Las referencias se
/// resuelven contra la historia anterior más todos los cambios del evento,
/// sin depender del orden de su lista.
void applyBasisEvent(BasisLedger ledger, BasisEvent event, String at) {
  requireBasis(
    event.revision == ledger.revision + 1 &&
        event.previousEventDigest == ledger.lastEventDigest &&
        !ledger.hasOperation(event.operationId),
    'history_gap',
    at,
  );
  requireBasis(
    event.revision == 1 || event.changes.isNotEmpty,
    'invalid_schema',
    '$at/changes',
  );
  requireBasis(isUtcTimestamp(event.acceptedAt), 'invalid_schema', at);
  requireText(event.reason, maxBasisReasonText, '$at/reason');
  validateBasisActor(event.actor, '$at/actor');
  final batch = <String, BasisRecordVersion>{};
  for (final (i, change) in event.changes.indexed) {
    requireBasis(batch[change.id] == null, 'invalid_schema', '$at/changes/$i');
    batch[change.id] = change;
  }
  for (final (i, change) in event.changes.indexed) {
    _change(ledger, batch, event.actor, change, '$at/changes/$i');
  }
  ledger._apply(event);
  requireNoReplacementCycle(ledger.current, at);
}

void _change(
  BasisLedger ledger,
  Map<String, BasisRecordVersion> batch,
  BasisActor actor,
  BasisRecordVersion change,
  String at,
) {
  final prior = ledger.currentOf(change.id);
  requireBasis(
    change.previousVersion == prior?.version &&
        change.version == (prior?.version ?? 0) + 1,
    'history_gap',
    at,
  );
  _kindAndAuthority(actor, prior?.payload, change.payload, at);
  BasisRecordVersion? available(String id, int version) =>
      batch[id]?.version == version ? batch[id] : ledger.versionOf(id, version);
  requirePersistedReferences((
    id: change.id,
    payload: change.payload,
    prior: prior?.payload,
    available: available,
    accepted: ledger.versionOf,
    latest: (id) => (batch[id] ?? ledger.currentOf(id))?.payload,
  ), '$at/payload');
}

/// El tipo de un ID no cambia, y el actor alcanza el ámbito anterior y el
/// nuevo: no se reduce un ámbito para eludir esa condición.
void _kindAndAuthority(
  BasisActor actor,
  BasisPayload? prior,
  BasisPayload payload,
  String at,
) {
  requireBasis(
    prior == null || prior.kind == payload.kind,
    'invalid_reference',
    '$at/payload/kind',
  );
  validateBasisPayload(payload, '$at/payload');
  requireBasis(
    authorizes(actor, payload) && (prior == null || authorizes(actor, prior)),
    'authority_scope',
    '$at/payload/scope',
  );
}

/// Las reglas de `basis.json` que su schema no expresa, salvo las huellas:
/// la historia continua desde 1, versiones sin huecos, tipos estables,
/// referencias existentes en su momento, autoridad declarada y vínculos de
/// revisión inmutables. Devuelve la historia reconstruida.
BasisLedger replayBasisLedger(BasisDocument document) {
  requireBasis(isUuidV4(document.projectId), 'invalid_schema', 'projectId');
  requireText(document.producerVersion, maxBasisShortText, 'producerVersion');
  requireBasis(
    document.events.isNotEmpty && document.revision == document.events.length,
    'history_gap',
    'revision',
  );
  final ledger = BasisLedger();
  for (final (i, event) in document.events.indexed) {
    applyBasisEvent(ledger, event, 'events/$i');
  }
  return ledger;
}

void validateBasisDocument(BasisDocument value) => replayBasisLedger(value);

/// El estado actual: la última versión de cada ID, tras validar toda la
/// historia.
Map<String, BasisRecordVersion> replayBasis(BasisDocument value) =>
    replayBasisLedger(value).current;

/// Las cotas de cantidad de [document] para [limits]; los bytes los cobra
/// quien lee el archivo.
void requireBasisWithin(BasisLedger ledger, BasisLimits limits) {
  requireBasis(
    ledger.revision <= limits.maxEvents,
    'budget_exceeded',
    'events',
  );
  requireBasis(
    ledger.current.length <= limits.maxCurrentRecords,
    'budget_exceeded',
    'events',
  );
}

/// Ninguna cadena de reemplazos vuelve a su origen.
void requireNoReplacementCycle(
  Map<String, BasisRecordVersion> current,
  String at,
) {
  for (final start in current.keys) {
    final seen = <String>{start};
    var next = _replacement(current[start]);
    while (next != null) {
      requireBasis(seen.add(next), 'invalid_reference', at);
      next = _replacement(current[next]);
    }
  }
}

String? _replacement(BasisRecordVersion? record) => switch (record?.payload) {
  BasisRule(:final lifecycle, :final replacementRef)
      when lifecycle == BasisRuleLifecycle.replaced =>
    replacementRef,
  _ => null,
};

/// Cuánto declara la base: sin una regla activa, las normas del proyecto
/// no están establecidas; con alguna, son parciales y declaradas. Nunca
/// «sin reglas» ni «completa».
BasisCoverage basisCoverage(Map<String, BasisRecordVersion> current) =>
    current.values.any(
      (v) => switch (v.payload) {
        BasisRule(:final lifecycle) => lifecycle == BasisRuleLifecycle.active,
        _ => false,
      },
    )
    ? BasisCoverage.declaredPartial
    : BasisCoverage.notEstablished;
