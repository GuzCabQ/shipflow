import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_decisions.dart';
import 'context_doctor.dart';
import 'context_observation.dart';
import 'context_init_publication.dart';
import 'context_request.dart';
import 'context_result.dart';
import 'context_service.dart';
import 'context_sharing_choice.dart';

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
    parts.actions.addAll([
      for (final action in nextActionsFor(parts.diagnostics, o))
        _withChoice(action),
    ]);
    if (_has('choice_required')) parts.actions.addAll(sharingActions());
    return resultOf(parts, effects.freeze(budget.started));
  }

  bool _has(String code) => parts.diagnostics.any((d) => d.code == code);

  /// Refresh conserva la elección guardada; si se pidió otra, la acción
  /// propuesta la lleva.
  ContextNextAction _withChoice(ContextNextAction action) {
    final wanted = request.sharing;
    if (wanted == null ||
        wanted == o.choice ||
        action.arguments.join() != '--refresh') {
      return action;
    }
    return initAction(
      ['--refresh', '--sharing=${wanted.toWireName()}'],
      action.purpose,
      '${action.effect} Aplica también la elección pedida.',
    );
  }

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
    await publishFor(this, (
      projectId: service.newId(),
      revision: 1,
      current: current,
      choice: choice,
      operation: TransactionOperation.init,
      success: ContextOutcome.initialized,
      keepSharing: false,
    ));
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
    if (wanted == o.choice && await _sharingInForce()) return;
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

  /// La elección guardada, comprobada ahora. Sin flag se informa tal cual,
  /// aunque no esté aplicada: nunca se alterna sola. Con el mismo flag sólo
  /// se republica si no está en vigor.
  Future<bool> _sharingInForce() async {
    final (:sharing, :diagnostics) = await sharingOf(o, service.git, budget);
    final inForce =
        sharing.effective != SharingEffective.conflict &&
        sharing.effective != SharingEffective.unverified;
    if (request.sharing != null && !inForce) return false;
    parts
      ..sharing = sharing
      ..diagnostics.addAll(diagnostics);
    return true;
  }

  /// La modalidad guardada, comprobada y reportada sin cambiarla.
  Future<void> reportSharing() async {
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
    final keep = request.sharing == null;
    if (keep && _rebound()) return;
    final choice = request.sharing ?? o.choice;
    if (!keep && !precheckSharing(o, choice, parts)) return;
    if (same && choice == o.choice) {
      parts.freshness = ContextFreshness.current;
      return reportSharing();
    }
    await publishFor(this, (
      projectId: saved.projectId,
      revision: same ? saved.revision : saved.revision + 1,
      current: same ? null : current,
      choice: choice,
      operation: same
          ? TransactionOperation.sharing
          : TransactionOperation.refresh,
      success: ContextOutcome.refreshed,
      keepSharing: keep,
    ));
  }

  /// Una elección local vinculada a otro repositorio no se revincula sola.
  bool _rebound() {
    if (!o.gitUsable || !reboundSettings(o)) return false;
    parts.diagnostics.add(bindingChanged());
    return true;
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

  Future<void> _publishSharing(SharingChoice choice) => publishFor(this, (
    projectId: o.project.value!.projectId,
    revision: o.project.value!.revision,
    current: null,
    choice: choice,
    operation: TransactionOperation.sharing,
    success: ContextOutcome.initialized,
    keepSharing: false,
  ));
}
