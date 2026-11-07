import 'package:core/core.dart';

/// Cada diagnóstico de bootstrap: precedencia (gana el menor), código de
/// salida y mensaje estable. Uso; fallos internos y de E/S; conflictos y
/// recuperación; almacenamiento inválido; presupuesto; reglas de la
/// propuesta; prerrequisitos; soporte no verificado; borrador preparado.
/// 9 es un aviso que no cambia el código.
const _catalog = <String, (int, int, String)>{
  'invalid_usage': (0, 64, 'Uso o combinación de opciones inválida.'),
  'cancelled': (1, 130, 'Se canceló: nada se aceptó.'),
  'internal_error': (1, 70, 'Error inesperado de Shipflow; nada se aceptó.'),
  'io_error': (1, 74, 'No se pudo leer o escribir un archivo propio.'),
  'input_unavailable': (1, 66, 'No se pudo leer la entrada indicada.'),
  'busy': (2, 75, 'Otra operación de Shipflow está publicando.'),
  'draft_conflict': (2, 75, 'Hay otro borrador activo: no se reemplaza.'),
  'base_changed': (
    2,
    75,
    'La base o el contexto cambiaron desde la preparación.',
  ),
  'source_changed': (2, 75, 'Una fuente cambió desde la preparación.'),
  'recovery_required': (2, 75, 'Hay una publicación sin terminar.'),
  'recovery_preconditions_changed': (
    2,
    75,
    'Las precondiciones cambiaron: no se publica la aceptación antigua.',
  ),
  'invalid_schema': (3, 65, 'Un documento no cumple su formato.'),
  'incompatible_version': (
    3,
    65,
    'Un documento tiene una versión no soportada.',
  ),
  'digest_mismatch': (3, 65, 'Una huella no corresponde a su contenido.'),
  'history_gap': (3, 65, 'La historia de la base tiene un hueco.'),
  'budget_exceeded': (4, 65, 'No cabe en el presupuesto del perfil pedido.'),
  'unknown_active_scope': (
    5,
    65,
    'Una regla activa necesita un ámbito conocido.',
  ),
  'missing_alternative': (
    5,
    65,
    'Una prohibición activa necesita alternativa y política de excepción.',
  ),
  'authority_scope': (5, 65, 'El actor declarado no alcanza ese ámbito.'),
  'invalid_reference': (5, 65, 'Una referencia no existe o no corresponde.'),
  'unsafe_path': (5, 65, 'Una ruta o un localizador no es seguro.'),
  'context_required': (6, 65, 'Falta el contexto inicial: inicializa primero.'),
  'basis_absent': (6, 65, 'Todavía no hay una base aceptada.'),
  'choice_required': (6, 65, 'Falta elegir una operación explícita.'),
  'source_unverified': (7, 65, 'Un soporte requerido no está vigente.'),
  'draft_prepared': (8, 65, 'Borrador preparado: todavía no está aceptado.'),
  'history_sources_not_rechecked': (
    9,
    0,
    'La historia no vuelve a comprobar los soportes.',
  ),
  'draft_not_accepted': (9, 0, 'Es un borrador: no es la base aceptada.'),
  'historical_support_not_rechecked': (
    9,
    0,
    'Soportes de la decisión histórica no revalidados.',
  ),
};

/// El diagnóstico de [code], con su ruta si la hay.
BasisDiagnostic basisDiagnostic(String code, {String? path, String? message}) =>
    BasisDiagnostic(
      code: code,
      message: message ?? _catalog[code]?.$3 ?? 'Diagnóstico de bootstrap.',
      path: path,
    );

/// El código de salida de [diagnostics]: el del de mayor precedencia.
int basisExitCode(Iterable<BasisDiagnostic> diagnostics) {
  var best = (99, 0);
  for (final d in diagnostics) {
    final (precedence, exit, _) = _catalog[d.code] ?? (1, 70, '');
    if (precedence < best.$1) best = (precedence, exit);
  }
  return best.$2;
}

/// Si [code] es un aviso que no cambia el código de salida.
bool isBasisWarning(String code) => _catalog[code]?.$1 == 9;

/// [diagnostics] en orden de precedencia y después de código.
List<BasisDiagnostic> basisByPrecedence(List<BasisDiagnostic> diagnostics) =>
    [...diagnostics]..sort((a, b) {
      final pa = _catalog[a.code]?.$1 ?? 1;
      final pb = _catalog[b.code]?.$1 ?? 1;
      return pa != pb ? pa.compareTo(pb) : a.code.compareTo(b.code);
    });

BasisAction _action(
  List<String> arguments,
  String purpose,
  BasisActionEffect e,
) => BasisAction(
  command: 'bootstrap',
  arguments: arguments,
  purpose: purpose,
  effect: e,
);

final showAction = _action(
  ['--show'],
  'Consultar la base aceptada.',
  BasisActionEffect.readOnly,
);
final showDraftAction = _action(
  ['--show', '--draft'],
  'Consultar el borrador sin aceptarlo.',
  BasisActionEffect.readOnly,
);
final recoverAction = _action(
  ['--recover'],
  'Completar o abortar la publicación aceptada pendiente.',
  BasisActionEffect.writeOwnState,
);

BasisAction acceptAction(String digest) => _action(
  ['--accept', digest],
  'Aceptar exactamente este borrador revisado.',
  BasisActionEffect.writeOwnState,
);

BasisAction discardAction(String digest) => _action(
  ['--discard', digest],
  'Descartar exactamente este borrador.',
  BasisActionEffect.writeOwnState,
);
