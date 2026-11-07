import 'package:core/core.dart';

import '../context/context_prompt.dart';
import 'basis_flow.dart';
import 'basis_human.dart';
import 'basis_presenter.dart';
import 'basis_prompt_changes.dart';
import 'basis_prompt_existing.dart';
import 'basis_prompt_questions.dart';
import 'basis_reply.dart';
import 'basis_service.dart';

/// La guía interactiva de la base: explica para qué sirve, junta
/// decisiones, fuentes o pendientes en lenguaje corriente, prepara un
/// borrador con el mismo servicio que `--input`, muestra el resumen y sólo
/// acepta si se escribe «aceptar». Enter vacío no acepta; el cierre de la
/// entrada cancela y conserva el último borrador guardado. Nunca toma un
/// lock mientras espera respuestas.
Future<BasisResponse> guideBasis(
  BasisService service,
  ContextPromptIO io,
) async {
  try {
    return await _Guide(service, io).run();
  } on GuideCancelled {
    return (BasisReply(BasisOperation.guide)
          ..outcome = BasisOutcome.cancelled
          ..add('cancelled'))
        .build();
  }
}

final class _Guide {
  _Guide(this.s, this.io);

  final BasisService s;
  final ContextPromptIO io;
  final changes = <BasisChange>[];
  final _groups = <int>[];
  final _used = <String>{};
  late final String _projectId;
  var _rules = <BasisRecordVersion>[];
  var _open = <BasisRecordVersion>[];
  (BasisActor, String)? _declared;

  String key(String prefix) {
    var n = _used.length;
    while (!_used.add('$prefix${++n}')) {}
    return '$prefix$n';
  }

  Future<BasisResponse> run() async {
    final blocked = await _context();
    if (blocked != null) return blocked;
    final shown = await s.show();
    io.show(_intro(shown));
    _rules = [
      for (final v in shown.selected)
        if (v.payload case BasisRule(lifecycle: BasisRuleLifecycle.active)) v,
    ];
    _open = [
      for (final v in shown.pending)
        if (v.payload is BasisPending) v,
    ];
    final draft = (await s.files.draft()).value;
    if (draft != null) {
      _used.addAll(draft.input.changes.map((c) => c.key));
      final resumed = await _resume(draft);
      if (resumed != null) return resumed;
    }
    return _collect(draft);
  }

  /// Sin contexto inicial no se pregunta nada: se remite a `init`.
  Future<BasisResponse?> _context() async {
    final env = await s.readProject();
    final r = BasisReply(BasisOperation.guide);
    if (!contextReady(env, r)) {
      return (r..outcome = BasisOutcome.blocked).build();
    }
    _projectId = env.projectId!;
    return null;
  }

  /// Un borrador guardado se ofrece retomar antes de empezar otro.
  Future<BasisResponse?> _resume(BasisDraft draft) async {
    final option = await choose(
      io,
      'Hay un borrador guardado sin aceptar (huella ${draft.digest}).',
      const [
        ('Revisarlo y decidir si se guarda', 1),
        ('Añadirle cambios', 2),
        ('Descartarlo', 3),
        ('Salir sin cambiar nada', 4),
      ],
    );
    switch (option) {
      case 1:
        return _decide(draft.digest, _fitted(await s.show(draft: true)));
      case 3:
        return s.discard(draft.digest);
      case 4:
        return _quit();
    }
    return null;
  }

  Future<BasisResponse> _collect(BasisDraft? draft) async {
    while (true) {
      switch (await _menu()) {
        case '1':
          _add(await askDecision(io, key));
        case '2':
          _add(await askSource(io, key));
        case '3':
          _add(await askPending(io, key));
        case '5':
          _add(await askRevision(io, key, _rules));
        case '6':
          _add(await askRetirement(io, key, _rules));
        case '7':
          _add(await askResolution(io, key, _open));
        case '4':
          final reviewed = await _review(draft);
          if (reviewed != null) return reviewed;
        case _:
          return _quit();
      }
    }
  }

  void _add(List<BasisChange> group) {
    if (group.isEmpty) return;
    changes.addAll(group);
    _groups.add(group.length);
  }

