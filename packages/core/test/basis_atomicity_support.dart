import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'basis_fixtures.dart';

/// Las operaciones de los tres primeros eventos de `documentOf`.
final operations = [uuid(0x100), uuid(0x101), uuid(0x102)];

BasisRule replacedBy(int id) =>
    ruleOf(lifecycle: BasisRuleLifecycle.replaced, replacementRef: uuid(id));

BasisLedger ledgerOf(List<List<BasisRecordVersion>> batches) =>
    replayBasisLedger(documentOf(batches));

/// El último evento de la historia de [batches], encadenado a los
/// anteriores igual que en `documentOf`.
BasisEvent eventAt(
  List<List<BasisRecordVersion>> batches, {
  List<BasisActor>? actors,
}) => documentOf(batches, actors: actors).events.last;

Matcher rejects(String code, String at) => throwsA(
  isA<ContextFormatException>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.at, 'at', at),
);

/// Todo lo que la API pública de [ledger] deja ver, como copia
/// serializada: los contadores van primero para que una diferencia en
/// ellos sea la primera que se informe.
Map<String, Object?> snapshotOf(
  BasisLedger ledger,
  Iterable<BasisRecordVersion> probes,
  Iterable<String> operations,
) =>
    jsonDecode(
          jsonEncode({
            'revision': ledger.revision,
            'lastEventDigest': ledger.lastEventDigest,
            'operations': {
              for (final o in operations) o: ledger.hasOperation(o),
            },
            'currentKeys': ledger.current.keys.toList(),
            'current': {
              for (final MapEntry(:key, :value) in ledger.current.entries)
                key: value.toJson(),
            },
            'currentOf': {
              for (final p in probes) p.id: ledger.currentOf(p.id)?.toJson(),
            },
            'versionOf': {
              for (final p in probes)
                '${p.id}@${p.version}': ledger
                    .versionOf(p.id, p.version)
                    ?.toJson(),
            },
          }),
        )
        as Map<String, Object?>;
