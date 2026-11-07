import 'package:core/core.dart';

import 'context_decisions.dart';
import 'state_layout.dart';

/// Lo que V2 informa de la base guiada: la ve como estado propio, nunca la
/// repara ni recupera su publicación; remite a `bootstrap`.

/// El check de integridad de `shipflow/basis.json`. Ausente es una
/// capacidad no inicializada, no un contexto inválido.
ContextCheck basisIntegrityCheck(BasisIntegrity state) => switch (state) {
  BasisIntegrity.absent => _check(
    ContextCheckId.basisIntegrity,
    ContextCheckStatus.notChecked,
    'basis_not_initialized',
    'Todavía no hay una base guiada.',
  ),
  BasisIntegrity.valid => _check(
    ContextCheckId.basisIntegrity,
    ContextCheckStatus.passed,
    'basis_valid',
    'La base guiada cumple su formato y su historia.',
  ),
  BasisIntegrity.unverified => _check(
    ContextCheckId.basisIntegrity,
    ContextCheckStatus.notChecked,
    'not_checked',
    'La base guiada no se comprobó.',
  ),
  _ => _check(
    ContextCheckId.basisIntegrity,
    ContextCheckStatus.failed,
    'basis_invalid',
    'La base guiada no cumple su formato; se conserva sin usarla.',
  ),
};

/// El check de una publicación de la base sin terminar.
ContextCheck basisTransactionCheck(BasisIntegrity state) => switch (state) {
  BasisIntegrity.absent => _check(
    ContextCheckId.basisTransaction,
    ContextCheckStatus.passed,
    'none_pending',
    'No hay una publicación de la base sin terminar.',
  ),
  BasisIntegrity.valid => _check(
    ContextCheckId.basisTransaction,
    ContextCheckStatus.failed,
    'basis_recovery_required',
    'Publicación de base pendiente.',
  ),
  BasisIntegrity.unverified => _check(
    ContextCheckId.basisTransaction,
    ContextCheckStatus.notChecked,
    'not_checked',
    'El journal de la base no se comprobó.',
  ),
  _ => _check(
    ContextCheckId.basisTransaction,
    ContextCheckStatus.failed,
    'basis_transaction_invalid',
    'El journal de la base no cumple su formato; se conserva.',
  ),
};

ContextCheck _check(
  ContextCheckId id,
  ContextCheckStatus status,
  String code,
  String message,
) => ContextCheck(
  id: id,
  status: status,
  code: code,
  scope: id == ContextCheckId.basisIntegrity
      ? basisDocumentPath
      : basisTransactionPath,
  message: message,
);

/// La acción que termina o aborta una publicación de la base.
final bootstrapRecoverAction = ContextNextAction(
  command: ContextCommand.bootstrap,
  arguments: const ['--recover'],
  purpose: 'Completar o abortar la publicación aceptada de la base.',
  effect: 'write_own_state',
);

/// Los diagnósticos de la base para doctor, desde la propiedad observada.
List<ContextDiagnostic> basisDiagnostics(StateOwnership ownership) => [
  if (ownership.basis == BasisIntegrity.invalid)
    diagnostic(
      'basis_invalid',
      'La base guiada no cumple su formato; se conserva sin usarla.',
      basisDocumentPath,
    ),
  if (ownership.basisTransaction == BasisIntegrity.valid)
    diagnostic(
      'basis_recovery_required',
      'Hay una publicación de la base sin terminar: la termina «shipflow '
          'bootstrap --recover».',
      basisTransactionPath,
    ),
  if (ownership.basisTransaction == BasisIntegrity.invalid)
    diagnostic(
      'basis_transaction_invalid',
      'El journal de la base no cumple su formato; se conserva.',
      basisTransactionPath,
    ),
];
