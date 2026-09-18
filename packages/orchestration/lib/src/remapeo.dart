/// Rutas del candidato → rutas del usuario.
///
/// La cascada corre sobre la raíz del candidato — un directorio temporal —,
/// así que sus diagnósticos apuntan ahí. El artefacto de revisión se los
/// muestra a una persona que no tiene ese directorio: sin remapear, ve una
/// ruta que no existe en su árbol.
library;

import 'package:core/core.dart';

import 'cascada.dart';

/// Vuelve a expresar [cascada] con las rutas de [Diagnostic.file] contadas
/// desde [raizDelCandidato] en vez de desde ella misma.
///
/// **Se remapea [Diagnostic.file] y nada más.** [Diagnostic.message] es un
/// [QuotedText]: el texto de la herramienta, sin reescribir (INV-6). Si ese
/// texto menciona la ruta temporal, la mención se queda tal cual — tocarla
/// rompería el contrato de evidencia citada, y una ruta rara en una cita es
/// preferible a una cita adulterada: con la ruta rara, la persona que revisa
/// todavía puede reconocer qué dijo la herramienta; con el mensaje reescrito,
/// ya no tendría cómo saberlo.
///
/// **Un archivo que no está bajo [raizDelCandidato] se deja igual.** Puede
/// pasar: una herramienta puede reportar sobre su propia instalación, fuera
/// del candidato. Remapearlo a la fuerza inventaría una ruta del usuario que
/// no existe.
ResultadoDeCascada remapear(
  ResultadoDeCascada cascada, {
  required String raizDelCandidato,
}) {
  // Con o sin `/` final en `raizDelCandidato`, lo que separa la raíz del
  // resto de la ruta es exactamente un `/`: sin agregarlo, una raíz
  // `/tmp/cand-1` recortaría también de `/tmp/cand-10/…`, que no es un
  // descendiente suyo.
  final prefijo = raizDelCandidato.endsWith('/')
      ? raizDelCandidato
      : '$raizDelCandidato/';

  Diagnostic remapearUno(Diagnostic d) {
    if (!d.file.startsWith(prefijo)) return d;
    return Diagnostic(
      file: d.file.substring(prefijo.length),
      line: d.line,
      severity: d.severity,
      ruleId: d.ruleId,
      message: d.message,
      sourceMetadata: d.sourceMetadata,
    );
  }

  final desenlaces = <String, StepOutcome>{};
  for (final entrada in cascada.desenlaces.entries) {
    final desenlace = entrada.value;
    desenlaces[entrada.key] = desenlace is Executed
        ? Executed(
            witness: desenlace.witness,
            diagnostics: [
              for (final d in desenlace.diagnostics) remapearUno(d),
            ],
          )
        : desenlace;
  }

  return ResultadoDeCascada(
    registrados: cascada.registrados,
    alcance: cascada.alcance,
    desenlaces: desenlaces,
  );
}
