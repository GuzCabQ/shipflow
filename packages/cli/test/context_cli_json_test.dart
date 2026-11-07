@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:cli/src/context/bounded_context_json.dart';
import 'package:cli/src/context/context_codec.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'support/context_service_support.dart';

const codec = ContextCodec();

void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create();
    box.project();
  });
  tearDown(() => box.dispose());

  Future<CliResponse> cli(List<String> arguments) => runCli(
    arguments,
    version: '0.0.0-prueba',
    workingDirectory: box.root,
    recognizeProject:
        (root, {required reportLimits, required authorizedOmissions}) =>
            recognizeDartProject(
              root,
              reportLimits: reportLimits,
              authorizedOmissions: authorizedOmissions,
            ),
    git: GitContextAdapter(parentEnvironment: box.noGit),
  );

  test('init, doctor and refresh answer one schema 3 line each', () async {
    for (final (arguments, exitCode) in [
      (['init', '--json'], 0),
      (['doctor', '--json'], 0),
      (['init', '--json'], 0),
      (['init', '--refresh', '--json'], 0),
      (['init', '--recover', '--json'], 0),
    ]) {
      final response = await cli(arguments);
      expect(response.exitCode, exitCode, reason: response.payload);
      expect(response.channel, CliOutputChannel.stdout);
      expect('\n'.allMatches(response.payload), hasLength(1));
      final result = codec.decodeResponse(utf8.encode(response.payload));
      expect(result.exitCode, exitCode);
    }
  });

  test('a choice that is impossible is 65 with a structured answer', () async {
    final response = await cli(['init', '--sharing=local', '--json']);
    expect(response.exitCode, 65);
    final json = jsonDecode(response.payload) as Map<String, Object?>;
    expect(json['outcome'], 'needs_attention');
    expect(Directory(box.path('shipflow')).existsSync(), isFalse);
  });

  test('usage errors and V0 keep schema 1', () async {
    final usage = await cli(['init', '--force', '--json']);
    expect(usage.exitCode, 64);
    expect((jsonDecode(usage.payload) as Map)['schemaVersion'], 1);
    final help = await cli(['doctor', '--help', '--json']);
    expect((jsonDecode(help.payload) as Map)['schemaVersion'], 1);
  });

  test(
    'a response that does not fit keeps outcome, effects and actions',
    () async {
      final response = await cli(['init', '--json']);
      final full = codec.decodeResponse(utf8.encode(response.payload));
      expect(utf8.encode(response.payload).length, greaterThan(2400));
      final compact = encodeContextWithinLimit(full, maxBytes: 2400);
      final again = codec.decodeResponse(utf8.encode(compact));
      expect(again.context, isNull);
      expect(again.outcome, full.outcome);
      expect(again.exitCode, full.exitCode);
      expect(again.effects.toJson(), full.effects.toJson());
      expect(again.nextActions.length, full.nextActions.length);
      expect(utf8.encode(compact).length, lessThanOrEqualTo(2400));
    },
  );
}
