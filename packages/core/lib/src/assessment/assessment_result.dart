import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'assessment_enums.dart';
import 'assessment_projection.dart';
import 'assessment_snapshot.dart';
import 'assessment_witnesses.dart';

const assessmentResponseKind = 'shipflow.assessment-response';
const _exitCodes = {0, 64, 65, 66, 70, 74, 75, 130};

/// Lo que una ejecución hizo: rutas propias creadas, reemplazadas y
/// retiradas, si se comprobó la publicación, y cuántas consultas a Git
/// lanzó. Nunca red ni escrituras en el producto.
final class AssessmentEffects {
  AssessmentEffects({
    required List<String> created,
    required List<String> replaced,
    required List<String> removed,
    required this.published,
    required this.gitQueries,
  }) : created = List.unmodifiable(created),
       replaced = List.unmodifiable(replaced),
       removed = List.unmodifiable(removed);

  factory AssessmentEffects.fromJson(Map<String, Object?> json) {
    requireSemantic(
      json['network'] == 0 && json['productWrites'] == 0,
      'effects',
    );
    return AssessmentEffects(
      created: readStrings(json['created']),
      replaced: readStrings(json['replaced']),
      removed: readStrings(json['removed']),
      published: json['published']! as bool,
      gitQueries: json['gitQueries']! as int,
    );
  }

  final List<String> created;
  final List<String> replaced;
  final List<String> removed;
  final bool published;
  final int gitQueries;
  final int network = 0;
  final int productWrites = 0;

  Map<String, Object?> toJson() => {
    'created': created,
    'replaced': replaced,
    'removed': removed,
    'published': published,
    'gitQueries': gitQueries,
    'network': network,
    'productWrites': productWrites,
  };
}

/// Un comando ya implementado, como argumentos, con su finalidad y su
/// efecto. Nunca una línea de shell.
final class AssessmentNextAction {
  AssessmentNextAction({
    required List<String> argv,
    required this.purpose,
    required this.effect,
  }) : argv = List.unmodifiable(argv);

  factory AssessmentNextAction.fromJson(Map<String, Object?> json) =>
      AssessmentNextAction(
        argv: readStrings(json['argv']),
        purpose: json['purpose']! as String,
        effect: AssessmentActionEffect.fromWireName(json['effect']! as String),
      );

  final List<String> argv;
  final String purpose;
  final AssessmentActionEffect effect;

  Map<String, Object?> toJson() => {
    'argv': argv,
    'purpose': purpose,
    'effect': effect.toWireName(),
  };
}

/// La respuesta de assess: resultado, vigencia y cobertura como ejes
/// independientes. Publicado o código 0 no significa completo ni vigente.
final class AssessmentResult {
  AssessmentResult({
    required this.operation,
    required this.exitCode,
    required this.outcome,
    required this.freshness,
    required this.coverage,
    required this.snapshot,
    required List<AssessmentDiagnostic> diagnostics,
    required this.effects,
    required List<AssessmentNextAction> nextActions,
    required this.comparison,
    required this.retiredRevision,
  }) : diagnostics = List.unmodifiable(diagnostics),
       nextActions = List.unmodifiable(nextActions) {
    validateAssessmentResult(this);
  }

  /// Sólo tras validar la forma por fuera: no es un lector tolerante.
  factory AssessmentResult.fromJson(Map<String, Object?> json) {
    requireSemantic(json['schemaVersion'] == 1, 'schema_version');
    requireSemantic(json['kind'] == assessmentResponseKind, 'kind');
    requireSemantic(json['command'] == 'assess', 'command');
    return AssessmentResult(
      operation: AssessmentOperation.fromWireName(json['operation']! as String),
      exitCode: json['exitCode']! as int,
      outcome: AssessmentOutcome.fromWireName(json['outcome']! as String),
      freshness: AssessmentFreshness.fromWireName(json['freshness']! as String),
      coverage: AssessmentCoverage.fromWireName(json['coverage']! as String),
      snapshot: json['snapshot'] == null
          ? null
          : readObject(json['snapshot'], AssessmentSnapshot.fromJson),
      diagnostics: readObjects(
        json['diagnostics'],
        AssessmentDiagnostic.fromJson,
      ),
      effects: readObject(json['effects'], AssessmentEffects.fromJson),
      nextActions: readObjects(
        json['nextActions'],
        AssessmentNextAction.fromJson,
      ),
      comparison: json['comparison'] == null
          ? null
          : readObject(json['comparison'], AssessmentComparison.fromJson),
      retiredRevision: json['retiredRevision'] as int?,
    );
  }

  final int schemaVersion = 1;
  final String kind = assessmentResponseKind;
  final String command = 'assess';
  final AssessmentOperation operation;
  final int exitCode;
  final AssessmentOutcome outcome;
  final AssessmentFreshness freshness;
  final AssessmentCoverage coverage;
  final AssessmentSnapshot? snapshot;
  final List<AssessmentDiagnostic> diagnostics;
  final AssessmentEffects effects;
  final List<AssessmentNextAction> nextActions;
  final AssessmentComparison? comparison;

  /// La revisión que dejó de conservarse al publicar, si alguna.
  final int? retiredRevision;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'kind': kind,
    'command': command,
    'operation': operation.toWireName(),
    'exitCode': exitCode,
    'outcome': outcome.toWireName(),
    'freshness': freshness.toWireName(),
    'coverage': coverage.toWireName(),
    'snapshot': snapshot?.toJson(),
    'diagnostics': [for (final d in diagnostics) d.toJson()],
    'effects': effects.toJson(),
    'nextActions': [for (final a in nextActions) a.toJson()],
    'comparison': comparison?.toJson(),
    'retiredRevision': retiredRevision,
  };
}

/// Los ejes no se contradicen: la cobertura es la del snapshot mostrado,
/// una vigencia obsoleta o no comprobada nunca sale con 0, sólo una
/// consulta es histórica y una publicación comprobada no es un bloqueo.
void validateAssessmentResult(AssessmentResult r) {
  requireSemantic(_exitCodes.contains(r.exitCode), 'exit_code');
  requireSemantic(
    r.snapshot == null || r.snapshot!.coverage == r.coverage,
    'coverage',
  );
  requireSemantic(
    r.exitCode != 0 ||
        (r.freshness != AssessmentFreshness.stale &&
            r.freshness != AssessmentFreshness.unverified),
    'stale_success',
  );
  requireSemantic(
    !r.effects.published || _publishing.contains(r.outcome),
    'publication_outcome',
  );
  requireSemantic(
    r.freshness != AssessmentFreshness.historical ||
        r.operation == AssessmentOperation.show,
    'historical',
  );
  requireSemantic(
    r.retiredRevision == null || r.retiredRevision! >= 1,
    'retired_revision',
  );
}

/// Los resultados que pueden acompañar una publicación comprobada.
const _publishing = {
  AssessmentOutcome.saved,
  AssessmentOutcome.recovered,
  AssessmentOutcome.failed,
  AssessmentOutcome.cancelled,
};
