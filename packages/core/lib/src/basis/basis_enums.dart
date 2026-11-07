/// Los valores cerrados de la base guiada, con su nombre de cable.
library;

import '../context/context_enums.dart' show wireValue;

/// A qué aplica un registro: todo el proyecto, prefijos de ruta o un ámbito
/// todavía desconocido (sólo en propuestas y pendientes).
enum BasisScopeKind {
  project('project'),
  paths('paths'),
  unknown('unknown');

  const BasisScopeKind(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisScopeKind fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// El ciclo de vida de una fuente registrada.
enum BasisSourceLifecycle {
  active('active'),
  retired('retired');

  const BasisSourceLifecycle(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisSourceLifecycle fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Una fuente local se lee bajo la raíz; una externa sólo se referencia.
enum BasisSourceType {
  local('local'),
  external('external');

  const BasisSourceType(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisSourceType fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué se comprobó del contenido de una fuente al registrarla.
enum BasisObservation {
  current('current'),
  unverified('unverified'),
  excluded('excluded');

  const BasisObservation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisObservation fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// El ciclo de vida de una regla: propuesta, activa, reemplazada o
/// retirada. Reemplazar o retirar conserva el antecedente en la historia.
enum BasisRuleLifecycle {
  proposed('proposed'),
  active('active'),
  replaced('replaced'),
  retired('retired');

  const BasisRuleLifecycle(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisRuleLifecycle fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// La clase declarada de una regla en prosa.
enum BasisRuleClass {
  obligation('obligation'),
  prohibition('prohibition'),
  preference('preference');

  const BasisRuleClass(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisRuleClass fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Si una regla admite excepciones y con qué autoridad.
enum BasisExceptionPolicy {
  notAllowed('not_allowed'),
  requiresAuthority('requires_authority'),
  unspecified('unspecified');

  const BasisExceptionPolicy(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisExceptionPolicy fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// De qué depende una regla: sólo de la declaración humana o de fuentes
/// citadas cuya vigencia se comprueba.
enum BasisSupport {
  humanDeclaration('human_declaration'),
  sourceSupported('source_supported');

  const BasisSupport(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisSupport fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Un pendiente abierto o resuelto con una resolución explícita.
enum BasisPendingStatus {
  open('open'),
  resolved('resolved');

  const BasisPendingStatus(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisPendingStatus fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// La fase de una publicación de la base en su journal.
enum BasisTransactionPhase {
  prepared('prepared'),
  published('published');

  const BasisTransactionPhase(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisTransactionPhase fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Cuánto admite una invocación de bootstrap. Vive sólo en ella.
enum BasisProfile {
  standard('standard'),
  extended('extended');

  const BasisProfile(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static BasisProfile fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}
