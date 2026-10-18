import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli/cli.dart';
import 'package:test/test.dart';
import 'static_evaluation.dart';

const failureDiagnostic = 'shipflow: no se pudo completar la operación.\n';

final class _Collector implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(bytes.addAll);

  @override
  Future<void> close() async {}
}

final class _Broken implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
    throw const FileSystemException('canal cerrado');
  }

  @override
  Future<void> close() async {}
}

({IOSink sink, _Collector collector}) collecting({Encoding encoding = utf8}) {
  final collector = _Collector();
  return (sink: IOSink(collector, encoding: encoding), collector: collector);
}

IOSink broken() => IOSink(_Broken());

void main() {
  test('una respuesta de stdout escribe sólo en stdout', () async {
    final out = collecting();
    final err = collecting();
    final code = await emitCliResponse(
      const CliResponse(
        exitCode: 0,
        channel: CliOutputChannel.stdout,
        payload: 'shipflow 1.0.0\n',
      ),
      standardOut: out.sink,
      standardError: err.sink,
    );
    expect(code, 0);
    expect(utf8.decode(out.collector.bytes), 'shipflow 1.0.0\n');
    expect(err.collector.bytes, isEmpty);
  });

  test('una respuesta de stderr escribe sólo en stderr', () async {
    final out = collecting();
    final err = collecting();
    final code = await emitCliResponse(
      evaluate(['--inventada'], version: '1.0.0'),
      standardOut: out.sink,
      standardError: err.sink,
    );
    expect(code, 64);
    expect(out.collector.bytes, isEmpty);
    expect(
      utf8.decode(err.collector.bytes),
      "shipflow: opción desconocida: '--inventada'\n"
      "Usa 'shipflow --help'.\n",
    );
  });

  test('un error JSON sale por stdout con código 64 y stderr vacío', () async {
    final out = collecting();
    final err = collecting();
    final code = await emitCliResponse(
      evaluate(['--json', '--inventada'], version: '1.0.0'),
      standardOut: out.sink,
      standardError: err.sink,
    );
    expect(code, 64);
    expect(const LineSplitter().convert(utf8.decode(out.collector.bytes)), [
      '{"schemaVersion":1,"type":"error","code":"invalid_usage",'
          '"message":"opción desconocida: \'--inventada\'","exitCode":64}',
    ]);
    expect(err.collector.bytes, isEmpty);
  });

  test('escribe UTF-8 aunque el sink tenga otra codificación', () async {
    final out = collecting(encoding: latin1);
    await emitCliResponse(
      evaluate(['--help'], version: '1.0.0'),
      standardOut: out.sink,
      standardError: collecting().sink,
    );
    expect(
      out.collector.bytes,
      utf8.encode(evaluate(['--help'], version: '1.0.0').payload),
    );
  });

  test('si stdout falla devuelve 70 y avisa por stderr', () async {
    final err = collecting();
    final code = await emitCliResponse(
      evaluate(['--json'], version: '1.0.0'),
      standardOut: broken(),
      standardError: err.sink,
    );
    expect(code, 70);
    expect(utf8.decode(err.collector.bytes), failureDiagnostic);
  });

  test('si stderr falla devuelve 70 y avisa por stdout', () async {
    final out = collecting();
    final code = await emitCliResponse(
      evaluate(['--inventada'], version: '1.0.0'),
      standardOut: out.sink,
      standardError: broken(),
    );
    expect(code, 70);
    expect(utf8.decode(out.collector.bytes), failureDiagnostic);
  });

  test('si fallan los dos canales devuelve 70 sin lanzar', () async {
    final code = await emitCliResponse(
      evaluate(['--version'], version: '1.0.0'),
      standardOut: broken(),
      standardError: broken(),
    );
    expect(code, 70);
  });

  test('sin declaración de compilación la versión es 0.0.0-dev', () {
    expect(buildVersion, '0.0.0-dev');
  });
}
