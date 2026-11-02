import '../context/context_validation.dart';
import 'assessment_claims.dart';
import 'assessment_derivation.dart';
import 'assessment_enums.dart';
import 'assessment_sources.dart';
import 'assessment_witnesses.dart';

/// La ruta del contexto citado, como entrada del inventario.
const assessmentContextPath = 'shipflow/project.json';

/// Las partes de un snapshot que sus reglas cruzadas miran.
typedef SnapshotParts = ({
  String snapshotId,
  String observedAt,
  String contract,
  String contextDigest,
  AssessmentCoverage coverage,
  bool inventoryComplete,
  List<AssessmentUnit> units,
  List<AssessmentInput> inputs,
  List<AssessmentFile> files,
  List<AssessmentClaim> claims,
  List<AssessmentWitness> witnesses,
  List<AssessmentContextLink> contextLinks,
  List<AssessmentDiagnostic> diagnostics,
});

/// Las reglas cruzadas de un snapshot, en orden: forma de huellas y fecha,
/// unicidad y orden canónico, testigos presentes, archivos, afirmaciones,
/// contexto citado, vínculos, cuentas, estados y cobertura.
void validateSnapshotParts(SnapshotParts s) {
  requireSemantic(
    isSha256Hex(s.snapshotId) && isSha256Hex(s.contextDigest),
    'digest_form',
  );
  requireSemantic(isUtcTimestamp(s.observedAt), 'observed_at');
  requireSemantic(s.coverage != AssessmentCoverage.notRun, 'coverage');
  _unique(s);
  _order(s);
  _witnessIdentity(s);
  _files(s);
  _claims(s);
  _groups(s.claims);
  _context(s);
  _links(s);
  _witnesses(s);
}

void _unique(SnapshotParts s) {
  bool distinct<T>(Iterable<T> keys) => keys.toSet().length == keys.length;
  requireSemantic(
    distinct(s.inputs.map((i) => (i.path, i.kind))),
    'duplicate_input',
  );
  requireSemantic(
    distinct(s.units.map((u) => u.path)) &&
        distinct(s.files.map((f) => f.path)),
    'duplicate_path',
  );
}

void _order(SnapshotParts s) {
  int byText(String a, String b) => a.compareTo(b);
  int pair(String a1, String a2, String b1, String b2) =>
      a1 == b1 ? a2.compareTo(b2) : a1.compareTo(b1);
  requireSemantic(
    isStrictlySorted([for (final u in s.units) u.id], byText) &&
        isStrictlySorted([for (final f in s.files) f.id], byText) &&
        isStrictlySorted([for (final c in s.claims) c.id], byText) &&
        isStrictlySorted(s.inputs, (a, b) {
          return pair(a.path, a.kind.toWireName(), b.path, b.kind.toWireName());
        }) &&
        isStrictlySorted([for (final w in s.witnesses) w.id], byText) &&
        isStrictlySorted(s.contextLinks, (a, b) {
          return pair(
            a.kind.toWireName(),
            a.sourceId,
            b.kind.toWireName(),
            b.sourceId,
          );
        }) &&
        isStrictlySorted(s.diagnostics, (a, b) {
          return pair(a.code, a.path ?? '', b.code, b.path ?? '');
        }),
    'order',
  );
}

void _witnessIdentity(SnapshotParts s) {
  requireSemantic(
    s.witnesses.length == AssessmentCapability.values.length &&
        {for (final w in s.witnesses) w.capability}.length ==
            AssessmentCapability.values.length,
    'capabilities',
  );
  requireSemantic(
    s.witnesses.every((w) => w.producerVersion == s.contract),
    'witness_identity',
  );
}

/// Cada archivo cita su propia entrada fuente y su unidad más profunda, y
/// cada fuente elegible del inventario tiene su archivo.
void _files(SnapshotParts s) {
  final unitIds = {for (final u in s.units) u.path: u.id};
  final sources = {
    for (final i in s.inputs)
      if (i.kind == AssessmentInputKind.source) i.path,
  };
  for (final file in s.files) {
    requireSemantic(
      file.path == file.inputPath && sources.contains(file.inputPath),
      'file_input',
      '/files',
    );
    requireSemantic(
      file.witnessId == AssessmentCapability.sourceReferences.toWireName(),
      'file_witness',
      '/files',
    );
    requireSemantic(
      unitIds[deepestUnitPath(file.path, unitIds.keys.toSet())] == file.unitId,
      'file_owner',
      '/files',
    );
  }
  requireSemantic(sources.length == s.files.length, 'file_input', '/files');
}

