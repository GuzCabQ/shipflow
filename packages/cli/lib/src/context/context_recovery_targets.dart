import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_codec.dart';
import 'context_observation.dart';
import 'context_publication_plan.dart';
import 'context_result.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';

const _shipflow = '$stateDirectory/';

/// Los destinos de un journal, recalculados desde raíces comprobadas: el
/// journal da huellas y nombres de staging, nunca rutas con autoridad.
final class RecoveryTargets {
  RecoveryTargets({
    required this.o,
    required this.journal,
    required this.store,
    required this.openAdministration,
    required this.effects,
  });

  final ObservedContext o;
  final ContextTransaction journal;
  final ContextStore store;
  final Future<ContextStore> Function(Directory) openAdministration;
  final EffectsLog effects;
  ContextStore? _admin;
  ContextLease? _lease;
  final _staged = <String, List<int>>{};

  SharingChoice get choice => journal.choice;

  TransactionTarget? _target(TransactionResource resource) {
    for (final t in journal.targets) {
      if (t.resource == resource) return t;
    }
    return null;
  }

  Future<void> acquire() async {
    final excludeTarget = _target(TransactionResource.exclude);
    final excludePath = o.git.excludePath;
    if (excludeTarget != null) {
      if (excludePath == null) throw const ContextStoreFailure('io');
      _admin = await openAdministration(File(excludePath).parent);
    }
    _lease = await store.acquirePublication([
      store.contextLock(),
      if (_admin case final admin?) admin.directoryLock(),
    ]);
    await _readStaging();
  }

  Future<void> _readStaging() async {
    final s = journal.staging;
    for (final path in [s.project, s.settingsBefore, s.settingsAfter]) {
      if (path == null) continue;
      final bytes = await store.readRelative(
        '$_shipflow$path',
        maxBytes: maxProjectBytes,
      );
      if (bytes != null) _staged[path] = bytes;
    }
  }

  Future<void> release() async {
    await _lease?.release();
    await _admin?.close();
  }

  Future<List<int>?> _current(TransactionResource resource) =>
      switch (resource) {
        TransactionResource.project => store.readRelative(
          projectPath,
          maxBytes: maxProjectBytes,
        ),
        TransactionResource.settings => store.readRelative(
          settingsPath,
          maxBytes: maxProjectBytes,
        ),
        TransactionResource.exclude => _admin!.readRelative(
          excludeName,
          maxBytes: maxExcludeBytes,
        ),
      };

  Future<String?> _hash(TransactionResource resource) async {
    final bytes = await _current(resource);
    return bytes == null ? null : hashOf(bytes);
  }

  /// La primera ruta cuyo contenido no es el anterior ni el preparado.
  Future<String?> conflicting() async {
    for (final t in journal.targets) {
      final now = await _hash(t.resource);
      if (now != t.before && now != t.after) {
        return switch (t.resource) {
          TransactionResource.project => projectPath,
          TransactionResource.settings => settingsPath,
          TransactionResource.exclude => o.git.excludePath,
        };
      }
    }
    return null;
  }

  /// Si el contexto ya está en su versión preparada, o no era un destino.
  Future<bool> projectPublished() async {
    final t = _target(TransactionResource.project);
    return t == null || await _hash(TransactionResource.project) == t.after;
  }

  /// El candidato preparado, si su staging está y coincide con su huella.
  ProjectContext? candidate() {
    final path = journal.staging.project;
    final bytes = path == null ? null : _staged[path];
    final t = _target(TransactionResource.project);
    if (bytes == null || t == null || hashOf(bytes) != t.after) return null;
    try {
      return const ContextCodec().decodeProject(bytes);
    } on ContextFormatException {
      return null;
    }
  }

  /// El contexto ya publicado, si es válido.
  ProjectContext? publishedProject() =>
      o.project.value ?? candidate() ?? _decoded(o.project.bytes);

