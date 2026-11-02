import 'assessment_enums.dart';

const _mebibyte = 1048576;
const _kibibyte = 1024;

/// El documento completo: dos snapshots extended y su envoltura.
const maxAssessmentDocumentBytes = 128 * _mebibyte + 64 * _kibibyte;

/// Una respuesta JSON: un snapshot extended y su envoltura.
const maxAssessmentResponseBytes = 64 * _mebibyte + 64 * _kibibyte;
const maxAssessmentJournalBytes = 64 * _kibibyte;
const maxAssessmentJsonDepth = 64;

/// Cada ruta o texto controlado, en bytes UTF-8.
const maxAssessmentTextBytes = 4096;
const maxAssessmentIdLength = 128;
const maxAssessmentDiagnostics = 256;
const maxAssessmentExamples = 5;

/// Las cotas inclusivas de una ejecución de assess. Sobrepasar un recorrido,
/// un conteo o un tiempo deja cobertura parcial; sobrepasar el snapshot
/// serializado impide publicarlo entero.
final class AssessmentLimits {
  const AssessmentLimits({
    required this.profile,
    required this.maxEntries,
    required this.maxDepth,
    required this.maxSourceFiles,
    required this.maxSourceBytes,
    required this.maxTotalSourceBytes,
    required this.maxClaims,
    required this.maxSnapshotBytes,
    required this.maxObservationMillis,
    required this.maxParseMillis,
  });

  factory AssessmentLimits.forProfile(AssessmentProfile profile) =>
      switch (profile) {
        AssessmentProfile.standard => const AssessmentLimits(
          profile: AssessmentProfile.standard,
          maxEntries: 100000,
          maxDepth: 32,
          maxSourceFiles: 4096,
          maxSourceBytes: 2 * _mebibyte,
          maxTotalSourceBytes: 32 * _mebibyte,
          maxClaims: 32768,
          maxSnapshotBytes: 16 * _mebibyte,
          maxObservationMillis: 30000,
          maxParseMillis: 2000,
        ),
        AssessmentProfile.extended => const AssessmentLimits(
          profile: AssessmentProfile.extended,
          maxEntries: 400000,
          maxDepth: 64,
          maxSourceFiles: 16384,
          maxSourceBytes: 2 * _mebibyte,
          maxTotalSourceBytes: 128 * _mebibyte,
          maxClaims: 131072,
          maxSnapshotBytes: 64 * _mebibyte,
          maxObservationMillis: 120000,
          maxParseMillis: 8000,
        ),
      };

  factory AssessmentLimits.fromJson(Map<String, Object?> json) =>
      AssessmentLimits(
        profile: AssessmentProfile.fromWireName(json['profile']! as String),
        maxEntries: json['maxEntries']! as int,
        maxDepth: json['maxDepth']! as int,
        maxSourceFiles: json['maxSourceFiles']! as int,
        maxSourceBytes: json['maxSourceBytes']! as int,
        maxTotalSourceBytes: json['maxTotalSourceBytes']! as int,
        maxClaims: json['maxClaims']! as int,
        maxSnapshotBytes: json['maxSnapshotBytes']! as int,
        maxObservationMillis: json['maxObservationMillis']! as int,
        maxParseMillis: json['maxParseMillis']! as int,
      );

  final AssessmentProfile profile;

  /// Toda entrada enumerada, incluidas las omitidas.
  final int maxEntries;

  /// La raíz tiene profundidad 0.
  final int maxDepth;
  final int maxSourceFiles;

  /// Cada fuente; nunca se trunca un archivo guardado.
  final int maxSourceBytes;

  /// Bytes únicos: releer no aumenta la capacidad.
  final int maxTotalSourceBytes;

  /// Afirmaciones de referencia, incluidas las alternativas.
  final int maxClaims;
  final int maxSnapshotBytes;

  /// Observación o cotejo, sin presentar.
  final int maxObservationMillis;

  /// Cada archivo, analizado en un trabajo cancelable.
  final int maxParseMillis;

  Map<String, Object?> toJson() => {
    'profile': profile.toWireName(),
    'maxEntries': maxEntries,
    'maxDepth': maxDepth,
    'maxSourceFiles': maxSourceFiles,
    'maxSourceBytes': maxSourceBytes,
    'maxTotalSourceBytes': maxTotalSourceBytes,
    'maxClaims': maxClaims,
    'maxSnapshotBytes': maxSnapshotBytes,
    'maxObservationMillis': maxObservationMillis,
    'maxParseMillis': maxParseMillis,
  };
}
