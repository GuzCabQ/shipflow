import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_codec.dart' show maxProjectBytes;
import 'context_observation.dart';
import 'context_publication_plan.dart';
import 'context_recovery_staging.dart';
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
  }) : _staging = RecoveryStaging(journal);

  final ObservedContext o;
  final ContextTransaction journal;
  final ContextStore store;
  final Future<ContextStore> Function(Directory) openAdministration;
  final EffectsLog effects;
  ContextStore? _admin;
  ContextLease? _lease;
  final RecoveryStaging _staging;

  SharingChoice get choice => journal.choice;

  TransactionTarget? _target(TransactionResource resource) {
    for (final t in journal.targets) {
      if (t.resource == resource) return t;
    }
    return null;
  }

  Future<void> acquire() async {
    final excludeTarget = _target(TransactionResource.exclude);
    final binding = o.git.binding;
    if (excludeTarget != null) {
      if (binding == null ||
          o.git.excludePath != '${binding.commonDir}/$excludeName') {
        throw const ContextStoreFailure('io');
      }
      _admin = await openAdministration(Directory(binding.commonDir));
    }
    _lease = await store.acquirePublication([
      store.contextLock(),
      if (_admin case final admin?) admin.directoryLock(),
    ]);
    await _staging.read(store);
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

  /// Si cada destino que todavía no está en su versión preparada tiene con
  /// qué llegar a ella: contexto y settings, su staging con la huella del
  /// journal. El exclude se recompone y se comprueba al aplicarlo.
  Future<bool> completable() async {
    for (final t in journal.targets) {
      if (t.resource == TransactionResource.exclude ||
          await _hash(t.resource) == t.after) {
        continue;
      }
      if (_prepared(t) == null) return false;
    }
    return true;
  }

  /// Los bytes preparados de [t], si su staging está y coincide.
  List<int>? _prepared(TransactionTarget t) =>
      _staging.matching(switch (t.resource) {
        TransactionResource.project => journal.staging.project,
        TransactionResource.settings => journal.staging.settingsAfter,
        TransactionResource.exclude => null,
      }, t.after);

  /// El candidato preparado, si su staging está y coincide con su huella.
  ProjectContext? candidate() =>
      _staging.project(_target(TransactionResource.project)?.after);

  /// El contexto ya publicado, si es válido.
  ProjectContext? publishedProject() =>
      o.project.value ?? candidate() ?? decodedProject(o.project.bytes);

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

  /// Exclude, settings y contexto en su versión preparada; false si alguno
  /// pendiente no tiene con qué llegar a ella.
  Future<bool> applyRemaining() async {
    if (!await completable() || !await applyExclude()) return false;
    await _applyFromStaging(TransactionResource.settings, settingsPath);
    final project = _target(TransactionResource.project);
    if (project != null &&
        await _hash(TransactionResource.project) == project.before) {
      await _keepPrevious(project);
      await _applyFromStaging(TransactionResource.project, projectPath);
    }
    return true;
  }

  Future<void> _applyFromStaging(
    TransactionResource resource,
    String path,
  ) async {
    final t = _target(resource);
    if (t == null || await _hash(resource) == t.after) return;
    await store.publishRelative(path, _prepared(t)!, expectedSha256: t.before);
    effects.published(path, existed: t.before != null);
  }

  Future<void> _keepPrevious(TransactionTarget project) async {
    final old = o.project.bytes;
    if (project.before == null || old == null) return;
    final previous = await store.readRelative(
      previousPath,
      maxBytes: maxProjectBytes,
    );
    if (previous != null && hashOf(previous) == hashOf(old)) return;
    await store.publishRelative(
      previousPath,
      old,
      expectedSha256: previous == null ? null : hashOf(previous),
    );
    effects.published(previousPath, existed: previous != null);
  }

  /// Deshace settings y exclude propios que ya estén en su versión
  /// preparada; el contexto publicado nunca se revierte. False si alguno no
  /// se puede llevar exactamente a su versión anterior: entonces no se toca
  /// y la operación queda para reconciliarla a mano.
  Future<bool> revert() async =>
      await _revertSettings() && await _revertExclude();

  Future<bool> _revertSettings() async {
    final t = _target(TransactionResource.settings);
    if (t == null || await _hash(TransactionResource.settings) != t.after) {
      return true;
    }
    final bytes = _staging.matching(journal.staging.settingsBefore, t.before);
    if (bytes != null) {
      await store.publishRelative(settingsPath, bytes, expectedSha256: t.after);
      return true;
    }
    if (t.before != null) return false;
    await store.removeRelative(settingsPath, expectedSha256: t.after!);
    return true;
  }

  Future<bool> _revertExclude() async {
    final t = _target(TransactionResource.exclude);
    if (t == null) return true;
    final now = await _current(TransactionResource.exclude);
    if (now == null || hashOf(now) != t.after) return true;
    final patch = _patch(now, forward: false);
    if (t.before == null && (patch == null || patch.isEmpty)) {
      await _admin!.removeRelative(excludeName, expectedSha256: t.after!);
    } else if (patch != null && hashOf(patch) == t.before) {
      await _admin!.publishRelative(
        excludeName,
        patch,
        expectedSha256: t.after,
      );
    } else {
      return false;
    }
    effects.excludeModified = true;
    return true;
  }

  /// Retira el staging propio, los temporales de publicaciones que este
  /// journal acredita, su directorio y el journal.
  Future<void> cleanup() async {
    for (final path in o.ownership.findings.where(isOwnTemporary)) {
      final bytes = await store.readRelative(path, maxBytes: maxProjectBytes);
      if (bytes == null) continue;
      await store.removeRelative(path, expectedSha256: hashOf(bytes));
      effects.filesRemoved.add(path);
    }
    for (final MapEntry(key: path, value: bytes) in _staging.files.entries) {
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
