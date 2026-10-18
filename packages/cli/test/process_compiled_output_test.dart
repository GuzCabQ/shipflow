@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';

import 'package:test/test.dart';

import 'process_contract_support.dart';

void main() {
  final contract = CompiledContract()..register();

  group('ejecutable compilado fuera del checkout', () {
    test('con stdout cerrado devuelve 70 y no afirma JSON', () async {
      for (final arguments in [
        ['--json'],
        ['--version', '--json'],
        ['--json', '--inventada'],
        ['--help'],
      ]) {
        final observed = await contract.run('/bin/sh', [
          '-c',
          r'exec "$0" "$@" 1>&-',
          contract.binary,
          ...arguments,
        ], workingDirectory: contract.sandbox);
        expect(observed.exitCode, 70, reason: '$arguments');
        expect(utf8.decode(observed.stderr), failureDiagnostic);
      }
    });

    test('con stderr cerrado un error devuelve 70', () async {
      final observed = await contract.run('/bin/sh', [
        '-c',
        r'exec "$0" "$@" 2>&-',
        contract.binary,
        '--inventada',
      ], workingDirectory: contract.sandbox);
      expect(observed.exitCode, 70);
      expect(utf8.decode(observed.stdout), failureDiagnostic);
    });

    test('un error controlado no filtra detalles del runtime', () async {
      for (final arguments in cases) {
        final observed = await contract.run(
          contract.binary,
          arguments,
          workingDirectory: contract.sandbox,
        );
        final text = utf8.decode(observed.stdout + observed.stderr);
        for (final leak in ['#0', 'dart:', 'Unhandled', 'Exception', '.dart']) {
          expect(text, isNot(contains(leak)), reason: '$arguments');
        }
        expect(text, isNot(contains(contract.sandbox.path)));
      }
    });

    test('cada respuesta JSON es exactamente una línea', () async {
      for (final arguments in cases.where((a) => a.contains('--json'))) {
        final observed = await contract.run(
          contract.binary,
          arguments,
          workingDirectory: contract.sandbox,
        );
        final lines = const LineSplitter().convert(
          utf8.decode(observed.stdout),
        );
        expect(lines, hasLength(1), reason: '$arguments');
        expect(jsonDecode(lines.single), isA<Map<String, Object?>>());
        expect(observed.stderr, isEmpty);
      }
    });

    test('el artefacto se llama shipflow y no responde como sdlc', () async {
      expect(contract.binary.split('/').last, 'shipflow');
      for (final arguments in cases) {
        final observed = await contract.run(
          contract.binary,
          arguments,
          workingDirectory: contract.sandbox,
        );
        expect(
          utf8.decode(observed.stdout + observed.stderr).toLowerCase(),
          isNot(contains('sdlc')),
        );
      }
    });
  });
}
