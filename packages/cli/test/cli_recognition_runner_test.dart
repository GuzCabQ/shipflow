import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'runner_support.dart';

void main() {
  final sandbox = RunnerSandbox()..register();

  test('reconoce la raíz canónica con su contexto Git', () async {
    Directory('${sandbox.root.path}/.git').createSync();
    final body = decode(await sandbox.run(['init', '--dry-run', '--json']));
    expect(body['status'], 'recognized');
    expect(body['requestedRoot'], sandbox.root.path);
    expect(body['resolvedRoot'], sandbox.root.path);
    expect(body['repository'], {
      'status': 'detected',
      'root': sandbox.root.path,
      'relation': 'same',
    });
    expect(body['exitCode'], 0);
    expect(sandbox.received, [sandbox.root.path]);
  });

  test('una raíz pedida por enlace muestra ambas rutas', () async {
    final real = Directory('${sandbox.root.path}/real')..createSync();
    final link = Link('${sandbox.root.path}/enlace')..createSync(real.path);
    final response = await sandbox.run([
      'init',
      '--dry-run',
      '--json',
    ], workingDirectory: Directory(link.path));
    final body = decode(response);
    expect(body['requestedRoot'], link.path);
    expect(body['resolvedRoot'], real.path);
    expect(sandbox.received, [real.path]);
  });

  test('la vista humana sale del mismo reconocimiento', () async {
    final response = await sandbox.run(['init', '--dry-run']);
    expect(response.channel, CliOutputChannel.stdout);
    expect(response.exitCode, 0);
    expect(response.payload, startsWith('Shipflow · reconocimiento\n'));
    expect(response.payload, contains('Raíz resuelta: ${sandbox.root.path}\n'));
    expect(sandbox.received, hasLength(1));
  });

  test('sin candidatos no es soportada y sale con 65', () async {
    final response = await sandbox.run(
      ['init', '--dry-run', '--json'],
      contributor: (_) async => RecognitionContribution(
        candidates: const [],
        units: const [],
        evidence: const [],
        conflicts: const [],
        limitations: const [],
      ),
    );
    expect(decode(response)['status'], 'unsupported');
    expect(response.exitCode, 65);
  });

  test('un conflicto es ambiguo y sale con 65', () async {
    final response = await sandbox.run(
      ['init', '--dry-run', '--json'],
      contributor: (root) async {
        final base = await sandbox.contribute(root);
        return RecognitionContribution(
          candidates: base.candidates,
          units: base.units,
          evidence: base.evidence,
          conflicts: [
            RecognitionConflict(
              code: 'c',
              message: 'm',
              evidenceIds: const ['e0001'],
            ),
          ],
          limitations: const [],
        );
      },
    );
    expect(decode(response)['status'], 'ambiguous');
    expect(response.exitCode, 65);
  });

  test('ayuda, versión y uso inválido nunca reconocen', () async {
    for (final arguments in [
      ['--help'],
      ['--version', '--json'],
      ['init'],
      ['init', '--help'],
      ['init', '--dry-run', '--bogus'],
      ['--json', 'init', '--dry-run'],
    ]) {
      final response = await sandbox.run(
        arguments,
        contributor: (_) => fail('$arguments no debía reconocer'),
      );
      expect(response.exitCode, anyOf(0, 64), reason: '$arguments');
    }
  });
}
