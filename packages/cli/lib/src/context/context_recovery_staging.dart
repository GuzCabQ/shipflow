import 'package:core/core.dart';

import 'context_codec.dart';
import 'context_observation.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';

const _shipflow = '$stateDirectory/';

/// El staging que nombra un journal, leído una vez bajo el lease. Un
/// archivo sólo vale como versión preparada si coincide con la huella que
/// el journal le asigna.
final class RecoveryStaging {
  RecoveryStaging(this.journal);

  final ContextTransaction journal;
  final _bytes = <String, List<int>>{};

  /// Los archivos leídos, por su nombre relativo a `shipflow/`.
  Map<String, List<int>> get files => Map.unmodifiable(_bytes);

  Future<void> read(ContextStore store) async {
    final s = journal.staging;
    for (final path in [s.project, s.settingsBefore, s.settingsAfter]) {
      if (path == null) continue;
      final bytes = await store.readRelative(
        '$_shipflow$path',
        maxBytes: maxProjectBytes,
      );
      if (bytes != null) _bytes[path] = bytes;
    }
  }

  /// Los bytes de [path] si su huella es [sha256].
  List<int>? matching(String? path, String? sha256) {
    final bytes = path == null ? null : _bytes[path];
    if (bytes == null || sha256 == null || hashOf(bytes) != sha256) {
      return null;
    }
    return bytes;
  }

  /// El candidato preparado, si su staging está y coincide con [sha256].
  ProjectContext? project(String? sha256) =>
      decodedProject(matching(journal.staging.project, sha256));
}

/// [bytes] como contexto, o null si no cumplen su formato.
ProjectContext? decodedProject(List<int>? bytes) {
  if (bytes == null) return null;
  try {
    return const ContextCodec().decodeProject(bytes);
  } on ContextFormatException {
    return null;
  }
}
