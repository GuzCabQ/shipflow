import '../context/context_validation.dart';
import '../recognition/recognition_json.dart';
import 'basis_enums.dart';
import 'basis_model.dart';

/// El contenido de una versión de registro: una fuente, una regla o un
/// pendiente. El tipo de un ID no cambia entre versiones.
abstract class BasisPayload {
  BasisPayload();

  /// Por su `kind`; sólo tras validar la forma por fuera.
  factory BasisPayload.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'source' => BasisSource.fromJson(json),
        'rule' => BasisRule.fromJson(json),
        'pending' => BasisPending.fromJson(json),
        _ => throw const ContextFormatException(
          ContextFormatLayer.schema,
          'invalid_schema',
          'kind',
        ),
      };

  String get kind;
  String get title;
  BasisScope get scope;

  /// Las versiones exactas de fuentes que cita; una fuente no cita nada.
  List<BasisReference> get citedSources;

  Map<String, Object?> toJson();
}

/// Una fuente señalada: local, cuyo contenido se lee acotado bajo la raíz,
/// o externa, que se conserva como referencia sin red.
final class BasisSource extends BasisPayload {
  BasisSource({
    required this.title,
    required this.scope,
    required this.lifecycle,
    required this.sourceType,
    required this.locator,
    required this.purpose,
    required this.contentDigest,
    required this.observation,
  });

  factory BasisSource.fromJson(Map<String, Object?> json) {
    requireSemantic(json['kind'] == 'source', 'invalid_schema');
    return BasisSource(
      title: json['title']! as String,
      scope: readObject(json['scope'], BasisScope.fromJson),
      lifecycle: BasisSourceLifecycle.fromWireName(
        json['lifecycle']! as String,
      ),
      sourceType: BasisSourceType.fromWireName(json['sourceType']! as String),
      locator: json['locator']! as String,
      purpose: json['purpose']! as String,
      contentDigest: json['contentDigest'] as String?,
      observation: BasisObservation.fromWireName(
        json['observation']! as String,
      ),
    );
  }

  @override
  final String kind = 'source';
  @override
  final String title;
  @override
  final BasisScope scope;
  final BasisSourceLifecycle lifecycle;
  final BasisSourceType sourceType;
  final String locator;
  final String purpose;

  /// `sha256:<hex>` del contenido leído; null si no se leyó.
  final String? contentDigest;
  final BasisObservation observation;

  @override
  List<BasisReference> get citedSources => const [];

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'scope': scope.toJson(),
    'lifecycle': lifecycle.toWireName(),
    'sourceType': sourceType.toWireName(),
    'locator': locator,
    'purpose': purpose,
    'contentDigest': contentDigest,
    'observation': observation.toWireName(),
  };
}

/// Una decisión en prosa: su nivel demostrado es siempre `declared`; no se
/// ejecuta contra el código ni se certifica su cumplimiento.
final class BasisRule extends BasisPayload {
  BasisRule({
    required this.title,
    required this.scope,
    required this.lifecycle,
    required this.replacementRef,
    required this.statement,
    required this.reason,
    required this.ruleClass,
    required this.alternative,
    required this.exceptionPolicy,
    required this.support,
    required List<BasisReference> sourceRefs,
  }) : sourceRefs = List.unmodifiable(sourceRefs);

  factory BasisRule.fromJson(Map<String, Object?> json) {
    requireSemantic(json['kind'] == 'rule', 'invalid_schema');
    requireSemantic(json['evidenceLevel'] == 'declared', 'invalid_schema');
    return BasisRule(
      title: json['title']! as String,
      scope: readObject(json['scope'], BasisScope.fromJson),
      lifecycle: BasisRuleLifecycle.fromWireName(json['lifecycle']! as String),
      replacementRef: json['replacementRef'] as String?,
      statement: json['statement']! as String,
      reason: json['reason']! as String,
      ruleClass: BasisRuleClass.fromWireName(json['ruleClass']! as String),
      alternative: json['alternative'] as String?,
      exceptionPolicy: BasisExceptionPolicy.fromWireName(
        json['exceptionPolicy']! as String,
      ),
      support: BasisSupport.fromWireName(json['support']! as String),
      sourceRefs: readObjects(json['sourceRefs'], BasisReference.fromJson),
    );
  }

  @override
  final String kind = 'rule';
  @override
  final String title;
  @override
  final BasisScope scope;
  final BasisRuleLifecycle lifecycle;

  /// La regla que la reemplaza, sólo si [lifecycle] es replaced.
  final String? replacementRef;
  final String statement;
  final String reason;
  final BasisRuleClass ruleClass;

  /// La alternativa permitida; una prohibición activa la exige.
  final String? alternative;
  final BasisExceptionPolicy exceptionPolicy;
  final BasisSupport support;
  final List<BasisReference> sourceRefs;
  final String evidenceLevel = 'declared';

  @override
  List<BasisReference> get citedSources => sourceRefs;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'scope': scope.toJson(),
    'lifecycle': lifecycle.toWireName(),
    'replacementRef': replacementRef,
    'statement': statement,
    'reason': reason,
    'ruleClass': ruleClass.toWireName(),
    'alternative': alternative,
    'exceptionPolicy': exceptionPolicy.toWireName(),
    'support': support.toWireName(),
    'sourceRefs': [for (final r in sourceRefs) r.toJson()],
    'evidenceLevel': evidenceLevel,
  };
}

/// Un asunto por aclarar: una pregunta ordinaria ([decisionReview] null) o
/// la revisión pendiente de una decisión aceptada. Un pendiente no revoca
/// ni suspende la decisión; sólo se resuelve con una resolución explícita.
final class BasisPending extends BasisPayload {
  BasisPending({
    required this.title,
    required this.scope,
    required this.status,
    required this.question,
    required this.reason,
    required this.revisitWhen,
    required List<BasisReference> sourceRefs,
    required this.resolution,
    required this.decisionReview,
  }) : sourceRefs = List.unmodifiable(sourceRefs);

  factory BasisPending.fromJson(Map<String, Object?> json) {
    requireSemantic(json['kind'] == 'pending', 'invalid_schema');
    return BasisPending(
      title: json['title']! as String,
      scope: readObject(json['scope'], BasisScope.fromJson),
      status: BasisPendingStatus.fromWireName(json['status']! as String),
      question: json['question']! as String,
      reason: json['reason']! as String,
      revisitWhen: json['revisitWhen']! as String,
      sourceRefs: readObjects(json['sourceRefs'], BasisReference.fromJson),
      resolution: json['resolution'] as String?,
      decisionReview: json['decisionReview'] == null
          ? null
          : readObject(json['decisionReview'], BasisDecisionReview.fromJson),
    );
  }

  @override
  final String kind = 'pending';
  @override
  final String title;
  @override
  final BasisScope scope;
  final BasisPendingStatus status;
  final String question;
  final String reason;

  /// Un acontecimiento o fecha en texto: no hay planificador ni caducidad.
  final String revisitWhen;
  final List<BasisReference> sourceRefs;

  /// `rule:<uuid>@<version>` o `disposition:<texto>`; null si abierto.
  final String? resolution;
  final BasisDecisionReview? decisionReview;

  @override
  List<BasisReference> get citedSources => sourceRefs;

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'title': title,
    'scope': scope.toJson(),
    'status': status.toWireName(),
    'question': question,
    'reason': reason,
    'revisitWhen': revisitWhen,
    'sourceRefs': [for (final r in sourceRefs) r.toJson()],
    'resolution': resolution,
    'decisionReview': decisionReview?.toJson(),
  };
}
