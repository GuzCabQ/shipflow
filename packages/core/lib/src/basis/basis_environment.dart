import '../recognition/recognition_json.dart';
import 'basis_draft.dart';
import 'basis_response_parts.dart';

/// Lo que dejó leer las fuentes citadas: el estado de cada versión, las
/// lecturas con su huella y si alguna cota detuvo la lectura.
final class BasisSourceReport {
  BasisSourceReport({
    required List<BasisSourceStatus> statuses,
    required List<BasisSourceReading> readings,
    required this.complete,
  }) : statuses = List.unmodifiable(statuses),
       readings = List.unmodifiable(readings);

  factory BasisSourceReport.fromJson(Map<String, Object?> json) =>
      BasisSourceReport(
        statuses: readObjects(json['statuses'], BasisSourceStatus.fromJson),
        readings: readObjects(json['readings'], BasisSourceReading.fromJson),
        complete: json['complete']! as bool,
      );

  final List<BasisSourceStatus> statuses;

  /// Sólo contenido admitido y leído: ruta y huella, nunca el cuerpo.
  final List<BasisSourceReading> readings;

  /// False si una cota de cantidad o de bytes dejó fuentes sin leer.
  final bool complete;

  Map<String, Object?> toJson() => {
    'statuses': [for (final s in statuses) s.toJson()],
    'readings': [for (final r in readings) r.toJson()],
    'complete': complete,
  };
}

/// El proyecto V2 tal como está ahora, sin ejecutar init ni assess: si el
/// contexto existe y valida, su identidad, la huella de sus bytes y si hay
/// una transacción de init o de assess sin terminar.
final class BasisEnvironment {
  BasisEnvironment({
    required this.context,
    required this.projectId,
    required this.contextDigest,
    required this.contextRecoveryPending,
    required this.assessmentRecoveryPending,
  });

  factory BasisEnvironment.fromJson(Map<String, Object?> json) =>
      BasisEnvironment(
        context: BasisIntegrity.fromWireName(json['context']! as String),
        projectId: json['projectId'] as String?,
        contextDigest: json['contextDigest'] as String?,
        contextRecoveryPending: json['contextRecoveryPending']! as bool,
        assessmentRecoveryPending: json['assessmentRecoveryPending']! as bool,
      );

  final BasisIntegrity context;

  /// La identidad V2 que vincula la base; null si no se demostró.
  final String? projectId;

  /// `sha256:<hex>` de los bytes de `project.json`: precondición de
  /// publicación, no de consulta.
  final String? contextDigest;
  final bool contextRecoveryPending;
  final bool assessmentRecoveryPending;

  Map<String, Object?> toJson() => {
    'context': context.toWireName(),
    'projectId': projectId,
    'contextDigest': contextDigest,
    'contextRecoveryPending': contextRecoveryPending,
    'assessmentRecoveryPending': assessmentRecoveryPending,
  };
}
