@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/build_release.dart';

final class _Collector implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('shipflow-build-');
  });

  tearDown(() => directory.delete(recursive: true));

  group('argumentos de la build oficial', () {
    Future<(int, String)> invoke(List<String> arguments) async {
      final out = _Collector();
      final err = _Collector();
      final code = await runBuildRelease(
        arguments,
        standardOut: IOSink(out),
        standardError: IOSink(err),
      );
      expect(out.bytes, isEmpty, reason: '$arguments');
      return (code, err.text);
    }

    test('sin versión falla antes de compilar', () async {
      final (code, message) = await invoke([
        '--output',
        '${directory.path}/release',
      ]);
      expect(code, 64);
      expect(message, contains('--version'));
      expect(directory.listSync(), isEmpty);
    });

    for (final version in [
      'v1.2.3',
      '1.2',
      '01.2.3',
      '1.2.3-01',
      ' 1.2.3',
      '1.2.3\n',
      '1.2.3-rc..1',
      '',
    ]) {
      test(
        '«${version.replaceAll('\n', r'\n')}» falla antes de compilar',
        () async {
          final (code, message) = await invoke([
            '--version',
            version,
            '--output',
            '${directory.path}/release',
          ]);
          expect(code, 64);
          expect(message, contains('no es SemVer 2.0'));
          expect(directory.listSync(), isEmpty);
        },
      );
    }

    test(
      'un --output sin directorio padre falla sin detalles del runtime',
      () async {
        final (code, message) = await invoke([
          '--version',
          '1.0.0',
          '--output',
          '${directory.path}/no-existe/release',
        ]);
        expect(code, 1);
        expect(
          message,
          'build_release: el directorio que contiene --output no existe o no '
          'es un directorio; no se compiló nada.\n',
        );
        expect(directory.listSync(), isEmpty);
      },
    );

    test(
      'un padre de --output sin escritura falla sin detalles del runtime',
      () async {
        final parent = await Directory(
          '${directory.path}/solo-lectura',
        ).create();
        await Process.run('chmod', ['0555', parent.path]);
        try {
          final (code, message) = await invoke([
            '--version',
            '1.0.0',
            '--output',
            '${parent.path}/release',
          ]);
          expect(code, 1);
          expect(
            message,
            'build_release: no se pudo crear el directorio de trabajo junto a '
            '--output (Permission denied); no se compiló nada.\n',
          );
          expect(parent.listSync(), isEmpty);
        } finally {
          await Process.run('chmod', ['0755', parent.path]);
        }
      },
    );

    for (final arguments in [
      <String>[],
      ['--version', '1.0.0'],
      ['--version'],
      ['--version', '1.0.0', '--output'],
      ['--version', '1.0.0', '--version', '1.0.1', '--output', 'x'],
      ['--version', '1.0.0', '--output', 'x', '--target-os', 'windows'],
      ['--version=1.0.0', '--output', 'x'],
    ]) {
      test('$arguments es uso inválido', () async {
        final (code, _) = await invoke(arguments);
        expect(code, 64);
        expect(directory.listSync(), isEmpty);
      });
    }
  });
}
