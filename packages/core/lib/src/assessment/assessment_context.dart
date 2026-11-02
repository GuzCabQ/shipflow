import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'assessment_enums.dart';
import 'assessment_snapshot.dart';
import 'assessment_sources.dart';
import 'assessment_witnesses.dart';

/// Una fuente de reconocimiento que el contexto citado exige sellada, con
/// la huella completa de sus bytes cuando la de V2 es comparable.
final class AssessmentRecognitionInput {
  const AssessmentRecognitionInput({required this.path, required this.sha256});

  factory AssessmentRecognitionInput.fromJson(Map<String, Object?> json) =>
      AssessmentRecognitionInput(
        path: json['path']! as String,
        sha256: json['sha256'] as String?,
      );

  final String path;
  final String? sha256;

  Map<String, Object?> toJson() => {'path': path, 'sha256': sha256};
}

/// Lo que un contexto citado exige de un levantamiento: sus unidades, las
/// fuentes de reconocimiento selladas y los vínculos esperados. La produce
/// el plugin desde el contexto, sin volver al sistema de archivos, con el
/// mismo cálculo al observar y al consultar.
final class AssessmentContextBasis {
  AssessmentContextBasis({
    required List<AssessmentUnit> units,
    required List<AssessmentRecognitionInput> recognitionInputs,
    required List<AssessmentContextLink> contextLinks,
  }) : units = List.unmodifiable(units),
       recognitionInputs = List.unmodifiable(recognitionInputs),
       contextLinks = List.unmodifiable(contextLinks);

  factory AssessmentContextBasis.fromJson(Map<String, Object?> json) =>
      AssessmentContextBasis(
        units: readObjects(json['units'], AssessmentUnit.fromJson),
        recognitionInputs: readObjects(
          json['recognitionInputs'],
          AssessmentRecognitionInput.fromJson,
        ),
        contextLinks: readObjects(
          json['contextLinks'],
          AssessmentContextLink.fromJson,
        ),
      );

  final List<AssessmentUnit> units;
  final List<AssessmentRecognitionInput> recognitionInputs;
  final List<AssessmentContextLink> contextLinks;

  Map<String, Object?> toJson() => {
    'units': [for (final u in units) u.toJson()],
    'recognitionInputs': [for (final i in recognitionInputs) i.toJson()],
    'contextLinks': [for (final l in contextLinks) l.toJson()],
  };
}

/// Que [snapshot] corresponda exactamente a [basis]: el mismo conjunto de
/// unidades con su identidad y nombre, cada fuente exigida leída con su
/// huella, y los mismos vínculos, ni uno inventado ni uno omitido. Una
/// huella correcta no legitima un contenido ajeno. Quien llama decide, por
/// el digest, que la base es la del contexto citado.
void validateAssessmentContext(
  AssessmentSnapshot snapshot,
  AssessmentContextBasis basis,
) {
  requireSemantic(
    _sameSet(snapshot.units.map(_unitKey), basis.units.map(_unitKey)),
    'context_units',
  );
  final read = {
    for (final i in snapshot.inputs)
      if (i.kind == AssessmentInputKind.recognitionSource &&
          i.state == AssessmentInputState.read)
        i.path: i.sha256,
  };
  for (final required in basis.recognitionInputs) {
    requireSemantic(
      read.containsKey(required.path) &&
          (required.sha256 == null || read[required.path] == required.sha256),
      'context_recognition',
    );
  }
  requireSemantic(
    _sameSet(
      snapshot.contextLinks.map(_linkKey),
      basis.contextLinks.map(_linkKey),
    ),
    'context_links',
  );
}

String _unitKey(AssessmentUnit u) => '${u.id}\u0000${u.path}\u0000${u.label}';

String _linkKey(AssessmentContextLink l) => [
  l.kind.toWireName(),
  l.sourceId,
  l.sourcePath,
  l.label,
  l.targetUnitId ?? '',
].join('\u0000');

bool _sameSet(Iterable<String> a, Iterable<String> b) {
  final left = a.toList();
  final right = b.toSet();
  return left.length == right.length &&
      left.toSet().length == left.length &&
      right.containsAll(left);
}
