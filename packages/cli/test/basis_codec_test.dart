import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_canonical.dart';
import 'package:cli/src/basis/basis_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/basis_support.dart';

final _fixtures = v4Fixtures();
final _limits = BasisLimits.forProfile(BasisProfile.standard);

List<int> fixture(String name) => File('$_fixtures/$name').readAsBytesSync();

Matcher rejects(String code) =>
    throwsA(isA<ContextFormatException>().having((e) => e.code, 'code', code));

/// El código de catálogo que cada fixture inválido del paquete exige.
const _expected = {
  'invalid-major.json': 'incompatible_version',
  'invalid-import-approval.json': 'invalid_schema',
  'invalid-active-unknown.json': 'unknown_active_scope',
  'invalid-prohibition-alternative.json': 'missing_alternative',
  'invalid-scope-escape.json': 'unsafe_path',
  'invalid-create-version.json': 'invalid_schema',
  'invalid-digest.json': 'digest_mismatch',
  'invalid-history-gap.json': 'history_gap',
  'invalid-journal-target.json': 'invalid_reference',
  'invalid-read-published.json': 'invalid_schema',
  'invalid-authority.json': 'invalid_schema',
  'invalid-duplicate-key.json': 'invalid_schema',
  'invalid-input-observation.json': 'invalid_schema',
  'invalid-source-ref-kind.json': 'invalid_reference',
  'invalid-review-kind.json': 'invalid_reference',
  'invalid-review-future.json': 'invalid_reference',
  'invalid-review-proposed.json': 'invalid_reference',
  'invalid-review-scope.json': 'invalid_reference',
  'invalid-review-empty-owner.json': 'invalid_schema',
  'invalid-review-missing.json': 'invalid_reference',
  'invalid-review-persisted-temporary.json': 'invalid_reference',
  'invalid-review-retarget.json': 'invalid_reference',
  'invalid-review-history-future.json': 'invalid_reference',
  'invalid-review-response-target.json': 'invalid_schema',
  'invalid-review-response-duplicate.json': 'invalid_schema',
  'invalid-review-draft-temporary.json': 'invalid_reference',
  'invalid-review-ordinary-retarget.json': 'invalid_reference',
  'invalid-proposed-change-kind.json': 'invalid_schema',
  'invalid-proposed-after-publish.json': 'invalid_schema',
  'invalid-proposed-change-name.json': 'invalid_schema',
  'invalid-proposed-already-applied.json': 'invalid_schema',
  'invalid-proposed-discarded.json': 'invalid_schema',
};

Object decodeAs(String schema, List<int> bytes) => switch (schema) {
  'basis' => decodeBasis(bytes, limits: _limits),
  'input' => decodeBasisInput(bytes, limits: _limits),
  'draft' => decodeBasisDraft(bytes, limits: _limits),
  'journal' => decodeBasisTransaction(bytes, limits: _limits),
  'response' => decodeBasisResponse(bytes, limits: _limits),
  _ => throw ArgumentError(schema),
};

List<int> encodeAs(Object value) => switch (value) {
  BasisDocument() => encodeBasis(value),
  BasisInput() => encodeBasisInput(value),
  BasisDraft() => encodeBasisDraft(value),
  BasisTransaction() => encodeBasisTransaction(value),
  BasisResponse() => encodeBasisResponse(value),
  _ => throw ArgumentError(value),
};

