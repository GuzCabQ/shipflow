/// Los valores cerrados del contexto persistente, con su nombre de cable.
library;

/// La conservación elegida para esta copia.
enum SharingChoice {
  share('share'),
  local('local'),
  pending('pending');

  const SharingChoice(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static SharingChoice fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué se observó de Git para la raíz.
enum GitState {
  available('available'),
  notInstalled('not_installed'),
  notRepository('not_repository'),
  unavailable('unavailable'),
  notChecked('not_checked');

  const GitState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static GitState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Si la elección está efectivamente aplicada.
enum SharingEffective {
  shareReady('share_ready'),
  localExcluded('local_excluded'),
  pending('pending'),
  unverified('unverified'),
  conflict('conflict');

  const SharingEffective(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static SharingEffective fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// El comando que produjo un resultado.
enum ContextCommand {
  init('init'),
  doctor('doctor');

  const ContextCommand(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextCommand fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// La operación pedida dentro del comando.
enum ContextOperation {
  init('init'),
  refresh('refresh'),
  recover('recover'),
  doctor('doctor');

  const ContextOperation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextOperation fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Cómo terminó la operación.
enum ContextOutcome {
  initialized('initialized'),
  unchanged('unchanged'),
  refreshed('refreshed'),
  recovered('recovered'),
  available('available'),
  needsAttention('needs_attention'),
  cancelled('cancelled'),
  failed('failed');

  const ContextOutcome(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextOutcome fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// En qué estado se encontró el contexto guardado.
enum ContextState {
  absent('absent'),
  present('present'),
  invalid('invalid'),
  incompatible('incompatible'),
  recoveryRequired('recovery_required');

  const ContextState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Si el contexto guardado coincide con lo observado ahora.
enum ContextFreshness {
  current('current'),
  stale('stale'),
  unverified('unverified'),
  notApplicable('not_applicable');

  const ContextFreshness(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextFreshness fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Las comprobaciones del catálogo cerrado.
enum ContextCheckId {
  contextPresence('context_presence'),
  contextIntegrity('context_integrity'),
  producerCompatibility('producer_compatibility'),
  transactionState('transaction_state'),
  recognitionFreshness('recognition_freshness'),
  sharingState('sharing_state');

  const ContextCheckId(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextCheckId fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// El resultado de una comprobación.
enum ContextCheckStatus {
  passed('passed'),
  failed('failed'),
  notChecked('not_checked');

  const ContextCheckStatus(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextCheckStatus fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué intenta una transacción: sharing cambia la modalidad sin reemplazar observaciones.
enum TransactionOperation {
  init('init'),
  refresh('refresh'),
  sharing('sharing');

  const TransactionOperation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static TransactionOperation fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Hasta dónde llegó una transacción; la recuperación mira los bytes, no sólo la fase.
enum TransactionPhase {
  prepared('prepared'),
  sharingApplied('sharing_applied'),
  contextPublished('context_published'),
  completed('completed'),
  aborting('aborting');

  const TransactionPhase(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static TransactionPhase fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Un destino que una transacción puede reemplazar.
enum TransactionResource {
  project('project'),
  settings('settings'),
  exclude('exclude');

  const TransactionResource(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static TransactionResource fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// El valor de [values] cuyo nombre de cable es [value].
T wireValue<T extends Enum>(
  List<T> values,
  String Function(T) wireName,
  String value,
) {
  for (final candidate in values) {
    if (wireName(candidate) == value) return candidate;
  }
  throw FormatException('valor desconocido de $T');
}
