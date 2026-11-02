import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

import 'bounded_git_process.dart';
import 'git_observation.dart';
import 'repository_context_inspector.dart';

const _revParse = [
  'rev-parse',
  '--path-format=absolute',
  '--show-toplevel',
  '--git-dir',
  '--git-common-dir',
  '--git-path',
  'info/exclude',
  '--show-prefix',
];

/// Las consultas Git de V2: versión, `rev-parse`, `ls-files` y
/// `check-ignore` sobre las rutas propias. Nunca escribe, no ejecuta hooks
/// ni comandos de red, y no corre un binario hallado dentro del proyecto.
///
/// [parentEnvironment] es el entorno del proceso; por omisión, el real. Del
/// hijo sólo llega lo que `entornoSaneado` deja pasar.
final class GitContextAdapter {
  GitContextAdapter({
    Map<String, String>? parentEnvironment,
    this.perProcess = const Duration(seconds: 5),
  }) : parentEnvironment = parentEnvironment ?? Platform.environment;

  final Map<String, String> parentEnvironment;
  final Duration perProcess;

  /// Qué es Git para [root], con lo observado de [ownPaths].
  Future<GitObservation> observe(
    Directory root, {
    required List<String> ownPaths,
    GitBudget? budget,
  }) async {
    GitObservation stop(GitState state, int started, [String? code]) =>
        GitObservation(
          root: root,
          ownPaths: ownPaths,
          state: state,
          processesStarted: started,
          code: code,
        );
    final git = _process(root, budget ?? GitBudget());
    if (git == null) return stop(GitState.notInstalled, 0);
    final version = await git.run(['--version'], cwd: root);
    if (version.cut ?? _notGit(version) case final code?) {
      return stop(GitState.unavailable, git.budget.started, code);
    }
    final revParse = await git.run(_revParse, cwd: root);
    final (state, code) = await _classify(revParse, root);
    if (state != null) return stop(state, git.budget.started, code);
    return _repository(git, root, ownPaths, parseRevParse(revParse.stdout));
  }

  /// [choice] contra lo que Git dice ahora de las rutas propias; vuelve a
  /// consultar, no reutiliza lo observado.
  Future<SharingCheck> verifySharing(
    GitObservation observation,
    SharingChoice choice, {
    GitBudget? budget,
  }) async {
    if (choice == SharingChoice.pending) {
      return const SharingCheck(SharingEffective.pending);
    }
    if (observation.state != GitState.available) {
      return SharingCheck(SharingEffective.unverified, code: observation.code);
    }
    final now = await observe(
      observation.root,
      ownPaths: observation.ownPaths,
      budget: budget,
    );
    if (now.state != GitState.available) {
      return SharingCheck(SharingEffective.unverified, code: now.code);
    }
    return choice == SharingChoice.share ? _share(now) : _local(now);
  }

  BoundedGitProcess? _process(Directory root, GitBudget budget) {
    final executable = resolveGitExecutable(
      parentEnvironment['PATH'],
      root.path,
    );
    if (executable == null) return null;
    return BoundedGitProcess(
      executable: executable,
      parentEnvironment: parentEnvironment,
      budget: budget,
      perProcess: perProcess,
    );
  }

  Future<GitObservation> _repository(
    BoundedGitProcess git,
    Directory root,
    List<String> ownPaths,
    RevParsePaths? paths,
  ) async {
    GitObservation unavailable(String code) => GitObservation(
      root: root,
      ownPaths: ownPaths,
      state: GitState.unavailable,
      processesStarted: git.budget.started,
      code: code,
    );
    if (paths == null) return unavailable('path_not_representable');
    if (_join(paths.top, paths.prefix) != root.path) {
      return unavailable('git_root_mismatch');
    }
    final (:tracked, :ignored, :cut) = await _ownPathQueries(
      git,
      root,
      ownPaths,
    );
    if (cut != null) return unavailable(cut);
    return _available(git, root, ownPaths, paths, tracked, ignored);
  }
}

/// Lo observado de un worktree utilizable.
GitObservation _available(
  BoundedGitProcess git,
  Directory root,
  List<String> ownPaths,
  RevParsePaths paths,
  List<String> tracked,
  List<int> ignored,
) => GitObservation(
  root: root,
  ownPaths: ownPaths,
  state: GitState.available,
  processesStarted: git.budget.started,
  binding: GitBinding(
    repositoryRoot: paths.top,
    gitDir: paths.gitDir,
    commonDir: paths.commonDir,
    prefix: paths.prefix,
  ),
  excludePath: paths.exclude,
  tracked: tracked,
  matches: parseCheckIgnore(ignored, paths.top),
);

