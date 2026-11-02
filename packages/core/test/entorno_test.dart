import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const padre = {
    'PATH': '/usr/bin',
    'HOME': '/home/a',
    'GIT_DIR': '/evil',
    'GIT_CONFIG_GLOBAL': '/evil/config',
    'SHIPFLOW_GITHUB_TOKEN': 'secreto',
  };

  test('only the whitelist is inherited, plus what the call declares', () {
    expect(entornoSaneado(padre, propias: {'GIT_TERMINAL_PROMPT': '0'}), {
      'PATH': '/usr/bin',
      'HOME': '/home/a',
      'GIT_TERMINAL_PROMPT': '0',
    });
  });

  test('a declared variable cannot replace the whitelist', () {
    expect(
      () => entornoSaneado(padre, propias: {'PATH': '/tmp/otro'}),
      throwsArgumentError,
    );
  });

  test('the result is immutable', () {
    expect(() => entornoSaneado(padre)['X'] = 'y', throwsUnsupportedError);
  });
}
