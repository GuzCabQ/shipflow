@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:cli/src/basis/basis_codec.dart';
import 'package:cli/src/basis/basis_human.dart';
import 'package:cli/src/basis/basis_presenter.dart';
import 'package:cli/src/basis/basis_prompt.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_prompt_support.dart';
import 'support/basis_service_support.dart';

void main() {
  late BasisBox box;
  setUp(() async => box = await BasisBox.initialized());
  tearDown(() => box.dispose());

  /// Una base con dos reglas y un pendiente, y un borrador que retira una,
  /// reemplaza la otra por una nueva y resuelve el pendiente.
  Future<List<String>> seeded() async {
    await box.publish(
      box.input([
        create('a', ruleOf(statement: 'Se retira.')),
        create('b', ruleOf(statement: 'Se reemplaza.')),
        create('p', pendingOf()),
      ]),
    );
    return [for (final v in replayBasis(box.document).values) v.id];
  }

  Future<(BasisResponse, List<String>)> retireReplaceResolve() async {
    final ids = await seeded();
    final prepared = await box.prepare(
      box.input([
        _revise(
          'retiro',
          ids[0],
          ruleOf(lifecycle: BasisRuleLifecycle.retired),
        ),
        create('nueva', ruleOf(statement: 'La sustituta.')),
        _revise(
          'reemplazo',
          ids[1],
          ruleOf(
            lifecycle: BasisRuleLifecycle.replaced,
            replacementRef: 'new:nueva',
          ),
        ),
        _revise(
          'resuelto',
          ids[2],
          pendingOf(
            status: BasisPendingStatus.resolved,
            resolution: 'disposition:Se confirmó.',
          ),
        ),
      ]),
    );
    return (prepared, ids);
  }

  List<(BasisChangeKind, String, int)> effects(BasisResponse r) => [
    for (final c in r.proposedChanges)
      (c.change, c.version.id, c.version.version),
  ];

  test(
    'retirements, replacements and resolutions show before accepting',
    () async {
      final (prepared, ids) = await retireReplaceResolve();
      final shown = await box.show(draft: true);
      for (final r in [prepared, shown]) {
        final found = effects(r);
        expect(found, contains((BasisChangeKind.retire, ids[0], 2)));
        expect(found, contains((BasisChangeKind.replace, ids[1], 2)));
        expect(found, contains((BasisChangeKind.resolve, ids[2], 2)));
        expect(
          found.where((e) => e.$1 == BasisChangeKind.create),
          hasLength(1),
        );
        final text = renderBasisHuman(r);
        expect(text, contains('Cambios de este borrador'));
        expect(text, contains('Retira «Contratos»'));
        expect(text, contains('Reemplaza «Contratos»'));
        expect(text, contains('Resuelve «Revisión»'));
        expect(text, contains(ids[0]));
      }
    },
  );

  test(
    'they are the exact prepared versions and the basis is untouched',
    () async {
      final (prepared, _) = await retireReplaceResolve();
      final draft = decodeBasisDraft(
        box.draft.readAsBytesSync(),
        limits: box.limits,
      );
      expect(
        jsonEncode([
          for (final c in prepared.proposedChanges) c.version.toJson(),
        ]),
        jsonEncode([for (final v in draft.preparedChanges) v.toJson()]),
      );
      expect(prepared.draftDigest, draft.digest);
      expect(box.document.revision, 1);
      final shown = await box.show(draft: true);
      expect(
        jsonEncode(shown.proposedChanges.map((c) => c.toJson()).toList()),
        jsonEncode(prepared.proposedChanges.map((c) => c.toJson()).toList()),
      );
    },
  );

  test('history keeps only accepted events', () async {
    final (prepared, _) = await retireReplaceResolve();
    expect(prepared.history, isEmpty);
    final accepted = await box.accept(prepared.draftDigest!);
    expect(accepted.proposedChanges, isEmpty);
    final history = await box.show(history: true);
    expect(history.proposedChanges, isEmpty);
    expect(history.history, hasLength(2));
  });

  test('the guide shows them when resuming the draft', () async {
    await retireReplaceResolve();
    final io = ScriptedIO(['1', 'borrador']);
    await box.using((s) => guideBasis(s, io));
    expect(io.shown.toString(), contains('Retira «Contratos»'));
    expect(io.shown.toString(), contains('Resuelve «Revisión»'));
  });

  test('changes that do not fit the budget are reported, not hidden', () async {
    final (prepared, _) = await retireReplaceResolve();
    final full = presentBasis(prepared, json: true, limits: box.limits);
    final tight = BasisLimits.fromJson({
      ...box.limits.toJson(),
      'maxResponseBytes': full.payload.length - 1,
    });
    final cut = decodeBasisResponse(
      utf8.encode(presentBasis(prepared, json: true, limits: tight).payload),
      limits: box.limits,
    );
    expect(cut.proposedChanges, isEmpty);
    expect(cut.selection.complete, isFalse);
    final budget = cut.diagnostics.singleWhere(
      (d) => d.code == 'budget_exceeded',
    );
    expect(budget.message, contains('4 cambios propuestos'));
    final actions = [for (final a in cut.nextActions) a.arguments.join(' ')];
    expect(actions, contains('--show --draft --report-budget=extended'));
    expect(actions.where((a) => a.startsWith('--accept')), isEmpty);
  });
}

/// La versión 2 de [id] con una clave propia en la propuesta.
BasisChange _revise(String key, String id, BasisPayload payload) =>
    BasisChange(key: key, targetId: id, expectedVersion: 1, payload: payload);
