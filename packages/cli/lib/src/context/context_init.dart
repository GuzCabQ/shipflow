import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_decisions.dart';
import 'context_doctor.dart';
import 'context_observation.dart';
import 'context_publication_plan.dart';
import 'context_request.dart';
import 'context_result.dart';
import 'context_service.dart';
import 'context_sharing_choice.dart';
import 'context_transaction_runner.dart';
import 'state_layout.dart';
import 'state_ownership.dart';

/// Una invocación de init o de init --refresh: decide con lo observado,
/// antes de cualquier efecto, y publica sólo si todo lo permite.
final class InitSession {
  InitSession({
    required this.service,
    required this.o,
    required this.request,
    required this.budget,
  }) : parts = ResultParts(
         command: ContextCommand.init,
         operation: request.operation,
         state: ContextState.absent,
         freshness: ContextFreshness.notApplicable,
         sharing: ContextSharing(
           choice: o.choice,
           gitState: o.git.state,
           effective: SharingEffective.unverified,
         ),
       );

  final ProjectContextService service;
  final ObservedContext o;
  final ContextRequest request;
  final GitBudget budget;
  final ResultParts parts;
  final effects = EffectsLog();

  bool get _refresh => request.operation == ContextOperation.refresh;

  Future<ContextOperationResult> run() async {
    final (:state, :diagnostics) = stateOf(o);
    parts.state = state;
    parts.diagnostics.addAll(diagnostics);
    final blocked =
        diagnostics.isNotEmpty &&
        !(_refresh && state == ContextState.incompatible);
    if (!blocked) {
      if (state == ContextState.absent) {
        await (_refresh ? _notInitialized() : _first());
      } else {
        parts.diagnostics.clear();
        await (_refresh ? _refreshPresent() : _present());
      }
    }
    parts.actions.addAll(nextActionsFor(parts.diagnostics, o));
    if (_has('choice_required')) parts.actions.addAll(sharingActions());
    return resultOf(parts, effects.freeze(budget.started));
  }

  bool _has(String code) => parts.diagnostics.any((d) => d.code == code);

  Future<void> _notInitialized() async => parts.diagnostics.add(
    diagnostic(
      'not_initialized',
      'No hay contexto que actualizar; inicializa primero.',
    ),
  );

  /// Primera incorporación: reconocimiento elegible, elección y publicación.
  Future<void> _first() async {
    if (ancestorContext(service.root, o.git) case final ancestor?) {
      parts.diagnostics.add(
        diagnostic(
          'ancestor_context',
          'Esta carpeta está dentro de un proyecto ya inicializado; opera '
              'desde su raíz.',
          ancestor,
        ),
      );
      return;
    }
    final current = o.current;
    if (current == null) return _ineligible();
    final choice = await chooseSharing(o, request, parts);
    if (choice == null || !precheckSharing(o, choice, parts)) return;
    await _publish(
      projectId: service.newId(),
      revision: 1,
      current: current,
      choice: choice,
      operation: TransactionOperation.init,
      success: ContextOutcome.initialized,
    );
  }

  /// Init sobre un contexto guardado: verifica, nunca actualiza
  /// observaciones; puede resolver o cambiar la elección de conservación.
  Future<void> _present() async {
    final (:freshness, :diagnostics) = freshnessOf(o, parts.state);
    parts
      ..freshness = freshness
      ..context = o.project.value?.recognition
      ..diagnostics.addAll(diagnostics);
    if (freshness != ContextFreshness.current) return;
    final wanted = await _wantedChoice();
    if (wanted == null) return;
    if (wanted == o.choice && request.sharing == null) {
      return _keepSharing();
    }
    if (!precheckSharing(o, wanted, parts)) return;
    await _publishSharing(wanted);
  }

  /// La elección que esta invocación quiere aplicar, o null si ya se decidió
  /// el resultado (elección requerida, cancelada o imposible).
  Future<SharingChoice?> _wantedChoice() async {
    if (request.sharing == null && o.choice != SharingChoice.pending) {
      return o.choice;
    }
    if (!o.gitUsable && request.sharing == null) return SharingChoice.pending;
    return chooseSharing(o, request, parts);
  }

  Future<void> _keepSharing() async {
    final (:sharing, :diagnostics) = await sharingOf(o, service.git, budget);
    parts
      ..sharing = sharing
      ..diagnostics.addAll(diagnostics);
  }

