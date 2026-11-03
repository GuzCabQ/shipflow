import 'package:core/core.dart';

import 'assessment_decisions.dart';

/// El resultado en construcción de una operación: cada flujo lo completa y
/// lo cierra una sola vez. El código de salida sale de los diagnósticos; las
/// acciones, de los diagnósticos y de lo que el flujo propone.
final class AssessmentDraft {
  AssessmentDraft(this.operation);

  final AssessmentOperation operation;
  var outcome = AssessmentOutcome.blocked;
  var freshness = AssessmentFreshness.notApplicable;
  var coverage = AssessmentCoverage.notRun;
  AssessmentSnapshot? snapshot;
  final diagnostics = <AssessmentDiagnostic>[];
  final created = <String>[];
  final replaced = <String>[];
  final removed = <String>[];
  var published = false;
  var gitQueries = 0;
  final actions = <AssessmentNextAction>[];
  AssessmentComparison? comparison;
  int? retiredRevision;

  void add(String code, {List<String> examples = const [], int? count}) =>
      diagnostics.add(
        assessmentDiagnostic(code, examples: examples, count: count),
      );

  bool has(String code) => diagnostics.any((d) => d.code == code);

  /// Si algo ya impide seguir: cualquier diagnóstico que no sea aviso.
  bool get stopped => diagnostics.any((d) => !isAssessmentWarning(d.code));

  /// [snapshot] como el mostrado, con su cobertura.
  void present(AssessmentSnapshot shown) {
    snapshot = shown;
    coverage = shown.coverage;
  }

  /// Las acciones del flujo y las de cada diagnóstico, sin repetir.
  List<AssessmentNextAction> _proposed(List<AssessmentDiagnostic> ordered) {
    final show = operation == AssessmentOperation.show;
    return <String, AssessmentNextAction>{
      for (final a in actions) a.argv.join('\u0000'): a,
      for (final d in ordered)
        for (final a in actionsFor(d.actionCode, show: show))
          a.argv.join('\u0000'): a,
    }.values.take(10).toList();
  }

  AssessmentResult build() {
    final ordered = byPrecedence(diagnostics);
    return AssessmentResult(
      operation: operation,
      exitCode: assessmentExitCode(ordered),
      outcome: outcome,
      freshness: freshness,
      coverage: coverage,
      snapshot: snapshot,
      diagnostics: ordered.take(maxAssessmentDiagnostics).toList(),
      effects: AssessmentEffects(
        created: created,
        replaced: replaced,
        removed: removed,
        published: published,
        gitQueries: gitQueries,
      ),
      nextActions: _proposed(ordered),
      comparison: comparison,
      retiredRevision: retiredRevision,
    );
  }
}
