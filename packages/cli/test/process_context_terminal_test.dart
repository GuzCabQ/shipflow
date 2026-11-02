@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final process = InitProcessSandbox()..register();

  for (final (input, output, expected) in [
    ('null', 'tty', 65),
    ('file', 'tty', 65),
    ('pipe', 'tty', 65),
    ('tty', 'null', 65),
    ('tty', 'pipe', 65),
    ('tty', 'tty', 130),
  ]) {
    test('init with $input input and $output output exits $expected', () async {
      process.place('pubspec.yaml', 'name: app\n');
      final git = Process.runSync('git', [
        'init',
        '-q',
      ], workingDirectory: process.root.path);
      expect(git.exitCode, 0, reason: '${git.stderr}');
      final before = treeSnapshot(process.root);
      final observed = await _runTerminal(process, input, output);
      expect(observed['exit'], expected, reason: '$observed');
      expect(observed['stderr'], isEmpty);
      if (output != 'null') {
        expect(
          observed['stdout'],
          expected == 130
              ? contains('Elige 1, 2, ? o q:')
              : isNot(contains('Elige 1, 2, ? o q:')),
        );
      }
      if (expected == 65 && output != 'null') {
        expect(observed['stdout'], contains('Falta elegir cómo conservarlo'));
      }
      expect(treeSnapshot(process.root), before);
    });
  }
}

Future<Map<String, Object?>> _runTerminal(
  InitProcessSandbox process,
  String input,
  String output,
) async {
  final result = await Process.run(
    '/usr/bin/python3',
    ['-I', '-c', _terminalRun, process.binary, input, output],
    workingDirectory: process.root.path,
    environment: {
      'HOME': process.home.path,
      'TMPDIR': process.temp.path,
      'PATH': '/usr/bin:/bin',
    },
    includeParentEnvironment: false,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String) as Map<String, Object?>;
}

const _terminalRun =
    r'''import errno, fcntl, json, os, pty, struct, subprocess, sys, tempfile, termios, threading
binary, input_kind, output_kind = sys.argv[1:]
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
with open(os.devnull, 'rb+') as null, tempfile.TemporaryFile() as file:
    inputs = {'null': null, 'file': file, 'pipe': subprocess.PIPE, 'tty': slave}
    outputs = {'null': null, 'pipe': subprocess.PIPE, 'tty': slave}
    child = subprocess.Popen([binary, 'init'], stdin=inputs[input_kind],
                             stdout=outputs[output_kind], stderr=subprocess.PIPE)
    os.close(slave)
    chunks = []
    def drain():
        while True:
            try:
                chunk = os.read(master, 4096)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            chunks.append(chunk)
    reader = threading.Thread(target=drain, daemon=True)
    reader.start()
    if input_kind == 'tty':
        os.write(master, b'q\n')
    try:
        out, err = child.communicate(timeout=15)
    except subprocess.TimeoutExpired:
        child.kill()
        child.communicate()
        raise
    reader.join(timeout=5)
    assert not reader.is_alive(), 'terminal did not close'
    terminal = b''.join(chunks)
    os.close(master)
    print(json.dumps({'exit': child.returncode,
                      'stdout': (terminal if output_kind == 'tty' else out or b'').decode(),
                      'stderr': err.decode()}))
''';
