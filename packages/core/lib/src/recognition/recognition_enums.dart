/// El resultado global de un reconocimiento.
enum RecognitionStatus {
  recognized('recognized'),
  ambiguous('ambiguous'),
  unsupported('unsupported'),
  invalidRoot('invalid_root');

  const RecognitionStatus(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static RecognitionStatus fromWireName(String value) =>
      _fromWireName(values, (s) => s._wireName, value);
}

/// Si la raíz pertenece a un repositorio, según sus metadatos.
enum RepositoryStatus {
  detected('detected'),
  absent('absent'),
  indeterminate('indeterminate');

  const RepositoryStatus(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static RepositoryStatus fromWireName(String value) =>
      _fromWireName(values, (s) => s._wireName, value);
}

/// Dónde está la raíz del repositorio respecto de la raíz reconocida.
enum RepositoryRelation {
  same('same'),
  ancestor('ancestor'),
  none('none');

  const RepositoryRelation(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static RepositoryRelation fromWireName(String value) =>
      _fromWireName(values, (r) => r._wireName, value);
}

/// Qué sostiene una evidencia, para agruparla sin interpretar su tipo.
enum EvidenceRole {
  identity('identity'),
  environment('environment'),
  description('description'),
  relation('relation'),
  resource('resource');

  const EvidenceRole(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static EvidenceRole fromWireName(String value) =>
      _fromWireName(values, (r) => r._wireName, value);
}

/// Cómo declara una unidad su relación con otra.
enum RelationKind {
  localDependency('local_dependency'),
  workspaceMember('workspace_member');

  const RelationKind(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static RelationKind fromWireName(String value) =>
      _fromWireName(values, (k) => k._wireName, value);
}

/// Si el destino declarado de una relación se observó.
enum RelationStatus {
  corroborated('corroborated'),
  unresolved('unresolved');

  const RelationStatus(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static RelationStatus fromWireName(String value) =>
      _fromWireName(values, (s) => s._wireName, value);
}

/// Para qué sirve una fuente candidata, según el catálogo que la buscó.
enum ContextSourceKind {
  documentation('documentation'),
  instructions('instructions'),
  analysisConfiguration('analysis_configuration'),
  taskConfiguration('task_configuration'),
  ciConfiguration('ci_configuration');

  const ContextSourceKind(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextSourceKind fromWireName(String value) =>
      _fromWireName(values, (k) => k._wireName, value);
}

/// Qué hay en la ruta de una fuente candidata, sólo por sus metadatos.
enum ContextEntityType {
  file('file'),
  directory('directory'),
  link('link'),
  special('special'),
  missing('missing'),
  unavailable('unavailable');

  const ContextEntityType(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  /// Si la ruta existe y se pudo mirar su tipo.
  bool get observed => index <= special.index;

  static ContextEntityType fromWireName(String value) =>
      _fromWireName(values, (t) => t._wireName, value);
}

/// Por qué una fuente candidata tiene el tipo que tiene.
enum ContextReason {
  observed('observed'),
  notFound('not_found'),
  accessFailed('access_failed'),
  ancestorLink('ancestor_link'),
  excluded('excluded');

  const ContextReason(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ContextReason fromWireName(String value) =>
      _fromWireName(values, (r) => r._wireName, value);
}

/// La regla de alcance que dejó un árbol sin recorrer.
enum OmissionRule {
  baselineExclusion('baseline_exclusion'),
  temporaryDirectory('temporary_directory'),
  declaredResource('declared_resource');

  const OmissionRule(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static OmissionRule fromWireName(String value) =>
      _fromWireName(values, (r) => r._wireName, value);
}

T _fromWireName<T extends Enum>(
  List<T> values,
  String Function(T) wireName,
  String value,
) {
  for (final candidate in values) {
    if (wireName(candidate) == value) return candidate;
  }
  throw FormatException('«$value» no es un valor conocido de $T.');
}
