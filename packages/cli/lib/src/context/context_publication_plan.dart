import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_decisions.dart';
import 'context_observation.dart';
import 'secure_context_store.dart';

/// El nombre del exclude dentro del directorio `info` de administración.
const excludeName = 'exclude';

/// Un cambio del exclude común ya calculado, con su directorio anclado.
final class ExcludeChange {
  ExcludeChange({
    required this.admin,
    required this.path,
    required this.before,
    required this.patch,
    required this.blockId,
    required this.prefix,
  });

  final ContextStore admin;

  /// El exclude absoluto, para el registro local.
  final String path;
  final List<int>? before;
  final ManagedExcludePatch patch;
  final String blockId;
  final String prefix;

  String? get beforeHash => before == null ? null : hashOf(before!);
  String get afterHash => hashOf(patch.after!);
}

/// Una publicación decidida: qué documentos y qué exclude pasan a qué.
final class PublicationPlan {
  PublicationPlan({
    required this.operationId,
    required this.operation,
    required this.settings,
    required this.observed,
    this.project,
    this.exclude,
  });

  final String operationId;
  final TransactionOperation operation;
  final LocalSettings settings;
  final ObservedContext observed;
  final ProjectContext? project;
  final ExcludeChange? exclude;

  SharingChoice get choice => settings.choice;
}

/// El ID del bloque propio: SHA-256 del prefix Git en UTF-8.
String blockIdOf(String prefix) => hashOf(utf8.encode(prefix));

/// El documento nuevo para [current], conservando [projectId].
ProjectContext candidateFor({
  required String projectId,
  required int revision,
  required String version,
  required PortableRecognition current,
  required List<String> pluginIds,
  required DateTime now,
}) => ProjectContext(
  projectId: projectId,
  revision: revision,
  producer: ContextProducer(
    version: version,
    recognitionContract: recognitionContract,
    pluginIds: pluginIds,
  ),
  observedAt: '${now.toUtc().toIso8601String().substring(0, 19)}Z',
  recognition: current,
  observationDigest: digestOf(current),
);

/// La configuración local de [choice]: aplicada salvo pendiente.
LocalSettings settingsFor(
  String projectId,
  SharingChoice choice,
  GitObservation git,
  ExcludeChange? exclude,
) => LocalSettings(
  projectId: projectId,
  choice: choice,
  binding: choice == SharingChoice.pending ? null : git.binding,
  applied: choice != SharingChoice.pending,
  managedExclude: choice == SharingChoice.local && exclude != null
      ? ManagedExcludeRecord(
          path: exclude.path,
          blockId: exclude.blockId,
          sha256: hashOf(utf8.encode(_ownBlock(exclude))),
        )
      : null,
);

/// El texto propio que queda en el exclude tras [exclude].
String _ownBlock(ExcludeChange exclude) =>
    exclude.patch.afterBlock ?? excludeBlock(exclude.prefix, exclude.blockId);

/// El cambio del exclude para [choice], leído desde su directorio anclado,
/// o null si [choice] no lo toca. El separador propio sólo se acredita si
/// su huella coincide con la registrada en [settings].
Future<ExcludeChange?> excludeChangeFor(
  ObservedContext o,
  SharingChoice choice,
  Future<ContextStore> Function(Directory) openAdministration,
) async {
  final path = o.git.excludePath;
  final prefix = o.git.binding?.prefix;
  if (choice == SharingChoice.pending || path == null || prefix == null) {
    return null;
  }
  final admin = await openAdministration(File(path).parent);
  final before = await admin.readRelative(
    excludeName,
    maxBytes: maxExcludeBytes,
  );
  final blockId = blockIdOf(prefix);
  final patch = planExclude(
    prefix: prefix,
    choice: choice,
    existing: before,
    blockId: blockId,
    ownedBlock: _recorded(o.settings.value, prefix, blockId, before),
  );
  return ExcludeChange(
    admin: admin,
    path: path,
    before: before,
    patch: patch,
    blockId: blockId,
    prefix: prefix,
  );
}

String? _recorded(
  LocalSettings? settings,
  String prefix,
  String blockId,
  List<int>? existing,
) {
  final recorded = settings?.managedExclude?.sha256;
  if (recorded == null) return null;
  final canonical = excludeBlock(prefix, blockId);
  for (final candidate in ['\n$canonical', canonical]) {
    if (hashOf(utf8.encode(candidate)) == recorded) return candidate;
  }
  return null;
}