  ProjectContext? _decoded(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      return const ContextCodec().decodeProject(bytes);
    } on ContextFormatException {
      return null;
    }
  }

  /// Lleva el exclude a su versión preparada; false si no se puede
  /// recomponer exactamente.
  Future<bool> applyExclude() async {
    final t = _target(TransactionResource.exclude);
    if (t == null) return true;
    final now = await _current(TransactionResource.exclude);
    if ((now == null ? null : hashOf(now)) == t.after) return true;
    final patch = _patch(now, forward: true);
    if (patch == null || hashOf(patch) != t.after) return false;
    await _admin!.publishRelative(excludeName, patch, expectedSha256: t.before);
    effects.excludeModified = true;
    return true;
  }

  /// El exclude recompuesto hacia la elección del journal o de vuelta.
  List<int>? _patch(List<int>? existing, {required bool forward}) {
    final prefix = o.git.binding?.prefix;
    final blockId = journal.exclude.blockId;
    if (prefix == null || blockId == null || blockIdOf(prefix) != blockId) {
      return null;
    }
    final local = choice == SharingChoice.local;
    final adding = local == forward;
    return planExclude(
      prefix: prefix,
      choice: adding ? SharingChoice.local : SharingChoice.share,
      existing: existing,
      blockId: blockId,
      ownedBlock: local
          ? journal.exclude.afterBlock
          : journal.exclude.beforeBlock,
    ).after;
  }

  /// Exclude, settings y contexto en su versión preparada.
  Future<bool> applyRemaining() async {
    if (!await applyExclude()) return false;
    await _applyFromStaging(
      TransactionResource.settings,
      settingsPath,
      journal.staging.settingsAfter,
    );
    final project = _target(TransactionResource.project);
    if (project != null &&
        await _hash(TransactionResource.project) == project.before) {
      await _keepPrevious(project);
      await _applyFromStaging(
        TransactionResource.project,
        projectPath,
        journal.staging.project,
      );
    }
    return true;
  }

  Future<void> _applyFromStaging(
    TransactionResource resource,
    String path,
    String? staged,
  ) async {
    final t = _target(resource);
    final bytes = staged == null ? null : _staged[staged];
    if (t == null || bytes == null || hashOf(bytes) != t.after) return;
    if (await _hash(resource) == t.after) return;
    await store.publishRelative(path, bytes, expectedSha256: t.before);
    effects.published(path, existed: t.before != null);
  }

  Future<void> _keepPrevious(TransactionTarget project) async {
    final old = o.project.bytes;
    if (project.before == null || old == null) return;
    final previous = await store.readRelative(
      previousPath,
      maxBytes: maxProjectBytes,
    );
    await store.publishRelative(
      previousPath,
      old,
      expectedSha256: previous == null ? null : hashOf(previous),
    );
    effects.published(previousPath, existed: previous != null);
  }

  /// Deshace settings y exclude propios que ya estén en su versión
  /// preparada; el contexto publicado nunca se revierte.
  Future<void> revert() async {
    final settings = _target(TransactionResource.settings);
    if (settings != null &&
        await _hash(TransactionResource.settings) == settings.after) {
      final before = journal.staging.settingsBefore;
      final bytes = before == null ? null : _staged[before];
      if (bytes != null) {
        await store.publishRelative(
          settingsPath,
          bytes,
          expectedSha256: settings.after,
        );
      } else {
        await store.removeRelative(
          settingsPath,
          expectedSha256: settings.after!,
        );
      }
    }
    await _revertExclude();
  }

  Future<void> _revertExclude() async {
    final t = _target(TransactionResource.exclude);
    if (t == null) return;
    final now = await _current(TransactionResource.exclude);
    if (now == null || hashOf(now) != t.after) return;
    final patch = _patch(now, forward: false);
    if (t.before == null && (patch == null || patch.isEmpty)) {
      await _admin!.removeRelative(excludeName, expectedSha256: t.after!);
    } else if (patch != null && hashOf(patch) == t.before) {
      await _admin!.publishRelative(
        excludeName,
        patch,
        expectedSha256: t.after,
      );
    }
    effects.excludeModified = true;
  }

  /// Retira el staging propio, su directorio y el journal.
  Future<void> cleanup() async {
    for (final MapEntry(key: path, value: bytes) in _staged.entries) {
      await store.removeRelative(
        '$_shipflow$path',
        expectedSha256: hashOf(bytes),
      );
    }
    await store.removeDirectory(
      'shipflow/local/staging/${journal.operationId}',
    );
    await store.removeRelative(
      transactionPath,
      expectedSha256: o.journal.sha256!,
    );
  }
}
