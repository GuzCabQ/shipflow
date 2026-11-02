import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

const _id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

String block(String pattern) =>
    '# shipflow:$_id:begin\n$pattern\n# shipflow:$_id:end\n';

ManagedExcludePatch plan(
  SharingChoice choice,
  String? existing, {
  String prefix = '',
  String? owned,
}) => planExclude(
  prefix: prefix,
  choice: choice,
  existing: existing == null ? null : latin1.encode(existing),
  blockId: _id,
  ownedBlock: owned,
);

String after(ManagedExcludePatch patch) => latin1.decode(patch.after!);

void main() {
  group('local adds one anchored block and keeps foreign bytes', () {
    test('to an absent file', () {
      final patch = plan(SharingChoice.local, null);
      expect(after(patch), block('/shipflow/'));
      expect(patch.changed, isTrue);
      expect(patch.beforeBlock, isNull);
      expect(patch.afterBlock, block('/shipflow/'));
    });

    test('after foreign rules, adding the missing newline as its own', () {
      final patch = plan(SharingChoice.local, '# mío\n*.log');
      expect(after(patch), '# mío\n*.log\n${block('/shipflow/')}');
      expect(patch.afterBlock, '\n${block('/shipflow/')}');
    });

    test('foreign bytes that are not UTF-8 survive untouched', () {
      final foreign = latin1.decode([0xFF, 0xFE, 0x0A]);
      expect(after(plan(SharingChoice.local, foreign)), startsWith(foreign));
    });

    test('an intact block is not repeated', () {
      final existing = 'x\n${block('/shipflow/')}';
      final patch = plan(SharingChoice.local, existing);
      expect(patch.changed, isFalse);
      expect(after(patch), existing);
    });

    test('metacharacters of the prefix are escaped', () {
      final patch = plan(SharingChoice.local, null, prefix: r'a [b]!*#?\ c/');
      expect(after(patch), block(r'/a\ \[b\]\!\*\#\?\\\ c/shipflow/'));
    });

    test('a prefix with a newline cannot be represented', () {
      final patch = plan(SharingChoice.local, null, prefix: 'a\nb/');
      expect(patch.problem, 'path_not_representable');
      expect(patch.after, isNull);
    });
  });

  group('share removes only an intact block of its own', () {
    test('with the separator it added, when that is its own', () {
      final local = plan(SharingChoice.local, '*.log');
      final patch = plan(
        SharingChoice.share,
        after(local),
        owned: local.afterBlock,
      );
      expect(after(patch), '*.log');
      expect(patch.afterBlock, isNull);
    });

    test('without proof of the separator, only the block', () {
      final added = after(plan(SharingChoice.local, '*.log'));
      expect(after(plan(SharingChoice.share, added)), '*.log\n');
    });

    test('a prefix with non-ASCII characters is found in the bytes', () {
      final local = plan(SharingChoice.local, null, prefix: 'ñandú/');
      final again = planExclude(
        prefix: 'ñandú/',
        choice: SharingChoice.local,
        existing: local.after,
        blockId: _id,
      );
      expect(again.changed, isFalse);
      expect(again.afterBlock, block('/ñandú/shipflow/'));
    });

    test('without one, there is nothing to change', () {
      final patch = plan(SharingChoice.share, '*.log\n');
      expect(patch.changed, isFalse);
    });

    test('another root keeps its block', () {
      final other = block('/otra/shipflow/').replaceAll(_id, 'b' * 64);
      final patch = plan(SharingChoice.share, '$other${block('/shipflow/')}');
      expect(after(patch), other);
    });
  });

  group('a damaged or repeated block is never repaired blindly', () {
    for (final (name, existing) in [
      ('a begin without end', '# shipflow:$_id:begin\n/shipflow/\n'),
      ('an altered pattern', block('/otra-cosa/')),
      ('two blocks', '${block('/shipflow/')}${block('/shipflow/')}'),
    ]) {
      for (final choice in [SharingChoice.local, SharingChoice.share]) {
        test('$name, choosing ${choice.toWireName()}', () {
          final patch = plan(choice, existing);
          expect(patch.problem, 'exclude_block_damaged');
          expect(patch.after, isNull);
        });
      }
    }
  });

  test('an exclude file above its limit is refused', () {
    final patch = planExclude(
      prefix: '',
      choice: SharingChoice.local,
      existing: List.filled(1048577, 0x61),
      blockId: _id,
    );
    expect(patch.problem, 'exclude_too_large');
  });
}
