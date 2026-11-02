import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import 'assessment_codec.dart';

/// Por qué una publicación no ocurrió: otra operación tiene el lock
/// (`busy`), algo cambió antes del commit (`source_changed`,
/// `concurrent_change`) o un journal propio sigue activo
/// (`recovery_pending`). Nunca sigue a un reemplazo no informado.
final class AssessmentAbort implements Exception {
  const AssessmentAbort(this.code);

  final String code;

  @override
  String toString() => 'AssessmentAbort($code)';
}

/// Un fallo del almacén después del rename: el documento nuevo ya está
/// publicado aunque su journal o su limpieza no terminaron.
final class AssessmentCommitFailure implements Exception {
  const AssessmentCommitFailure(this.code, this.publication);

  final String code;
  final AssessmentPublication publication;

  @override
  String toString() => 'AssessmentCommitFailure($code)';
}

/// El documento leído con sus bytes, o su ausencia.
final class AssessmentRead {
  const AssessmentRead(this.document, this.sha256);

  const AssessmentRead.absent() : document = null, sha256 = null;

  final AssessmentDocument? document;
  final String? sha256;
}

/// Lo que dejó una publicación: rutas propias creadas, reemplazadas y
/// retiradas, y si se comprobó en disco el documento publicado.
final class AssessmentPublication {
  AssessmentPublication({
    required this.created,
    required this.replaced,
    required this.published,
  });

  final List<String> created;
  final List<String> replaced;
  final bool published;
}

const _locks = 'shipflow/local/locks';
const _staging = 'shipflow/local/assessment-staging';

/// La ruta de staging de [operationId], relativa a la raíz.
String stagingDirectoryOf(String operationId) => '$_staging/$operationId';

/// El documento `shipflow/assessment.json` y su publicación bajo el lock del
/// contexto que comparten init, refresh y recover: staging validado, journal
/// con huellas antes y después, revalidación de fuentes, reemplazo atómico
/// con CAS y limpieza de lo propio.
final class AssessmentStore {
  AssessmentStore(this.store);

  final ContextStore store;

