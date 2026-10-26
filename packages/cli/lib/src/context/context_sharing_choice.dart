import 'package:core/core.dart';
import 'package:vcs/vcs.dart';

import 'context_assessment.dart';
import 'context_decisions.dart';
import 'context_observation.dart';
import 'context_request.dart';
import 'context_result.dart';

/// La elección de conservación de esta invocación: el flag, la guardada, o
/// la que se pregunte en una terminal. Null si ya se decidió el resultado:
/// elección requerida sin terminal, cancelación o elección imposible.
Future<SharingChoice?> chooseSharing(
  ObservedContext o,
  ContextRequest request,
  ResultParts parts,
) async {
  final explicit = request.sharing;
  if (!o.gitUsable) {
    if (explicit == null) return SharingChoice.pending;
    parts.diagnostics.add(
      diagnostic(
        'sharing_unavailable',
        'Sin Git utilizable no hay elección que aplicar; no se escribió nada.',
      ),
    );
    return null;
  }
  return explicit ?? _ask(o, request, parts);
}

/// Pregunta en la terminal, o pide la elección por flag si no la hay.
Future<SharingChoice?> _ask(
  ObservedContext o,
  ContextRequest request,
  ResultParts parts,
) async {
  final ask = request.choose;
  if (ask == null) {
    parts.diagnostics.add(
      diagnostic(
        'choice_required',
        'Hay que elegir cómo conservar el contexto; sin terminal no se '
            'pregunta.',
      ),
    );
    return null;
  }
  final chosen = await ask(
    SharingQuestion(
      stacks: [for (final c in o.report.candidates) c.displayName],
      units: o.report.units.length,
      sharedExclude: o.git.linkedWorktree,
    ),
  );
  if (chosen == null) parts.cancelled = true;
  return chosen;
}

/// Lo que impide [choice] según lo observado, sin escribir: un archivo ya
/// seguido para local, una regla ajena que lo ignora para share.
bool precheckSharing(
  ObservedContext o,
  SharingChoice choice,
  ResultParts parts,
) {
  if (choice == SharingChoice.pending || !o.gitUsable) return true;
  if (choice == SharingChoice.local && o.git.tracked.isNotEmpty) {
    parts.diagnostics.add(
      sharingConflict(
        const SharingCheck(SharingEffective.conflict, code: 'already_tracked'),
      ),
    );
    return false;
  }
  if (choice == SharingChoice.share) {
    for (final path in ownSharedPaths) {
      if (o.git.tracked.contains(path)) continue;
      final rule = o.git.ignoredBy[path];
      if (rule != null && !_ownBlock(o, rule)) {
        parts.diagnostics.add(
          sharingConflict(
            SharingCheck(
              SharingEffective.conflict,
              code: 'ignored_by_rule',
              rule: rule,
            ),
          ),
        );
        return false;
      }
    }
  }
  return true;
}

/// Si [rule] es el bloque propio de esta raíz en el exclude local, que el
/// cambio a share retira.
bool _ownBlock(ObservedContext o, IgnoreMatch rule) {
  final prefix = o.git.binding?.prefix;
  final saved = o.settings.value?.managedExclude;
  return prefix != null &&
      saved != null &&
      rule.source == o.git.excludePath &&
      rule.pattern == excludePattern(prefix);
}

ContextDiagnostic excludeProblem(String problem) => diagnostic(
  'sharing_conflict',
  switch (problem) {
    'path_not_representable' =>
      'La ruta del proyecto no se puede expresar sin ambigüedad en una regla '
          'de exclusión; elige compartir.',
    'exclude_unsafe' =>
      'El exclude local de Git es un enlace o está fuera de la administración '
          'del repositorio; no se sigue ni se modifica. Elige compartir o '
          'reemplázalo por un archivo.',
    'exclude_too_large' =>
      'El exclude local supera el máximo admitido; no se modifica.',
    _ =>
      'El bloque propio del exclude está dañado o repetido; no se repara a '
          'ciegas.',
  },
);

/// El aviso de un registro guardado sin Git utilizable.
ContextDiagnostic gitWarning(GitObservation git) =>
    git.state == GitState.unavailable
    ? diagnostic(
        'git_unverified',
        'No se pudo consultar Git (${git.code ?? 'error'}); el contexto quedó '
            'local con la elección pendiente.',
      )
    : diagnostic(
        'git_absent',
        'Sin Git o sin repositorio: el contexto sirve en esta copia, pero '
            'Shipflow no lo versiona ni lo comparte; recuperarlo tras perder la '
            'copia requiere respaldo.',
      );
