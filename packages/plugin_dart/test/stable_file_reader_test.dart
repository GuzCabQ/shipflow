import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_dart/src/stable_file_reader.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  late File file;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('shipflow-lectura-');
    file = File('${sandbox.path}/fuente.yaml')..writeAsStringSync('name: a\n');
  });

  tearDown(() => sandbox.delete(recursive: true));

  test('los límites por defecto son los del contrato', () {
    const limits = ScanLimits();
    expect(limits.maxEntries, 100000);
    expect(limits.maxDepth, 32);
    expect(limits.maxManifests, 4096);
    expect(limits.maxManifestBytes, 262144);
    expect(limits.maxMarkerBytes, 4096);
    expect(limits.maxTotalSourceBytes, 16777216);
  });

  test('bytes estables devuelven su SHA-256', () async {
    final read = await readStableFile(file, maxBytes: 64);
    expect(read, isA<StableSource>());
    final source = read as StableSource;
    expect(source.bytes, 'name: a\n'.codeUnits);
    expect(source.size, 8);
    expect(source.fingerprint, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
    expect(
      source.fingerprint,
      'sha256:1e7e5f3c45fc71cc0d92ffd6a4136ce35256118f2cb9a940b09a9e336022a571',
    );
  });

  test(
    'bytes distintos entre las dos lecturas son una fuente inestable',
    () async {
      var call = 0;
      final read = await readStableFile(
        file,
        maxBytes: 64,
        readBytes: (_, _) async => call++ == 0 ? [1, 2, 3] : [1, 2, 4],
      );
      expect(read, isA<UnstableSource>());
      expect(call, 2);
    },
  );

  test('un tamaño declarado mayor al máximo no se lee', () async {
    var reads = 0;
    final read = await readStableFile(
      file,
      maxBytes: 4,
      readBytes: (_, _) async {
        reads++;
        return <int>[];
      },
    );
    expect(read, isA<OversizedSource>());
    expect((read as OversizedSource).size, 8);
    expect(reads, 0);
  });

  test('justo el máximo se acepta', () async {
    expect(await readStableFile(file, maxBytes: 8), isA<StableSource>());
  });

  test('una lectura que crece por encima del máximo se rechaza', () async {
    final read = await readStableFile(
      file,
      maxBytes: 8,
      readBytes: (_, int max) async => List.filled(max + 1, 0),
    );
    expect(read, isA<OversizedSource>());
  });

  test('el lector por defecto nunca devuelve más de un byte extra', () async {
    file.writeAsStringSync('x' * 1000);
    final bytes = await readBoundedBytes(file, 10);
    expect(bytes.length, 11);
  });

  test('un archivo ilegible es una fuente ilegible', () async {
    final read = await readStableFile(
      file,
      maxBytes: 64,
      readBytes: (_, _) async =>
          throw const FileSystemException('denegado', '/ruta/interna'),
    );
    expect(read, isA<UnreadableSource>());
  });
}
