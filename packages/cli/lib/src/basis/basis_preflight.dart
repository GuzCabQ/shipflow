import 'package:core/core.dart';

import '../context/context_codec.dart';
import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import 'basis_canonical.dart';

/// El contexto V2 de ahora por el almacén anclado: su presencia y validez,
/// su identidad, la huella de sus bytes y las transacciones de init o de
/// assess sin terminar. No ejecuta init, doctor ni assess, y no escribe.
Future<BasisEnvironment> readBasisEnvironment(ContextStore store) async {
  final (context, projectId, digest) = await _context(store);
  return BasisEnvironment(
    context: context,
    projectId: projectId,
    contextDigest: digest,
    contextRecoveryPending: await _present(store, transactionPath),
    assessmentRecoveryPending: await _present(store, assessmentTransactionPath),
  );
}

Future<(BasisIntegrity, String?, String?)> _context(ContextStore store) async {
  final List<int>? bytes;
  try {
    bytes = await store.readRelative(projectPath, maxBytes: maxProjectBytes);
  } on ContextStoreFailure {
    return (BasisIntegrity.unverified, null, null);
  }
  if (bytes == null) return (BasisIntegrity.absent, null, null);
  try {
    final context = const ContextCodec().decodeProject(bytes);
    return (BasisIntegrity.valid, context.projectId, bytesDigest(bytes));
  } on ContextFormatException catch (e) {
    final incompatible = e.code == 'schema_version';
    return (
      incompatible ? BasisIntegrity.incompatible : BasisIntegrity.invalid,
      null,
      null,
    );
  }
}

/// Si hay algo en [path]; una lectura fallida no prueba ausencia.
Future<bool> _present(ContextStore store, String path) async {
  try {
    return await store.readRelative(path, maxBytes: 1) != null;
  } on ContextStoreFailure {
    return true;
  }
}