  /// Refresh: reobserva y publica sólo un reconocimiento elegible y
  /// distinto; conserva projectId y decisiones locales.
  Future<void> _refreshPresent() async {
    final saved = o.project.value!;
    parts.context = saved.recognition;
    final current = o.current;
    if (current == null) return _ineligible();
    final same =
        saved.observationDigest == digestOf(current) &&
        saved.producer.recognitionContract == recognitionContract;
    final choice = request.sharing ?? o.choice;
    if (request.sharing != null && !precheckSharing(o, choice, parts)) return;
    if (same && choice == o.choice) {
      parts.freshness = ContextFreshness.current;
      return _keepSharing();
    }
    await _publish(
      projectId: saved.projectId,
      revision: same ? saved.revision : saved.revision + 1,
      current: same ? null : current,
      choice: choice,
      operation: same
          ? TransactionOperation.sharing
          : TransactionOperation.refresh,
      success: ContextOutcome.refreshed,
    );
  }

  void _ineligible() {
    final limit = reachedReportLimit(o.report);
    parts.diagnostics.add(
      diagnostic(
        limit ? 'recognition_unverified' : 'not_eligible',
        limit
            ? 'El reconocimiento no cabe en el perfil pedido; no se publica.'
            : 'El reconocimiento actual no es elegible; no se publica nada.',
      ),
    );
  }

  Future<void> _publishSharing(SharingChoice choice) => _publish(
    projectId: o.project.value!.projectId,
    revision: o.project.value!.revision,
    current: null,
    choice: choice,
    operation: TransactionOperation.sharing,
    success: ContextOutcome.initialized,
  );

  Future<void> _publish({
    required String projectId,
    required int revision,
    required PortableRecognition? current,
    required SharingChoice choice,
    required TransactionOperation operation,
    required ContextOutcome success,
  }) async {
    final exclude = await excludeChangeFor(
      o,
      choice,
      service.openAdministration,
    );
    if (exclude?.patch.problem case final problem?) {
      parts.diagnostics.add(excludeProblem(problem));
      return;
    }
    final project = current == null
        ? null
        : candidateFor(
            projectId: projectId,
            revision: revision,
            version: service.version,
            current: current,
            pluginIds: o.report.proposal.pluginIds,
            now: service.now(),
          );
    final plan = PublicationPlan(
      operationId: service.newId(),
      operation: operation,
      settings: settingsFor(projectId, choice, o.git, exclude),
      observed: o,
      project: project,
      exclude: exclude,
    );
    await _run(plan, success);
  }

  Future<void> _run(PublicationPlan plan, ContextOutcome success) async {
    final result = await runTransaction(
      plan: plan,
      store: service.store,
      git: service.git,
      budget: budget,
      effects: effects,
      sourcesUnchanged: () => _sourcesUnchanged(plan.project),
    );
    parts.diagnostics.addAll(result.diagnostics);
    if (result.journalLeft) parts.state = ContextState.recoveryRequired;
    if (!result.ok) return;
    final context = plan.project?.recognition ?? o.project.value?.recognition;
    parts
      ..state = ContextState.present
      ..freshness = ContextFreshness.current
      ..context = context
      ..success = success
      ..sharing = ContextSharing(
        choice: plan.choice,
        gitState: o.git.state,
        effective: result.sharing ?? SharingEffective.pending,
      );
    if (!o.gitUsable) parts.diagnostics.add(gitWarning(o.git));
  }

  Future<bool> _sourcesUnchanged(ProjectContext? candidate) async {
    if (candidate == null) return true;
    final report = await service.recognize(
      request.profile,
      authorizedStateOmissions(await inspectStateOwnership(service.root)),
    );
    try {
      return digestOf(projectRecognition(report)) ==
          candidate.observationDigest;
    } on ContextFormatException {
      return false;
    }
  }
}

/// Un `shipflow/project.json` en una carpeta ancestro, sólo por metadatos:
/// hasta la raíz Git, o a lo sumo 32 niveles sin Git.
String? ancestorContext(Directory root, GitObservation git) {
  final top = git.binding?.repositoryRoot;
  var dir = root.parent;
  for (var level = 0; level < 32 && dir.path != root.path; level++) {
    if (top != null && !'${root.path}/'.startsWith('$top/')) break;
    final candidate = '${dir.path}/$projectPath';
    if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
        FileSystemEntityType.file) {
      return candidate;
    }
    if (dir.path == top || dir.parent.path == dir.path) break;
    dir = dir.parent;
  }
  return null;
}
