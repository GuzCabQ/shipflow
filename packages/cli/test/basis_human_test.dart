@Timeout(Duration(minutes: 3))
library;

import 'package:cli/src/basis/basis_human.dart';
import 'package:cli/src/basis/basis_presenter.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_service_support.dart';

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  BasisDecisionReview unowned(String ref) =>
      BasisDecisionReview(ref: ref, version: 1, reviewer: null);

  List<BasisChange> ruleAndReview() => [
    create('compat', ruleOf()),
    create('debt', pendingOf(review: unowned('new:compat'))),
  ];

  test('accepted_decision_with_pending_review_is_explained', () async {
    final accepted = await box.publish(box.input(ruleAndReview()));
    expect(accepted.published, isTrue);
    final text = renderBasisHuman(await box.show());
    expect(text, contains('Decisión aceptada por el usuario'));
    expect(text, contains('versión 1'));
    expect(text, contains('Este aspecto sigue pendiente'));
    expect(text, contains('Falta confirmar consumidores.'));
    expect(text, contains('Al integrar el segundo consumidor.'));
    expect(text, contains('Responsable por definir'));
  });

  test('unchanged_source_does_not_claim_semantic_validity', () async {
    box.box.file('docs/politica.md', 'Revisar contratos.\n');
    await box.publish(box.input(ruleWithSource('docs/politica.md')));
    final text = renderBasisHuman(await box.show());
    expect(text, contains('La fuente no cambió desde su registro'));
    expect(text, contains('No se comprobó automáticamente'));
    expect(text, isNot(contains('correcta')));
    expect(text, isNot(contains('válida')));
  });

  test('historical_target_is_not_current_rule', () async {
    await box.publish(box.input(ruleAndReview()));
    final rule = currentOf(box, 'rule');
    await box.publish(
      box.input([revise(rule.id, 1, ruleOf(statement: 'Versión dos.'))]),
    );
    final shown = await box.show();
    expect(shown.reviewTargets.single.version, 1);
    expect(shown.selected.single.version, 2);
    final text = renderBasisHuman(shown);
    expect(text, contains('Decisión a la que corresponde esta revisión'));
    expect(text, contains('Soportes de la decisión histórica no revalidados'));
    final current = text.indexOf('Reglas vigentes');
    final target = text.indexOf('Decisión a la que corresponde');
    expect(current, isNot(-1));
    expect(target, greaterThan(current));
  });

  test('review_targets_count_toward_response_budget', () async {
    await box.publish(box.input(ruleAndReview()));
    final shown = await box.show();
    final full = presentBasis(shown, json: true, limits: box.limits);
    expect(full.exitCode, 0);
    final tight = BasisLimits.fromJson({
      ...box.limits.toJson(),
      'maxResponseBytes': full.payload.length - 1,
    });
    final cut = presentBasis(shown, json: true, limits: tight);
    expect(cut.exitCode, 65);
    expect(cut.payload, contains('"complete":false'));
    expect(cut.payload, contains('budget_exceeded'));
    expect(cut.payload, isNot(contains('"reviewTargets":[{')));
    expect(cut.payload.length, lessThanOrEqualTo(full.payload.length - 1));
    final human = presentBasis(shown, json: false, limits: tight);
    expect(human.exitCode, 65);
  });

  group('show_does_not_claim_rules_absent_or_compliance', () {
    test('an empty basis is not established, never «no rules»', () async {
      await box.publish(box.input([]));
      final shown = await box.show();
      final text = renderBasisHuman(shown);
      expect(shown.normativeCoverage, BasisCoverage.notEstablished);
      expect(text, contains('no significa que el proyecto no tenga reglas'));
      expect(text, isNot(contains('sin reglas')));
    });

    test('integrity is reported apart from the exit code', () async {
      box.basis.parent.createSync(recursive: true);
      box.basis.writeAsStringSync('{"roto": true}\n');
      final shown = await box.show();
      expect(shown.exitCode, 65);
      expect(shown.storageIntegrity.basis, BasisIntegrity.invalid);
      expect(shown.selected, isEmpty);
      expect(renderBasisHuman(shown), contains('no cumple su formato'));
    });

    test('actions carry the exact digest of the draft shown', () async {
      final prepared = await box.prepare(box.input([create('rule', ruleOf())]));
      final shown = await box.show(draft: true);
      final text = renderBasisHuman(shown);
      expect(
        text,
        contains('shipflow bootstrap --accept ${prepared.draftDigest}'),
      );
      expect(text, contains('todavía no está aceptado'));
    });

    test('history names each change and the version a review cites', () async {
      await box.publish(box.input(ruleAndReview()));
      final text = renderBasisHuman(await box.show(history: true));
      expect(text, contains('«Contratos» regla · versión 1'));
      expect(text, contains('«Revisión» pendiente · versión 1 · revisa'));
      expect(text, contains('versión 1 de «Contratos»'));
    });

    test('a draft never calls its decisions accepted', () async {
      final prepared = await box.prepare(box.input(ruleAndReview()));
      final shown = await box.show(draft: true);
      for (final text in [
        renderBasisHuman(prepared),
        renderBasisHuman(shown),
      ]) {
        expect(text, isNot(contains('Decisión aceptada')));
        expect(text, contains('no cuenta como aceptado hasta aceptar'));
      }
    });

    test('a stale support stays visible with its rule', () async {
      box.box.file('docs/politica.md', 'v1\n');
      await box.publish(box.input(ruleWithSource('docs/politica.md')));
      box.box.file('docs/politica.md', 'v2\n');
      final text = renderBasisHuman(await box.show());
      expect(text, contains('La fuente cambió desde su registro'));
      expect(text, contains('Los contratos públicos se revisan.'));
    });

    test('record text cannot control the terminal', () async {
      await box.publish(
        box.input([
          create('rule', ruleOf(statement: 'Antes\u001b[2JDespués\u0007')),
        ]),
      );
      final text = renderBasisHuman(await box.show());
      expect(text, isNot(contains('\u001b')));
      expect(text, isNot(contains('\u0007')));
    });
  });
}