  /// El documento vigente, leído dos veces seguidas con la misma huella; si
  /// cambió, se reintenta una vez y después es una publicación concurrente.
  Future<AssessmentRead> read() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final bytes = await bytesOf(assessmentPath);
      if (bytes == null) return const AssessmentRead.absent();
      final again = await bytesOf(assessmentPath);
      if (again != null && sha256Of(again) == sha256Of(bytes)) {
        return AssessmentRead(decodeAssessment(bytes), sha256Of(bytes));
      }
    }
    throw const AssessmentAbort('concurrent_change');
  }

  /// El journal de assess, si hay uno; un journal que no valida se rechaza.
  Future<AssessmentTransaction?> readJournal() async {
    final bytes = await store.readRelative(
      assessmentJournalPath,
      maxBytes: maxAssessmentJournalBytes,
    );
    return bytes == null ? null : decodeAssessmentTransaction(bytes);
  }

  /// Publica [candidate] si el documento actual tiene [expectedSha256]
  /// (null: ausente) y [preconditions] y [revalidate] no lanzan. Un
  /// [AssessmentAbort] antes del commit retira sólo lo propio y conserva el
  /// documento anterior; un fallo del almacén deja el journal para
  /// `assess --recover`.
  Future<AssessmentPublication> publish(
    AssessmentDocument candidate, {
    required String operationId,
    required String? expectedSha256,
    required String baseContextDigest,
    required Future<void> Function() preconditions,
    required Future<void> Function() revalidate,
  }) async {
    final bytes = encodeAssessment(candidate);
    decodeAssessment(bytes);
    final created = await store.createDirectory(_locks);
    final lease = await store.acquirePublication([store.contextLock()]);
    try {
      await _expect(expectedSha256);
      await preconditions();
      final journal = AssessmentTransaction(
        projectId: candidate.projectId,
        operationId: operationId,
        before: expectedSha256,
        after: sha256Of(bytes),
        state: AssessmentTransactionState.prepared,
        baseContextDigest: baseContextDigest,
        snapshotId: candidate.current.snapshotId,
      );
      await _stage(journal, bytes);
      await _withAbortCleanup(journal, revalidate);
      AssessmentPublication done(bool published) => AssessmentPublication(
        created: [...created, if (expectedSha256 == null) assessmentPath],
        replaced: [if (expectedSha256 != null) assessmentPath],
        published: published,
      );
      await _committed(journal, bytes, done);
      return done(await hashOf(assessmentPath) == journal.after);
    } finally {
      await lease.release();
    }
  }

  /// [commit]; si falla después del rename, lo dice como publicado.
  Future<void> _committed(
    AssessmentTransaction journal,
    List<int> bytes,
    AssessmentPublication Function(bool published) done,
  ) async {
    try {
      await commit(journal, bytes);
    } on ContextStoreFailure catch (failure) {
      String? now;
      try {
        now = await hashOf(assessmentPath);
      } on ContextStoreFailure {
        now = null;
      }
      if (now != journal.after) rethrow;
      throw AssessmentCommitFailure(failure.code, done(true));
    }
  }

  /// Ningún journal propio activo y el documento como se observó.
  Future<void> _expect(String? expectedSha256) async {
    if (await bytesOf(assessmentJournalPath) != null) {
      throw const AssessmentAbort('recovery_pending');
    }
    if (await hashOf(assessmentPath) != expectedSha256) {
      throw const AssessmentAbort('concurrent_change');
    }
  }

  /// El candidato completo en su staging y después el journal preparado.
  Future<void> _stage(AssessmentTransaction journal, List<int> bytes) async {
    await store.createDirectory(stagingDirectoryOf(journal.operationId));
    await store.publishRelative(
      journal.candidatePath,
      bytes,
      expectedSha256: null,
    );
    await store.publishRelative(
      assessmentJournalPath,
      encodeAssessmentTransaction(journal),
      expectedSha256: null,
    );
  }

  /// [revalidate]; si aborta, se retiran el candidato y el journal propios.
  Future<void> _withAbortCleanup(
    AssessmentTransaction journal,
    Future<void> Function() revalidate,
  ) async {
    try {
      await revalidate();
    } on AssessmentAbort {
      await cleanup(journal);
      rethrow;
    }
  }

  /// El reemplazo atómico con CAS, el journal publicado y la limpieza.
  /// Sólo con el lock tomado y el documento todavía en su versión anterior.
  Future<void> commit(AssessmentTransaction journal, List<int> bytes) async {
    await store.publishRelative(
      assessmentPath,
      bytes,
      expectedSha256: journal.before,
    );
    final prepared = await hashOf(assessmentJournalPath);
    await store.publishRelative(
      assessmentJournalPath,
      encodeAssessmentTransaction(_published(journal)),
      expectedSha256: prepared,
    );
    await cleanup(_published(journal));
  }

  /// Retira el candidato, su staging y el journal de [journal], cada uno
  /// sólo si sigue siendo el propio: un candidato con otra huella no está
  /// identificado y se conserva, igual que su directorio.
  Future<List<String>> cleanup(AssessmentTransaction journal) async {
    final removed = <String>[];
    final candidate = await hashOf(journal.candidatePath);
    if (candidate == journal.after) {
      await store.removeRelative(
        journal.candidatePath,
        expectedSha256: journal.after,
      );
      removed.add(journal.candidatePath);
    }
    if (candidate == null || candidate == journal.after) {
      await store.removeDirectory(stagingDirectoryOf(journal.operationId));
    }
    final current = await hashOf(assessmentJournalPath);
    if (current != null) {
      await store.removeRelative(
        assessmentJournalPath,
        expectedSha256: current,
      );
      removed.add(assessmentJournalPath);
    }
    return removed;
  }

  Future<List<int>?> bytesOf(String path) => store.readRelative(
    path,
    maxBytes: path == assessmentJournalPath
        ? maxAssessmentJournalBytes
        : maxAssessmentDocumentBytes,
  );

  Future<String?> hashOf(String path) async {
    final bytes = await bytesOf(path);
    return bytes == null ? null : sha256Of(bytes);
  }
}

AssessmentTransaction _published(AssessmentTransaction journal) =>
    AssessmentTransaction(
      projectId: journal.projectId,
      operationId: journal.operationId,
      before: journal.before,
      after: journal.after,
      state: AssessmentTransactionState.published,
      baseContextDigest: journal.baseContextDigest,
      snapshotId: journal.snapshotId,
    );
