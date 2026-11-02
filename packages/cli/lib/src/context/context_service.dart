import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_codec.dart';
import 'context_doctor.dart';
import 'context_init.dart';
import 'context_observation.dart';
import 'context_recovery.dart';
import 'context_request.dart';
import 'secure_context_store.dart';

/// Compone reconocer, leer, decidir, publicar y presentar para una raíz ya
/// resuelta. Cada operación observa una vez, decide antes de cualquier
/// efecto y devuelve un único resultado, del que salen humano y JSON.
final class ProjectContextService {
  ProjectContextService({
    required this.root,
    required this.store,
    required this.git,
    required this.recognize,
    required this.codec,
    required this.version,
    required this.now,
    required this.newId,
    Future<ContextStore> Function(Directory)? openAdministration,
  }) : openAdministration = openAdministration ?? SecureContextStore.open;

  final Directory root;
  final ContextStore store;
  final GitContextAdapter git;
  final ContextRecognizer recognize;
  final ContextCodec codec;
  final String version;
  final DateTime Function() now;
  final String Function() newId;

  /// Ancla el directorio de administración Git que contiene el exclude.
  final Future<ContextStore> Function(Directory) openAdministration;

  Future<ContextOperationResult> run(ContextRequest request) async {
    final budget = GitBudget();
    final o = await observeContext(
      root: root,
      store: store,
      git: git,
      budget: budget,
      recognize: recognize,
      profile: request.profile,
    );
    return switch (request.operation) {
      ContextOperation.doctor => runDoctor(o, git, budget),
      ContextOperation.recover => recoverContext(
        o: o,
        store: store,
        git: git,
        budget: budget,
        openAdministration: openAdministration,
      ),
      ContextOperation.init || ContextOperation.refresh => InitSession(
        service: this,
        o: o,
        request: request,
        budget: budget,
      ).run(),
    };
  }
}
