import 'dart:io';

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:vcs/vcs.dart';

import '../cli_command.dart';
import 'context_codec.dart';
import 'context_request.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';
import 'state_ownership.dart';

/// Las rutas propias que Git debe poder versionar o excluir.
const ownSharedPaths = [projectPath, gitignorePath];

/// Un documento leído: sus bytes y su huella, o su ausencia, y su valor o
/// el código por el que no se acepta.
final class DocumentRead<T> {
  const DocumentRead(this.bytes, this.value, this.error);

  const DocumentRead.absent() : bytes = null, value = null, error = null;

  final List<int>? bytes;
  final T? value;
  final String? error;

  bool get present => bytes != null;
  String? get sha256 => bytes == null ? null : hashOf(bytes!);
}

String hashOf(List<int> bytes) => sha256.convert(bytes).toString();

/// El digest canónico de [recognition].
String digestOf(PortableRecognition recognition) =>
    const ContextCodec().digest(recognition);

/// Todo lo observado antes de decidir, sin escribir nada.
final class ObservedContext {
  ObservedContext({
    required this.ownership,
    required this.project,
    required this.settings,
    required this.journal,
    required this.git,
    required this.report,
    required this.current,
    this.stable = true,
  });

  final StateOwnership ownership;
  final DocumentRead<ProjectContext> project;
  final DocumentRead<LocalSettings> settings;
  final DocumentRead<ContextTransaction> journal;
  final GitObservation git;
  final RecognitionReport report;

  /// La proyección portable del reconocimiento actual, si es elegible.
  final PortableRecognition? current;

  /// False si los documentos cambiaron entre dos lecturas seguidas, dos
  /// veces: no hay una vista consistente de una sola generación.
  final bool stable;

  SharingChoice get choice => settings.value?.choice ?? SharingChoice.pending;

  bool get gitUsable => git.state == GitState.available;
}

/// Observa la raíz: propiedad, documentos, Git y reconocimiento actual.
Future<ObservedContext> observeContext({
  required Directory root,
  required ContextStore store,
  required GitContextAdapter git,
  required GitBudget budget,
  required ContextRecognizer recognize,
  required ReportBudgetProfile profile,
}) async {
  final ownership = await inspectStateOwnership(root);
  final report = await recognize(profile, authorizedStateOmissions(ownership));
  final docs = ownership.kind == StateOwnershipKind.foreign
      ? _Documents.absent()
      : await _stableDocuments(store);
  return ObservedContext(
    ownership: ownership,
    project: docs.project,
    settings: docs.settings,
    journal: docs.journal,
    git: await git.observe(root, ownPaths: ownSharedPaths, budget: budget),
    report: report,
    current: _portable(report),
    stable: docs.stable,
  );
}

/// Los tres documentos de una misma generación: se leen, se vuelven a
/// mirar sus huellas y, si cambiaron, se reintenta una sola vez.
Future<_Documents> _stableDocuments(ContextStore store) async {
  late _Documents docs;
  for (var attempt = 0; attempt < 2; attempt++) {
    docs = await _Documents.read(store);
    if (await docs.unchanged(store)) return docs;
  }
  return docs.unstable();
}

final class _Documents {
  _Documents(this.project, this.settings, this.journal, {this.stable = true});

  _Documents.absent()
    : this(
        const DocumentRead.absent(),
        const DocumentRead.absent(),
        const DocumentRead.absent(),
      );

  static Future<_Documents> read(ContextStore store) async {
    const codec = ContextCodec();
    return _Documents(
      await readDocument(store, projectPath, codec.decodeProject),
      await readDocument(store, settingsPath, codec.decodeSettings),
      await readDocument(store, transactionPath, codec.decodeTransaction),
    );
  }

  final DocumentRead<ProjectContext> project;
  final DocumentRead<LocalSettings> settings;
  final DocumentRead<ContextTransaction> journal;
  final bool stable;

  Future<bool> unchanged(ContextStore store) async {
    for (final (path, read) in [
      (projectPath, project),
      (settingsPath, settings),
      (transactionPath, journal),
    ]) {
      final bytes = await store.readRelative(path, maxBytes: maxProjectBytes);
      if ((bytes == null ? null : hashOf(bytes)) != read.sha256) return false;
    }
    return true;
  }

  _Documents unstable() =>
      _Documents(project, settings, journal, stable: false);
}

/// [path] leído por el almacén y validado con [decode].
Future<DocumentRead<T>> readDocument<T>(
  ContextStore store,
  String path,
  T Function(List<int>) decode,
) async {
  final List<int>? bytes;
  try {
    bytes = await store.readRelative(path, maxBytes: maxProjectBytes);
  } on ContextStoreFailure catch (failure) {
    return DocumentRead([], null, failure.code);
  }
  if (bytes == null) return const DocumentRead.absent();
  try {
    return DocumentRead(bytes, decode(bytes), null);
  } on ContextFormatException catch (e) {
    return DocumentRead(bytes, null, e.code);
  }
}

PortableRecognition? _portable(RecognitionReport report) {
  try {
    return projectRecognition(report);
  } on ContextFormatException {
    return null;
  }
}

/// Si el reconocimiento actual no pudo completarse por una cota del perfil.
bool reachedReportLimit(RecognitionReport report) =>
    report.limitations.any((l) => l.code == reportLimitReachedCode);
