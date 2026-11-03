/// Los valores cerrados del levantamiento, con su nombre de cable.
library;

import '../context/context_enums.dart' show wireValue;

/// Cuánto admite una ejecución de assess. Vive sólo en ella.
enum AssessmentProfile {
  standard('standard'),
  extended('extended');

  const AssessmentProfile(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentProfile fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué es una entrada del inventario sellado.
enum AssessmentInputKind {
  source('source'),
  recognitionSource('recognition_source'),
  directory('directory'),
  excluded('excluded'),
  context('context');

  const AssessmentInputKind(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentInputKind fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué se hizo con una entrada: leída, listada, excluida por política, no
/// legible o fuera del presupuesto.
enum AssessmentInputState {
  read('read'),
  listed('listed'),
  excluded('excluded'),
  unreadable('unreadable'),
  limit('limit');

  const AssessmentInputState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentInputState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

enum AssessmentFileRole {
  source('source'),
  test('test');

  const AssessmentFileRole(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentFileRole fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Si el detector sintáctico procesó un archivo.
enum AssessmentParseState {
  parsed('parsed'),
  failed('failed'),
  notRun('not_run');

  const AssessmentParseState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentParseState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Una referencia de un archivo a otro, o la parte que se adjunta a su
/// biblioteca. Ninguna es una llamada ni una regla.
enum AssessmentRelation {
  sourceReference('source_reference'),
  sourceAttachment('source_attachment');

  const AssessmentRelation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentRelation fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Adónde llegó la resolución de una referencia.
enum AssessmentResolution {
  local('local'),
  external('external'),
  unresolved('unresolved');

  const AssessmentResolution(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentResolution fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Cuándo aplica una referencia: siempre, como alternativa condicional,
/// como base de las alternativas, o no representable.
enum AssessmentCondition {
  always('always'),
  conditional('conditional'),
  fallback('fallback'),
  unknown('unknown');

  const AssessmentCondition(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentCondition fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Las capacidades obligatorias: cada una deja un testigo.
enum AssessmentCapability {
  sourceInventory('source_inventory'),
  sourceReferences('source_references'),
  localResolution('local_resolution'),
  testInventory('test_inventory'),
  contextCandidates('context_candidates');

  const AssessmentCapability(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentCapability fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

enum AssessmentWitnessState {
  complete('complete'),
  partial('partial'),
  failed('failed'),
  notRun('not_run');

  const AssessmentWitnessState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentWitnessState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Cuánto del universo explícito se procesó. Completa no significa que se
/// comprenda todo el proyecto; not_run sólo existe en una respuesta.
enum AssessmentCoverage {
  complete('complete'),
  partial('partial'),
  failed('failed'),
  notRun('not_run');

  const AssessmentCoverage(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentCoverage fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Un vínculo al reconocimiento citado: una dependencia declarada o una
/// fuente candidata sin inspeccionar.
enum AssessmentLinkKind {
  declaredDependency('declared_dependency'),
  candidateSource('candidate_source');

  const AssessmentLinkKind(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentLinkKind fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Si el levantamiento mostrado corresponde a sus insumos de ahora.
enum AssessmentFreshness {
  current('current'),
  stale('stale'),
  unverified('unverified'),
  historical('historical'),
  notApplicable('not_applicable');

  const AssessmentFreshness(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentFreshness fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

enum AssessmentOutcome {
  saved('saved'),
  unchanged('unchanged'),
  shown('shown'),
  recovered('recovered'),
  blocked('blocked'),
  failed('failed'),
  cancelled('cancelled');

  const AssessmentOutcome(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentOutcome fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

enum AssessmentOperation {
  observe('observe'),
  show('show'),
  recover('recover');

  const AssessmentOperation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentOperation fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

/// Qué hace una acción propuesta: sólo lee, escribe estado propio o pide
/// una decisión de la persona.
enum AssessmentActionEffect {
  readOnly('read_only'),
  writeOwnState('write_own_state'),
  userDecision('user_decision');

  const AssessmentActionEffect(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentActionEffect fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}

enum AssessmentTransactionState {
  prepared('prepared'),
  published('published');

  const AssessmentTransactionState(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static AssessmentTransactionState fromWireName(String value) =>
      wireValue(values, (v) => v._wireName, value);
}
