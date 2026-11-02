@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final process = InitProcessSandbox()..register();

  /// [arguments] con la entrada desde /dev/null, como en un script o en un
  /// contenedor sin terminal.
  Future<RunResult> withoutTerminal(List<String> arguments) async {
    final result = await Process.run(
      '/bin/sh',
      ['-c', r'"$0" "$@" </dev/null', process.binary, ...arguments],
      workingDirectory: process.root.path,
      environment: {'HOME': process.home.path, 'TMPDIR': process.temp.path},
      includeParentEnvironment: false,
    );
    return RunResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  void project() {
    process.place('pubspec.yaml', '''
name: app
environment:
  sdk: ^3.6.0
dependencies:
  widgets:
    path: packages/widgets
''');
    process.place('packages/widgets/pubspec.yaml', 'name: widgets\n');
    process.place('packages/widgets/lib/widget.dart', 'class W {}\n');
    process.place('lib/main.dart', "import 'package:widgets/widget.dart';\n");
  }

  AssessmentResult decoded(RunResult run) =>
      decodeAssessmentResponse(utf8.encode(run.stdout));

  test(
    'without init the JSON answer is blocked, valid and writes nothing',
    () async {
      project();
      final before = treeSnapshot(process.root);
      final run = await withoutTerminal(['assess', '--json']);
      expect(run.exitCode, 65);
      expect(run.stderr, isEmpty);
      expect(decoded(run).outcome, AssessmentOutcome.blocked);
      expect(treeSnapshot(process.root), before);
    },
  );

  test('save, consult in another process and see it stale', () async {
    project();
    expect((await process.run(['init', '--json'])).exitCode, 0);
    final saved = await withoutTerminal(['assess', '--json']);
    expect(saved.exitCode, 0, reason: saved.stdout);
    expect(decoded(saved).effects.published, isTrue);
    final shown = await withoutTerminal(['assess', '--show', '--json']);
    expect(decoded(shown).freshness, AssessmentFreshness.current);
    final human = await process.run(['assess', '--show']);
    expect(human.stdout, startsWith('Levantamiento vigente'));
    process.place('lib/nuevo.dart', 'class N {}\n');
    final stale = await withoutTerminal(['assess', '--show', '--json']);
    expect(
      (stale.exitCode, decoded(stale).freshness),
      (65, AssessmentFreshness.stale),
    );
  });

  test('help and usage answer without reading the project', () async {
    final help = await process.run(['assess', '--help']);
    expect(help.exitCode, 0);
    expect(help.stdout, contains('shipflow assess --recover'));
    final usage = await process.run(['assess', '--previous']);
    expect(usage.exitCode, 64);
    expect(usage.stderr, contains("Usa 'shipflow assess --help'."));
  });
}
