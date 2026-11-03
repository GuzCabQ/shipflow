import 'dart:io';

import 'package:core/core.dart';

import '../scan_guard.dart';
import '../stable_file_reader.dart';
import 'assessment_ids.dart';

/// Lo que dejó leer una fuente: su estado, el motivo si no se selló, su
/// huella completa y, si se pidió, sus bytes.
typedef SealedRead = ({
  AssessmentInputState state,
  String? reason,
  String? sha256,
  List<int>? bytes,
});

SealedRead unsealedRead(AssessmentInputState state, String reason) =>
    (state: state, reason: reason, sha256: null, bytes: null);

/// Lee [absolute] dos veces bajo [maxBytes], sin seguir un enlace puesto
/// después de enumerarla: leída con su huella, o ilegible, cambiante o
/// demasiado grande con su motivo. Nunca trunca.
Future<SealedRead> readSealed(
  RootGuard guard,
  String absolute,
  int maxBytes, {
  required bool keep,
}) async {
  if (guard.escapedFile(absolute) != null) {
    return unsealedRead(AssessmentInputState.unreadable, 'source_changed');
  }
  final read = await readStableFile(File(absolute), maxBytes: maxBytes);
  return switch (read) {
    StableSource(:final bytes, :final fingerprint) => (
      state: AssessmentInputState.read,
      reason: null,
      sha256: fullByteHash(fingerprint),
      bytes: keep ? bytes : null,
    ),
    OversizedSource() => unsealedRead(
      AssessmentInputState.limit,
      'source_too_large',
    ),
    UnstableSource() => unsealedRead(
      AssessmentInputState.unreadable,
      'source_changed',
    ),
    UnreadableSource() => unsealedRead(
      AssessmentInputState.unreadable,
      'source_unreadable',
    ),
  };
}

/// Los presupuestos de lectura de fuentes: archivos leídos y bytes únicos.
final class SourceBudget {
  SourceBudget(this.limits);

  final AssessmentLimits limits;
  var read = 0;
  var bytes = 0;

  /// El motivo por el que [size] bytes más no caben, o null si caben. Una
  /// fuente mayor que su máximo pasa: la lectura la rechaza por tamaño.
  String? refuse(int size) {
    if (read >= limits.maxSourceFiles) return 'source_budget';
    if (size <= limits.maxSourceBytes &&
        bytes + size > limits.maxTotalSourceBytes) {
      return 'source_budget';
    }
    return null;
  }

  void charge(int size) {
    read++;
    bytes += size;
  }
}
