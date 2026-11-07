import 'basis_enums.dart';

const _kibibyte = 1024;
const _mebibyte = 1024 * _kibibyte;

/// La profundidad máxima de anidamiento de cualquier documento de la base.
const maxBasisJsonDepth = 32;

/// Títulos, etiquetas, roles, responsables y versiones, en bytes UTF-8.
const maxBasisShortText = 512;

/// Motivos, resoluciones, alternativas, propósitos, disparadores,
/// localizadores y prefijos de ámbito, en bytes UTF-8.
const maxBasisReasonText = 4 * _kibibyte;

/// Enunciados de reglas y preguntas de pendientes, en bytes UTF-8.
const maxBasisStatementText = 16 * _kibibyte;

/// Las cotas inclusivas de una invocación de bootstrap. Son independientes:
/// la de bytes puede agotarse antes que la de eventos, y ninguna se cumple
/// borrando historia.
final class BasisLimits {
  const BasisLimits({
    required this.profile,
    required this.maxBasisBytes,
    required this.maxDraftBytes,
    required this.maxCurrentRecords,
    required this.maxEvents,
    required this.maxChanges,
    required this.maxSourceBytes,
    required this.maxSources,
    required this.maxTotalSourceBytes,
    required this.maxResponseBytes,
  });

  factory BasisLimits.forProfile(BasisProfile profile) => switch (profile) {
    BasisProfile.standard => const BasisLimits(
      profile: BasisProfile.standard,
      maxBasisBytes: 4 * _mebibyte,
      maxDraftBytes: _mebibyte,
      maxCurrentRecords: 1024,
      maxEvents: 8192,
      maxChanges: 64,
      maxSourceBytes: _mebibyte,
      maxSources: 64,
      maxTotalSourceBytes: 16 * _mebibyte,
      maxResponseBytes: 8 * _mebibyte,
    ),
    BasisProfile.extended => const BasisLimits(
      profile: BasisProfile.extended,
      maxBasisBytes: 16 * _mebibyte,
      maxDraftBytes: 4 * _mebibyte,
      maxCurrentRecords: 4096,
      maxEvents: 32768,
      maxChanges: 256,
      maxSourceBytes: 4 * _mebibyte,
      maxSources: 256,
      maxTotalSourceBytes: 64 * _mebibyte,
      maxResponseBytes: 32 * _mebibyte,
    ),
  };

  factory BasisLimits.fromJson(Map<String, Object?> json) => BasisLimits(
    profile: BasisProfile.fromWireName(json['profile']! as String),
    maxBasisBytes: json['maxBasisBytes']! as int,
    maxDraftBytes: json['maxDraftBytes']! as int,
    maxCurrentRecords: json['maxCurrentRecords']! as int,
    maxEvents: json['maxEvents']! as int,
    maxChanges: json['maxChanges']! as int,
    maxSourceBytes: json['maxSourceBytes']! as int,
    maxSources: json['maxSources']! as int,
    maxTotalSourceBytes: json['maxTotalSourceBytes']! as int,
    maxResponseBytes: json['maxResponseBytes']! as int,
  );

  final BasisProfile profile;

  /// `basis.json` completo, historia incluida.
  final int maxBasisBytes;

  /// Una entrada, un borrador o un journal.
  final int maxDraftBytes;

  /// Registros en su versión actual.
  final int maxCurrentRecords;
  final int maxEvents;

  /// Cambios de una sola propuesta.
  final int maxChanges;

  /// Cada fuente leída; nunca se trunca.
  final int maxSourceBytes;

  /// Fuentes verificadas por operación.
  final int maxSources;

  /// Bytes de fuentes leídos por operación.
  final int maxTotalSourceBytes;
  final int maxResponseBytes;

  Map<String, Object?> toJson() => {
    'profile': profile.toWireName(),
    'maxBasisBytes': maxBasisBytes,
    'maxDraftBytes': maxDraftBytes,
    'maxCurrentRecords': maxCurrentRecords,
    'maxEvents': maxEvents,
    'maxChanges': maxChanges,
    'maxSourceBytes': maxSourceBytes,
    'maxSources': maxSources,
    'maxTotalSourceBytes': maxTotalSourceBytes,
    'maxResponseBytes': maxResponseBytes,
  };
}
