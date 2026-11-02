import 'package:core/core.dart';

import 'assessment_codec.dart';
import 'assessment_store.dart';

/// Cómo terminó `assess --recover`.
enum AssessmentRecoveryOutcome {
  /// No había nada propio que recuperar.
  nothing,

  /// El documento ya era el publicado: sólo se limpió lo propio.
  cleaned,

  /// Se terminó la publicación interrumpida.
  published,

  /// Las fuentes cambiaron: se conservó el documento anterior y se retiró
  /// sólo lo propio.
  aborted,

  /// Restos sin journal acreditados como propios y retirados.
  leftoversRemoved,

  /// El documento no es el anterior ni el preparado, o el candidato no se
  /// puede acreditar: se conserva todo para reconciliarlo a mano.
  conflict,
}

/// Lo que dejó una recuperación.
final class AssessmentRecovery {
  AssessmentRecovery(
    this.outcome, {
    this.created = const [],
    this.removed = const [],
    this.replaced = const [],
    this.published = false,
    this.kept = const [],
  });

  final AssessmentRecoveryOutcome outcome;
  final List<String> created;
  final List<String> removed;
  final List<String> replaced;
  final bool published;

  /// Restos que no se pudieron acreditar y no se tocaron.
  final List<String> kept;
}

/// Termina o aborta sólo una publicación propia demostrable, bajo el lock
/// del contexto: el documento en su versión preparada se limpia sin
/// republicar; en la anterior, con candidato válido y fuentes vigentes, se
/// publica; con fuentes cambiadas se aborta; en otra versión es conflicto.
/// Un journal de otro proyecto que [projectId] es un conflicto: los hashes
/// no acreditan pertenencia. Sin journal, sólo se retiran [candidates]
/// completos y propios de [projectId]; nunca se adoptan, y [temporaries]
/// los vuelven un conflicto. Un fallo después del rename sale como
/// [AssessmentCommitFailure], con lo publicado.
Future<AssessmentRecovery> recoverAssessment(
  AssessmentStore assessments, {
  required String projectId,
  required List<String> candidates,
  required Future<void> Function(AssessmentDocument candidate) revalidate,
  List<String> temporaries = const [],
}) async {
  final store = assessments.store;
  await store.createDirectory('shipflow/local/locks');
  final lease = await store.acquirePublication([store.contextLock()]);
  try {
    final journal = await assessments.readJournal();
    if (journal == null && temporaries.isNotEmpty) {
      // Un temporal sin journal no se puede acreditar: no se retira ni se
      // declara ajeno, se informa para reconciliarlo a mano.
      return AssessmentRecovery(
        AssessmentRecoveryOutcome.conflict,
        kept: temporaries,
      );
    }
    if (journal == null) {
      return _leftovers(assessments, projectId, candidates);
    }
    if (journal.projectId != projectId) {
      return AssessmentRecovery(
        AssessmentRecoveryOutcome.conflict,
        kept: [assessmentJournalPath, journal.candidatePath],
      );
    }
    return await _withJournal(assessments, journal, revalidate);
  } finally {
    await lease.release();
  }
}

Future<AssessmentRecovery> _withJournal(
  AssessmentStore assessments,
  AssessmentTransaction journal,
  Future<void> Function(AssessmentDocument) revalidate,
) async {
  final now = await assessments.hashOf(assessmentPath);
  if (now == journal.after) {
    final removed = await assessments.cleanup(journal);
    return AssessmentRecovery(
      AssessmentRecoveryOutcome.cleaned,
      removed: removed,
    );
  }
  if (now != journal.before) {
    return AssessmentRecovery(AssessmentRecoveryOutcome.conflict);
  }
  return _finish(assessments, journal, revalidate);
}

/// El documento sigue en su versión anterior: se publica el candidato si
/// es el preparado y sus fuentes siguen vigentes; si no, se aborta.
Future<AssessmentRecovery> _finish(
  AssessmentStore assessments,
  AssessmentTransaction journal,
  Future<void> Function(AssessmentDocument) revalidate,
) async {
  final candidate = await _candidate(assessments, journal);
  if (candidate == null) {
    return AssessmentRecovery(
      AssessmentRecoveryOutcome.conflict,
      kept: [journal.candidatePath],
    );
  }
  try {
    await revalidate(candidate.$1);
  } on AssessmentAbort {
    final removed = await assessments.cleanup(journal);
    return AssessmentRecovery(
      AssessmentRecoveryOutcome.aborted,
      removed: removed,
    );
  }
  return _commit(assessments, journal, candidate.$2);
}

/// El commit del candidato con sus efectos verdaderos: creado si no había
/// documento y reemplazado si lo había, también si algo falla después.
Future<AssessmentRecovery> _commit(
  AssessmentStore assessments,
  AssessmentTransaction journal,
  List<int> bytes,
) async {
  AssessmentPublication done(bool published) => AssessmentPublication(
    created: [if (journal.before == null) assessmentPath],
    replaced: [if (journal.before != null) assessmentPath],
    published: published,
  );
  await assessments.commitReported(journal, bytes, done);
  final publication = done(
    await assessments.hashOf(assessmentPath) == journal.after,
  );
  return AssessmentRecovery(
    AssessmentRecoveryOutcome.published,
    created: publication.created,
    replaced: publication.replaced,
    published: publication.published,
  );
}

/// El candidato del journal, sólo si sus bytes tienen la huella preparada,
/// valida, es del mismo proyecto y cita el snapshot del journal.
Future<(AssessmentDocument, List<int>)?> _candidate(
  AssessmentStore assessments,
  AssessmentTransaction journal,
) async {
  final bytes = await assessments.bytesOf(journal.candidatePath);
  if (bytes == null || sha256Of(bytes) != journal.after) return null;
  try {
    final document = decodeAssessment(bytes);
    final own =
        document.projectId == journal.projectId &&
        document.current.snapshotId == journal.snapshotId;
    return own ? (document, bytes) : null;
  } on ContextFormatException {
    return null;
  }
}

/// Sin journal: un candidato completo y propio se retira tras
/// identificarlo; cualquier otro se conserva y se informa.
Future<AssessmentRecovery> _leftovers(
  AssessmentStore assessments,
  String projectId,
  List<String> candidates,
) async {
  final removed = <String>[];
  final kept = <String>[];
  for (final path in candidates) {
    final bytes = await assessments.bytesOf(path);
    if (bytes != null && _own(bytes, projectId)) {
      await assessments.store.removeRelative(
        path,
        expectedSha256: sha256Of(bytes),
      );
      await assessments.store.removeDirectory(
        path.substring(0, path.lastIndexOf('/')),
      );
      removed.add(path);
    } else {
      kept.add(path);
    }
  }
  return AssessmentRecovery(
    removed.isEmpty && kept.isEmpty
        ? AssessmentRecoveryOutcome.nothing
        : kept.isEmpty
        ? AssessmentRecoveryOutcome.leftoversRemoved
        : AssessmentRecoveryOutcome.conflict,
    removed: removed,
    kept: kept,
  );
}

bool _own(List<int> bytes, String projectId) {
  try {
    return decodeAssessment(bytes).projectId == projectId;
  } on ContextFormatException {
    return false;
  }
}
