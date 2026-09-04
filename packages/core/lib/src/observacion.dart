/// Lo que el arnés observa: trazas, hallazgos inferenciales y resultados de
/// verificación.
library;

import 'entidades.dart';
import 'valores.dart';

/// Superficie **operacional** de una traza: herramientas, tokens, tiempos.
class OperationalSurface {
  final List<String> toolsUsed;
  final int inputTokens;
  final int outputTokens;
  final Duration elapsed;

  OperationalSurface({
    required List<String> toolsUsed,
    required this.inputTokens,
    required this.outputTokens,
    required this.elapsed,
  }) : toolsUsed = List.unmodifiable(toolsUsed);

  Map<String, Object?> toJson() => {
        'toolsUsed': toolsUsed,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'elapsed': elapsed.inMilliseconds,
      };

  factory OperationalSurface.fromJson(Map<String, Object?> json) =>
      OperationalSurface(
        toolsUsed: List<String>.from(json['toolsUsed']! as List<Object?>),
        inputTokens: json['inputTokens']! as int,
        outputTokens: json['outputTokens']! as int,
        elapsed: Duration(milliseconds: json['elapsed']! as int),
      );
}

/// Superficie **cognitiva**: plan y decisiones.
///
/// Es la más frágil de las tres: depende de que el CLI ajeno exponga su
/// razonamiento, y **no todos lo hacen**. Por eso [available] es un campo y no
/// un detalle: una superficie vacía porque el CLI no la expone tiene que ser
/// distinguible de una vacía porque no hubo decisiones (ADR-011, corolario 5).
class CognitiveSurface {
  final bool available;
  final List<String> decisions;
  final String? planSummary;

  CognitiveSurface({
    required this.available,
    List<String> decisions = const [],
    this.planSummary,
  }) : decisions = List.unmodifiable(decisions);

  Map<String, Object?> toJson() => {
        'available': available,
        'decisions': decisions,
        'planSummary': planSummary,
      };

  factory CognitiveSurface.fromJson(Map<String, Object?> json) =>
      CognitiveSurface(
        available: json['available']! as bool,
        decisions: List<String>.from(json['decisions']! as List<Object?>),
        planSummary: json['planSummary'] as String?,
      );
}

/// Superficie **contextual**: estado del código en cada inferencia.
class ContextualSurface {
  final String revision;
  final List<String> filesInContext;
  final bool dirtyWorktree;

  ContextualSurface({
    required this.revision,
    required List<String> filesInContext,
    required this.dirtyWorktree,
  }) : filesInContext = List.unmodifiable(filesInContext);

  Map<String, Object?> toJson() => {
        'revision': revision,
        'filesInContext': filesInContext,
        'dirtyWorktree': dirtyWorktree,
      };

  factory ContextualSurface.fromJson(Map<String, Object?> json) =>
      ContextualSurface(
        revision: json['revision']! as String,
        filesInContext:
            List<String>.from(json['filesInContext']! as List<Object?>),
        dirtyWorktree: json['dirtyWorktree']! as bool,
      );
}

/// Una corrida del agente, normalizada a un esquema propio.
class Trace {
  final String runId;
  final DateTime startedAt;
  final OperationalSurface operational;
  final CognitiveSurface cognitive;
  final ContextualSurface contextual;

  Trace({
    required this.runId,
    required this.startedAt,
    required this.operational,
    required this.cognitive,
    required this.contextual,
  });

  Map<String, Object?> toJson() => {
        'runId': runId,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'operational': operational.toJson(),
        'cognitive': cognitive.toJson(),
        'contextual': contextual.toJson(),
      };

  factory Trace.fromJson(Map<String, Object?> json) => Trace(
        runId: json['runId']! as String,
        startedAt: DateTime.parse(json['startedAt']! as String),
        operational: OperationalSurface.fromJson(
            Map<String, Object?>.from(json['operational']! as Map)),
        cognitive: CognitiveSurface.fromJson(
            Map<String, Object?>.from(json['cognitive']! as Map)),
        contextual: ContextualSurface.fromJson(
            Map<String, Object?>.from(json['contextual']! as Map)),
      );
}

/// La salida de un sensor **inferencial**. Anota, no bloquea.
///
/// **No tiene campo de severidad, y esa ausencia es el invariante** (INV-4,
/// ADR-006): no se puede configurar un [Finding] para que detenga nada, porque
/// no hay dónde escribirlo. Un control que necesite bloquear tiene que producir
/// un [Diagnostic], y para eso tiene que ser determinista.
class Finding {
  final String sensorId;

  /// Qué criterio del sensor lo produjo. Sin id no hay telemetría ni promoción
  /// de regla, que es el hueco `RS-2` del sensor real analizado.
  final String criterionId;

  final String file;
  final int? line;

  /// La nota del sensor, tal como la escribió (INV-6).
  final QuotedText note;

  Finding({
    required this.sensorId,
    required this.criterionId,
    required this.file,
    required this.note,
    this.line,
  });

  Map<String, Object?> toJson() => {
        'sensorId': sensorId,
        'criterionId': criterionId,
        'file': file,
        'line': line,
        'note': note.toJson(),
      };

  factory Finding.fromJson(Map<String, Object?> json) => Finding(
        sensorId: json['sensorId']! as String,
        criterionId: json['criterionId']! as String,
        file: json['file']! as String,
        line: json['line'] as int?,
        note: QuotedText.fromJson(
            Map<String, Object?>.from(json['note']! as Map)),
      );
}

