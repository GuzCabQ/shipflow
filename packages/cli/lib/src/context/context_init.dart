import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_decisions.dart';
import 'context_doctor.dart';
import 'context_observation.dart';
import 'context_init_publication.dart';
import 'context_publication_outcome.dart';
import 'context_request.dart';
import 'context_result.dart';
import 'context_sharing_choice.dart';

/// Una invocación de init o de init --refresh: decide con lo observado,
/// antes de cualquier efecto, y publica sólo si todo lo permite.
final class InitSession {
  InitSession({
    required Directory root,
    required GitContextAdapter git,
    required String Function() newId,
    required ContextPublisher publisher,
    required this.o,
    required this.request,
    required GitBudget budget,
  }) : _root = root,
       _git = git,
       _newId = newId,
       _publisher = publisher,
       _budget = budget,
       _parts = ResultParts(
         command: ContextCommand.init,
         operation: request.operation,
         state: ContextState.absent,
         freshness: ContextFreshness.notApplicable,
         sharing: ContextSharing(
           choice: o.choice,
           gitState: o.git.state,
           effective: SharingEffective.unverified,
         ),
       ) {
    _parts
      ..basis = o.ownership.basis
      ..basisTransaction = o.ownership.basisTransaction;
  }

  // Dependencias y trabajo de la invocación, privados: ninguno se expone por
  // getter ni callback. El resultado sale sólo por `run`.
  final Directory _root;
  final GitContextAdapter _git;
  final String Function() _newId;
  final ContextPublisher _publisher;
  final GitBudget _budget;
  final ResultParts _parts;
  final _effects = EffectsLog();

  /// Lo que se observó de la raíz antes de decidir; sólo se lee.
  final ObservedContext o;
  final ContextRequest request;

  bool get _refresh => request.operation == ContextOperation.refresh;

  Future<ContextOperationResult> run() async {
    final (:state, :diagnostics) = stateOf(o);
    _parts.state = state;
    _parts.diagnostics.addAll(diagnostics);
    final blocked =
        diagnostics.isNotEmpty &&
        !(_refresh && state == ContextState.incompatible);
    if (!blocked) {
      if (state == ContextState.absent) {
        await (_refresh ? _notInitialized() : _first());
      } else {
        _parts.diagnostics.clear();
        await (_refresh ? _refreshPresent() : _present());
      }
    }
    _parts.actions.addAll([
      for (final action in nextActionsFor(_parts.diagnostics, o))
        _withChoice(action),
    ]);
    if (_has('choice_required')) _parts.actions.addAll(sharingActions());
    return resultOf(_parts, _effects.freeze(_budget.started));
  }

  bool _has(String code) => _parts.diagnostics.any((d) => d.code == code);

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

  Future<void> _notInitialized() async => _parts.diagnostics.add(
    diagnostic(
      'not_initialized',
      'No hay contexto que actualizar; inicializa primero.',
    ),
  );

