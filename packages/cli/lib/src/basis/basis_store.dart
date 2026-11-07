import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import 'basis_canonical.dart';
import 'basis_codec.dart';

/// Un archivo propio leído: su valor si valida, sus bytes, lo que se
/// demostró de él y, si no valida, el código del catálogo.
final class BasisFile<T> {
  const BasisFile(this.value, this.bytes, this.integrity, [this.code]);

  final T? value;
  final List<int>? bytes;
  final BasisIntegrity integrity;
  final String? code;

  bool get absent => integrity == BasisIntegrity.absent;

  /// `sha256:` de los bytes tal cual están; null si no existe.
  String? get bytesDigest => bytes == null ? null : _digest(bytes!);
}

String _digest(List<int> bytes) => bytesDigest(bytes);

/// La ruta de staging de una operación.
String basisStagingOf(String operationId) =>
    'shipflow/local/basis-staging/$operationId';

/// Los documentos de bootstrap sobre el almacén anclado existente: nunca
/// un segundo puerto de filesystem. Las huellas V4 llevan `sha256:`; el
/// CAS del almacén las recibe sin prefijo.
final class BasisStore {
  BasisStore(this.store, this.limits);

  final ContextStore store;
  final BasisLimits limits;

  Future<BasisFile<BasisDocument>> basis() => _read(
    basisDocumentPath,
    limits.maxBasisBytes,
    (b) => decodeBasis(b, limits: limits),
  );

  Future<BasisFile<BasisDraft>> draft() => _read(
    basisDraftPath,
    limits.maxDraftBytes,
    (b) => decodeBasisDraft(b, limits: limits),
  );

  Future<BasisFile<BasisTransaction>> journal() => _read(
    basisTransactionPath,
    limits.maxDraftBytes,
    (b) => decodeBasisTransaction(b, limits: limits),
  );

  Future<BasisFile<BasisDocument>> candidate(String path) =>
      _read(path, limits.maxBasisBytes, (b) => decodeBasis(b, limits: limits));

  Future<BasisFile<T>> _read<T>(
    String path,
    int maxBytes,
    T Function(List<int> bytes) decode,
  ) async {
    final List<int>? bytes;
    try {
      bytes = await store.readRelative(path, maxBytes: maxBytes);
    } on ContextStoreFailure {
      return const BasisFile(null, null, BasisIntegrity.unverified, 'io_error');
    }
    if (bytes == null) {
      return const BasisFile(null, null, BasisIntegrity.absent);
    }
    if (bytes.length > maxBytes) {
      return BasisFile(
        null,
        bytes,
        BasisIntegrity.unverified,
        'budget_exceeded',
      );
    }
    try {
      return BasisFile(decode(bytes), bytes, BasisIntegrity.valid);
    } on ContextFormatException catch (e) {
      return BasisFile(null, bytes, _integrity(e.code), e.code);
    }
  }

  BasisIntegrity _integrity(String code) => switch (code) {
    'incompatible_version' => BasisIntegrity.incompatible,
    'budget_exceeded' => BasisIntegrity.unverified,
    _ => BasisIntegrity.invalid,
  };

  /// Publica [bytes] en [path] si su versión actual tiene [expected]
  /// (`sha256:<hex>` de sus bytes; null: ausente).
  Future<void> publish(String path, List<int> bytes, String? expected) =>
      store.publishRelative(path, bytes, expectedSha256: _hex(expected));

  /// Retira [path] sólo si sigue teniendo [expected].
  Future<void> remove(String path, String expected) =>
      store.removeRelative(path, expectedSha256: _hex(expected)!);

  /// `sha256:` de [path] ahora; null si no existe.
  Future<String?> digestOf(String path, int maxBytes) async {
    final bytes = await store.readRelative(path, maxBytes: maxBytes);
    return bytes == null ? null : _digest(bytes);
  }

  /// [body] con el lock de contexto que comparten init, assess y bootstrap.
  Future<T> locked<T>(Future<T> Function() body) async {
    await store.createDirectory('shipflow/local/locks');
    final lease = await store.acquirePublication([store.contextLock()]);
    try {
      return await body();
    } finally {
      await lease.release();
    }
  }
}

String? _hex(String? digest) => digest?.substring('sha256:'.length);
