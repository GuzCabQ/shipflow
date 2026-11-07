/// Qué fuentes locales se abren y cuáles se conservan sólo como referencia.
/// Los filtros de secretos reducen el riesgo; no son un detector infalible.
library;

const _excludedSegments = {'.git', '.ssh', '.aws', '.env'};
const _admitted = {'.md', '.txt', '.rst'};
const _secretSuffixes = {'.pem', '.key', '.p12', '.pfx'};
const _secretNames = {'id_rsa', 'id_ed25519'};
const _secretStems = {'.env', 'credentials', 'secrets'};

/// Si [path] no se abre nunca: carpetas de credenciales o de estado local,
/// y nombres de secretos, sin importar mayúsculas.
bool isExcludedSourcePath(String path) {
  final segments = path.split('/');
  if (segments.any(_excludedSegments.contains)) return true;
  if (segments.length >= 2 &&
      segments[0] == 'shipflow' &&
      segments[1] == 'local') {
    return true;
  }
  final name = segments.last.toLowerCase();
  if (_secretNames.contains(name)) return true;
  if (_secretSuffixes.any(name.endsWith)) return true;
  return _secretStems.any((stem) => name == stem || name.startsWith('$stem.'));
}

/// Si el contenido de [path] se lee: sólo texto de los tipos admitidos.
bool isAdmittedSourceType(String path) {
  final name = path.split('/').last.toLowerCase();
  final dot = name.lastIndexOf('.');
  return dot > 0 && _admitted.contains(name.substring(dot));
}

final _privateKey = RegExp(
  r'-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----|-----BEGIN OPENSSH PRIVATE KEY-----',
);
final _awsKeyId = RegExp(r'\b(?:AKIA|ASIA)[A-Za-z0-9]{16}\b');
final _assignment = RegExp(
  r'''(?:aws_secret_access_key|password|api[_-]key|access[_-]token)["']?[ \t]*[:=][ \t]*["']?[^\s"']''',
  caseSensitive: false,
);

/// Si [text] contiene un marcador mínimo de credencial: una clave privada,
/// un identificador de acceso o una asignación no vacía de un secreto.
bool hasCredentialMarker(String text) =>
    _privateKey.hasMatch(text) ||
    _awsKeyId.hasMatch(text) ||
    _assignment.hasMatch(text);
