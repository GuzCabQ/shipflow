import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import '../cli_command.dart';
import '../cli_response.dart';
import '../recognition_runner.dart';
import 'context_codec.dart';
import 'context_decisions.dart';
import 'context_presenter.dart';
import 'context_prompt.dart';
import 'context_request.dart';
import 'context_result.dart';
import 'context_service.dart';
import 'secure_context_store.dart';

/// Ejecuta un comando de contexto: resuelve la raíz como el reconocimiento,
/// ancla el almacén, delega una vez en el servicio y presenta su resultado.
/// Sólo pregunta en una terminal y nunca con `--json`.
Future<CliResponse> runContextCommand(
  RunContext command, {
  required String version,
  required Directory workingDirectory,
  required RecognitionContributor recognizeProject,
  String? logicalRootHint,
  GitContextAdapter? git,
  ContextPromptIO? prompt,
}) async {
  final requested = absolutePathOf(workingDirectory);
  final (:resolved, :problem) = await inspectableRoot(requested);
  if (resolved == null) {
    return _failed(command, requested, 'invalid_root', problem!.message);
  }
  final root = Directory(resolved);
  final SecureContextStore store;
  try {
    store = await SecureContextStore.open(root);
  } on ContextStoreFailure catch (failure) {
    return _failed(command, resolved, 'io_failure', failure.code);
  }
  try {
    final result = await contextServiceFor(
      root,
      store,
      version: version,
      recognizeProject: recognizeProject,
      logicalRootHint: logicalRootHint,
      git: git,
    ).run(_request(command, prompt ?? const TerminalPromptIO()));
    return presentContext(result, json: command.json, root: resolved);
  } finally {
    await store.close();
  }
}

/// El servicio de contexto de [root] como lo compone el CLI.
ProjectContextService contextServiceFor(
  Directory root,
  ContextStore store, {
  required String version,
  required RecognitionContributor recognizeProject,
  required String? logicalRootHint,
  required GitContextAdapter? git,
}) => ProjectContextService(
  root: root,
  store: store,
  git: git ?? GitContextAdapter(),
  recognize: (profile, omissions) => recognizeRoot(
    root,
    recognizeProject,
    logicalRootHint: logicalRootHint,
    budgetProfile: profile,
    authorizedOmissions: omissions,
  ),
  codec: const ContextCodec(),
  version: version,
  now: DateTime.now,
  newId: newUuidV4,
);

ContextRequest _request(RunContext command, ContextPromptIO io) =>
    ContextRequest(
      operation: operationOf(command),
      sharing: switch (command) {
        RunInit(:final sharing) || RunInitRefresh(:final sharing) => sharing,
        _ => null,
      },
      profile: command.budgetProfile,
      choose: !command.json && io.interactive
          ? (question) => askSharing(io, question)
          : null,
    );

ContextOperation operationOf(RunContext command) => switch (command) {
  RunInit() => ContextOperation.init,
  RunInitRefresh() => ContextOperation.refresh,
  RunInitRecover() => ContextOperation.recover,
  RunDoctor() => ContextOperation.doctor,
};

/// Un resultado sin inspección: la raíz no se puede usar o el almacén no
/// se pudo anclar.
CliResponse _failed(
  RunContext command,
  String root,
  String code,
  String message,
) {
  final parts = ResultParts(
    command: command is RunDoctor ? ContextCommand.doctor : ContextCommand.init,
    operation: operationOf(command),
    state: ContextState.absent,
    freshness: ContextFreshness.notApplicable,
    sharing: const ContextSharing(
      choice: SharingChoice.pending,
      gitState: GitState.notChecked,
      effective: SharingEffective.unverified,
    ),
  )..diagnostics.add(diagnostic(code, message));
  return presentContext(
    resultOf(parts, EffectsLog().freeze(0)),
    json: command.json,
    root: root,
  );
}

/// Un UUID v4 aleatorio: opaco, sin identidad personal ni ruta.
String newUuidV4() {
  final random = Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = [
    for (final b in bytes) b.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