  /// Primera incorporación: reconocimiento elegible, elección y publicación.
  Future<void> _first() async {
    if (ancestorContext(_root, o.git) case final ancestor?) {
      _parts.diagnostics.add(
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
    final choice = await chooseSharing(o, request, _parts);
    if (choice == null || !precheckSharing(o, choice, _parts)) return;
    await _publish((
      projectId: _newId(),
      revision: 1,
      current: current,
      choice: choice,
      operation: TransactionOperation.init,
      keepSharing: false,
    ), ContextOutcome.initialized);
  }

  /// Init sobre un contexto guardado: verifica, nunca actualiza
  /// observaciones; puede resolver o cambiar la elección de conservación.
  Future<void> _present() async {
    final (:freshness, :diagnostics) = freshnessOf(o, _parts.state);
    _parts
      ..freshness = freshness
      ..context = o.project.value?.recognition
      ..diagnostics.addAll(diagnostics);
    if (freshness != ContextFreshness.current) return;
    final wanted = await _wantedChoice();
    if (wanted == null) return;
    if (wanted == o.choice && await _sharingInForce()) return;
    if (!precheckSharing(o, wanted, _parts)) return;
    await _publishSharing(wanted);
  }

  /// La elección que esta invocación quiere aplicar, o null si ya se decidió
  /// el resultado (elección requerida, cancelada o imposible).
  Future<SharingChoice?> _wantedChoice() async {
    if (request.sharing == null && o.choice != SharingChoice.pending) {
      return o.choice;
    }
    if (!o.gitUsable && request.sharing == null) return SharingChoice.pending;
    return chooseSharing(o, request, _parts);
  }

  /// La elección guardada, comprobada ahora. Sin flag se informa tal cual,
  /// aunque no esté aplicada: nunca se alterna sola. Con el mismo flag sólo
  /// se republica si no está en vigor.
  Future<bool> _sharingInForce() async {
    final (:sharing, :diagnostics) = await sharingOf(o, _git, _budget);
    final inForce =
        sharing.effective != SharingEffective.conflict &&
        sharing.effective != SharingEffective.unverified;
    if (request.sharing != null && !inForce) return false;
    _reportSharingWith(sharing, diagnostics);
    return true;
  }

  /// La modalidad guardada, comprobada y reportada sin cambiarla.
  Future<void> _reportSharing() async {
    final (:sharing, :diagnostics) = await sharingOf(o, _git, _budget);
    _reportSharingWith(sharing, diagnostics);
  }

  void _reportSharingWith(
    ContextSharing sharing,
    List<ContextDiagnostic> diagnostics,
  ) {
    _parts
      ..sharing = sharing
      ..diagnostics.addAll(diagnostics);
  }

  /// Publica [r] y proyecta lo ocurrido sobre el resultado de esta sesión.
  Future<void> _publish(PublishRequest r, ContextOutcome success) async =>
      _apply(
        await _publisher.publish(
          r,
          o: o,
          profile: request.profile,
          budget: _budget,
          effects: _effects,
        ),
        success,
      );

  /// Proyección exhaustiva: cada variante escribe exactamente lo que escribía
  /// el publicador antes, en el mismo orden.
  void _apply(PublicationOutcome outcome, ContextOutcome success) =>
      switch (outcome) {
        NothingToPublish(:final sharing, :final diagnostics) =>
          _reportSharingWith(sharing, diagnostics),
        final PublicationRefused refused => _refused(refused),
        final PublicationCompleted done => _completed(done, success),
      };

  void _refused(PublicationRefused refused) {
    _parts.diagnostics.addAll(refused.diagnostics);
    if (refused.journalLeft) _parts.state = ContextState.recoveryRequired;
  }

  void _completed(PublicationCompleted done, ContextOutcome success) {
    _parts
      ..state = ContextState.present
      ..freshness = ContextFreshness.current
      ..context = done.recognition ?? o.project.value?.recognition
      ..success = success
      ..sharing = ContextSharing(
        choice: done.choice,
        gitState: o.git.state,
        effective: done.effective,
      );
    if (!o.gitUsable) _parts.diagnostics.add(gitWarning(o.git));
  }

  /// Refresh: reobserva y publica sólo un reconocimiento elegible y
  /// distinto; conserva projectId y decisiones locales.
  Future<void> _refreshPresent() async {
    final saved = o.project.value!;
    _parts.context = saved.recognition;
    final current = o.current;
    if (current == null) return _ineligible();
    final same =
        saved.observationDigest == digestOf(current) &&
        saved.producer.recognitionContract == recognitionContract;
    final keep = request.sharing == null;
    if (keep && _rebound()) return;
    final choice = request.sharing ?? o.choice;
    if (!keep && !precheckSharing(o, choice, _parts)) return;
    if (same && choice == o.choice) {
      _parts.freshness = ContextFreshness.current;
      return _reportSharing();
    }
    await _publish((
      projectId: saved.projectId,
      revision: same ? saved.revision : saved.revision + 1,
      current: same ? null : current,
      choice: choice,
      operation: same
          ? TransactionOperation.sharing
          : TransactionOperation.refresh,
      keepSharing: keep,
    ), ContextOutcome.refreshed);
  }

  /// Una elección local vinculada a otro repositorio no se revincula sola.
  bool _rebound() {
    if (!o.gitUsable || !reboundSettings(o)) return false;
    _parts.diagnostics.add(bindingChanged());
    return true;
  }

  void _ineligible() {
    final limit = reachedReportLimit(o.report);
    _parts.diagnostics.add(
      diagnostic(
        limit ? 'recognition_unverified' : 'not_eligible',
        limit
            ? 'El reconocimiento no cabe en el perfil pedido; no se publica.'
            : 'El reconocimiento actual no es elegible; no se publica nada.',
      ),
    );
  }

  Future<void> _publishSharing(SharingChoice choice) => _publish((
    projectId: o.project.value!.projectId,
    revision: o.project.value!.revision,
    current: null,
    choice: choice,
    operation: TransactionOperation.sharing,
    keepSharing: false,
  ), ContextOutcome.initialized);
}
