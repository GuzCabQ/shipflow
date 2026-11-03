import 'package:core/core.dart';

import 'assessment_codec.dart';

/// Quién observa, como lo declara el plugin por la raíz de composición.
typedef AssessmentProducerInfo = ({
  String contract,
  String pluginId,
  String parserVersion,
});

const _placeholder =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// El snapshot sellado de [observation]: el inventario más el contexto
/// citado, los cinco testigos y la cobertura derivados de las colecciones
/// —nunca del detector— y su identidad canónica.
AssessmentSnapshot assembleSnapshot({
  required AssessmentObservation observation,
  required String contextDigest,
  required AssessmentProfile profile,
  required AssessmentProducer producer,
  required String observedAt,
}) {
  final inputs = _withContext(observation.inputs, contextDigest);
  final WitnessBasis basis = (
    inventoryComplete: observation.inventoryComplete,
    inputs: inputs,
    files: observation.files,
    claims: observation.claims,
    contextLinks: observation.contextLinks,
  );
  final witnesses = deriveWitnesses(producer.contract, basis);
  AssessmentSnapshot seal(String id) => AssessmentSnapshot(
    snapshotId: id,
    observedAt: observedAt,
    producer: producer,
    contextDigest: contextDigest,
    profile: profile,
    coverage: coverageOf(witnesses, observation.inventoryComplete),
    inventoryComplete: observation.inventoryComplete,
    units: observation.units,
    inputs: inputs,
    files: observation.files,
    claims: observation.claims,
    witnesses: witnesses,
    contextLinks: observation.contextLinks,
    diagnostics: [...observation.diagnostics]..sort(_byCodeAndPath),
  );
  return seal(snapshotIdOf(seal(_placeholder)));
}

/// El inventario observado más el contexto citado, en orden canónico.
List<AssessmentInput> _withContext(
  List<AssessmentInput> observed,
  String contextDigest,
) => [
  ...observed,
  AssessmentInput(
    path: assessmentContextPath,
    kind: AssessmentInputKind.context,
    state: AssessmentInputState.read,
    sha256: contextDigest,
    reason: null,
  ),
]..sort(_byPathAndKind);

/// El instante UTC al segundo, con la forma del schema.
String observedAtOf(DateTime now) =>
    '${now.toUtc().toIso8601String().substring(0, 19)}Z';

int _byPathAndKind(AssessmentInput a, AssessmentInput b) {
  final path = a.path.compareTo(b.path);
  return path != 0 ? path : a.kind.toWireName().compareTo(b.kind.toWireName());
}

int _byCodeAndPath(AssessmentDiagnostic a, AssessmentDiagnostic b) {
  final code = a.code.compareTo(b.code);
  return code != 0 ? code : (a.path ?? '').compareTo(b.path ?? '');
}
