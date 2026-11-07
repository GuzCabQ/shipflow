import 'dart:convert';

import 'package:cli/src/context/context_codec.dart';
import 'package:cli/src/context/strict_json.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'v2_fixtures.dart';

const codec = ContextCodec();

/// La capa en que [schema] rechaza [bytes], o `valid` si los acepta.
String layerOf(String schema, List<int> bytes) {
  try {
    switch (schema) {
      case 'project-context':
        codec.decodeProject(bytes);
      case 'local-settings':
        codec.decodeSettings(bytes);
      case 'transaction':
        codec.decodeTransaction(bytes);
      case 'operation-response':
        codec.decodeResponse(currentMajor(bytes, from: 3, to: 4));
      case 'recognition-dry-run':
        codec.checkDryRun(bytes);
      default:
        throw StateError(schema);
    }
    return 'valid';
  } on ContextFormatException catch (e) {
    return e.layer.name;
  }
}

/// [json] como documento de disco: dos espacios y salto final.
List<int> pretty(Object? json) =>
    utf8.encode('${const JsonEncoder.withIndent('  ').convert(json)}\n');

void main() {
  group('the 19 package fixtures fail at their expected layer', () {
    test(
      'a V2 response keeps its shape but its old major is refused',
      () async {
        final bytes = await v2Bytes('fixtures/valid/doctor-current.json');
        expect(layerOf('operation-response', bytes), 'valid');
        expect(
          () => codec.decodeResponse(bytes),
          throwsA(isA<ContextFormatException>()),
        );
      },
    );

    test('each case', () async {
      final cases = await v2Cases();
      expect(cases, hasLength(19));
      for (final c in cases) {
        final bytes = await v2Bytes(c.path);
        expect(layerOf(c.schema, bytes), c.layer, reason: c.path);
      }
    });
  });

  group('the project document', () {
    test(
      'decodes to the portable shape and re-encodes byte for byte',
      () async {
        final bytes = await v2Bytes('fixtures/valid/project.json');
        final decoded = codec.decodeProject(bytes);
        expect(decoded.root, '.');
        expect(decoded.toJson().containsKey('resolvedRoot'), isFalse);
        expect(codec.encodeProject(decoded), bytes);
      },
    );

    test('duplicate keys are a parser error, never a last-wins map', () async {
      final duplicateKeys = await v2Bytes(
        'fixtures/invalid/duplicate-keys.json',
      );
      expect(
        () => codec.decodeProject(duplicateKeys),
        throwsA(isA<ContextFormatException>()),
      );
    });

    test('an exception never carries the raw content', () async {
      final json = await v2Json('fixtures/valid/project.json');
      json['secreto-ajeno'] = 'contenido';
      try {
        codec.decodeProject(pretty(json));
        fail('accepted an unknown field');
      } on ContextFormatException catch (e) {
        expect('${e.code} ${e.at}', isNot(contains('secreto')));
        expect('$e', isNot(contains('contenido')));
      }
    });
  });

  group('the canonical digest', () {
    test('matches the package vector byte for byte', () async {
      final vector = await v2Json('fixtures/canonical-digest.json');
      final recognition = await _portable(vector['input']);
      expect(
        utf8.decode(codec.canonicalRecognition(recognition)),
        vector['canonicalUtf8'],
      );
      expect(codec.digest(recognition), vector['sha256']);
    });

    test('does not depend on the enumeration order', () async {
      final input =
          (await v2Json('fixtures/canonical-digest.json'))['input']
              as Map<String, Object?>;
      final two = _withTwoUnits(input);
      final reversed = _withTwoUnits(input, reverse: true);
      expect(
        codec.digest(await _portable(two)),
        codec.digest(await _portable(reversed)),
      );
    });
  });

  group('bounds are inclusive and the next byte fails', () {
    for (final (name, max, decode) in [
      ('project', maxProjectBytes, codec.decodeProject),
      ('settings', maxSettingsBytes, codec.decodeSettings),
      ('transaction', maxTransactionBytes, codec.decodeTransaction),
    ]) {
      test(name, () async {
        final source = await v2Bytes(switch (name) {
          'project' => 'fixtures/valid/project.json',
          'settings' => 'fixtures/valid/settings-pending.json',
          _ => 'fixtures/valid/journal.json',
        });
        expect(() => decode(_padded(source, max)), returnsNormally);
        expect(
          () => decode(_padded(source, max + 1)),
          throwsA(_layer(ContextFormatLayer.parser, 'too_large')),
        );
      });
    }
  });

  group('strict JSON', () {
    test('depth 64 is read and 65 is not', () {
      expect(
        decodeStrictJson(_nested(64), maxBytes: 1 << 20),
        isA<List<Object?>>(),
      );
      expect(
        () => decodeStrictJson(_nested(65), maxBytes: 1 << 20),
        throwsA(_layer(ContextFormatLayer.parser, 'too_deep')),
      );
    });

    for (final (name, bytes, code) in [
      ('an encoded surrogate', [0x22, 0xED, 0xA0, 0x80, 0x22], 'invalid_utf8'),
      ('a lone surrogate escape', utf8.encode(r'"\ud800"'), 'invalid_text'),
      (
        'a reversed surrogate pair',
        utf8.encode(r'"\udc00\ud800"'),
        'invalid_text',
      ),
      (
        'a byte order mark',
        [0xEF, 0xBB, 0xBF, ...utf8.encode('{}')],
        'invalid_json',
      ),
      ('a float', utf8.encode('{"a":1.0}'), 'invalid_json'),
      ('a raw control character', utf8.encode('"a\nb"'), 'invalid_json'),
      ('trailing content', utf8.encode('{} {}'), 'invalid_json'),
      ('a duplicate key', utf8.encode('{"a":1,"a":2}'), 'duplicate_key'),
    ]) {
      test('rejects $name', () {
        expect(
          () => decodeStrictJson(bytes, maxBytes: 1 << 20),
          throwsA(_layer(ContextFormatLayer.parser, code)),
        );
      });
    }

    test('a valid pair, escapes and a trailing newline are read', () {
      expect(
        decodeStrictJson(
          utf8.encode('{"a":"\\ud83d\\ude00\\n"}\n'),
          maxBytes: 99,
        ),
        {'a': '😀\n'},
      );
    });
  });

  group('an impossible date is semantic', () {
    test('February 30', () async {
      final json = await v2Json('fixtures/valid/project.json');
      json['observedAt'] = '2026-02-30T00:00:00Z';
      expect(
        () => codec.decodeProject(pretty(json)),
        throwsA(_layer(ContextFormatLayer.semantic, 'observed_at')),
      );
    });
  });

  group('extendedContextDoesNotRaiseObservationBudget', () {
    test('a document above standard and within extended is read', () async {
      final json = await _withEvidence(17000);
      final decoded = codec.decodeProject(pretty(json));
      expect(decoded.recognition.evidence, hasLength(17000));
      // Leerlo no cambia el perfil de una inspección nueva sin flag.
      expect(const ReportLimits().maxDerivedItems, 16384);
      expect(
        () => admitPortable(decoded.recognition, const ReportLimits()),
        throwsA(isA<ReportLimitExceeded>()),
      );
    });

    test('a document above the extended ceiling is rejected', () async {
      final json = await _withEvidence(18432, digest: false);
      expect(
        () => codec.decodeProject(utf8.encode(jsonEncode(json))),
        throwsA(_layer(ContextFormatLayer.semantic, 'budget_exceeded')),
      );
    });
  });
}

