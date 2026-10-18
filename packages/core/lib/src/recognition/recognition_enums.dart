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