/// Qué rutas propias sigue Git y qué reglas las alcanzan; [cut] si una de
/// las dos consultas no terminó bien.
Future<({List<String> tracked, List<int> ignored, String? cut})>
_ownPathQueries(
  BoundedGitProcess git,
  Directory root,
  List<String> ownPaths,
) async {
  final tracked = await git.run([
    '--literal-pathspecs',
    'ls-files',
    '-z',
    '--',
    ...ownPaths,
  ], cwd: root);
  final ignored = await git.run(
    ['check-ignore', '-v', '-n', '-z', '--no-index', '--stdin'],
    cwd: root,
    input: utf8.encode(ownPaths.map((p) => '$p\u0000').join()),
  );
  final failed = tracked.exitCode != 0 || ignored.exitCode > 1;
  return (
    tracked: parseNulList(tracked.stdout),
    ignored: ignored.stdout,
    cut: tracked.cut ?? ignored.cut ?? (failed ? 'git_failed' : null),
  );
}

/// El estado si `rev-parse` no describe un worktree utilizable, o null.
/// Un repositorio cuyos metadatos existen pero Git rechaza es un error, no
/// una ausencia.
Future<(GitState?, String?)> _classify(
  GitCommandResult result,
  Directory root,
) async {
  if (result.cut case final cut?) return (GitState.unavailable, cut);
  if (result.exitCode == 0) return (null, null);
  final message = utf8.decode(result.stderr, allowMalformed: true);
  if (message.contains('dubious ownership')) {
    return (GitState.unavailable, 'git_dubious_ownership');
  }
  if (!message.contains('not a git repository')) {
    return (GitState.unavailable, 'git_failed');
  }
  final metadata = await inspectRepositoryContext(root);
  return metadata.status == RepositoryStatus.absent
      ? (GitState.notRepository, null)
      : (GitState.unavailable, 'git_repository_damaged');
}

String? _notGit(GitCommandResult version) =>
    version.exitCode == 0 &&
        utf8.decode(version.stdout, allowMalformed: true).startsWith('git ')
    ? null
    : 'git_failed';

String _join(String top, String prefix) =>
    prefix.isEmpty ? top : '$top/${prefix.substring(0, prefix.length - 1)}';

SharingCheck _share(GitObservation now) {
  for (final path in now.ownPaths) {
    if (now.tracked.contains(path)) continue;
    if (now.ignoredBy[path] case final rule?) {
      return SharingCheck(
        SharingEffective.conflict,
        code: 'ignored_by_rule',
        rule: rule,
      );
    }
  }
  return const SharingCheck(SharingEffective.shareReady);
}

SharingCheck _local(GitObservation now) {
  if (now.tracked.isNotEmpty) {
    return const SharingCheck(
      SharingEffective.conflict,
      code: 'already_tracked',
    );
  }
  for (final path in now.ownPaths) {
    if (now.ignoredBy[path] == null) {
      return SharingCheck(
        SharingEffective.conflict,
        code: 'not_excluded',
        rule: now.matches[path],
      );
    }
  }
  return const SharingCheck(SharingEffective.localExcluded);
}

/// El primer `git` ejecutable de las entradas absolutas de [path] que no
/// estén dentro de [projectRoot], con sus enlaces resueltos; null si no hay.
/// Una entrada vacía o relativa se salta: la decidiría el directorio actual.
String? resolveGitExecutable(String? path, String projectRoot) {
  bool inside(String p) => p == projectRoot || p.startsWith('$projectRoot/');
  for (final entry in (path ?? '').split(':')) {
    if (!entry.startsWith('/') || inside(entry)) continue;
    final candidate = File('$entry/git');
    try {
      final resolved = candidate.resolveSymbolicLinksSync();
      final stat = File(resolved).statSync();
      if (stat.type == FileSystemEntityType.file &&
          stat.mode & 73 != 0 &&
          !inside(resolved)) {
        return resolved;
      }
    } on FileSystemException {
      continue;
    }
  }
  return null;
}
