import 'package:core/core.dart';

import 'context_basis.dart';
import 'context_decisions.dart';
import 'context_result.dart';
import 'state_layout.dart';

/// Las transacciones de otros dueños que `init --recover` encuentra: no
/// las recupera ni adivina un orden con la suya; remite a su comando.
void remitForeignJournals(
  StateOwnership ownership,
  ResultParts parts, {
  required bool bothActive,
}) {
  if (ownership.assessmentJournal) {
    parts.diagnostics.add(assessmentPending(bothActive: bothActive));
  }
  if (ownership.basisJournal) {
    parts
      ..diagnostics.add(basisPending(bothActive: bothActive))
      ..actions.add(bootstrapRecoverAction);
  }
}

/// Una publicación de assess sin terminar: init no la recupera. Con las dos
/// activas no se adivina un orden.
ContextDiagnostic assessmentPending({required bool bothActive}) => bothActive
    ? diagnostic(
        'recovery_conflict',
        'Hay una operación de init y otra de assess sin terminar; no se '
            'adivina su orden: reconcílialas a mano.',
        assessmentTransactionPath,
      )
    : diagnostic(
        'recovery_pending',
        'La operación sin terminar es de assess: la termina «shipflow '
            'assess --recover».',
        assessmentTransactionPath,
      );

ContextDiagnostic basisPending({required bool bothActive}) => bothActive
    ? diagnostic(
        'recovery_conflict',
        'Hay una operación de init y una publicación de la base sin '
            'terminar; no se adivina su orden: reconcílialas a mano.',
        basisTransactionPath,
      )
    : diagnostic(
        'recovery_pending',
        'La publicación sin terminar es de la base guiada: la termina '
            '«shipflow bootstrap --recover».',
        basisTransactionPath,
      );
