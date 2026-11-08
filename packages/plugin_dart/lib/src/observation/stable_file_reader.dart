import 'dart:io';

import 'package:crypto/crypto.dart';

/// Lee hasta [maxBytes] más uno: nunca más, aunque el archivo crezca.
typedef ByteReader = Future<List<int>> Function(File file, int maxBytes);

/// El resultado de leer una fuente dos veces bajo su máximo.
sealed class StableRead {
  const StableRead();
}

/// Las dos lecturas coincidieron.
final class StableSource extends StableRead {
  /// Una copia no modificable de [bytes], con la huella calculada sobre esa
  /// misma copia: nada de fuera puede cambiar el contenido ni darle otra
  /// huella. No prueba que el archivo estuviera estable; eso lo decide la
  /// doble lectura de [readStableFile].
  factory StableSource.fromBytes(List<int> bytes) {
    final copy = List<int>.unmodifiable(bytes);
    return StableSource._(copy, 'sha256:${sha256.convert(copy)}');
  }

  const StableSource._(this.bytes, this.fingerprint);

  /// No modificable.
  final List<int> bytes;

  /// `sha256:<hex>` de [bytes].
  final String fingerprint;

  int get size => bytes.length;
}

/// La fuente excede su máximo, por tamaño declarado o leído.
final class OversizedSource extends StableRead {
  const OversizedSource(this.size);

  final int size;
}

/// Las dos lecturas devolvieron bytes distintos.
final class UnstableSource extends StableRead {
  const UnstableSource();
}

final class UnreadableSource extends StableRead {
  const UnreadableSource(this.reason);

  /// El motivo del sistema operativo, sin rutas.
  final String reason;
}

Future<List<int>> readBoundedBytes(File file, int maxBytes) async {
  final handle = await file.open();
  try {
    return await handle.read(maxBytes + 1);
  } finally {
    await handle.close();
  }
}

/// Lee [file] dos veces y la acepta sólo si ambas lecturas coinciden y caben
/// en [maxBytes]. El tamaño declarado se mira antes de leer.
Future<StableRead> readStableFile(
  File file, {
  required int maxBytes,
  ByteReader readBytes = readBoundedBytes,
}) async {
  try {
    final declared = file.statSync().size;
    if (declared > maxBytes) return OversizedSource(declared);
    final first = await readBytes(file, maxBytes);
    if (first.length > maxBytes) return OversizedSource(first.length);
    final second = await readBytes(file, maxBytes);
    if (second.length > maxBytes) return OversizedSource(second.length);
    if (!_sameBytes(first, second)) return const UnstableSource();
    return StableSource.fromBytes(first);
  } on FileSystemException catch (error) {
    return UnreadableSource(error.osError?.message ?? error.message);
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
