import 'package:core/core.dart';
import 'package:test/test.dart';

import 'basis_atomicity_support.dart';
import 'basis_fixtures.dart';

void main() {
  final active = [versionOf(1, 1, ruleOf()), versionOf(2, 1, ruleOf())];
  final lateCycle = [
    versionOf(3, 1, ruleOf()),
    versionOf(1, 2, replacedBy(2)),
    versionOf(2, 2, replacedBy(1)),
  ];
  final probes = [...active, ...lateCycle];

  group('a rejected cycle leaves the ledger as it was', () {
    test('late cycle preserves state', () {
      final ledger = ledgerOf([active]);
      final before = snapshotOf(ledger, probes, operations);
      expect(
        () => applyBasisEvent(ledger, eventAt([active, lateCycle]), 'events/1'),
        rejects('invalid_reference', 'events/1'),
      );
      expect(snapshotOf(ledger, probes, operations), before);
      expect(ledger.revision, 1);
      expect(ledger.current.keys, [uuid(1), uuid(2)]);
      expect(ledger.currentOf(uuid(3)), isNull);
    });

    test('first rejected event leaves empty ledger', () {
      final ledger = BasisLedger();
      final cycle = [
        versionOf(1, 1, replacedBy(2)),
        versionOf(2, 1, replacedBy(1)),
      ];
      expect(
        () => applyBasisEvent(ledger, eventAt([cycle]), 'events/0'),
        rejects('invalid_reference', 'events/0'),
      );
      expect(ledger.revision, 0);
      expect(ledger.lastEventDigest, isNull);
      expect(ledger.current, isEmpty);
      expect([
        for (final v in cycle) ledger.versionOf(v.id, v.version),
      ], everyElement(isNull));
      expect(operations.map(ledger.hasOperation), everyElement(isFalse));
    });

    test('corrected retry succeeds once', () {
      final ledger = ledgerOf([active]);
      final corrected = [versionOf(3, 1, ruleOf())];
      expect(
        () => applyBasisEvent(ledger, eventAt([active, lateCycle]), 'events/1'),
        rejects('invalid_reference', 'events/1'),
      );
      applyBasisEvent(ledger, eventAt([active, corrected]), 'events/1');
      expect(ledger.revision, 2);
      expect(ledger.lastEventDigest, digestOf(0x301));
      expect(ledger.hasOperation(uuid(0x101)), isTrue);
      expect(ledger.current.keys, [uuid(1), uuid(2), uuid(3)]);
      expect([1, 2, 3].map((id) => ledger.currentOf(uuid(id))!.version), [
        1,
        1,
        1,
      ]);
      expect(ledger.versionOf(uuid(1), 2), isNull);
      final accepted = snapshotOf(ledger, probes, operations);
      expect(
        () => applyBasisEvent(ledger, eventAt([active, corrected]), 'events/1'),
        rejects('history_gap', 'events/1'),
      );
      expect(snapshotOf(ledger, probes, operations), accepted);
    });
  });

  group('replacement chains are checked over the whole candidate', () {
    final aToB = [versionOf(1, 1, replacedBy(2)), versionOf(2, 1, ruleOf())];

    test('cycle through unchanged record is rejected', () {
      final ledger = ledgerOf([aToB]);
      final bToA = versionOf(2, 2, replacedBy(1));
      final before = snapshotOf(ledger, [...aToB, bToA], operations);
      expect(
        () => applyBasisEvent(
          ledger,
          eventAt([
            aToB,
            [bToA],
          ]),
          'events/1',
        ),
        rejects('invalid_reference', 'events/1'),
      );
      expect(snapshotOf(ledger, [...aToB, bToA], operations), before);
    });

    test('replacement can leave the prior chain', () {
      final ledger = ledgerOf([aToB]);
      final leave = [versionOf(2, 2, replacedBy(3)), versionOf(3, 1, ruleOf())];
      applyBasisEvent(ledger, eventAt([aToB, leave]), 'events/1');
      expect(ledger.current.keys, [uuid(1), uuid(2), uuid(3)]);
      expect([1, 2, 3].map((id) => ledger.currentOf(uuid(id))!.version), [
        1,
        2,
        1,
      ]);
      expect(ledger.currentOf(uuid(2))!.toJson(), leave.first.toJson());
      expect(ledger.versionOf(uuid(2), 1)!.toJson(), aToB.last.toJson());
    });
  });

  group('early rejections preserve state', () {
    final early = [
      (
        'a version gap',
        versionOf(1, 3, ruleOf(), previous: 1),
        actorOf(),
        'history_gap',
        'events/1/changes/0',
      ),
      (
        'an actor without the scope of the rule',
        versionOf(1, 2, ruleOf(statement: 'Revisada.')),
        actorOf(paths(['lib/a'])),
        'authority_scope',
        'events/1/changes/0/payload/scope',
      ),
      (
        'a replacement towards an absent ID',
        versionOf(1, 2, replacedBy(9)),
        actorOf(),
        'invalid_reference',
        'events/1/changes/0/payload/replacementRef',
      ),
    ];
    for (final (name, change, actor, code, at) in early) {
      test(name, () {
        final ledger = ledgerOf([active]);
        final seen = [...active, change];
        final before = snapshotOf(ledger, seen, operations);
        final event = eventAt(
          [
            active,
            [change],
          ],
          actors: [actorOf(), actor],
        );
        expect(
          () => applyBasisEvent(ledger, event, 'events/1'),
          rejects(code, at),
        );
        expect(snapshotOf(ledger, seen, operations), before);
      });
    }
  });

  group('references inside an event', () {
    test('batch references preserve order', () {
      final source = versionOf(4, 1, sourceOf());
      final rule = versionOf(
        1,
        1,
        ruleOf(sourceRefs: [BasisReference(ref: uuid(4), version: 1)]),
      );
      for (final (batch, keys) in [
        ([rule, source], [uuid(1), uuid(4)]),
        ([source, rule], [uuid(4), uuid(1)]),
      ]) {
        final ledger = BasisLedger();
        applyBasisEvent(ledger, eventAt([batch]), 'events/0');
        expect(ledger.current.keys, keys);
        expect(ledger.currentOf(uuid(1))!.toJson(), rule.toJson());
        expect(ledger.versionOf(uuid(4), 1)!.toJson(), source.toJson());
      }
    });

    test('resolution uses previously accepted version', () {
      final rule = versionOf(1, 1, ruleOf());
      final resolved = versionOf(
        5,
        1,
        pendingOf(
          status: BasisPendingStatus.resolved,
          resolution: 'rule:${uuid(1)}@1',
        ),
      );
      final ledger = BasisLedger();
      expect(
        () => applyBasisEvent(
          ledger,
          eventAt([
            [resolved, rule],
          ]),
          'events/0',
        ),
        rejects('invalid_reference', 'events/0/changes/0/payload/resolution'),
      );
      expect((ledger.revision, ledger.current.length), (0, 0));
      expect(ledger.hasOperation(uuid(0x100)), isFalse);
      applyBasisEvent(
        ledger,
        eventAt([
          [rule],
        ]),
        'events/0',
      );
      applyBasisEvent(
        ledger,
        eventAt([
          [rule],
          [resolved],
        ]),
        'events/1',
      );
      expect(ledger.current.keys, [uuid(1), uuid(5)]);
      expect(ledger.currentOf(uuid(5))!.toJson(), resolved.toJson());
    });
  });
}
