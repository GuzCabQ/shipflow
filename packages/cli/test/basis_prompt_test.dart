@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_cli.dart';
import 'package:cli/src/basis/basis_prompt.dart';
import 'package:cli/src/cli_command.dart';
import 'package:cli/src/context/context_prompt.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_prompt_support.dart';
import 'support/basis_service_support.dart';

const _actor = ['Ana', 'mantenimiento', 'proyecto', 'Primera base.'];

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  Future<(BasisResponse, ScriptedIO)> guide(List<String> answers) async {
    final io = ScriptedIO(answers);
    final response = await box.using((s) => guideBasis(s, io));
    return (response, io);
  }

  test('first_run_can_save_explicit_pending', () async {
    final (result, io) = await guide([
      '3',
      'Consumidores',
      '¿Qué consumidores externos hay?',
      'Sin registro.',
      'Antes de cambiar contratos.',
      '?',
      '4',
      ..._actor,
      'aceptar',
    ]);
    expect(result.outcome, BasisOutcome.published, reason: io.shown.toString());
    final pending = currentOf(box, 'pending').payload as BasisPending;
    expect(pending.scope.kind, BasisScopeKind.unknown);
    expect(io.shown.toString(), contains('Este aspecto sigue pendiente'));
  });

  test('global_scope_requires_choice', () async {
    final (result, io) = await guide([
      '1',
      'Contratos',
      'Revisar contratos públicos.',
      'Compatibilidad.',
      '',
      'proyecto',
      'n',
      'n',
      '4',
      ..._actor,
      'aceptar',
    ]);
    expect(result.published, isTrue, reason: io.shown.toString());
    expect(io.shown.toString(), contains('elige el alcance'));
    expect(currentOf(box, 'rule').payload.scope.kind, BasisScopeKind.project);
  });

  test('a decision with review keeps the reviewer unknown', () async {
    final (result, io) = await guide([
      '1',
      'Contratos',
      'Revisar contratos públicos.',
      'Compatibilidad.',
      'proyecto',
      'n',
      's',
      '¿Siguen valiendo?',
      'Falta otro consumidor.',
      'Al integrar el segundo consumidor.',
      '',
      '4',
      ..._actor,
      'aceptar',
    ]);
    expect(result.published, isTrue, reason: io.shown.toString());
    final pending = currentOf(box, 'pending').payload as BasisPending;
    expect(pending.decisionReview!.reviewer, isNull);
    expect(pending.decisionReview!.ref, currentOf(box, 'rule').id);
    expect(io.shown.toString(), contains('Responsable por definir'));
  });

  test('existing_decision_not_asked_again', () async {
    await box.publish(box.input([create('rule', ruleOf())]));
    final (result, io) = await guide(['q']);
    final text = io.shown.toString();
    expect(text, contains('1 decisión vigente'));
    expect(text, isNot(contains('¿Qué se debe respetar?')));
    expect(result.published, isFalse);
  });

  group('blank_or_eof_never_accepts', () {
    test('blank answers never accept and EOF cancels', () async {
      final (result, _) = await guide([
        '3',
        'Consumidores',
        '¿Qué falta?',
        'Sin datos.',
        'Pronto.',
        '?',
        '4',
        ..._actor,
        '',
        '',
      ]);
      expect(result.exitCode, 130);
      expect(result.outcome, BasisOutcome.cancelled);
      expect(box.basis.existsSync(), isFalse);
      expect(box.draft.existsSync(), isTrue);
    });

    test('EOF before reviewing writes nothing', () async {
      final before = box.snapshot();
      final (result, _) = await guide(['1', 'Contratos']);
      expect(result.exitCode, 130);
      expect(box.snapshot(), before);
    });
  });

  test('resume_changed_draft_shows_new_summary', () async {
    final first = await box.prepare(box.input([create('a', ruleOf())]));
    final (result, io) = await guide([
      '2',
      '3',
      'Consumidores',
      '¿Qué falta?',
      'Sin datos.',
      'Pronto.',
      '?',
      '4',
      'aceptar',
    ]);
    expect(result.published, isTrue, reason: io.shown.toString());
    expect(result.draftDigest, isNot(first.draftDigest));
    expect(io.shown.toString(), contains(result.draftDigest!));
    expect(box.document.events.single.changes, hasLength(2));
  });

  test('json_and_human_have_same_effects', () async {
    final other = await BasisBox.initialized();
    addTearDown(other.dispose);
    final effects = <(int, String)>[];
    for (final (target, json) in [(box, true), (other, false)]) {
      final file = File(target.path('propuesta.json'))
        ..writeAsStringSync(
          jsonEncode(target.input([create('rule', ruleOf())]).toJson()),
        );
      final response = await runBootstrapCommand(
        RunBootstrap(
          json: json,
          operation: BasisOperation.prepare,
          input: file.path,
        ),
        version: '0.0.0-prueba',
        workingDirectory: target.box.root,
      );
      effects.add((
        response.exitCode,
        [
          for (final e in target.box.root.listSync(recursive: true))
            if (e is File && e.path.contains('basis')) e.path.split('/').last,
        ].join(','),
      ));
    }
    expect(effects[0], effects[1]);
    expect(effects[0].$2, 'basis-draft.json');
  });

  test('without a terminal or with --json the guide never asks', () async {
    final before = box.snapshot();
    final response = await runBootstrapCommand(
      const RunBootstrap(json: false, operation: BasisOperation.guide),
      version: '0.0.0-prueba',
      workingDirectory: box.box.root,
      prompt: _NoTerminal(),
    );
    expect(response.exitCode, 65);
    expect(response.payload, contains('Falta elegir una operación explícita'));
    expect(box.snapshot(), before);
  });
}

final class _NoTerminal implements ContextPromptIO {
  @override
  bool get interactive => false;

  @override
  Future<String?> readLine() => throw StateError('no se pregunta');

  @override
  void show(String text) => throw StateError('no se pregunta');
}
