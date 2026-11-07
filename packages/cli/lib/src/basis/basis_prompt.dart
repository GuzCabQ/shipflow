import 'package:core/core.dart';

import '../context/context_prompt.dart';
import 'basis_human.dart';
import 'basis_prompt_changes.dart';
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
  final _used = <String>{};

  String key(String prefix) {
    var n = _used.length;
    while (!_used.add('$prefix${++n}')) {}
    return '$prefix$n';
  }

  Future<BasisResponse> run() async {
    io.show(_intro(await s.show()));
    final draft = (await s.files.draft()).value;
    if (draft != null) {
      _used.addAll(draft.input.changes.map((c) => c.key));
      final resumed = await _resume(draft);
      if (resumed != null) return resumed;
    }
    return _collect(draft);
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
        final shown = await s.show(draft: true);
        io.show(renderBasisHuman(shown));
        return _decide(draft.digest, shown);
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
          changes.addAll(await askDecision(io, key));
        case '2':
          changes.addAll(await askSource(io, key));
        case '3':
          changes.addAll(await askPending(io, key));
        case '4':
          final reviewed = await _review(draft);
          if (reviewed != null) return reviewed;
        case _:
          return _quit();
      }
    }
  }

  Future<String> _menu() async {
    while (true) {
      final answer = await ask(
        io,
        '¿Qué quieres hacer?\n'
        '  1) Añadir una decisión\n'
        '  2) Señalar una fuente de referencia\n'
        '  3) Anotar un asunto por aclarar\n'
        '  4) Revisar lo preparado y decidir si se guarda\n'
        '  q) Salir sin guardar lo nuevo',
      );
      if (const {'1', '2', '3', '4', 'q'}.contains(answer)) return answer;
      io.show('No reconozco esa respuesta.\n');
    }
  }

  /// Prepara o revisa el borrador con lo juntado y muestra su resumen;
  /// null si no hay nada que revisar todavía.
  Future<BasisResponse?> _review(BasisDraft? draft) async {
    if (changes.isEmpty && !await _emptyAllowed(draft)) return null;
    final prepared = draft == null
        ? await s.prepare(await _input())
        : await s.revise(_appended(draft), expectedDraftDigest: draft.digest);
    io.show(renderBasisHuman(prepared));
    final digest = prepared.draftDigest;
    if (digest == null || prepared.outcome != BasisOutcome.draftPrepared) {
      return prepared;
    }
    return _decide(digest, prepared);
  }

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

  Future<BasisInput> _input() async {
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
    return BasisInput(
      projectId: (await s.readProject()).projectId!,
      expectedBasisDigest: (await s.files.basis()).value?.digest,
      actor: BasisActor(label: label, role: role, scope: scope),
      reason: reason,
      changes: changes,
    );
  }

  BasisInput _appended(BasisDraft draft) => BasisInput(
    projectId: draft.input.projectId,
    expectedBasisDigest: draft.input.expectedBasisDigest,
    actor: draft.input.actor,
    reason: draft.input.reason,
    changes: [...draft.input.changes, ...changes],
  );

  /// Sólo «aceptar» acepta la huella mostrada; Enter vacío no elige.
  Future<BasisResponse> _decide(String digest, BasisResponse prepared) async {
    while (true) {
      final answer = await ask(
        io,
        'Escribe «aceptar» para guardar exactamente lo revisado, «borrador» '
        'para conservarlo sin aceptar o «descartar» para descartarlo:',
        optional: true,
      );
      switch (answer.toLowerCase()) {
        case 'aceptar':
          return s.accept(digest);
        case 'borrador':
          return prepared;
        case 'descartar':
          return s.discard(digest);
      }
    }
  }

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
