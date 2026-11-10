import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import '../command/cli_command.dart';
import 'context_assessment.dart';
import 'context_observation.dart';
import 'context_publication_outcome.dart';
import 'context_publication_plan.dart';
import 'context_request.dart';
import 'context_result.dart';
import 'context_sharing_choice.dart';
import 'context_transaction_runner.dart';
import 'secure_context_store.dart';
import 'state_layout.dart';
import 'state_ownership.dart';

/// Lo que una invocación de init decidió publicar.
typedef PublishRequest = ({
  String projectId,
  int revision,
  PortableRecognition? current,
  SharingChoice choice,
  TransactionOperation operation,
  bool keepSharing,
});

/// Publica lo que decide la sesión y devuelve lo ocurrido. Es dueño de la
/// administración Git que abre para el exclude y la cierra al terminar.
///
/// Sus dependencias son privadas y no incluyen la sesión, el servicio ni el
/// resultado: sólo lo que la publicación usa para observar, escribir y
/// producir valores (IDs, reloj, reconocimiento y el abridor administrativo).
final class ContextPublisher {
  ContextPublisher({
    required Directory root,
    required ContextStore store,
    required GitContextAdapter git,
    required ContextRecognizer recognize,
    required String version,
    required DateTime Function() now,
    required String Function() newId,
    required Future<ContextStore> Function(Directory) openAdministration,
  }) : _root = root,
       _store = store,
       _git = git,
       _recognize = recognize,
       _version = version,
       _now = now,
       _newId = newId,
       _openAdministration = openAdministration;

  final Directory _root;
  final ContextStore _store;
  final GitContextAdapter _git;
  final ContextRecognizer _recognize;
  final String _version;
  final DateTime Function() _now;
  final String Function() _newId;
  final Future<ContextStore> Function(Directory) _openAdministration;

  /// Publica [r] con la observación y el contexto de ejecución de la llamada.
  /// Sin `--sharing`, `keepSharing` deja configuración y exclude tal cual.
  ///
  /// La administración del exclude, si se abrió, se cierra al terminar: en una
  /// publicación, después de soltar su lease, y después de la comprobación Git
  /// del caso sin plan. Si algo falla antes, se cierra también y se propaga el
  /// fallo original.
  Future<PublicationOutcome> publish(
    PublishRequest r, {
    required ObservedContext o,
    required ReportBudgetProfile profile,
    required GitBudget budget,
    required EffectsLog effects,
  }) async {
    final exclude = r.keepSharing
        ? null
        : await excludeChangeFor(o, r.choice, _openAdministration);
    if (exclude == null) {
      return _publish(r, o, profile, budget, effects, null);
    }
    final PublicationOutcome outcome;
    try {
      outcome = await _publish(r, o, profile, budget, effects, exclude);
    } on Object {
      await closeAfterFailure(exclude.admin);
      rethrow;
    }
    await exclude.admin.close();
    return outcome;
  }

  Future<PublicationOutcome> _publish(
    PublishRequest r,
    ObservedContext o,
    ReportBudgetProfile profile,
    GitBudget budget,
    EffectsLog effects,
    ExcludeChange? exclude,
  ) async {
    if (exclude?.patch.problem case final problem?) {
      return PublicationRefused(diagnostics: [excludeProblem(problem)]);
    }
    final plan = _planFor(r, o, exclude);
    if (plan == null) {
      final (:sharing, :diagnostics) = await sharingOf(o, _git, budget);
      return NothingToPublish(sharing: sharing, diagnostics: diagnostics);
    }
    return _run(plan, o, profile, budget, effects);
  }

  PublicationPlan? _planFor(
    PublishRequest r,
    ObservedContext o,
    ExcludeChange? e,
  ) {
    final project = _candidate(r, o);
    final settings = r.keepSharing
        ? null
        : settingsFor(r.projectId, r.choice, o.git, e);
    final unchanged =
        project == null &&
        !(e?.patch.changed ?? false) &&
        (settings == null || sameBytes(o.settings, settingsBytes(settings)));
    return unchanged
        ? null
        : PublicationPlan(
            operationId: _newId(),
            operation: r.operation,
            projectId: r.projectId,
            choice: r.choice,
            settings: settings,
            observed: o,
            project: project,
            exclude: e,
          );
  }

  ProjectContext? _candidate(PublishRequest r, ObservedContext o) {
    final current = r.current;
    return current == null
        ? null
        : candidateFor(
            projectId: r.projectId,
            revision: r.revision,
            version: _version,
            current: current,
            pluginIds: o.report.proposal.pluginIds,
            now: _now(),
          );
  }

  Future<PublicationOutcome> _run(
    PublicationPlan plan,
    ObservedContext o,
    ReportBudgetProfile profile,
    GitBudget budget,
    EffectsLog effects,
  ) async {
    final result = await runTransaction(
      plan: plan,
      store: _store,
      git: _git,
      budget: budget,
      effects: effects,
      sourcesUnchanged: () => _sourcesUnchanged(plan.project, profile),
    );
    if (!result.ok) {
      return PublicationRefused(
        diagnostics: result.diagnostics,
        journalLeft: result.journalLeft,
      );
    }
    return PublicationCompleted(
      choice: plan.choice,
      effective: result.sharing ?? SharingEffective.pending,
      recognition: plan.project?.recognition,
    );
  }

  /// Si el reconocimiento, repetido bajo el lease, sigue dando [candidate].
  Future<bool> _sourcesUnchanged(
    ProjectContext? candidate,
    ReportBudgetProfile profile,
  ) async {
    if (candidate == null) return true;
    final report = await _recognize(
      profile,
      authorizedStateOmissions(await inspectStateOwnership(_root)),
    );
    try {
      return digestOf(projectRecognition(report)) ==
          candidate.observationDigest;
    } on ContextFormatException {
      return false;
    }
  }
}

/// Un `shipflow/project.json` en una carpeta superior de la misma raíz Git,
/// sólo por metadatos y sin pasar del toplevel. Sin Git no se busca: no hay
/// un proyecto que acote la búsqueda.
String? ancestorContext(Directory root, GitObservation git) {
  final top = git.binding?.repositoryRoot;
  if (top == null || root.path == top || !root.path.startsWith('$top/')) {
    return null;
  }
  var dir = root.parent;
  while (dir.path.length >= top.length) {
    final candidate = '${dir.path}/$projectPath';
    if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
        FileSystemEntityType.file) {
      return candidate;
    }
    if (dir.path == top) break;
    dir = dir.parent;
  }
  return null;
}
