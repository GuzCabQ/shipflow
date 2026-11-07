import 'package:core/core.dart';

import 'context_basis.dart';
import 'context_decisions.dart';
import 'state_layout.dart';

/// Los efectos reales de una operación, anotados al ocurrir: un fallo
/// posterior no los borra.
final class EffectsLog {
  final filesCreated = <String>[];
  final filesReplaced = <String>[];
  final filesRemoved = <String>[];
  final directoriesCreated = <String>[];
  var excludeModified = false;

  /// [path] publicado: creado si no existía, reemplazado si sí.
  void published(String path, {required bool existed}) =>
      (existed ? filesReplaced : filesCreated).add(path);

  ContextEffects freeze(int processes) => ContextEffects(
    filesCreated: filesCreated,
    filesReplaced: filesReplaced,
    filesRemoved: filesRemoved,
    directoriesCreated: directoriesCreated,
    processesStarted: processes,
    excludeModified: excludeModified,
  );
}

/// Lo que un resultado necesita, antes de derivar código y outcome.
final class ResultParts {
  ResultParts({
    required this.command,
    required this.operation,
    required this.state,
    required this.freshness,
    required this.sharing,
    this.context,
    this.success = ContextOutcome.unchanged,
  });

  final ContextCommand command;
  final ContextOperation operation;
  ContextState state;
  ContextFreshness freshness;
  ContextSharing sharing;
  PortableRecognition? context;
  ContextOutcome success;
  final diagnostics = <ContextDiagnostic>[];
  final actions = <ContextNextAction>[];
  var cancelled = false;

  /// Lo demostrado de la base guiada y de su journal; sin observarlos, sus
  /// checks quedan sin comprobar.
  BasisIntegrity basis = BasisIntegrity.unverified;
  BasisIntegrity basisTransaction = BasisIntegrity.unverified;
}

/// El resultado único: código del diagnóstico de mayor precedencia, outcome
/// coherente con él y los seis checks del catálogo.
ContextOperationResult resultOf(ResultParts p, ContextEffects effects) {
  final exitCode = p.cancelled ? 130 : exitCodeOf(p.diagnostics);
  final present = p.state == ContextState.present;
  return ContextOperationResult(
    command: p.command,
    operation: p.operation,
    outcome: switch (exitCode) {
      0 => p.success,
      130 => ContextOutcome.cancelled,
      70 || 74 => ContextOutcome.failed,
      _ => ContextOutcome.needsAttention,
    },
    exitCode: exitCode,
    contextState: p.state,
    freshness: present || p.freshness == ContextFreshness.unverified
        ? p.freshness
        : ContextFreshness.notApplicable,
    sharing: p.sharing,
    checks: checksOf(p),
    diagnostics: p.diagnostics,
    context: present ? p.context : null,
    effects: effects,
    nextActions: p.actions,
  );
}

/// Los ocho checks, derivados del estado y los diagnósticos ya decididos.
List<ContextCheck> checksOf(ResultParts p) {
  final codes = {for (final d in p.diagnostics) d.code};
  return [
    _presence(p, _check),
    _integrity(p, _check),
    _compatibility(p, _check),
    _transaction(p, codes, _check),
    _freshness(p, _check),
    _sharing(p, codes, _check),
    basisIntegrityCheck(p.basis),
    basisTransactionCheck(p.basisTransaction),
  ];
}

ContextCheck _check(
  ContextCheckId id,
  ContextCheckStatus status,
  String code,
  String message,
) => ContextCheck(
  id: id,
  status: status,
  code: code,
  scope: projectPath,
  message: message,
);

ContextCheck _presence(ResultParts p, _Check check) {
  final present = p.state != ContextState.absent;
  return check(
    ContextCheckId.contextPresence,
    present ? ContextCheckStatus.passed : ContextCheckStatus.failed,
    present ? 'context_found' : 'context_absent',
    present ? 'Hay un contexto guardado.' : 'No hay contexto guardado.',
  );
}

ContextCheck _transaction(ResultParts p, Set<String> codes, _Check check) {
  if (codes.contains('state_occupied')) {
    return check(
      ContextCheckId.transactionState,
      ContextCheckStatus.notChecked,
      'not_checked',
      'La carpeta no es de Shipflow: no se leyeron sus documentos.',
    );
  }
  final pending = p.state == ContextState.recoveryRequired;
  return check(
    ContextCheckId.transactionState,
    pending ? ContextCheckStatus.failed : ContextCheckStatus.passed,
    pending ? 'recovery_pending' : 'none',
    pending
        ? 'Hay una operación por recuperar.'
        : 'No hay operaciones pendientes.',
  );
}

typedef _Check =
    ContextCheck Function(ContextCheckId, ContextCheckStatus, String, String);

ContextCheck _integrity(ResultParts p, _Check check) => switch (p.state) {
  ContextState.absent || ContextState.recoveryRequired => check(
    ContextCheckId.contextIntegrity,
    ContextCheckStatus.notChecked,
    'not_checked',
    'No hay un documento que validar ahora.',
  ),
  ContextState.invalid => check(
    ContextCheckId.contextIntegrity,
    ContextCheckStatus.failed,
    'context_invalid',
    'El documento no cumple su formato.',
  ),
  _ => check(
    ContextCheckId.contextIntegrity,
    ContextCheckStatus.passed,
    'valid',
    'El documento cumple su formato.',
  ),
};

ContextCheck _compatibility(ResultParts p, _Check check) => switch (p.state) {
  ContextState.present => check(
    ContextCheckId.producerCompatibility,
    ContextCheckStatus.passed,
    recognitionContract,
    'El contrato de reconocimiento es compatible.',
  ),
  ContextState.incompatible => check(
    ContextCheckId.producerCompatibility,
    ContextCheckStatus.failed,
    'context_incompatible',
    'Otro contrato de reconocimiento produjo el contexto.',
  ),
  _ => check(
    ContextCheckId.producerCompatibility,
    ContextCheckStatus.notChecked,
    'not_checked',
    'No hay un productor que comparar.',
  ),
};

ContextCheck _freshness(ResultParts p, _Check check) => switch (p.freshness) {
  ContextFreshness.current => check(
    ContextCheckId.recognitionFreshness,
    ContextCheckStatus.passed,
    'current',
    'Coincide con lo observado ahora.',
  ),
  ContextFreshness.stale => check(
    ContextCheckId.recognitionFreshness,
    ContextCheckStatus.failed,
    'stale',
    'Difiere de lo observado ahora.',
  ),
  ContextFreshness.unverified => check(
    ContextCheckId.recognitionFreshness,
    ContextCheckStatus.failed,
    'unverified',
    'No se pudo comprobar con lo observado ahora.',
  ),
  ContextFreshness.notApplicable => check(
    ContextCheckId.recognitionFreshness,
    ContextCheckStatus.notChecked,
    'not_checked',
    'No hay un contexto que comparar.',
  ),
};

ContextCheck _sharing(ResultParts p, Set<String> codes, _Check check) {
  final effective = p.sharing.effective;
  final ok =
      effective == SharingEffective.shareReady ||
      effective == SharingEffective.localExcluded;
  final failed =
      effective == SharingEffective.conflict ||
      codes.contains('git_unavailable');
  return check(
    ContextCheckId.sharingState,
    ok
        ? ContextCheckStatus.passed
        : failed
        ? ContextCheckStatus.failed
        : ContextCheckStatus.notChecked,
    effective.toWireName(),
    ok
        ? 'La elección está aplicada.'
        : failed
        ? 'La elección no se pudo aplicar o comprobar.'
        : 'La elección está pendiente o no se pudo comprobar sin Git.',
  );
}
