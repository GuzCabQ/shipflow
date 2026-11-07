import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import 'basis_preparation.dart';
import 'basis_publication.dart';
import 'basis_recovery.dart';
import 'basis_reply.dart';
import 'basis_show.dart';
import 'basis_sources.dart';
import 'basis_store.dart';

/// Las operaciones de la base guiada sobre un almacén anclado. Preparar,
/// guardar un borrador o descartarlo nunca cambian la base; aceptar
/// publica sólo la huella exacta revisada; recuperar completa o aborta
/// una aceptación ya registrada. Perfil e identidades se fijan aquí.
final class BasisService {
  BasisService({
    required this.store,
    required this.reader,
    required this.readProject,
    required this.newId,
    required this.now,
    required this.limits,
    required this.version,
  });

  final ContextStore store;
  final BasisSourceReader reader;

  /// El proyecto V2 tal como está ahora, sin ejecutar init ni assess.
  final Future<BasisEnvironment> Function() readProject;
  final String Function() newId;
  final DateTime Function() now;
  final BasisLimits limits;

  /// La versión del productor que firma los documentos.
  final String version;

  BasisStore get files => BasisStore(store, limits);

  Future<BasisResponse> prepare(BasisInput input) => _run(
    BasisOperation.prepare,
    (r) => prepareBasis(this, r, input, expectedDraftDigest: null),
  );

  /// Reemplaza el borrador de [expectedDraftDigest] por uno nuevo, con CAS:
  /// cambia la huella e invalida el resumen anterior.
  Future<BasisResponse> revise(
    BasisInput input, {
    required String expectedDraftDigest,
  }) => _run(
    BasisOperation.prepare,
    (r) =>
        prepareBasis(this, r, input, expectedDraftDigest: expectedDraftDigest),
  );

  Future<BasisResponse> accept(String draftDigest) =>
      _run(BasisOperation.accept, (r) => acceptBasis(this, r, draftDigest));

  Future<BasisResponse> discard(String draftDigest) =>
      _run(BasisOperation.discard, (r) => discardBasis(this, r, draftDigest));

  Future<BasisResponse> recover() =>
      _run(BasisOperation.recover, (r) => recoverBasis(this, r));

  Future<BasisResponse> show({
    String? path,
    bool history = false,
    bool draft = false,
  }) => _run(
    BasisOperation.show,
    (r) => showBasis(this, r, path: path, history: history, draft: draft),
  );

  /// [body], con cada fallo esperado del almacén o del formato como su
  /// diagnóstico: nunca una excepción que borre los efectos ya anotados.
  Future<BasisResponse> _run(
    BasisOperation operation,
    Future<void> Function(BasisReply reply) body,
  ) async {
    final reply = BasisReply(operation);
    try {
      await body(reply);
    } on ContextStoreFailure catch (failure) {
      reply.add(failure.code == 'busy' ? 'busy' : 'io_error');
    } on ContextFormatException catch (rejected) {
      reply.add(rejected.code, path: rejected.at.isEmpty ? null : rejected.at);
    }
    return reply.build();
  }
}
