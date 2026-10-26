import 'package:core/core.dart';

/// El contrato de reconocimiento que este productor sabe comparar.
const recognitionContract = 'declared-project-v2.1';

/// Cada diagnóstico con su código de salida y su precedencia: gana el de
/// menor número. 0 es un aviso que no cambia el resultado.
const _catalog = <String, (int, int)>{
  'io_failure': (1, 74),
  'unexpected': (1, 70),
  'busy': (2, 75),
  'concurrent_change': (2, 75),
  'recovery_pending': (2, 75),
  'recovery_conflict': (2, 75),
  'context_invalid': (3, 65),
  'context_incompatible': (3, 65),
  'state_occupied': (3, 65),
  'state_invalid': (3, 65),
  'bootstrap_unverified': (3, 65),
  'journal_invalid': (3, 65),
  'not_initialized': (4, 65),
  'context_absent': (4, 65),
  'context_stale': (4, 65),
  'recognition_unverified': (4, 65),
  'not_eligible': (4, 65),
  'recovery_aborted': (4, 65),
  'ancestor_context': (4, 65),
  'choice_required': (5, 65),
  'sharing_unavailable': (5, 65),
  'sharing_conflict': (5, 65),
  'already_tracked': (5, 65),
  'binding_changed': (5, 65),
  'git_unavailable': (5, 65),
  'choice_pending': (9, 0),
  'git_absent': (9, 0),
  'git_unverified': (9, 0),
  'exclude_shared': (9, 0),
};

/// El código de salida de [diagnostics]: el del de mayor precedencia.
int exitCodeOf(Iterable<ContextDiagnostic> diagnostics) {
  var best = (99, 0);
  for (final d in diagnostics) {
    final entry = _catalog[d.code] ?? (1, 70);
    if (entry.$1 < best.$1) best = entry;
  }
  return best.$2;
}

/// Un diagnóstico de [code] con su mensaje y la ruta que lo ubica.
ContextDiagnostic diagnostic(String code, String message, [String? path]) =>
    ContextDiagnostic(code: code, message: message, path: path);

ContextNextAction initAction(
  List<String> arguments,
  String purpose,
  String effect,
) => ContextNextAction(
  command: ContextCommand.init,
  arguments: arguments,
  purpose: purpose,
  effect: effect,
);

final refreshAction = initAction(
  ['--refresh'],
  'Actualizar el contexto guardado con lo observado ahora.',
  'Reemplaza shipflow/project.json si el reconocimiento es elegible.',
);

final recoverAction = initAction(
  ['--recover'],
  'Terminar o deshacer la operación interrumpida.',
  'Sólo toca archivos propios de esa operación.',
);

final firstInitAction = initAction(
  [],
  'Inicializar el contexto de este proyecto.',
  'Crea shipflow/project.json y su configuración local.',
);

/// Las dos invocaciones que expresan la elección de conservación.
List<ContextNextAction> sharingActions() => [
  initAction(
    ['--sharing=share'],
    'Compartir el contexto con el repositorio.',
    'Deja shipflow/project.json versionable; no hace add ni commit.',
  ),
  initAction(
    ['--sharing=local'],
    'Guardar el contexto sólo en esta copia.',
    'Agrega una regla propia al exclude local de Git.',
  ),
];

final extendedAction = ContextNextAction(
  command: ContextCommand.doctor,
  arguments: ['--report-budget=extended'],
  purpose: 'Comprobar la vigencia con el perfil ampliado.',
  effect: 'Sólo lee; no cambia la configuración del perfil.',
);
