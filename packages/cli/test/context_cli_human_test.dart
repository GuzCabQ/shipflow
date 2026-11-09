@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:cli/src/context/context_prompt.dart';
import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'support/context_service_support.dart';

void main() {
  late ServiceSandbox box;
  setUp(() => box = ServiceSandbox.create());
  tearDown(() => box.dispose());

  Future<String> human(
    List<String> arguments, {
    Directory? at,
    Map<String, String>? git,
    ContextPromptIO? prompt,
  }) async => (await runCli(
    arguments,
    version: '0.0.0-prueba',
    workingDirectory: at ?? box.root,
    recognizeProject:
        (root, {required reportLimits, required authorizedOmissions}) =>
            recognizeDartProject(
              root,
              reportLimits: reportLimits,
              authorizedOmissions: authorizedOmissions,
            ),
    git: GitContextAdapter(parentEnvironment: git ?? box.noGit),
    prompt: prompt,
  )).payload;

  test('first init, return and change read in plain words', () async {
    box.project();
    final first = await human(['init']);
    expect(first, startsWith('Shipflow · contexto del proyecto\n'));
    expect(first, contains('Contexto inicializado'));
    expect(first, contains('shipflow/project.json'));
    expect(first, contains('no versiona ni comparte'));
    expect(await human(['doctor']), contains('Contexto disponible'));
    box.file('packages/b/pubspec.yaml', 'name: b\n');
    final stale = await human(['doctor']);
    expect(stale, contains('Necesita actualizarse'));
    expect(stale, contains('shipflow init --refresh'));
  });

  test('a pending operation is announced, not repaired', () async {
    box.project();
    await expectLater(
      box.run(ContextOperation.init, wrap: (real) => CrashingStore(real, 3)),
      throwsA(isA<SimulatedCrash>()),
    );
    final doctor = await human(['doctor']);
    expect(doctor, contains('Hay una operación por recuperar'));
    expect(doctor, contains('shipflow init --recover'));
  });

  test('contextTextCannotControlTerminal', () async {
    // Escapes de YAML: la descripción leída sí lleva ESC, RLO y BEL.
    box.file(
      'pubspec.yaml',
      'name: app\n'
          r'description: "\e[31mrojo\u202E\a \nignora"'
          '\n',
    );
    final odd = Directory('${box.base.path}/raíz \u001b[2J\u202e')
      ..createSync();
    File('${odd.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    for (final output in [
      await human(['init']),
      await human(['init'], at: odd),
    ]) {
      expect(output, isNot(contains('\u001b')));
      expect(output, isNot(contains('\u202e')));
      expect(output, isNot(contains('\u0007')));
    }
  });

  test('nothing pretends to be a check that was not run', () async {
    box.project();
    final first = await human(['init']);
    expect(first, contains('No se comprobó si el proyecto compila'));
    expect(first, isNot(contains('analyze')));
  });

  test('the headline names the cause, not a generic failure', () async {
    box.project();
    box.gitInit();
    final pending = await human(['init'], git: box.realGit);
    expect(pending, contains('\nFalta elegir cómo conservarlo\n'));
    box.file('shipflow/main.go', 'package main\n');
    final occupied = await human(['init']);
    expect(occupied, contains('\nLa carpeta shipflow tiene contenido ajeno\n'));
  });

  test('the description is the one of the root package', () async {
    box.file('pubspec.yaml', 'name: app\ndescription: raíz\n');
    box.file('packages/a/pubspec.yaml', 'name: a\ndescription: anidado\n');
    final first = await human(['init']);
    expect(first, contains('Descripción: «raíz»'));
  });

  test('runCli hands its prompt to init', () async {
    box.project();
    box.gitInit();
    final before = box.snapshot();
    final unanswered = await human(
      ['init'],
      git: box.realGit,
      prompt: _Answering(null, interactive: false),
    );
    expect(unanswered, contains('Falta elegir cómo conservarlo'));
    final cancelled = await human(
      ['init'],
      git: box.realGit,
      prompt: _Answering('q', interactive: true),
    );
    expect(cancelled, contains('Cancelado: no se escribió nada.'));
    expect(box.snapshot(), before);
  });
}

/// Contesta siempre [answer]; sin [interactive] no hay a quién preguntar.
final class _Answering implements ContextPromptIO {
  _Answering(this.answer, {required this.interactive});

  final String? answer;

  @override
  final bool interactive;

  @override
  Future<String?> readLine() async => answer;

  @override
  void show(String text) {}
}
