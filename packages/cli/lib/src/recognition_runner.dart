import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'cli_application.dart';
import 'cli_command.dart';
import 'cli_response.dart';
import 'logical_root.dart';
import 'recognition_presenter.dart';

const _rootNotFound = 'root_not_found';
const _rootNotDirectory = 'root_not_directory';
const _rootInaccessible = 'root_inaccessible';

/// Lo que un plugin observa en una raíz canónica.
typedef RecognitionContributor =
    Future<RecognitionContribution> Function(Directory root);

/// Responde [arguments]. Un fallo de programación sale tal cual, con su
/// objeto y su traza: traducirlo es trabajo de la frontera del proceso.
///
/// [logicalRootHint] es la ruta lógica que el entorno dice tener, como
/// `PWD`; sólo se muestra si resuelve a la misma carpeta real.
Future<CliResponse> runCli(
  List<String> arguments, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
}) => runCommand(
  parseCliCommand(arguments),
  version: version,
  workingDirectory: workingDirectory,
  recognizeProject: recognizeProject,
  logicalRootHint: logicalRootHint,
);

Future<CliResponse> runCommand(
  CliCommand command, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
}) async => switch (command) {
  final StaticCommand static => respondStatically(static, version: version),
  RunInitDryRun(:final json) => presentRecognition(
    await recognizeRoot(
      workingDirectory,
      recognizeProject,
      logicalRootHint: logicalRootHint,
    ),
    json: json,
  ),
};

/// El directorio actual, o `.` si el sistema ya no puede nombrarlo: entonces
/// la raíz se informa inválida en vez de hacer caer al proceso.
Directory currentWorkingDirectory() {
  try {
    return Directory.current;
  } on FileSystemException {
    return Directory('.');
  }
}

/// Resuelve la raíz, observa su repositorio, la entrega al plugin una vez y
/// agrega el resultado una vez. Una raíz que no se puede inspeccionar no
/// llega al plugin, y [logicalRootHint] no la rescata: la pista se corrobora
/// sólo después, contra la raíz ya resuelta, y sólo cambia lo que se muestra.
Future<RecognitionReport> recognizeRoot(
  Directory workingDirectory,
  RecognitionContributor recognizeProject, {
  String? logicalRootHint,
}) async {
  final requested = _absolutePath(workingDirectory);
  final (:resolved, :problem) = await _inspectableRoot(requested);
  if (problem != null) {
    return RecognitionReport.invalidRoot(
      requestedRoot: requested,
      reason: problem,
    );
  }
  final root = Directory(resolved!);
  final alias = await corroborateLogicalRoot(
    logicalRootHint,
    canonicalRoot: root.path,
  );
  return assembleRecognition(
    requestedRoot: alias ?? requested,
    resolvedRoot: root.path,
    repository: await inspectRepositoryContext(root),
    contributions: [await recognizeProject(root)],
  );
}

String _absolutePath(Directory directory) {
  try {
    return directory.absolute.path;
  } on FileSystemException {
    return directory.path;
  }
}

/// La ruta canónica de [requested], o la limitación que impide inspeccionarla.
Future<({String? resolved, RecognitionLimitation? problem})> _inspectableRoot(
  String requested,
) async {
  if (_typeProblem(requested) case final problem?) {
    return (resolved: null, problem: problem);
  }
  try {
    final resolved = Directory(requested).resolveSymbolicLinksSync();
    await Directory(resolved).list(followLinks: false).isEmpty;
    return (resolved: resolved, problem: null);
  } on FileSystemException catch (error) {
    return (
      resolved: null,
      problem: _rootProblem(
        _rootInaccessible,
        'la raíz no se puede leer (${error.osError?.message ?? error.message})',
      ),
    );
  }
}

RecognitionLimitation? _typeProblem(String requested) =>
    switch (FileSystemEntity.typeSync(requested)) {
      FileSystemEntityType.directory => null,
      FileSystemEntityType.notFound => _rootProblem(
        _rootNotFound,
        'la raíz no existe',
      ),
      _ => _rootProblem(_rootNotDirectory, 'la raíz no es un directorio'),
    };

RecognitionLimitation _rootProblem(String code, String message) =>
    RecognitionLimitation(
      code: code,
      message: message,
      path: null,
      blocking: true,
    );