/// La unidad de raíz más profunda que contiene [path], o null.
String? deepestUnitPath(String path, Set<String> unitPaths) {
  var at = path;
  while (true) {
    final slash = at.lastIndexOf('/');
    at = slash < 0 ? '.' : at.substring(0, slash);
    if (unitPaths.contains(at)) return at;
    if (at == '.') return null;
  }
}

/// Las afirmaciones nacen de archivos analizados y leídos, bajo un testigo
/// de referencias que corrió; una local apunta a un archivo incluido de su
/// unidad.
void _claims(SnapshotParts s) {
  final files = {for (final f in s.files) f.id: f};
  final read = {
    for (final i in s.inputs)
      if (i.kind == AssessmentInputKind.source &&
          i.state == AssessmentInputState.read)
        i.path,
  };
  final ran = _referencesRan(s.witnesses);
  for (final claim in s.claims) {
    final source = files[claim.sourceFileId];
    requireSemantic(source != null, 'claim_source', '/claims');
    requireSemantic(
      source!.parseState == AssessmentParseState.parsed &&
          read.contains(source.inputPath),
      'unparsed_claim',
      '/claims',
    );
    requireSemantic(
      ran &&
          claim.witnessId == AssessmentCapability.sourceReferences.toWireName(),
      'claim_witness',
      '/claims',
    );
    _target(claim, files);
  }
}

/// Si el testigo de referencias corrió: sólo entonces nacen afirmaciones.
bool _referencesRan(List<AssessmentWitness> witnesses) {
  final state = witnesses
      .firstWhere((w) => w.capability == AssessmentCapability.sourceReferences)
      .state;
  return state != AssessmentWitnessState.failed &&
      state != AssessmentWitnessState.notRun;
}

void _target(AssessmentClaim claim, Map<String, AssessmentFile> files) {
  if (claim.resolution != AssessmentResolution.local) return;
  requireSemantic(
    files[claim.targetFileId]?.unitId == claim.targetUnitId,
    'claim_target',
    '/claims',
  );
}

/// Las alternativas de una directiva comparten archivo; un grupo es una
/// referencia incondicional, o una base con al menos una condición.
void _groups(List<AssessmentClaim> claims) {
  final groups = <String, List<AssessmentClaim>>{};
  for (final claim in claims) {
    groups.putIfAbsent(claim.groupId, () => []).add(claim);
  }
  for (final group in groups.values) {
    final conditions = [for (final c in group) c.condition];
    final always = conditions.where((c) => c == AssessmentCondition.always);
    final fallback = conditions.where((c) => c == AssessmentCondition.fallback);
    requireSemantic(
      {for (final c in group) c.sourceFileId}.length == 1 &&
          (group.length == 1
              ? always.length == 1
              : always.isEmpty && fallback.length == 1),
      'claim_group',
      '/claims',
    );
  }
}

void _context(SnapshotParts s) {
  final context = [
    for (final i in s.inputs)
      if (i.kind == AssessmentInputKind.context) i,
  ];
  requireSemantic(
    context.length == 1 &&
        context.single.path == assessmentContextPath &&
        context.single.state == AssessmentInputState.read &&
        context.single.sha256 == s.contextDigest,
    'context_input',
  );
}

void _links(SnapshotParts s) {
  final units = {for (final u in s.units) u.id};
  requireSemantic(
    s.contextLinks.every(
      (l) => l.targetUnitId == null || units.contains(l.targetUnitId),
    ),
    'link_target',
    '/contextLinks',
  );
}

/// Cada testigo tiene las cuentas y el estado que corresponden a las
/// colecciones; un inventario cortado no es completo, y la cobertura es la
/// que corresponde a los testigos.
void _witnesses(SnapshotParts s) {
  final WitnessBasis basis = (
    inventoryComplete: s.inventoryComplete,
    inputs: s.inputs,
    files: s.files,
    claims: s.claims,
    contextLinks: s.contextLinks,
  );
  for (final w in s.witnesses) {
    final counts = witnessCountsOf(w.capability, basis);
    requireSemantic(
      counts == (w.expected, w.processed, w.failed, w.omitted),
      'witness_counts',
      '/witnesses',
    );
    requireSemantic(
      w.state == witnessStateOf(w.capability, counts, basis),
      'witness_state',
      '/witnesses',
    );
  }
  _coverage(s);
}

/// Un inventario cortado no es completo, y la cobertura es la que
/// corresponde a los testigos.
void _coverage(SnapshotParts s) {
  final cut = s.inputs.any(
    (i) =>
        i.kind == AssessmentInputKind.directory &&
        i.state != AssessmentInputState.listed,
  );
  requireSemantic(!(s.inventoryComplete && cut), 'inventory');
  requireSemantic(
    s.coverage == coverageOf(s.witnesses, s.inventoryComplete),
    'coverage',
  );
}