  Future<String> _menu() async {
    final valid = {
      '1',
      '2',
      '3',
      '4',
      'q',
      if (_rules.isNotEmpty) ...['5', '6'],
      if (_open.isNotEmpty) '7',
    };
    while (true) {
      final answer = await ask(
        io,
        '¿Qué quieres hacer?\n'
        '  1) Añadir una decisión\n'
        '  2) Señalar una fuente de referencia\n'
        '  3) Anotar un asunto por aclarar\n'
        '  4) Revisar lo preparado y decidir si se guarda\n'
        '${_rules.isEmpty ? '' : '  5) Revisar una decisión vigente\n'
                  '  6) Retirar una decisión vigente\n'}'
        '${_open.isEmpty ? '' : '  7) Resolver un asunto pendiente\n'}'
        '  q) Salir sin guardar lo nuevo',
      );
      if (valid.contains(answer)) return answer;
      io.show('No reconozco esa respuesta.\n');
    }
  }

  /// Prepara o revisa el borrador con lo juntado y muestra su resumen;
  /// null para volver al menú: no había nada que revisar, o se quitó lo
  /// último añadido porque no se pudo preparar.
  Future<BasisResponse?> _review(BasisDraft? draft) async {
    if (changes.isEmpty && !await _emptyAllowed(draft)) return null;
    final prepared = draft == null
        ? await s.prepare(await _input())
        : await s.revise(_appended(draft), expectedDraftDigest: draft.digest);
    final fitted = _fitted(prepared);
    final digest = prepared.draftDigest;
    if (digest != null && prepared.outcome == BasisOutcome.draftPrepared) {
      return _decide(digest, fitted);
    }
    if (_groups.isEmpty || !await yesNo(io, _retry)) return prepared;
    changes.removeRange(changes.length - _groups.removeLast(), changes.length);
    return null;
  }

  static const _retry =
      'No se pudo preparar. ¿Quitar lo último añadido, conservar lo demás y '
      'volver al menú?';

  /// Sin cambios sólo se guarda una base vacía por elección expresa.
  Future<bool> _emptyAllowed(BasisDraft? draft) async {
    if (draft != null || (await s.files.basis()).value != null) {
      io.show('No hay cambios preparados todavía.\n');
      return false;
    }
    return yesNo(
      io,
      '¿Guardar una base vacía? Quedará con cobertura normativa no '
      'establecida, que no significa que no haya reglas.',
    );
  }

  /// Quién acepta y por qué se pregunta una sola vez por guía.
  Future<BasisInput> _input() async {
    final (actor, reason) = _declared ??= await _declare();
    return BasisInput(
      projectId: _projectId,
      expectedBasisDigest: (await s.files.basis()).value?.digest,
      actor: actor,
      reason: reason,
      changes: changes,
    );
  }

  Future<(BasisActor, String)> _declare() async {
    final label = await ask(
      io,
      '¿Quién acepta? (un nombre o rol que te identifique)',
    );
    final role = await ask(io, '¿Con qué responsabilidad lo aceptas?');
    final scope = await askScope(
      io,
      '¿Sobre qué ámbito decides?',
      unknownAllowed: false,
    );
    final reason = await ask(io, 'Motivo de estos cambios:');
    return (BasisActor(label: label, role: role, scope: scope), reason);
  }

  BasisInput _appended(BasisDraft draft) => BasisInput(
    projectId: draft.input.projectId,
    expectedBasisDigest: draft.input.expectedBasisDigest,
    actor: draft.input.actor,
    reason: draft.input.reason,
    changes: [...draft.input.changes, ...changes],
  );

  /// [response] acotada por el presupuesto del perfil, como la daría el
  /// comando, y mostrada así: lo que no cabe no se presenta como revisado.
  BasisResponse _fitted(BasisResponse response) {
    final fitted = fitBasisResponse(response, s.limits.maxResponseBytes);
    io.show(renderBasisHuman(fitted));
    return fitted;
  }

  /// Sólo «aceptar» acepta la huella mostrada, y sólo si la respuesta
  /// mostrada ofrece aceptarla: unos cambios que no se pudieron mostrar no
  /// se aceptan. Enter vacío no elige.
  Future<BasisResponse> _decide(String digest, BasisResponse prepared) async {
    final acceptable = prepared.nextActions.any(
      (a) => a.arguments.first == '--accept',
    );
    while (true) {
      final answer = await ask(
        io,
        acceptable ? _choices : _withoutAccepting,
        optional: true,
      );
      switch (answer.toLowerCase()) {
        case 'aceptar' when acceptable:
          return s.accept(digest);
        case 'borrador':
          return prepared;
        case 'descartar':
          return s.discard(digest);
      }
    }
  }

  static const _choices =
      'Escribe «aceptar» para guardar exactamente lo revisado, «borrador» '
      'para conservarlo sin aceptar o «descartar» para descartarlo:';
  static const _withoutAccepting =
      'Este borrador no se puede aceptar desde aquí sin haberlo revisado '
      'completo. Escribe «borrador» para conservarlo sin aceptar o '
      '«descartar» para descartarlo:';

  BasisResponse _quit() => (BasisReply(
    BasisOperation.guide,
  )..outcome = BasisOutcome.noChanges).build();
}

String _intro(BasisResponse shown) {
  final rules = shown.selected.where((v) => v.payload is BasisRule).length;
  final pending = shown.pending.length;
  final existing = shown.basisDigest == null
      ? 'Todavía no hay una base aceptada: puedes empezar con una decisión, '
            'una fuente o un asunto por aclarar.'
      : 'La base tiene ${_count(rules, 'decisión vigente', 'decisiones vigentes')} '
            'y ${_count(pending, 'asunto pendiente', 'asuntos pendientes')}: no '
            'se vuelven a preguntar. Consúltala con «shipflow bootstrap --show».';
  return 'Base guiada del proyecto: guarda las decisiones que una persona '
      'acepta, sus fuentes y lo que falta aclarar. No interpreta el código ni '
      'certifica que se cumpla.\n$existing\n\n';
}

String _count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';
