import 'dart:io';

import 'package:core/core.dart';

import '../cli_command.dart';
import '../cli_response.dart';
import '../context/context_cli.dart';
import '../context/context_prompt.dart';
import '../context/secure_context_store.dart';
import '../context/state_layout.dart';
import '../recognition_runner.dart';
import 'basis_catalog.dart';
import 'basis_codec.dart';
import 'basis_preflight.dart';
import 'basis_presenter.dart';
import 'basis_prompt.dart';
import 'basis_reply.dart';
import 'basis_service.dart';
import 'basis_sources.dart';

/// Lee la entrada estándar una sola vez, hasta [maxBytes] + 1 bytes.
typedef BasisStdin = Future<List<int>> Function(int maxBytes);

/// Ejecuta `bootstrap`: resuelve la raíz como los demás comandos, ancla el
/// almacén, delega una vez en el servicio y presenta su respuesta. Sólo la
/// guía pregunta, y sólo en una terminal.
Future<CliResponse> runBootstrapCommand(
  RunBootstrap command, {
  required String version,
  required Directory workingDirectory,
  ContextPromptIO? prompt,
  BasisStdin? readStdin,
}) async {
  final requested = absolutePathOf(workingDirectory);
  final (:resolved, :problem) = await inspectableRoot(requested);
  if (resolved == null) {
    return _failed(command, 'input_unavailable', 'La raíz no se puede usar.');
  }
  final SecureContextStore store;
  try {
    store = await SecureContextStore.open(Directory(resolved));
  } on ContextStoreFailure {
    return _failed(command, 'io_error', null);
  }
  try {
    final service = _service(store, command.profile, version, resolved);
    final response = await _dispatch(
      command,
      service,
      prompt ?? const TerminalPromptIO(),
      readStdin ?? _stdin,
      requested,
    );
    return presentBasis(response, json: command.json, limits: service.limits);
  } finally {
    await store.close();
  }
}

BasisService _service(
  ContextStore store,
  BasisProfile profile,
  String version,
  String root,
) => BasisService(
  store: store,
  reader: BasisSourceReader(store),
  readProject: () => readBasisEnvironment(store),
  newId: newUuidV4,
  now: DateTime.now,
  limits: BasisLimits.forProfile(profile),
  version: version,
  observeLayout: () => observeStateLayout(Directory(root)),
);

Future<BasisResponse> _dispatch(
  RunBootstrap c,
  BasisService s,
  ContextPromptIO prompt,
  BasisStdin readStdin,
  String cwd,
) async => switch (c.operation) {
  BasisOperation.guide =>
    c.json || !prompt.interactive
        ? _choiceRequired()
        : await guideBasis(s, prompt),
  BasisOperation.show => await s.show(
    path: c.scope,
    history: c.history,
    draft: c.draft,
  ),
  BasisOperation.prepare => await _prepare(s, c.input!, readStdin, cwd),
  BasisOperation.accept => await s.accept(c.digest!),
  BasisOperation.discard => await s.discard(c.digest!),
  BasisOperation.recover => await s.recover(),
};

/// Sin terminal o con `--json` no se pregunta ni se crea un borrador.
BasisResponse _choiceRequired() =>
    (BasisReply(BasisOperation.guide)
          ..outcome = BasisOutcome.choiceRequired
          ..add('choice_required')
          ..addAction(showAction))
        .build();

/// Prepara desde un archivo o desde la entrada estándar, acotado por el
/// perfil antes de interpretar.
Future<BasisResponse> _prepare(
  BasisService s,
  String source,
  BasisStdin readStdin,
  String cwd,
) async {
  final bytes = await _read(source, s.limits.maxDraftBytes, readStdin, cwd);
  final reply = BasisReply(BasisOperation.prepare);
  if (bytes == null) {
    reply.add('input_unavailable', path: source == '-' ? null : source);
    return reply.build();
  }
  try {
    return await s.prepare(decodeBasisInput(bytes, limits: s.limits));
  } on ContextFormatException catch (e) {
    reply.add(e.code, path: e.at.isEmpty ? null : e.at);
    return reply.build();
  }
}

Future<List<int>?> _read(
  String source,
  int maxBytes,
  BasisStdin readStdin,
  String cwd,
) async {
  try {
    if (source == '-') return await readStdin(maxBytes);
    final file = File(source.startsWith('/') ? source : '$cwd/$source');
    if (FileSystemEntity.typeSync(file.path) != FileSystemEntityType.file) {
      return null;
    }
    final handle = await file.open();
    try {
      return await handle.read(maxBytes + 1);
    } finally {
      await handle.close();
    }
  } on FileSystemException {
    return null;
  }
}

Future<List<int>> _stdin(int maxBytes) async {
  final bytes = <int>[];
  await for (final chunk in stdin) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) break;
  }
  return bytes;
}

CliResponse _failed(RunBootstrap c, String code, String? message) {
  final reply = BasisReply(c.operation)..add(code, message: message);
  return presentBasis(
    reply.build(),
    json: c.json,
    limits: BasisLimits.forProfile(c.profile),
  );
}
