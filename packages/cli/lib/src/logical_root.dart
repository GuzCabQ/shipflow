import 'dart:convert';
import 'dart:io';

/// El máximo, en bytes UTF-8, de una pista `PWD` que se intenta corroborar.
/// Acota la pista del entorno; no es una afirmación sobre el filesystem.
const maxLogicalRootBytes = 4096;

/// La ruta real de [path]; las pruebas la sustituyen para cubrir entradas
/// que el sistema no permite construir como directorio.
typedef PathResolver = Future<String> Function(String path);

Future<String> _resolveSymbolicLinks(String path) =>
    Directory(path).resolveSymbolicLinks();

/// [pwd] si es una pista válida de la misma carpeta que [canonicalRoot]:
/// absoluta, sin NUL, dentro de [maxLogicalRootBytes] y con la misma ruta
/// real. Si no, null y la pista se ignora. Sólo resuelve la ruta: no lista
/// ni lee nada de su destino, y nunca autoriza leer otra carpeta.
Future<String?> corroborateLogicalRoot(
  String? pwd, {
  required String canonicalRoot,
  PathResolver resolve = _resolveSymbolicLinks,
}) async {
  if (pwd == null ||
      !pwd.startsWith('/') ||
      pwd.contains('\x00') ||
      utf8.encode(pwd).length > maxLogicalRootBytes) {
    return null;
  }
  try {
    return await resolve(pwd) == canonicalRoot ? pwd : null;
  } on FileSystemException {
    return null;
  }
}
