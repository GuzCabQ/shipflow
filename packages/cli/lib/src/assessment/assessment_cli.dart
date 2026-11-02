import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import '../cli_command.dart';
import '../cli_response.dart';
import '../context/context_cli.dart';
import '../context/context_request.dart';
import '../context/secure_context_store.dart';
import '../recognition_runner.dart';
import 'assessment_draft.dart';
import 'assessment_presenter.dart';
import 'assessment_service.dart';

/// Lo que el plugin aporta a assess, entregado por la raíz de composición:
/// el CLI no conoce extensiones, manifiestos ni el parser del stack.
typedef AssessmentPlugin = ({
  AssessmentObserver observe,
  AssessmentInputObserver observeInputs,
  ContextBasisProjector basisOf,
  AssessmentProducerInfo producer,
});

/// Ejecuta `assess`: resuelve la raíz como el reconocimiento, ancla el
/// almacén, delega una vez en el servicio y presenta su resultado. Nunca
/// pregunta.
Future<CliResponse> runAssessmentCommand(
  RunAssessment command, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  required AssessmentPlugin? plugin,
  String? logicalRootHint,
  GitContextAdapter? git,
}) async {
  final requested = absolutePathOf(workingDirectory);
  if (plugin == null) return _failed(command, requested, 'unexpected');
  final (:resolved, :problem) = await inspectableRoot(requested);
  if (resolved == null) return _failed(command, requested, 'invalid_root');
  final root = Directory(resolved);
  final SecureContextStore store;
  try {
    store = await SecureContextStore.open(root);
  } on ContextStoreFailure {
    return _failed(command, resolved, 'io_failure');
  }
  try {
    final result = await _service(
      root,
      store,
      version: version,
      recognizeProject: recognizeProject,
      plugin: plugin,
      logicalRootHint: logicalRootHint,
      git: git,
    ).run(_request(command));
    return presentAssessment(result, json: command.json, root: resolved);
  } finally {
    await store.close();
  }
}

AssessmentService _service(
  Directory root,
  ContextStore store, {
  required String version,
  required RecognitionContributor recognizeProject,
  required AssessmentPlugin plugin,
  required String? logicalRootHint,
  required GitContextAdapter? git,
}) {
  final context = contextServiceFor(
    root,
    store,
    version: version,
    recognizeProject: recognizeProject,
    logicalRootHint: logicalRootHint,
    git: git,
  );
  return AssessmentService(
    root: root,
    store: store,
    observe: plugin.observe,
    observeInputs: plugin.observeInputs,
    basisOf: plugin.basisOf,
    producer: plugin.producer,
    doctor: (profile) => context.run(
      ContextRequest(
        operation: ContextOperation.doctor,
        profile: _budgetOf(profile),
      ),
    ),
    version: version,
    now: DateTime.now,
    newId: newUuidV4,
  );
}

AssessmentRequest _request(RunAssessment command) => AssessmentRequest(
  operation: command.action,
  previous: command.previous,
  profile: command.budgetProfile == ReportBudgetProfile.extended
      ? AssessmentProfile.extended
      : AssessmentProfile.standard,
);

ReportBudgetProfile _budgetOf(AssessmentProfile profile) =>
    profile == AssessmentProfile.extended
    ? ReportBudgetProfile.extended
    : ReportBudgetProfile.standard;

/// Un resultado sin inspección: la raíz no se puede usar o el almacén no
/// se pudo anclar.
CliResponse _failed(RunAssessment command, String root, String code) {
  final draft = AssessmentDraft(command.action)..add(code);
  return presentAssessment(draft.build(), json: command.json, root: root);
}
