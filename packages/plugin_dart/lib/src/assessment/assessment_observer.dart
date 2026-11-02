import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

import 'assessment_claims_builder.dart';
import 'assessment_context_projection.dart';
import 'assessment_diagnostics.dart';
import 'assessment_ids.dart';
import 'directive_extractor.dart';
import 'local_reference_resolver.dart';
import 'parser_worker.dart';
import 'source_inventory.dart';

export 'directive_extractor.dart' show parserVersion;
export 'parser_worker.dart' show DirectiveParser;

/// El contrato del detector: alcance, exclusiones y semántica de las
/// afirmaciones. Cambia con su semántica, no con la distribución.
const assessmentContract = 'source-topology-v3.2';

/// El plugin que produce el levantamiento.
const assessmentPluginId = 'plugin_dart';

/// Observa las fuentes de las unidades de [context] bajo [root]: inventario
/// sellado, directivas por su árbol sintáctico, resolución acotada y
/// vínculos al contexto citado. No publica ni decide la modalidad.
Future<AssessmentObservation> observeDartSources(
  Directory root,
  ProjectContext context,
  AssessmentLimits limits, {
  DirectiveParser? parser,
  int Function()? elapsedMillis,
}) async {
  final clock = Stopwatch()..start();
  final elapsed = elapsedMillis ?? () => clock.elapsedMilliseconds;
  final basis = projectDartAssessmentContext(context);
  final diagnostics = DiagnosticGroups();
  final inventory = await inventorySources(
    root,
    context,
    limits,
    elapsedMillis: elapsed,
    diagnostics: diagnostics,
  );
  final worker = parser == null ? IsolateDirectiveParser() : null;
  try {
    final parsed = await _parse(
      inventory,
      context,
      limits,
      parser ?? worker!.call,
      elapsed,
      diagnostics,
    );
    return _observation(basis, inventory, parsed, diagnostics, elapsed());
  } finally {
    await worker?.close();
  }
}

/// El inventario que comparte la generación, sin parser: para comprobar la
/// vigencia de un levantamiento guardado. Un corte o un fallo quedan como
/// entradas fuera de presupuesto o ilegibles, nunca como lista vacía.
Future<List<AssessmentInput>> observeDartInputs(
  Directory root,
  ProjectContext context,
  AssessmentLimits limits,
) async {
  final clock = Stopwatch()..start();
  final inventory = await inventorySources(
    root,
    context,
    limits,
    elapsedMillis: () => clock.elapsedMilliseconds,
    diagnostics: DiagnosticGroups(),
    keepBytes: false,
  );
  return inventory.inputs;
}

typedef _Parsed = ({List<AssessmentFile> files, List<AssessmentClaim> claims});

/// Analiza cada fuente leída en orden de ruta y admite sus afirmaciones
/// enteras o ninguna.
Future<_Parsed> _parse(
  SourceInventory inventory,
  ProjectContext context,
  AssessmentLimits limits,
  DirectiveParser parser,
  int Function() elapsed,
  DiagnosticGroups diagnostics,
) async {
  final builder = ClaimsBuilder(
    LocalReferenceResolver(inventory, context.recognition),
    diagnostics,
  );
  final files = <AssessmentFile>[];
  for (final source in inventory.sources) {
    final state = await _parseOne(source, limits, parser, elapsed, builder);
    if (state.$2 != null) diagnostics.add(state.$2!, source.path);
    files.add(_file(source, state.$1));
  }
  return (
    files: files..sort((a, b) => a.id.compareTo(b.id)),
    claims: builder.claims..sort((a, b) => a.id.compareTo(b.id)),
  );
}

/// El estado de análisis de [source] y el diagnóstico que deja, si alguno.
Future<(AssessmentParseState, String?)> _parseOne(
  InventorySource source,
  AssessmentLimits limits,
  DirectiveParser parser,
  int Function() elapsed,
  ClaimsBuilder builder,
) async {
  final bytes = source.bytes;
  if (source.state != AssessmentInputState.read || bytes == null) {
    return (AssessmentParseState.notRun, null);
  }
  if (elapsed() > limits.maxObservationMillis) {
    return (AssessmentParseState.notRun, 'observation_deadline');
  }
  final String content;
  try {
    content = utf8.decode(bytes);
  } on FormatException {
    return (AssessmentParseState.failed, 'parse_failed');
  }
  final batch = await parser(
    content,
    source.path,
    Duration(milliseconds: limits.maxParseMillis),
  );
  return switch (batch) {
    ParsedDirectives(:final directives) =>
      builder.admit(source, directives, limits.maxClaims)
          ? (AssessmentParseState.parsed, null)
          : (AssessmentParseState.notRun, 'claims_budget'),
    ParseFailed() => (AssessmentParseState.failed, 'parse_failed'),
    ParseTimedOut() => (AssessmentParseState.notRun, 'parse_deadline'),
  };
}

AssessmentFile _file(InventorySource source, AssessmentParseState state) =>
    AssessmentFile(
      id: assessmentId(fileIdPrefix, fileTuple(source.path)),
      path: source.path,
      unitId: unitIdOf(source.unitPath),
      inputPath: source.path,
      role: source.role,
      parseState: state,
      witnessId: AssessmentCapability.sourceReferences.toWireName(),
    );

AssessmentObservation _observation(
  AssessmentContextBasis basis,
  SourceInventory inventory,
  _Parsed parsed,
  DiagnosticGroups diagnostics,
  int elapsed,
) => AssessmentObservation(
  inventoryComplete: inventory.complete,
  units: basis.units,
  inputs: inventory.inputs,
  files: parsed.files,
  claims: parsed.claims,
  contextLinks: basis.contextLinks,
  diagnostics: diagnostics.build(),
  metrics: AssessmentMetrics(
    entries: inventory.entries,
    sourceBytes: inventory.sourceBytes,
    parsedFiles: parsed.files
        .where((f) => f.parseState == AssessmentParseState.parsed)
        .length,
    elapsedMillis: elapsed,
  ),
);
