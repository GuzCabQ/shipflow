import 'dart:io';

import 'package:core/core.dart';

import 'assessment_diagnostics.dart';
import 'inventory_walk.dart';
import 'source_reading.dart';

/// Una fuente elegible del universo: su unidad dueña, su papel, qué se hizo
/// con ella y, si se leyó y se pidió, sus bytes sellados.
final class InventorySource {
  const InventorySource({
    required this.path,
    required this.unitPath,
    required this.role,
    required this.state,
    required this.reason,
    required this.sha256,
    required this.bytes,
  });

  final String path;
  final String unitPath;
  final AssessmentFileRole role;
  final AssessmentInputState state;
  final String? reason;
  final String? sha256;
  final List<int>? bytes;
}

/// El inventario sellado: entradas ordenadas, fuentes elegibles y lo que el
/// resolvedor necesita saber del universo sin volver a mirar el disco.
final class SourceInventory {
  SourceInventory({
    required this.inputs,
    required this.sources,
    required this.complete,
    required this.entries,
    required this.sourceBytes,
    required this.listedDirectories,
    required this.knownEntries,
    required this.excluded,
  });

  final List<AssessmentInput> inputs;
  final List<InventorySource> sources;
  final bool complete;
  final int entries;
  final int sourceBytes;
  final Set<String> listedDirectories;
  final Set<String> knownEntries;
  final Set<String> excluded;
}

/// Recorre [root] una vez dentro de [limits] y lee cada fuente elegible
/// de una unidad en orden de ruta, dentro de los presupuestos de archivos,
/// bytes únicos y tiempo. Nunca se inventan filas.
Future<SourceInventory> inventorySources(
  Directory root,
  ProjectContext context,
  AssessmentLimits limits, {
  required int Function() elapsedMillis,
  required DiagnosticGroups diagnostics,
  bool keepBytes = true,
}) async {
  final walk = InventoryWalk(root, context, limits, elapsedMillis, diagnostics);
  await walk.visit('.', 0);
  final budget = SourceBudget(limits);
  final sources = <InventorySource>[];
  for (final (path, owner)
      in walk.candidates..sort((a, b) => a.$1.compareTo(b.$1))) {
    final read = await _readSource(walk, budget, path, keepBytes);
    if (read.reason != null) diagnostics.add(read.reason!, path);
    sources.add(_source(path, owner, read));
  }
  return _result(walk, sources, budget.bytes);
}

Future<SealedRead> _readSource(
  InventoryWalk walk,
  SourceBudget budget,
  String path,
  bool keep,
) async {
  if (walk.late) {
    return unsealedRead(AssessmentInputState.limit, 'observation_deadline');
  }
  final file = File(walk.absolute(path));
  final size = file.existsSync() ? file.lengthSync() : 0;
  final refused = budget.refuse(size);
  if (refused != null) return unsealedRead(AssessmentInputState.limit, refused);
  final read = await readSealed(
    walk.guard,
    file.path,
    walk.limits.maxSourceBytes,
    keep: keep,
  );
  if (read.state == AssessmentInputState.read) budget.charge(size);
  return read;
}

InventorySource _source(String path, String owner, SealedRead read) =>
    InventorySource(
      path: path,
      unitPath: owner,
      role: roleOf(path, owner),
      state: read.state,
      reason: read.reason,
      sha256: read.sha256,
      bytes: read.bytes,
    );

SourceInventory _result(
  InventoryWalk walk,
  List<InventorySource> sources,
  int sourceBytes,
) => SourceInventory(
  inputs: [
    ...walk.inputs,
    for (final s in sources)
      AssessmentInput(
        path: s.path,
        kind: AssessmentInputKind.source,
        state: s.state,
        sha256: s.sha256,
        reason: s.reason,
      ),
  ]..sort(compareInputs),
  sources: sources,
  complete: walk.complete,
  entries: walk.entries,
  sourceBytes: sourceBytes,
  listedDirectories: walk.listed,
  knownEntries: walk.known,
  excluded: walk.excluded,
);

/// Prueba sólo bajo `test/` o `integration_test/` de su unidad y con el
/// sufijo `_test.dart`; no se cuentan casos ni se ejecuta nada.
AssessmentFileRole roleOf(String path, String unitPath) {
  final inside = unitPath == '.' ? path : path.substring(unitPath.length + 1);
  final test =
      (inside.startsWith('test/') || inside.startsWith('integration_test/')) &&
      inside.endsWith('_test.dart');
  return test ? AssessmentFileRole.test : AssessmentFileRole.source;
}

/// El orden canónico de las entradas: ruta y después tipo.
int compareInputs(AssessmentInput a, AssessmentInput b) {
  final path = a.path.compareTo(b.path);
  return path != 0 ? path : a.kind.toWireName().compareTo(b.kind.toWireName());
}