Matcher _layer(ContextFormatLayer layer, String code) =>
    isA<ContextFormatException>()
        .having((e) => e.layer, 'layer', layer)
        .having((e) => e.code, 'code', code);

/// [source] con espacios antes del salto final hasta medir [size] bytes.
List<int> _padded(List<int> source, int size) => [
  ...source.sublist(0, source.length - 1),
  ...List.filled(size - source.length, 0x20),
  0x0A,
];

List<int> _nested(int depth) => utf8.encode('${'[' * depth}${']' * depth}');

/// [recognition] como reconocimiento portable, pasando por el codec.
Future<PortableRecognition> _portable(Object? recognition) async =>
    codec.decodeRecognition(pretty(recognition));

Map<String, Object?> _withTwoUnits(
  Map<String, Object?> input, {
  bool reverse = false,
}) {
  final copy = jsonDecode(jsonEncode(input)) as Map<String, Object?>;
  final units = copy['units']! as List<Object?>;
  units.add({
    ...units.first! as Map<String, Object?>,
    'id': 'u0002',
    'path': 'b',
  });
  if (reverse) copy['units'] = units.reversed.toList();
  return copy;
}

/// El fixture con [count] evidencias breves, su digest recalculado.
Future<Map<String, Object?>> _withEvidence(
  int count, {
  bool digest = true,
}) async {
  final json = await v2Json('fixtures/valid/project.json');
  final recognition = json['recognition']! as Map<String, Object?>;
  final first = (recognition['evidence']! as List<Object?>).first!;
  recognition['evidence'] = [
    first,
    for (var i = 2; i <= count; i++)
      {
        'id': 'e${i.toString().padLeft(5, '0')}',
        'kind': 'n',
        'role': 'identity',
        'label': 'L',
        'path': 'p',
        'value': 'v',
        'fingerprint': 'f',
      },
  ];
  json['observationDigest'] = digest
      ? codec.digest(codec.decodeRecognition(pretty(recognition)))
      : '0' * 64;
  return json;
}
