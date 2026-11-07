@Timeout(Duration(minutes: 3))
library;

import 'package:cli/src/basis/basis_prompt.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_prompt_support.dart';
import 'support/basis_service_support.dart';

const _actor = ['Ana', 'mantenimiento', 'proyecto', 'Ajustes.'];

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  Future<(BasisResponse, ScriptedIO)> guide(List<String> answers) async {
    final io = ScriptedIO(answers);
    final response = await box.using((s) => guideBasis(s, io));
    return (response, io);
  }

  BasisRecordVersion record(String id) =>
      replayBasis(box.document).values.singleWhere((v) => v.id == id);

  test('later_runs_revise_retire_and_resolve', () async {
    await box.publish(
      box.input([
        create('a', ruleOf(statement: 'Primera.')),
        create('b', ruleOf(statement: 'Segunda.')),
        create('p', pendingOf()),
      ]),
    );
    final ids = [for (final v in replayBasis(box.document).values) v.id];
    final (result, io) = await guide([
      '5', '1', 'Primera, revisada.', '', 'n', 'n', // revisar
      '6', '2', 's', // retirar
      '7', '1', 'Se confirmó con los consumidores.', // resolver
      '4', ..._actor, 'aceptar',
    ]);
    expect(result.published, isTrue, reason: io.shown.toString());
    final revised = record(ids[0]);
    expect(revised.version, 2);
    expect((revised.payload as BasisRule).statement, 'Primera, revisada.');
    expect((revised.payload as BasisRule).reason, 'Compatibilidad.');
    final retired = record(ids[1]).payload as BasisRule;
    expect(retired.lifecycle, BasisRuleLifecycle.retired);
    final resolved = record(ids[2]).payload as BasisPending;
    expect(resolved.status, BasisPendingStatus.resolved);
    expect(
      resolved.resolution,
      'disposition:Se confirmó con los consumidores.',
    );
  });

  test('a revised decision can get its own review', () async {
    await box.publish(box.input([create('a', ruleOf())]));
    final rule = currentOf(box, 'rule');
    final (result, io) = await guide([
      '5', '1', '', '', 's', 'lib', // revisar con otro ámbito
      's', '¿Aplica a lib/x?', 'Sin confirmar.', 'Pronto.', '',
      '4', ..._actor, 'aceptar',
    ]);
    expect(result.published, isTrue, reason: io.shown.toString());
    final review = currentOf(box, 'pending').payload as BasisPending;
    expect(review.decisionReview!.ref, rule.id);
    expect(review.decisionReview!.version, 2);
    expect(review.scope.paths, ['lib']);
  });

  test('without context the guide asks nothing', () async {
    box.box.file('shipflow/project.json', '{"roto": true}\n');
    final (result, io) = await guide(['1']);
    expect(result.exitCode, 65);
    expect(result.diagnostics.map((d) => d.code), contains('context_required'));
    expect(io.shown.toString(), isNot(contains('¿Qué quieres hacer?')));
  });

  test('a change that cannot be prepared is removed, the rest kept', () async {
    final (result, io) = await guide([
      '1', 'Local', 'Sólo en lib.', 'Orden.', 'lib', 'n', 'n',
      '3', 'Global', '¿Algo global?', 'Falta.', 'Pronto.', 'proyecto',
      '4', 'Ana', 'mantenimiento', 'lib', 'Ajustes.',
      's', // quitar lo último añadido
      '4', 'aceptar',
    ]);
    expect(result.published, isTrue, reason: io.shown.toString());
    expect(io.shown.toString(), contains('authority_scope'));
    final kinds = replayBasis(box.document).values.map((v) => v.payload.kind);
    expect(kinds, ['rule']);
  });
}
