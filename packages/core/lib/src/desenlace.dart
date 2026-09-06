/// El desenlace de un paso: variantes cerradas, no campos opcionales.
///
/// **La jerarquía tiene dos niveles, y la diferencia es el invariante que
/// esta rebanada existe para instalar.** [StepOutcome] es todo lo que la
/// cascada puede producir; [VerificationOutcome] es el subconjunto propio que
/// un `Verifier` puede devolver. El salto, lo no observable y lo roto los
/// decide quien compone la corrida — nunca el verificador, que estaría
/// pidiendo y aprobando su propia exención — y por eso cuelgan directamente
/// de [StepOutcome] y no de [VerificationOutcome].
///
/// **Todas las variantes viven en este mismo archivo.** Una clase `sealed`
/// exige que sus subtipos directos estén en su misma biblioteca: no es estilo,
/// es lo que hace exhaustivo un `switch` sobre [StepKind].
library;

import 'alcance.dart';
import 'entidades.dart';
import 'valores.dart';

/// Qué NO cubrió un paso, y por qué.
///
/// **El sujeto es opcional, y la diferencia importa.** Con sujeto, la omisión
/// salda la obligación de ese par paso-sujeto: el paso dice que no lo miró y
/// dice por qué. Sin sujeto, es residuo general — el paso cuya herramienta no
/// informa qué archivos leyó no puede atribuirlo a ninguno.
class Omission {
  final String? subject;
  final String reason;

  /// **No es `const`, y no puede serlo:** valida en el cuerpo. Un `assert` no
  /// corre en producción, y este invariante tiene que valer siempre.
  Omission({this.subject, required this.reason}) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason',
          'Una omisión sin motivo no dice qué quedó afuera');
    }
    if (subject != null && subject!.trim().isEmpty) {
      throw ArgumentError.value(subject, 'subject',
          'Un sujeto en blanco no nombra nada. Si la omisión no es de ningún '
          'sujeto, dejalo nulo: eso significa residuo general');
    }
  }

  Map<String, Object?> toJson() => {'subject': subject, 'reason': reason};

  factory Omission.fromJson(Map<String, Object?> json) => Omission(
        subject: json['subject'] as String?,
        reason: json['reason']! as String,
      );
}

/// Un intento que no llegó a una terminación completa.
///
/// **Nunca [Termination.completa].** Si la herramienta corrió hasta el final,
/// lo que hay es un [Witness], no un intento: representar los dos casos con
/// el mismo tipo es exactamente el hecho falso que ADR-011 vino a impedir.
class Attempt {
  final String invocation;
  final List<String> subjects;
  final Termination termination;
  final int exitCode;

  /// Por qué no llegó a completarse. **No se acepta en blanco**: es la
  /// diferencia entre «no terminó» y «no terminó, y esto es lo que pasó».
  final String note;
  final DateTime finishedAt;

  Attempt({
    required this.invocation,
    required List<String> subjects,
    required this.termination,
    required this.exitCode,
    required this.note,
    required this.finishedAt,
  }) : subjects = List.unmodifiable(subjects) {
    if (termination == Termination.completa) {
      throw ArgumentError.value(termination, 'termination',
          'Un intento que terminó completo no es un intento: es un testigo. '
          'Construí un Witness, no un Attempt');
    }
    if (note.trim().isEmpty) {
      throw ArgumentError.value(
          note, 'note', 'Una nota en blanco no dice qué pasó');
    }
  }

  Map<String, Object?> toJson() => {
        'invocation': invocation,
        'subjects': subjects,
        'termination': termination.name,
        'exitCode': exitCode,
        'note': note,
        'finishedAt': finishedAt.toUtc().toIso8601String(),
      };

  factory Attempt.fromJson(Map<String, Object?> json) => Attempt(
        invocation: json['invocation']! as String,
        subjects: List<String>.from(json['subjects']! as List<Object?>),
        termination:
            Termination.values.byName(json['termination']! as String),
        exitCode: json['exitCode']! as int,
        note: json['note']! as String,
        finishedAt: DateTime.parse(json['finishedAt']! as String),
      );
}

/// Los cinco desenlaces posibles de un paso.
enum StepKind { executed, aborted, skipped, unobservable, broken }

/// **No lleva el id del paso.** Lo atribuye la cascada desde su registro, y
/// por eso un paso que devuelve el resultado de otro dejó de ser
/// representable.
sealed class StepOutcome {
  StepKind get kind;

  /// **No hay `toJson` declarado acá arriba.** El verificador de campos de
  /// este repositorio lee un `toJson` desde su literal de mapa devuelto, y
  /// una firma abstracta sin cuerpo no tiene ninguno que leer. Cada variante
  /// trae el suyo, con cuerpo; serializar un `StepOutcome` genérico es el
  /// `switch` exhaustivo de siempre sobre una clase sellada.

  /// Despacha por [kind]. **Un discriminador que no nombra ninguna variante
  /// lanza**: `StepKind.values.byName` no tiene una lectura benigna para eso,
  /// y no se le agrega ninguna. Caer en la variante más mansa —por ejemplo,
  /// tratar cualquier valor desconocido como [Broken]— sería inventar un
  /// hecho que nadie afirmó.
  static StepOutcome fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    return switch (kind) {
      StepKind.executed => Executed.fromJson(json),
      StepKind.aborted => Aborted.fromJson(json),
      StepKind.skipped => Skipped.fromJson(json),
      StepKind.unobservable => Unobservable.fromJson(json),
      StepKind.broken => Broken.fromJson(json),
    };
  }
}

