import 'package:cli/src/context/context_prompt.dart';
import 'package:cli/src/context/context_request.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

/// Una terminal guionada: devuelve [answers] en orden y luego EOF.
final class ScriptedPrompt implements ContextPromptIO {
  ScriptedPrompt(this.answers);

  final List<String> answers;
  final shown = StringBuffer();
  var reads = 0;

  @override
  bool get interactive => true;

  @override
  Future<String?> readLine() async =>
      reads < answers.length ? answers[reads++] : null;

  @override
  void show(String text) => shown.write(text);
}

final _question = SharingQuestion(
  stacks: const ['Flutter'],
  units: 2,
  sharedExclude: false,
);

void main() {
  for (final (answers, expected) in [
    (['1'], SharingChoice.share),
    (['2'], SharingChoice.local),
    (['', '1'], SharingChoice.share),
    (['x', '2'], SharingChoice.local),
    (['?', '2'], SharingChoice.local),
    (['q'], null),
    (<String>[], null),
  ]) {
    test('answers $answers choose $expected', () async {
      final io = ScriptedPrompt(answers);
      expect(await askSharing(io, _question), expected);
      expect(io.reads, answers.length.clamp(0, 99));
    });
  }

  test('an empty Enter never consents: the options come back', () async {
    final io = ScriptedPrompt(['', '']);
    expect(await askSharing(io, _question), isNull);
    expect('Elige 1, 2, ? o q'.allMatches(io.shown.toString()), hasLength(3));
  });

  test('the main text says consequences, the detail names Git', () async {
    final io = ScriptedPrompt(['?', 'q']);
    await askSharing(io, _question);
    final shown = io.shown.toString();
    final main = shown.substring(0, shown.indexOf('Detalle técnico'));
    expect(main, contains('Compartir con el proyecto — recomendado'));
    expect(main, contains('Mantenerlo sólo aquí'));
    expect(main, contains('respaldo'));
    expect(main, isNot(contains('exclude')));
    expect(main, isNot(contains('commit')));
    expect(shown, contains('info/exclude'));
    expect(shown, contains('no ejecuta git add, commit ni push'));
  });

  test('a shared exclude across worktrees is explained up front', () async {
    final io = ScriptedPrompt(['q']);
    await askSharing(
      io,
      SharingQuestion(stacks: const ['Dart'], units: 1, sharedExclude: true),
    );
    expect(io.shown.toString(), contains('otras copias de trabajo'));
  });
}
