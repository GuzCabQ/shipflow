import 'dart:convert';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';

/// SHA-256 hexadecimal de [bytes].
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// [prefix] y la huella de la forma canónica de [tuple]: el mismo cálculo
/// que comprueba el lector del levantamiento.
String assessmentId(String prefix, List<Object?> tuple) =>
    '$prefix${sha256Hex(identityBytes(tuple))}';

/// La huella completa de bytes que contiene una huella de V2, o null si su
/// forma no es comparable: `sha256:<hex>` o el hex mismo.
String? fullByteHash(String fingerprint) {
  final hex = fingerprint.startsWith('sha256:')
      ? fingerprint.substring('sha256:'.length)
      : fingerprint;
  return isSha256Hex(hex) ? hex : null;
}

/// La huella del texto [value] en UTF-8.
String textHash(String value) => sha256Hex(utf8.encode(value));
