import 'assessment_claims.dart';
import 'assessment_enums.dart';
import 'assessment_sources.dart';
import 'assessment_witnesses.dart';

/// Esperado, procesado, fallido y omitido.
typedef WitnessCounts = (int, int, int, int);

/// Lo que los testigos de un snapshot miran: las colecciones selladas.
typedef WitnessBasis = ({
  bool inventoryComplete,
  List<AssessmentInput> inputs,
  List<AssessmentFile> files,
  List<AssessmentClaim> claims,
  List<AssessmentContextLink> contextLinks,
});

/// Las cuentas de cada capacidad según las colecciones: lo esperado sale
/// del inventario y del coordinador, nunca del propio detector.
WitnessCounts witnessCountsOf(
  AssessmentCapability capability,
  WitnessBasis b,
) => switch (capability) {
  AssessmentCapability.sourceInventory => _inventoryCounts(b.inputs),
  AssessmentCapability.sourceReferences => (
    b.files.length,
    _count(b.files, (f) => f.parseState == AssessmentParseState.parsed),
    _count(b.files, (f) => f.parseState == AssessmentParseState.failed),
    _count(b.files, (f) => f.parseState == AssessmentParseState.notRun),
  ),
  AssessmentCapability.localResolution => (
    b.claims.length,
    _count(b.claims, (c) => c.resolution != AssessmentResolution.unresolved),
    0,
    _count(b.claims, (c) => c.resolution == AssessmentResolution.unresolved),
  ),
  AssessmentCapability.testInventory => (b.files.length, b.files.length, 0, 0),
  AssessmentCapability.contextCandidates => (
    b.contextLinks.length,
    b.contextLinks.length,
    0,
    0,
  ),
};

const _processedInputs = {
  AssessmentInputState.read,
  AssessmentInputState.listed,
  AssessmentInputState.excluded,
};

WitnessCounts _inventoryCounts(List<AssessmentInput> inputs) => (
  inputs.length,
  _count(inputs, (i) => _processedInputs.contains(i.state)),
  _count(inputs, (i) => i.state == AssessmentInputState.unreadable),
  _count(inputs, (i) => i.state == AssessmentInputState.limit),
);

int _count<T>(Iterable<T> items, bool Function(T) test) =>
    items.where(test).length;

/// El estado de cada capacidad según sus cuentas. Referencias: sin ejecutar
/// si no procesó ni falló nada y omitió algo; fallida si sólo falló.
/// Resolución: parcial con cualquier referencia sin resolver. Inventario:
/// fallido si la raíz no se pudo listar. Pruebas: sólo completo sobre un
/// inventario completo.
AssessmentWitnessState witnessStateOf(
  AssessmentCapability capability,
  WitnessCounts counts,
  WitnessBasis b,
) {
  final (_, processed, failed, omitted) = counts;
  final clean = failed == 0 && omitted == 0;
  return switch (capability) {
    AssessmentCapability.sourceInventory =>
      _rootUnlisted(b.inputs)
          ? AssessmentWitnessState.failed
          : clean && b.inventoryComplete
          ? AssessmentWitnessState.complete
          : AssessmentWitnessState.partial,
    AssessmentCapability.sourceReferences =>
      clean
          ? AssessmentWitnessState.complete
          : processed == 0 && failed == 0
          ? AssessmentWitnessState.notRun
          : processed == 0 && omitted == 0
          ? AssessmentWitnessState.failed
          : AssessmentWitnessState.partial,
    AssessmentCapability.testInventory =>
      b.inventoryComplete
          ? AssessmentWitnessState.complete
          : AssessmentWitnessState.partial,
    _ =>
      clean ? AssessmentWitnessState.complete : AssessmentWitnessState.partial,
  };
}

bool _rootUnlisted(List<AssessmentInput> inputs) => inputs.any(
  (i) =>
      i.path == '.' &&
      i.kind == AssessmentInputKind.directory &&
      i.state != AssessmentInputState.listed,
);

/// Los cinco testigos de [b] bajo [contract], en orden de capacidad.
List<AssessmentWitness> deriveWitnesses(String contract, WitnessBasis b) {
  final witnesses = [
    for (final capability in AssessmentCapability.values)
      _witness(capability, contract, b),
  ]..sort((a, b) => a.id.compareTo(b.id));
  return witnesses;
}

AssessmentWitness _witness(
  AssessmentCapability capability,
  String contract,
  WitnessBasis b,
) {
  final counts = witnessCountsOf(capability, b);
  final (expected, processed, failed, omitted) = counts;
  return AssessmentWitness(
    capability: capability,
    producerVersion: contract,
    state: witnessStateOf(capability, counts, b),
    expected: expected,
    processed: processed,
    failed: failed,
    omitted: omitted,
  );
}

/// La cobertura de [witnesses]: fallida sin inventario válido, completa con
/// inventario completo y todos los testigos completos, parcial si no.
AssessmentCoverage coverageOf(
  List<AssessmentWitness> witnesses,
  bool inventoryComplete,
) {
  final inventory = witnesses.firstWhere(
    (w) => w.capability == AssessmentCapability.sourceInventory,
  );
  if (inventory.state == AssessmentWitnessState.failed) {
    return AssessmentCoverage.failed;
  }
  return inventoryComplete &&
          witnesses.every((w) => w.state == AssessmentWitnessState.complete)
      ? AssessmentCoverage.complete
      : AssessmentCoverage.partial;
}