/// Lo único que un `Verifier` puede devolver.
///
/// El salto, lo no observable y lo roto **no están acá a propósito**: los
/// produce quien compone la corrida. Un verificador que pudiera devolverlos
/// estaría pidiendo y aprobando su propia exención.
sealed class VerificationOutcome extends StepOutcome {}

/// El paso corrió hasta el final, con o sin diagnósticos.
class Executed extends VerificationOutcome {
  @override
  final StepKind kind = StepKind.executed;

  final Witness witness;

  /// Se copian: el veredicto se deriva de ellos, y una lista mutable desde
  /// afuera sería un veredicto mutable desde afuera.
  final List<Diagnostic> diagnostics;

  Executed({required this.witness, required List<Diagnostic> diagnostics})
      : diagnostics = List.unmodifiable(diagnostics);

  /// El veredicto, calculado. No hay forma de fijarlo desde afuera: sin
  /// sujetos cubiertos no es concluyente, y con un bloqueante es rojo.
  Verdict get verdict {
    if (witness.subjects.isEmpty) return Verdict.noConcluyente;
    return diagnostics.any((d) => d.severity == Severity.bloquea)
        ? Verdict.rojo
        : Verdict.verde;
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'witness': witness.toJson(),
        'diagnostics': [for (final d in diagnostics) d.toJson()],
      };

  factory Executed.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.executed) {
      throw ArgumentError.value(kind, 'kind',
          'Executed.fromJson recibió un discriminador que no es el suyo');
    }
    return Executed(
      witness: Witness.fromJson(
          Map<String, Object?>.from(json['witness']! as Map)),
      diagnostics: [
        for (final d in json['diagnostics']! as List<Object?>)
          Diagnostic.fromJson(Map<String, Object?>.from(d! as Map)),
      ],
    );
  }
}

/// El paso no llegó a terminar: el intento queda registrado, sin testigo.
class Aborted extends VerificationOutcome {
  @override
  final StepKind kind = StepKind.aborted;

  final Attempt attempt;

  Aborted({required this.attempt});

  Map<String, Object?> toJson() =>
      {'kind': kind.name, 'attempt': attempt.toJson()};

  factory Aborted.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.aborted) {
      throw ArgumentError.value(kind, 'kind',
          'Aborted.fromJson recibió un discriminador que no es el suyo');
    }
    return Aborted(
      attempt:
          Attempt.fromJson(Map<String, Object?>.from(json['attempt']! as Map)),
    );
  }
}

/// Ninguno de los sujetos pedidos era del stack: no había nada que invocar.
///
/// **No lo decide un `Verifier`.** Corolario 4 de ADR-011: declarar «esto no
/// es mío» es juzgar la propia cobertura. Lo decide quien compone la corrida,
/// a partir de lo que devolvió el observador de alcance.
class Skipped extends StepOutcome {
  @override
  final StepKind kind = StepKind.skipped;

  final List<ObservedSubject> notOfStack;

  Skipped({required List<ObservedSubject> notOfStack})
      : notOfStack = List.unmodifiable(notOfStack) {
    if (this.notOfStack.isEmpty) {
      throw ArgumentError.value(notOfStack, 'notOfStack',
          'Un salto sin sujetos ajenos no es un salto: no hay nada que '
          'explique por qué el paso no tenía nada que hacer');
    }
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'notOfStack': [for (final o in notOfStack) o.toJson()],
      };

  factory Skipped.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.skipped) {
      throw ArgumentError.value(kind, 'kind',
          'Skipped.fromJson recibió un discriminador que no es el suyo');
    }
    return Skipped(
      notOfStack: [
        for (final o in json['notOfStack']! as List<Object?>)
          ObservedSubject.fromJson(Map<String, Object?>.from(o! as Map)),
      ],
    );
  }
}

/// Alguno de los sujetos pedidos no se pudo mirar.
class Unobservable extends StepOutcome {
  @override
  final StepKind kind = StepKind.unobservable;

  final List<UnobservedSubject> causes;

  Unobservable({required List<UnobservedSubject> causes})
      : causes = List.unmodifiable(causes) {
    if (this.causes.isEmpty) {
      throw ArgumentError.value(causes, 'causes',
          'Lo no observable sin causa no dice qué no se pudo mirar ni por '
          'qué');
    }
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'causes': [for (final c in causes) c.toJson()],
      };

  factory Unobservable.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.unobservable) {
      throw ArgumentError.value(kind, 'kind',
          'Unobservable.fromJson recibió un discriminador que no es el suyo');
    }
    return Unobservable(
      causes: [
        for (final c in json['causes']! as List<Object?>)
          UnobservedSubject.fromJson(Map<String, Object?>.from(c! as Map)),
      ],
    );
  }
}

/// El instrumento se rompió: no hay lectura que ofrecer, ni verde ni rojo.
class Broken extends StepOutcome {
  @override
  final StepKind kind = StepKind.broken;

  final String component;
  final String error;
  final String context;

  Broken({
    required this.component,
    required this.error,
    required this.context,
  }) {
    if (component.trim().isEmpty) {
      throw ArgumentError.value(
          component, 'component', 'Un roto sin componente no dice qué falló');
    }
    if (error.trim().isEmpty) {
      throw ArgumentError.value(
          error, 'error', 'Un roto sin error no dice qué pasó');
    }
    if (context.trim().isEmpty) {
      throw ArgumentError.value(
          context, 'context', 'Un roto sin contexto no dice dónde pasó');
    }
  }

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'component': component,
        'error': error,
        'context': context,
      };

  factory Broken.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.broken) {
      throw ArgumentError.value(kind, 'kind',
          'Broken.fromJson recibió un discriminador que no es el suyo');
    }
    return Broken(
      component: json['component']! as String,
      error: json['error']! as String,
      context: json['context']! as String,
    );
  }
}
