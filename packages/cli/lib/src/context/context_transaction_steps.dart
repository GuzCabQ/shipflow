import 'package:core/core.dart';
import 'package:vcs/vcs.dart' show maxExcludeBytes;

import 'context_codec.dart';
import 'context_observation.dart';
import 'context_publication_plan.dart';
import 'context_result.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';

const _shipflow = '$stateDirectory/';

/// Cada paso de una publicación, sobre el almacén anclado y siempre contra
/// la huella esperada: ninguno escribe sobre una versión que no vio.
final class TransactionSteps {
  TransactionSteps(this.plan, this.store, this.effects)
    : _projectBytes = plan.project == null
          ? null
          : const ContextCodec().encodeProject(plan.project!),
      _settingsBytes = const ContextCodec().encodeSettings(plan.settings);

  final PublicationPlan plan;
  final ContextStore store;
  final EffectsLog effects;
  final List<int>? _projectBytes;
  final List<int> _settingsBytes;
  final _transient = <String>[];
  String? _journalHash;

  ObservedContext get _o => plan.observed;
  String get _op => plan.operationId;
  bool get journalWritten => _journalHash != null;

  bool get _settingsChange =>
      !_o.settings.present || hashOf(_settingsBytes) != _o.settings.sha256;

  Future<void> scaffold() async {
    effects.directoriesCreated.addAll(
      await store.createDirectory('shipflow/local/locks'),
    );
    final ignore = await store.readRelative(gitignorePath, maxBytes: 4096);
    if (ignore == null) {
      await store.publishRelative(
        gitignorePath,
        generatedGitignore.codeUnits,
        expectedSha256: null,
      );
      effects.published(gitignorePath, existed: false);
    }
  }

  /// Si project, settings, journal y exclude siguen como se observaron.
  Future<bool> unchangedSince() async {
    for (final (path, expected) in [
      (projectPath, _o.project.sha256),
      (settingsPath, _o.settings.sha256),
      (transactionPath, _o.journal.sha256),
    ]) {
      final bytes = await store.readRelative(path, maxBytes: maxProjectBytes);
      if ((bytes == null ? null : hashOf(bytes)) != expected) return false;
    }
    final exclude = plan.exclude;
    if (exclude == null) return true;
    final now = await exclude.admin.readRelative(
      excludeName,
      maxBytes: maxExcludeBytes,
    );
    return (now == null ? null : hashOf(now)) == exclude.beforeHash;
  }

  ContextTransaction _journal(TransactionPhase phase) => ContextTransaction(
    operationId: _op,
    projectId: plan.settings.projectId,
    operation: plan.operation,
    choice: plan.choice,
    phase: phase,
    targets: _targets(),
    staging: TransactionStaging(
      project: _projectBytes == null ? null : stagedProjectPath(_op),
      settingsBefore: _settingsChange && _o.settings.present
          ? stagedSettingsBeforePath(_op)
          : null,
      settingsAfter: _settingsChange ? stagedSettingsAfterPath(_op) : null,
    ),
    exclude: TransactionExclude(
      blockId: plan.exclude?.blockId,
      beforeBlock: plan.exclude?.patch.beforeBlock,
      afterBlock: plan.exclude?.patch.afterBlock,
    ),
  );

  /// Las huellas antes y después de cada destino que cambia.
  List<TransactionTarget> _targets() => [
    if (_projectBytes case final bytes?)
      TransactionTarget(
        resource: TransactionResource.project,
        before: _o.project.sha256,
        after: hashOf(bytes),
      ),
    if (_settingsChange)
      TransactionTarget(
        resource: TransactionResource.settings,
        before: _o.settings.sha256,
        after: hashOf(_settingsBytes),
      ),
    if (plan.exclude case final e? when e.patch.changed)
      TransactionTarget(
        resource: TransactionResource.exclude,
        before: e.beforeHash,
        after: e.afterHash,
      ),
  ];

  Future<void> writeJournal(TransactionPhase phase) async {
    final bytes = const ContextCodec().encodeTransaction(_journal(phase));
    await store.publishRelative(
      transactionPath,
      bytes,
      expectedSha256: _journalHash,
    );
    _journalHash = hashOf(bytes);
  }

  /// El staging de esta operación, creado después del journal: un fallo
  /// antes de él no deja restos.
  Future<void> stage() async {
    final created = await store.createDirectory('shipflow/local/staging/$_op');
    effects.directoriesCreated.addAll(
      created.where((dir) => !dir.endsWith(_op)),
    );
    final staging = _journal(TransactionPhase.prepared).staging;
    for (final (path, bytes) in [
      (staging.project, _projectBytes),
      (staging.settingsAfter, _settingsBytes),
      (staging.settingsBefore, _o.settings.bytes),
    ]) {
      if (path == null || bytes == null) continue;
      await store.publishRelative(
        '$_shipflow$path',
        bytes,
        expectedSha256: null,
      );
      _transient.add('$_shipflow$path');
    }
  }

  Future<void> publishExclude() async {
    final e = plan.exclude!;
    await e.admin.publishRelative(
      excludeName,
      e.patch.after!,
      expectedSha256: e.beforeHash,
    );
    effects.excludeModified = true;
  }

  /// El exclude vuelve a sus bytes previos, sólo si sigue como se dejó.
  Future<void> revertExclude() async {
    final e = plan.exclude;
    if (e == null || !e.patch.changed || !effects.excludeModified) return;
    if (e.before == null) {
      await e.admin.removeRelative(excludeName, expectedSha256: e.afterHash);
    } else {
      await e.admin.publishRelative(
        excludeName,
        e.before!,
        expectedSha256: e.afterHash,
      );
    }
  }

  Future<void> publishSettings() async {
    if (!_settingsChange) return;
    await store.publishRelative(
      settingsPath,
      _settingsBytes,
      expectedSha256: _o.settings.sha256,
    );
    effects.published(settingsPath, existed: _o.settings.present);
  }

  /// Una copia válida anterior, antes de reemplazar el contexto.
  Future<void> publishPrevious() async {
    if (_projectBytes == null || !_o.project.present) return;
    final old = await store.readRelative(
      previousPath,
      maxBytes: maxProjectBytes,
    );
    await store.publishRelative(
      previousPath,
      _o.project.bytes!,
      expectedSha256: old == null ? null : hashOf(old),
    );
    effects.published(previousPath, existed: old != null);
  }

  Future<void> publishProject() async {
    final bytes = _projectBytes;
    if (bytes == null) return;
    await store.publishRelative(
      projectPath,
      bytes,
      expectedSha256: _o.project.sha256,
    );
    effects.published(projectPath, existed: _o.project.present);
    await writeJournal(TransactionPhase.contextPublished);
  }

  /// Retira el staging propio, su directorio y el journal.
  Future<void> cleanup() async {
    for (final path in _transient.toList()) {
      final bytes = await store.readRelative(path, maxBytes: maxProjectBytes);
      if (bytes != null) {
        await store.removeRelative(path, expectedSha256: hashOf(bytes));
      }
      _transient.remove(path);
    }
    await store.removeDirectory('shipflow/local/staging/$_op');
    if (_journalHash case final hash?) {
      await store.removeRelative(transactionPath, expectedSha256: hash);
      _journalHash = null;
    }
  }

  /// Lo que quedó tras un fallo: se informa como creado.
  void leaveTransient() {
    effects.filesCreated.addAll(_transient);
    if (journalWritten) effects.filesCreated.add(transactionPath);
  }
}
