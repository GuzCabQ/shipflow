import 'package:core/core.dart';

/// La base que el plugin deriva de un contexto citado, inyectada por la
/// raíz de composición: el CLI no conoce el stack.
typedef ContextBasisProjector =
    AssessmentContextBasis Function(ProjectContext context);

/// Cómo se relaciona un snapshot con el contexto V2 de ahora.
enum AssessmentBinding {
  /// Cita exactamente este contexto, y su correspondencia se comprobó.
  matched,

  /// Cita otro contexto del mismo proyecto: es consultable como historia,
  /// pero su vínculo no se vuelve a comprobar ni se reenlaza.
  basisUnavailable,
}

/// La relación de [snapshot], de un documento de [projectId], con
/// [context], cuyos bytes exactos tienen [contextDigest]. Otro proyecto se
/// rechaza; la misma huella exige correspondencia exacta, porque una
/// huella correcta no legitima unidades ni vínculos ajenos.
AssessmentBinding bindToContext({
  required String projectId,
  required AssessmentSnapshot snapshot,
  required ProjectContext context,
  required String contextDigest,
  required ContextBasisProjector basisOf,
}) {
  requireSemantic(projectId == context.projectId, 'project_identity');
  if (snapshot.contextDigest != contextDigest) {
    return AssessmentBinding.basisUnavailable;
  }
  validateAssessmentContext(snapshot, basisOf(context));
  return AssessmentBinding.matched;
}
