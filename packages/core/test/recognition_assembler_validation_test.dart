import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'assembler_support.dart';

void main() {
  group('invalid evidence reference is rejected', () {
    for (final (name, contribution) in [
      (
        'candidato',
        contribution(
          candidates: [
            candidate('stack', ['e0009']),
          ],
        ),
      ),
      (
        'unidad',
        contribution(
          units: [
            unit('u', 'p', ['e0009']),
          ],
        ),
      ),
      (
        'conflicto',
        contribution(
          conflicts: [
            RecognitionConflict(
              code: 'c',
              message: 'm',
              evidenceIds: const ['e0009'],
            ),
          ],
        ),
      ),
    ]) {
      test(name, () {
        expect(() => assemble([contribution]), throwsArgumentError);
      });
    }

    test('IDs repetidos', () {
      expect(
        () => assemble([
          contribution(evidence: [evidence('e0001'), evidence('e0001')]),
        ]),
        throwsArgumentError,
      );
      expect(
        () => assemble([
          contribution(
            evidence: [evidence('e0001')],
            units: [
              unit('u', 'a', ['e0001']),
              unit('u', 'b', ['e0001']),
            ],
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => assemble([recognizable(), recognizable()]),
        throwsArgumentError,
      );
    });
  });

  test('orders all collections deterministically', () {
    final forward = assemble([_shuffled(false)]);
    final backward = assemble([_shuffled(true)]);
    expect(jsonEncode(forward), jsonEncode(backward));
    expect(forward.candidates.map((c) => c.id), ['a', 'b']);
    expect(forward.candidates.last.evidenceIds, ['e0001', 'e0002']);
    expect(forward.units.map((u) => u.path), ['a', 'z']);
    expect(forward.evidence.map((e) => e.id), ['e0001', 'e0002']);
    expect(forward.conflicts.map((c) => '${c.code}${c.message}'), [
      'am',
      'an',
      'bm',
    ]);
    expect(forward.limitations.map((l) => '${l.code}${l.path}'), [
      'anull',
      'ay',
      'bx',
    ]);
  });
}

/// La misma contribución en un orden o en el inverso.
RecognitionContribution _shuffled(bool reversed) {
  List<T> order<T>(List<T> items) => reversed ? items.reversed.toList() : items;
  return contribution(
    candidates: order([
      candidate('b', ['e0002', 'e0001']),
      candidate('a', ['e0001']),
    ]),
    units: order([
      unit('u2', 'z', ['e0002']),
      unit('u1', 'a', ['e0001']),
    ]),
    evidence: order([evidence('e0002'), evidence('e0001')]),
    conflicts: order(_unorderedConflicts()),
    limitations: order(_unorderedLimitations),
  );
}

List<RecognitionConflict> _unorderedConflicts() => [
  RecognitionConflict(code: 'b', message: 'm', evidenceIds: ['e0002']),
  RecognitionConflict(code: 'a', message: 'n', evidenceIds: ['e0001']),
  RecognitionConflict(code: 'a', message: 'm', evidenceIds: ['e0001']),
];

const _unorderedLimitations = [
  RecognitionLimitation(code: 'b', message: 'm', path: 'x', blocking: false),
  RecognitionLimitation(code: 'a', message: 'm', path: 'y', blocking: false),
  RecognitionLimitation(code: 'a', message: 'm', path: null, blocking: true),
];
