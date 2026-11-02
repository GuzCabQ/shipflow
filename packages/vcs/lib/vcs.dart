/// vcs — el contexto del repositorio y las consultas Git acotadas.
library;

export 'src/bounded_git_process.dart' show GitBudget;
export 'src/git_context_probe.dart'
    show GitContextAdapter, resolveGitExecutable;
export 'src/git_observation.dart'
    show GitObservation, IgnoreMatch, SharingCheck;
export 'src/managed_exclude.dart';
export 'src/repository_context_inspector.dart' show inspectRepositoryContext;
