import 'dart:convert';
import 'dart:io';

import 'package:cli/src/basis/basis_codec.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import '../init_process_support.dart';
import 'basis_service_support.dart';

/// La base recorrida con el ejecutable compilado: cada paso es otro
/// proceso, con la entrada desde /dev/null, y su respuesta JSON pasa por el
/// codec estricto.
final class BasisWalk {
  BasisWalk(this.process);

  final InitProcessSandbox process;
  final limits = BasisLimits.forProfile(BasisProfile.standard);
  var _inputs = 0;

  File get basis => File('${process.root.path}/shipflow/basis.json');

  String get projectId =>
      (jsonDecode(
                File(
                  '${process.root.path}/shipflow/project.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>)['projectId']!
          as String;

  BasisDocument get document =>
      decodeBasis(basis.readAsBytesSync(), limits: limits);

  /// [arguments] sin terminal: la entrada es /dev/null, como en un script.
  Future<RunResult> raw(List<String> arguments) async {
    final result = await Process.run(
      '/bin/sh',
      ['-c', r'"$0" "$@" </dev/null', process.binary, ...arguments],
      workingDirectory: process.root.path,
      environment: {'HOME': process.home.path, 'TMPDIR': process.temp.path},
      includeParentEnvironment: false,
    );
    return RunResult(
      result.exitCode,
      result.stdout as String,
      result.stderr as String,
    );
  }

  /// `bootstrap [arguments] --json`; la respuesta es una sola línea válida
  /// cuyo exitCode es el del proceso.
  Future<BasisResponse> bootstrap(List<String> arguments) async =>
      decoded(await raw(['bootstrap', ...arguments, '--json']));

  BasisResponse decoded(RunResult run) {
    expect(run.stderr, isEmpty);
    expect(run.stdout.split('\n'), hasLength(2), reason: run.stdout);
    final response = decodeBasisResponse(
      utf8.encode(run.stdout),
      limits: limits,
    );
    expect(response.exitCode, run.exitCode);
    return response;
  }

  /// La propuesta de [changes] sobre la base actual, escrita fuera del
  /// proyecto.
  String inputFile(List<BasisChange> changes, {BasisActor? actor}) {
    final file = File('${process.temp.path}/entrada-${++_inputs}.json');
    file.writeAsBytesSync(encodeBasisInput(inputOf(changes, actor: actor)));
    return file.path;
  }

  BasisInput inputOf(List<BasisChange> changes, {BasisActor? actor}) =>
      BasisInput(
        projectId: projectId,
        expectedBasisDigest: basis.existsSync() ? document.digest : null,
        actor: actor ?? actorOf(),
        reason: 'Propuesta de aceptación.',
        changes: changes,
      );

  Future<BasisResponse> prepare(
    List<BasisChange> changes, {
    BasisActor? actor,
  }) => bootstrap(['--input', inputFile(changes, actor: actor)]);

  /// Prepara en un proceso y acepta la huella exacta en otro.
  Future<BasisResponse> publish(
    List<BasisChange> changes, {
    BasisActor? actor,
  }) async {
    final prepared = await prepare(changes, actor: actor);
    expect(prepared.outcome, BasisOutcome.draftPrepared, reason: '$prepared');
    final accepted = await bootstrap(['--accept', prepared.draftDigest!]);
    expect(accepted.published, isTrue, reason: codesOf(accepted).join());
    return accepted;
  }

  /// La versión actual del registro titulado [title].
  BasisRecordVersion current(String title) =>
      replayBasis(document).values.singleWhere((v) => v.payload.title == title);
}

/// Una forma de proyecto de la aceptación: sus archivos, la fuente de
/// gobierno, una parte con decisiones propias y otra ajena a ellas.
typedef ProjectShape = ({
  String name,
  Map<String, String> files,
  String source,
  String area,
  String other,
});

const flutterMinimal = (
  name: 'Flutter mínimo',
  files: {
    'pubspec.yaml':
        'name: minimo\nenvironment:\n  sdk: ^3.6.0\n'
        'dependencies:\n  flutter:\n    sdk: flutter\n',
    'lib/main.dart':
        "import 'package:flutter/material.dart';\n\n"
        'void main() => runApp(const MaterialApp());\n',
    'test/widget_test.dart': 'void main() {}\n',
    'docs/politica.md': 'Los contratos públicos se revisan.\n',
  },
  source: 'docs/politica.md',
  area: 'lib',
  other: 'test',
);

const dartPackage = (
  name: 'paquete Dart',
  files: {
    'pubspec.yaml': 'name: paquete\nenvironment:\n  sdk: ^3.6.0\n',
    'lib/paquete.dart': "export 'src/api.dart';\n",
    'lib/src/api.dart': 'class Api {}\n',
    'bin/paquete.dart': 'void main() {}\n',
    'docs/politica.md': 'Los contratos públicos se revisan.\n',
  },
  source: 'docs/politica.md',
  area: 'lib/src',
  other: 'bin',
);

/// Otra organización: aplicaciones y servicios en carpetas propias, con la
/// documentación de gobierno fuera de cualquier paquete.
const independentLayout = (
  name: 'organización independiente',
  files: {
    'pubspec.yaml': 'name: plataforma\nenvironment:\n  sdk: ^3.6.0\n',
    'apps/movil/pubspec.yaml': 'name: movil\n',
    'apps/movil/lib/main.dart': 'void main() {}\n',
    'services/pagos/pubspec.yaml': 'name: pagos\n',
    'services/pagos/lib/cobro.dart': 'class Cobro {}\n',
    'gobierno/docs/politica.md': 'Los contratos públicos se revisan.\n',
  },
  source: 'gobierno/docs/politica.md',
  area: 'services/pagos',
  other: 'apps/movil',
);