void main() {
  test('arrays_keep_order', () {
    expect(
      utf8.decode(
        canonicalBasisJson({
          'z': [2, 1],
        }),
      ),
      '{"z":[2,1]}',
    );
  });

  test('canonical vectors match byte for byte', () {
    final vectors =
        jsonDecode(File('$_fixtures/canonical-vectors.json').readAsStringSync())
            as List<Object?>;
    for (final vector in vectors.cast<Map<String, Object?>>()) {
      final bytes = canonicalBasisJson(vector['input']);
      final hex = [
        for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
      ].join();
      expect(hex, vector['utf8Hex']);
      expect(basisDigest(vector['input']), vector['digest']);
    }
  });

  group('every package fixture', () {
    final index =
        jsonDecode(File('$_fixtures/index.json').readAsStringSync())
            as List<Object?>;
    for (final entry in index.cast<Map<String, Object?>>()) {
      final file = entry['file']! as String;
      final schema = entry['schema']! as String;
      if (entry['valid'] == true) {
        test('$file decodes and survives a round trip', () {
          final value = decodeAs(schema, fixture(file));
          final again = decodeAs(schema, encodeAs(value));
          expect(
            utf8.decode(
              canonicalBasisJson(jsonDecode(utf8.decode(encodeAs(again)))),
            ),
            utf8.decode(
              canonicalBasisJson(jsonDecode(utf8.decode(fixture(file)))),
            ),
          );
        });
      } else {
        test('$file is rejected with ${_expected[file]}', () {
          expect(
            () => decodeAs(schema, fixture(file)),
            rejects(_expected[file]!),
          );
        });
      }
    }
    test('every invalid fixture has its expected code', () {
      final invalid = {
        for (final e in index.cast<Map<String, Object?>>())
          if (e['valid'] != true) e['file'],
      };
      expect(invalid, _expected.keys.toSet());
    });
  });

  test('review_link_roundtrip_preserves_exact_version_and_null_reviewer', () {
    final basis = decodeBasis(
      fixture('valid-review-basis.json'),
      limits: _limits,
    );
    final pending = replayBasis(
      basis,
    ).values.map((v) => v.payload).whereType<BasisPending>().single;
    expect(pending.decisionReview!.ref, '0000000a-0000-4000-8000-000000000000');
    expect(pending.decisionReview!.version, 1);
    expect(pending.decisionReview!.reviewer, isNull);
    final again = decodeBasis(encodeBasis(basis), limits: _limits);
    expect(again.digest, basis.digest);
  });

  test('ordinary_pending_can_refine_scope', () {
    final basis = decodeBasis(
      fixture('valid-ordinary-pending-scope-update.json'),
      limits: _limits,
    );
    final pending = replayBasis(
      basis,
    ).values.firstWhere((v) => v.payload is BasisPending);
    expect(pending.version, 2);
    expect(pending.previousVersion, 1);
  });

  test('review_binding_cannot_change', () {
    expect(
      () =>
          decodeBasis(fixture('invalid-review-retarget.json'), limits: _limits),
      rejects('invalid_reference'),
    );
  });

  test('history_target_must_exist_at_event', () {
    expect(
      () => decodeBasis(
        fixture('invalid-review-history-future.json'),
        limits: _limits,
      ),
      rejects('invalid_reference'),
    );
  });

  group('strict JSON before anything else', () {
    List<int> text(String s) => utf8.encode(s);
    final basis = utf8.decode(fixture('valid-basis.json'));

    test('a duplicate key, a float or a BOM is invalid_schema', () {
      expect(
        () => decodeBasis(text('{"a":1,"a":2}'), limits: _limits),
        rejects('invalid_schema'),
      );
      expect(
        () => decodeBasis(
          text(basis.replaceFirst('"revision": 1,', '"revision": 1.0,')),
          limits: _limits,
        ),
        rejects('invalid_schema'),
      );
      expect(
        () => decodeBasis([0xEF, 0xBB, 0xBF, ...text(basis)], limits: _limits),
        rejects('invalid_schema'),
      );
    });

    test('nesting deeper than 32 is invalid_schema', () {
      final deep = '${'[' * 33}${']' * 33}';
      expect(
        () => decodeBasis(text(deep), limits: _limits),
        rejects('invalid_schema'),
      );
    });

    test('more bytes than the profile is budget_exceeded before parsing', () {
      final tiny = BasisLimits.fromJson({
        ..._limits.toJson(),
        'maxBasisBytes': 10,
      });
      expect(
        () => decodeBasis(fixture('valid-basis.json'), limits: tiny),
        rejects('budget_exceeded'),
      );
    });

    test('an unknown field is invalid_schema', () {
      expect(
        () => decodeBasis(
          text(basis.replaceFirst('{', '{"extra": 1,')),
          limits: _limits,
        ),
        rejects('invalid_schema'),
      );
    });
  });

  test('the encoded basis is sealed by its own canonical digest', () {
    final basis = decodeBasis(fixture('valid-basis.json'), limits: _limits);
    final json = basis.toJson()..remove('digest');
    expect(basisDigest(json), basis.digest);
    final event = basis.events.single.toJson()..remove('eventDigest');
    expect(basisDigest(event), basis.events.single.eventDigest);
  });
}
