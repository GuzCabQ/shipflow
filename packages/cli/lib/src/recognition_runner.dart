import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'assessment/assessment_cli.dart';
import 'basis/basis_cli.dart';
import 'cli_application.dart';
import 'cli_command.dart';
import 'cli_response.dart';
import 'logical_root.dart';
import 'context/context_cli.dart';
import 'context/context_prompt.dart';
import 'context/state_ownership.dart';
import 'recognition_presenter.dart';

const _rootNotFound = 'root_not_found';
const _rootNotDirectory = 'root_not_directory';
const _rootInaccessible = 'root_inaccessible';

/// Lo que un plugin observa en una raíz canónica, dentro de [reportLimits].
/// Si no cabe, lanza [ReportLimitExceeded].
typedef RecognitionContributor =
    Future<RecognitionContribution> Function(
      Directory root, {
      required ReportLimits reportLimits,
      required List<AuthorizedOmission> authorizedOmissions,
    });

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
  GitContextAdapter? git,
  ContextPromptIO? prompt,
  AssessmentPlugin? assessment,
}) => runCommand(
  parseCliCommand(arguments),
  version: version,
  workingDirectory: workingDirectory,
  recognizeProject: recognizeProject,
  logicalRootHint: logicalRootHint,
  git: git,
  prompt: prompt,
  assessment: assessment,
);

Future<CliResponse> runCommand(
  CliCommand command, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
  GitContextAdapter? git,
  ContextPromptIO? prompt,
  AssessmentPlugin? assessment,
}) async => switch (command) {
  final StaticCommand static => respondStatically(static, version: version),
  final RunContext context => await runContextCommand(
    context,
    version: version,
    workingDirectory: workingDirectory,
    recognizeProject: recognizeProject,
    logicalRootHint: logicalRootHint,
    git: git,
    prompt: prompt,
  ),
  RunAssessment() || RunBootstrap() => await _stateCommand(
    command,
    version,
    workingDirectory,
    recognizeProject,
    (logicalRootHint: logicalRootHint, git: git, prompt: prompt),
    assessment,
  ),
  final RunInitDryRun dryRun => await _dryRun(
    dryRun,
    workingDirectory,
    recognizeProject,
    logicalRootHint,
  ),
};

/// Los comandos con estado propio fuera del contexto V2: assess y
/// bootstrap.
Future<CliResponse> _stateCommand(
  CliCommand command,
  String version,
  Directory workingDirectory,
  RecognitionContributor recognizeProject,
  ({String? logicalRootHint, GitContextAdapter? git, ContextPromptIO? prompt})
  optional,
  AssessmentPlugin? assessment,
) => switch (command) {
  final RunBootstrap run => runBootstrapCommand(
    run,
    version: version,
    workingDirectory: workingDirectory,
    prompt: optional.prompt,
  ),
  _ => runAssessmentCommand(
    command as RunAssessment,
    version: version,
    workingDirectory: workingDirectory,
    recognizeProject: recognizeProject,
    plugin: assessment,
    logicalRootHint: optional.logicalRootHint,
    git: optional.git,
  ),
};

/// `init --dry-run`: reconoce y presenta, sin escribir.
Future<CliResponse> _dryRun(
  RunInitDryRun command,
  Directory workingDirectory,
  RecognitionContributor recognizeProject,
  String? logicalRootHint,
) async => presentRecognition(
  await recognizeRoot(
    workingDirectory,
    recognizeProject,
    logicalRootHint: logicalRootHint,
    budgetProfile: command.budgetProfile,
  ),
  json: command.json,
  budgetProfile: command.budgetProfile,
);

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
///
/// Si la producción o el ensamblado exceden [budgetProfile], el inventario
/// se descarta por un reporte compacto; cualquier otro error sale tal cual.
///
/// El estado propio se omite sólo si [inspectStateOwnership] lo acredita,
/// salvo que quien llama ya lo haya decidido en [authorizedOmissions].
Future<RecognitionReport> recognizeRoot(
  Directory workingDirectory,
  RecognitionContributor recognizeProject, {
  String? logicalRootHint,
  ReportBudgetProfile budgetProfile = ReportBudgetProfile.standard,
  List<AuthorizedOmission>? authorizedOmissions,
}) async {
  final requested = _absolutePath(workingDirectory);
  final (:resolved, :problem) = await inspectableRoot(requested);
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
  return _recognizeWithin(
    root,
    requestedRoot: alias ?? requested,
    repository: await inspectRepositoryContext(root),
    recognizeProject: recognizeProject,
    budgetProfile: budgetProfile,
    authorizedOmissions:
        authorizedOmissions ??
        authorizedStateOmissions(await inspectStateOwnership(root)),
  );
}

/// Produce y ensambla dentro del perfil; si no cabe, el reporte compacto.
Future<RecognitionReport> _recognizeWithin(
  Directory root, {
  required String requestedRoot,
  required RepositoryContext repository,
  required RecognitionContributor recognizeProject,
  required ReportBudgetProfile budgetProfile,
  required List<AuthorizedOmission> authorizedOmissions,
}) async {
  final limits = reportLimitsOf(budgetProfile);
  try {
    return assembleRecognition(
      requestedRoot: requestedRoot,
      resolvedRoot: root.path,
      repository: repository,
      contributions: [
        await recognizeProject(
          root,
          reportLimits: limits,
          authorizedOmissions: authorizedOmissions,
        ),
      ],
      limits: limits,
    );
  } on ReportLimitExceeded catch (exceeded) {
    return reportLimitReached(
      requestedRoot: requestedRoot,
      resolvedRoot: root.path,
      repository: repository,
      dimension: exceeded.dimension,
      extended: budgetProfile == ReportBudgetProfile.extended,
    );
  }
}

/// [directory] absoluto, o tal cual si el sistema ya no puede nombrarlo.
String absolutePathOf(Directory directory) => _absolutePath(directory);

String _absolutePath(Directory directory) {
  try {
    return directory.absolute.path;
  } on FileSystemException {
    return directory.path;
  }
}

/// La ruta canónica de [requested], o la limitación que impide inspeccionarla.
Future<({String? resolved, RecognitionLimitation? problem})> inspectableRoot(
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
