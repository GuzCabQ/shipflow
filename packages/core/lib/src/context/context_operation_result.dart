import '../recognition/recognition_json.dart';
import 'context_enums.dart';
import 'context_result_parts.dart';
import 'context_validation.dart';
import 'portable_recognition.dart';

/// Los códigos de salida que una operación de contexto puede devolver.
const contextExitCodes = {0, 64, 65, 66, 70, 74, 75, 130};

const _succeeded = {
  ContextOutcome.initialized,
  ContextOutcome.unchanged,
  ContextOutcome.refreshed,
  ContextOutcome.recovered,
  ContextOutcome.available,
};

/// El resultado único de init, refresh, recover o doctor: humanos y JSON se
/// derivan de él, sin otra inspección. Sus códigos, outcome, estados y
/// efectos son consistentes entre sí, no sólo valores de sus enums.
final class ContextOperationResult {
  ContextOperationResult({
    required this.command,
    required this.operation,
    required this.outcome,
    required this.exitCode,
    required this.contextState,
    required this.freshness,
    required this.sharing,
    required List<ContextCheck> checks,
    required List<ContextDiagnostic> diagnostics,
    required this.context,
    required this.effects,
    required List<ContextNextAction> nextActions,
  }) : checks = List.unmodifiable(checks),
       diagnostics = List.unmodifiable(diagnostics),
       nextActions = List.unmodifiable(nextActions) {
    _validate(this);
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory ContextOperationResult.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 4, 'schema_version');
    return ContextOperationResult(
      command: ContextCommand.fromWireName(json['command']! as String),
      operation: ContextOperation.fromWireName(json['operation']! as String),
      outcome: ContextOutcome.fromWireName(json['outcome']! as String),
      exitCode: json['exitCode']! as int,
      contextState: ContextState.fromWireName(json['contextState']! as String),
      freshness: ContextFreshness.fromWireName(json['freshness']! as String),
      sharing: readObject(json['sharing'], ContextSharing.fromJson),
      checks: readObjects(json['checks'], ContextCheck.fromJson),
      diagnostics: readObjects(json['diagnostics'], ContextDiagnostic.fromJson),
      context: json['context'] == null
          ? null
          : readObject(json['context'], PortableRecognition.fromJson),
      effects: readObject(json['effects'], ContextEffects.fromJson),
      nextActions: readObjects(json['nextActions'], ContextNextAction.fromJson),
    );
  }

  final int schemaVersion = 4;
  final ContextCommand command;
  final ContextOperation operation;
  final ContextOutcome outcome;
  final int exitCode;
  final ContextState contextState;
  final ContextFreshness freshness;
  final ContextSharing sharing;
  final List<ContextCheck> checks;
  final List<ContextDiagnostic> diagnostics;

  /// El subconjunto portable guardado, o null si no hay uno legible.
  final PortableRecognition? context;
  final ContextEffects effects;
  final List<ContextNextAction> nextActions;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'command': command.toWireName(),
    'operation': operation.toWireName(),
    'outcome': outcome.toWireName(),
    'exitCode': exitCode,
    'contextState': contextState.toWireName(),
    'freshness': freshness.toWireName(),
    'sharing': sharing.toJson(),
    'checks': [for (final c in checks) c.toJson()],
    'diagnostics': [for (final d in diagnostics) d.toJson()],
    'context': context?.toJson(),
    'effects': effects.toJson(),
    'nextActions': [for (final a in nextActions) a.toJson()],
  };
}

void _validate(ContextOperationResult r) {
  final doctor = r.command == ContextCommand.doctor;
  requireSemantic(
    doctor == (r.operation == ContextOperation.doctor),
    'command_operation',
  );
  requireSemantic(!doctor || !r.effects.wrote, 'doctor_effects');
  requireSemantic(contextExitCodes.contains(r.exitCode), 'exit_code');
  requireSemantic(switch (r.outcome) {
    ContextOutcome.cancelled => r.exitCode == 130,
    _ when _succeeded.contains(r.outcome) => r.exitCode == 0,
    _ => r.exitCode != 0 && r.exitCode != 130,
  }, 'exit_code');
  final ids = {for (final c in r.checks) c.id};
  requireSemantic(ids.length == r.checks.length, 'checks');
  requireSemantic(
    r.context == null || r.contextState == ContextState.present,
    'context_state',
  );
  requireSemantic(
    r.contextState == ContextState.present ||
        (r.freshness != ContextFreshness.current &&
            r.freshness != ContextFreshness.stale),
    'freshness',
  );
  requireSemantic(r.effects.processesStarted <= 12, 'processes');
}
