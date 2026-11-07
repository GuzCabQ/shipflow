@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'init_process_support.dart';

void main() {
  final process = InitProcessSandbox()..register();
  setUp(() async {
    process.place('pubspec.yaml', 'name: app\n');
    expect((await process.run(['init', '--json'])).exitCode, 0);
  });

  test(
    'in a real terminal the guide asks and «q» leaves it unchanged',
    () async {
      final before = treeSnapshot(process.root);
      final observed = await _runGuide(process, answer: 'q');
      expect(observed['exit'], 0, reason: '$observed');
      expect(observed['stdout'], contains('Base guiada del proyecto'));
      expect(observed['stdout'], contains('¿Qué quieres hacer?'));
      expect(treeSnapshot(process.root), before);
    },
  );

  test('closing the terminal input cancels without accepting', () async {
    final observed = await _runGuide(process, answer: null);
    expect(observed['exit'], 130, reason: '$observed');
    expect(observed['stdout'], contains('nada se aceptó'));
    expect(
      File('${process.root.path}/shipflow/basis.json').existsSync(),
      isFalse,
    );
  });
}

/// `bootstrap` con entrada y salida en un pty de 80×24: espera el menú y
/// contesta [answer], o cierra la entrada si es null.
Future<Map<String, Object?>> _runGuide(
  InitProcessSandbox process, {
  required String? answer,
}) async {
  final result = await Process.run(
    '/usr/bin/python3',
    ['-I', '-c', _guideRun, process.binary, answer ?? ''],
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

const _guideRun =
    r'''import errno, fcntl, json, os, pty, struct, subprocess, sys, termios, threading
binary, answer = sys.argv[1:]
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
child = subprocess.Popen([binary, 'bootstrap'], stdin=slave, stdout=slave,
                         stderr=subprocess.PIPE)
os.close(slave)
chunks = []
prompted = threading.Event()
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
        if '¿Qué quieres hacer?'.encode() in b''.join(chunks):
            prompted.set()
reader = threading.Thread(target=drain, daemon=True)
reader.start()
if prompted.wait(timeout=15):
    os.write(master, (answer + '\n').encode() if answer else b'\x04')
try:
    _, err = child.communicate(timeout=15)
except subprocess.TimeoutExpired:
    child.kill()
    child.communicate()
    raise
reader.join(timeout=5)
os.close(master)
print(json.dumps({'exit': child.returncode,
                  'stdout': b''.join(chunks).decode(errors='replace'),
                  'stderr': err.decode()}))
''';
