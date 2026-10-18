/// Valida una versión según la gramática completa de SemVer 2.0.0.
///
/// Recorre la entrada una sola vez y sin expresiones regulares, así que una
/// entrada hostil se decide en tiempo lineal.
bool isValidSemVer(String value) {
  final plus = value.indexOf('+');
  final beforeBuild = plus < 0 ? value : value.substring(0, plus);
  if (plus >= 0 && !_identifiers(value.substring(plus + 1), _isBuildPart)) {
    return false;
  }
  final dash = beforeBuild.indexOf('-');
  final core = dash < 0 ? beforeBuild : beforeBuild.substring(0, dash);
  if (dash >= 0 &&
      !_identifiers(beforeBuild.substring(dash + 1), _isPrereleasePart)) {
    return false;
  }
  final numbers = core.split('.');
  return numbers.length == 3 && numbers.every(_isNumericIdentifier);
}

bool _identifiers(String dotted, bool Function(String) isValid) =>
    dotted.split('.').every(isValid);

bool _isPrereleasePart(String part) =>
    _isAlphanumericIdentifier(part) &&
    (!_isDigits(part) || _isNumericIdentifier(part));

bool _isBuildPart(String part) => _isAlphanumericIdentifier(part);

bool _isNumericIdentifier(String part) =>
    _isDigits(part) && (part == '0' || !part.startsWith('0'));

bool _isDigits(String part) =>
    part.isNotEmpty && part.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

bool _isAlphanumericIdentifier(String part) =>
    part.isNotEmpty &&
    part.codeUnits.every(
      (c) =>
          (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A) ||
          c == 0x2D,
    );