/// Por qué un paso **no tuvo nada que hacer**. No es un [Witness].
///
/// **Un testigo atestigua una invocación, y acá no hubo ninguna.** Cuando no
/// queda ningún sujeto de la incumbencia del paso no hay herramienta que
/// llamar —hacerlo sin rutas la haría mirar el directorio entero— así que no
/// hay terminación ni código de salida que registrar.
///
/// Existe porque se estaba fabricando: el paso devolvía un testigo con
/// `Termination.completa` y código 0, que significa literalmente «la
/// herramienta corrió y produjo un resultado». Peor: la cascada **exigía ese
/// hecho falso** para clasificar bien el salto, así que lo correcto dependía
/// de una mentira. Lo encontró un review, y la raíz que nombró es esta: querer
/// representar ejecución, inaplicabilidad y observabilidad con los mismos
/// campos empuja la contradicción hacia el CLI y la documentación.
class NotApplicable {
  /// Sobre qué se preguntó. Vacío es un dato: no le dieron alcance.
  final List<String> subjects;

  /// Por qué ninguno era suyo, uno por sujeto. **Vacía no se acepta**: un paso
  /// que no dice por qué no tuvo nada que hacer es un salto silencioso, y el
  /// corolario 1 de ADR-011 lo prohíbe.
  final List<String> reasons;

  final DateTime decidedAt;

  NotApplicable({
    required List<String> subjects,
    required List<String> reasons,
    required this.decidedAt,
  })  : subjects = List.unmodifiable(subjects),
        reasons = List.unmodifiable(reasons) {
    if (this.reasons.every((m) => m.trim().isEmpty)) {
      throw ArgumentError.value(
          reasons,
          'reasons',
          'Un paso que no dice por qué no tuvo nada que hacer es un salto '
              'silencioso. Escribí el motivo, o no declares que no aplicaba');
    }
  }

  Map<String, Object?> toJson() => {
        'subjects': subjects,
        'reasons': reasons,
        'decidedAt': decidedAt.toUtc().toIso8601String(),
      };

  factory NotApplicable.fromJson(Map<String, Object?> json) => NotApplicable(
        subjects: List<String>.from(json['subjects']! as List<Object?>),
        reasons: List<String>.from(json['reasons']! as List<Object?>),
        decidedAt: DateTime.parse(json['decidedAt']! as String),
      );
}

/// El resultado de un paso de la cascada: **par (diagnósticos, testigo)**.
///
/// [verdict] se **deriva**; no es un campo que alguien pueda escribir en verde.
/// Sin [witness], o con un testigo que no atestigua sobre nada, el veredicto es
/// [Verdict.noConcluyente] y se trata como rojo (INV-2, `D-001`, `D-003`).
///
/// Esta es la diferencia entera entre este arnés y el intento anterior: allá el
/// verde era un valor que se asignaba; acá es una conclusión que se calcula, y
/// solo se puede calcular si hubo alguien mirando.
class VerificationOutcome {
  final String verifierId;
  final List<Diagnostic> diagnostics;

  /// Qué corrió y sobre qué. `null` significa **que no corrió, o que nadie
  /// registró que corriera**, y las dos cosas son lo mismo para el veredicto.
  final Witness? witness;

  /// **No tenía nada que hacer.** Excluyente con [witness]: o hubo invocación
  /// y hay testigo, o no la hubo y hay motivo.
  final NotApplicable? notApplicable;

  /// Los diagnósticos se copian: el veredicto se deriva de ellos, y una lista
  /// mutable desde afuera es un veredicto mutable desde afuera.
  VerificationOutcome({
    required this.verifierId,
    required List<Diagnostic> diagnostics,
    this.witness,
    this.notApplicable,
  }) : diagnostics = List.unmodifiable(diagnostics) {
    // **No se puede haber invocado Y no haber tenido nada que hacer.** Un
    // resultado que declarara las dos cosas dejaría a quien lo lea eligiendo
    // cuál creer, que es peor que no declarar ninguna.
    if (witness != null && notApplicable != null) {
      throw ArgumentError(
          'Un paso o invocó una herramienta —y hay testigo— o no tuvo nada que '
          'hacer —y hay motivo—. Declarar las dos cosas no significa nada');
    }
  }

  /// El veredicto, calculado. No hay forma de fijarlo desde afuera.
  Verdict get verdict {
    final w = witness;
    if (w == null || !w.attests) return Verdict.noConcluyente;
    final bloquea = diagnostics.any((d) => d.severity == Severity.bloquea);
    return bloquea ? Verdict.rojo : Verdict.verde;
  }

  Map<String, Object?> toJson() => {
        'verifierId': verifierId,
        'diagnostics': [for (final d in diagnostics) d.toJson()],
        'witness': witness?.toJson(),
        'notApplicable': notApplicable?.toJson(),
      };

  factory VerificationOutcome.fromJson(Map<String, Object?> json) =>
      VerificationOutcome(
        verifierId: json['verifierId']! as String,
        diagnostics: [
          for (final d in json['diagnostics']! as List<Object?>)
            Diagnostic.fromJson(Map<String, Object?>.from(d! as Map)),
        ],
        witness: json['witness'] == null
            ? null
            : Witness.fromJson(
                Map<String, Object?>.from(json['witness']! as Map)),
        notApplicable: json['notApplicable'] == null
            ? null
            : NotApplicable.fromJson(
                Map<String, Object?>.from(json['notApplicable']! as Map)),
      );
}
