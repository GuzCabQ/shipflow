import '../recognition/recognition_json.dart';
import 'assessment_claims.dart';
import 'assessment_sources.dart';
import 'assessment_witnesses.dart';

/// Cuánto costó observar: lo que se midió, no una promesa de rendimiento.
final class AssessmentMetrics {
  const AssessmentMetrics({
    required this.entries,
    required this.sourceBytes,
    required this.parsedFiles,
    required this.elapsedMillis,
  });

  factory AssessmentMetrics.fromJson(Map<String, Object?> json) =>
      AssessmentMetrics(
        entries: json['entries']! as int,
        sourceBytes: json['sourceBytes']! as int,
        parsedFiles: json['parsedFiles']! as int,
        elapsedMillis: json['elapsedMillis']! as int,
      );

  /// Entradas enumeradas, incluidas las omitidas.
  final int entries;

  /// Bytes únicos de fuentes leídas.
  final int sourceBytes;
  final int parsedFiles;
  final int elapsedMillis;

  Map<String, Object?> toJson() => {
    'entries': entries,
    'sourceBytes': sourceBytes,
    'parsedFiles': parsedFiles,
    'elapsedMillis': elapsedMillis,
  };
}

/// Lo que un plugin observó del código, en tipos neutrales: unidades,
/// inventario sellado sin el contexto citado, archivos, afirmaciones,
/// vínculos y diagnósticos agrupados. No publica, no decide la modalidad ni
/// calcula testigos: eso lo hace quien coordina, desde estas colecciones.
final class AssessmentObservation {
  AssessmentObservation({
    required this.inventoryComplete,
    required List<AssessmentUnit> units,
    required List<AssessmentInput> inputs,
    required List<AssessmentFile> files,
    required List<AssessmentClaim> claims,
    required List<AssessmentContextLink> contextLinks,
    required List<AssessmentDiagnostic> diagnostics,
    required this.metrics,
  }) : units = List.unmodifiable(units),
       inputs = List.unmodifiable(inputs),
       files = List.unmodifiable(files),
       claims = List.unmodifiable(claims),
       contextLinks = List.unmodifiable(contextLinks),
       diagnostics = List.unmodifiable(diagnostics);

  factory AssessmentObservation.fromJson(Map<String, Object?> json) =>
      AssessmentObservation(
        inventoryComplete: json['inventoryComplete']! as bool,
        units: readObjects(json['units'], AssessmentUnit.fromJson),
        inputs: readObjects(json['inputs'], AssessmentInput.fromJson),
        files: readObjects(json['files'], AssessmentFile.fromJson),
        claims: readObjects(json['claims'], AssessmentClaim.fromJson),
        contextLinks: readObjects(
          json['contextLinks'],
          AssessmentContextLink.fromJson,
        ),
        diagnostics: readObjects(
          json['diagnostics'],
          AssessmentDiagnostic.fromJson,
        ),
        metrics: readObject(json['metrics'], AssessmentMetrics.fromJson),
      );

  final bool inventoryComplete;
  final List<AssessmentUnit> units;
  final List<AssessmentInput> inputs;
  final List<AssessmentFile> files;
  final List<AssessmentClaim> claims;
  final List<AssessmentContextLink> contextLinks;
  final List<AssessmentDiagnostic> diagnostics;
  final AssessmentMetrics metrics;

  Map<String, Object?> toJson() => {
    'inventoryComplete': inventoryComplete,
    'units': [for (final u in units) u.toJson()],
    'inputs': [for (final i in inputs) i.toJson()],
    'files': [for (final f in files) f.toJson()],
    'claims': [for (final c in claims) c.toJson()],
    'contextLinks': [for (final l in contextLinks) l.toJson()],
    'diagnostics': [for (final d in diagnostics) d.toJson()],
    'metrics': metrics.toJson(),
  };
}
