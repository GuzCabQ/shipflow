import 'dart:io';

import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_init.dart';
import 'context_observation.dart';
import 'context_publication_plan.dart';
import 'context_sharing_choice.dart';
import 'context_transaction_runner.dart';
import 'state_layout.dart';
import 'state_ownership.dart';

/// Lo que una invocación de init decidió publicar.
typedef PublishRequest = ({
  String projectId,
  int revision,
  PortableRecognition? current,
  SharingChoice choice,
  TransactionOperation operation,
  ContextOutcome success,
  bool keepSharing,
});

/// Publica [r] para [s], o sólo informa la modalidad si no hay nada que
/// cambiar. Sin `--sharing`, `keepSharing` deja configuración y exclude
/// tal cual.
Future<void> publishFor(InitSession s, PublishRequest r) async {
  final o = s.o;
  final exclude = r.keepSharing
      ? null
      : await excludeChangeFor(o, r.choice, s.service.openAdministration);
  if (exclude?.patch.problem case final problem?) {
    s.parts.diagnostics.add(excludeProblem(problem));
    return;
  }
  final plan = _planFor(s, r, exclude);
  if (plan == null) return s.reportSharing();
  await _run(s, plan, r.success);
}

PublicationPlan? _planFor(InitSession s, PublishRequest r, ExcludeChange? e) {
  final o = s.o;
  final project = _candidate(s, r);
  final settings = r.keepSharing
      ? null
      : settingsFor(r.projectId, r.choice, o.git, e);
  final unchanged =
      project == null &&
      !(e?.patch.changed ?? false) &&
      (settings == null || sameBytes(o.settings, settingsBytes(settings)));
  return unchanged
      ? null
      : PublicationPlan(
          operationId: s.service.newId(),
          operation: r.operation,
          projectId: r.projectId,
          choice: r.choice,
          settings: settings,
          observed: o,
          project: project,
          exclude: e,
        );
}

ProjectContext? _candidate(InitSession s, PublishRequest r) {
  final current = r.current;
  return current == null
      ? null
      : candidateFor(
          projectId: r.projectId,
          revision: r.revision,
          version: s.service.version,
          current: current,
          pluginIds: s.o.report.proposal.pluginIds,
          now: s.service.now(),
        );
}

Future<void> _run(
  InitSession s,
  PublicationPlan plan,
  ContextOutcome ok,
) async {
  final o = s.o;
  final result = await runTransaction(
    plan: plan,
    store: s.service.store,
    git: s.service.git,
    budget: s.budget,
    effects: s.effects,
    sourcesUnchanged: () => _sourcesUnchanged(s, plan.project),
  );
  s.parts.diagnostics.addAll(result.diagnostics);
  if (result.journalLeft) s.parts.state = ContextState.recoveryRequired;
  if (!result.ok) return;
  s.parts
    ..state = ContextState.present
    ..freshness = ContextFreshness.current
    ..context = plan.project?.recognition ?? o.project.value?.recognition
    ..success = ok
    ..sharing = ContextSharing(
      choice: plan.choice,
      gitState: o.git.state,
      effective: result.sharing ?? SharingEffective.pending,
    );
  if (!o.gitUsable) s.parts.diagnostics.add(gitWarning(o.git));
}

/// Si el reconocimiento, repetido bajo el lease, sigue dando [candidate].
Future<bool> _sourcesUnchanged(InitSession s, ProjectContext? candidate) async {
  if (candidate == null) return true;
  final report = await s.service.recognize(
    s.request.profile,
    authorizedStateOmissions(await inspectStateOwnership(s.service.root)),
  );
  try {
    return digestOf(projectRecognition(report)) == candidate.observationDigest;
  } on ContextFormatException {
    return false;
  }
}

/// Un `shipflow/project.json` en una carpeta superior de la misma raíz Git,
/// sólo por metadatos y sin pasar del toplevel. Sin Git no se busca: no hay
/// un proyecto que acote la búsqueda.
String? ancestorContext(Directory root, GitObservation git) {
  final top = git.binding?.repositoryRoot;
  if (top == null || root.path == top || !root.path.startsWith('$top/')) {
    return null;
  }
  var dir = root.parent;
  while (dir.path.length >= top.length) {
    final candidate = '${dir.path}/$projectPath';
    if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
        FileSystemEntityType.file) {
      return candidate;
    }
    if (dir.path == top) break;
    dir = dir.parent;
  }
  return null;
}
