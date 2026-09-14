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
      throw ArgumentError.value(
        reason,
        'reason',
        'Una omisión sin motivo no dice qué quedó afuera',
      );
    }
    if (subject != null && subject!.trim().isEmpty) {
      throw ArgumentError.value(
        subject,
        'subject',
        'Un sujeto en blanco no nombra nada. Si la omisión no es de ningún '
            'sujeto, dejalo nulo: eso significa residuo general',
      );
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
    if (this.subjects.isEmpty) {
      throw ArgumentError.value(
        subjects,
        'subjects',
        'Un alcance vacío es precondición violada, no un desenlace: no se '
            'invoca nada sobre una lista de sujetos vacía, así que tampoco '
            'hay un intento que registrar sobre ella',
      );
    }
    if (termination == Termination.completa) {
      throw ArgumentError.value(
        termination,
        'termination',
        'Un intento que terminó completo no es un intento: es un testigo. '
            'Construí un Witness, no un Attempt',
      );
    }
    if (note.trim().isEmpty) {
      throw ArgumentError.value(
        note,
        'note',
        'Una nota en blanco no dice qué pasó',
      );
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
    termination: Termination.values.byName(json['termination']! as String),
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

  /// Cada variante trae su propio cuerpo. El verificador de campos de este
  /// repositorio sabe leer un literal de mapa devuelto por una implementación
  /// concreta, y sabe saltear una firma abstracta sin cuerpo como esta en vez
  /// de fallar al intentarlo.
  Map<String, Object?> toJson();

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
sealed class VerificationOutcome extends StepOutcome {
  /// Despacha por [StepOutcome.fromJson] y **lanza** si lo que llegó es una
  /// de las tres variantes que un `Verifier` no puede devolver.
  ///
  /// Sin esto, rechazar un `Skipped` disfrazado de resultado de verificador
  /// dependía de un `as VerificationOutcome` en el sitio de uso —un error de
  /// tipo lejos de donde se leyó el JSON— y nada impedía que un consumidor
  /// futuro lo esquivara con una comprobación de respaldo que fabricara un
  /// verde nuevo sobre algo que un verificador nunca afirmó.
  static VerificationOutcome fromJson(Map<String, Object?> json) {
    final outcome = StepOutcome.fromJson(json);
    if (outcome is VerificationOutcome) return outcome;
    throw ArgumentError.value(
      outcome.kind.name,
      'kind',
      'Un Verifier no puede devolver esto: el salto, lo no observable y lo '
          'roto los decide quien compone la corrida, no un verificador',
    );
  }
}

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

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'witness': witness.toJson(),
    'diagnostics': [for (final d in diagnostics) d.toJson()],
  };

  factory Executed.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.executed) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Executed.fromJson recibió un discriminador que no es el suyo',
      );
    }
    return Executed(
      witness: Witness.fromJson(
        Map<String, Object?>.from(json['witness']! as Map),
      ),
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

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'attempt': attempt.toJson(),
  };

  factory Aborted.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.aborted) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Aborted.fromJson recibió un discriminador que no es el suyo',
      );
    }
    return Aborted(
      attempt: Attempt.fromJson(
        Map<String, Object?>.from(json['attempt']! as Map),
      ),
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
      throw ArgumentError.value(
        notOfStack,
        'notOfStack',
        'Un salto sin sujetos ajenos no es un salto: no hay nada que '
            'explique por qué el paso no tenía nada que hacer',
      );
    }
    final propios = this.notOfStack.where((o) => o.ofStack).toList();
    if (propios.isNotEmpty) {
      throw ArgumentError.value(
        propios,
        'notOfStack',
        'Estos sujetos el observador los declaró del stack. Un salto '
            'afirma «ninguno de estos era mío»: no puede listar uno que sí '
            'lo era',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'notOfStack': [for (final o in notOfStack) o.toJson()],
  };

  factory Skipped.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.skipped) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Skipped.fromJson recibió un discriminador que no es el suyo',
      );
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
      throw ArgumentError.value(
        causes,
        'causes',
        'Lo no observable sin causa no dice qué no se pudo mirar ni por '
            'qué',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'causes': [for (final c in causes) c.toJson()],
  };

  factory Unobservable.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.unobservable) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Unobservable.fromJson recibió un discriminador que no es el suyo',
      );
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
        component,
        'component',
        'Un roto sin componente no dice qué falló',
      );
    }
    if (error.trim().isEmpty) {
      throw ArgumentError.value(
        error,
        'error',
        'Un roto sin error no dice qué pasó',
      );
    }
    if (context.trim().isEmpty) {
      throw ArgumentError.value(
        context,
        'context',
        'Un roto sin contexto no dice dónde pasó',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'component': component,
    'error': error,
    'context': context,
  };

  factory Broken.fromJson(Map<String, Object?> json) {
    final kind = StepKind.values.byName(json['kind']! as String);
    if (kind != StepKind.broken) {
      throw ArgumentError.value(
        kind,
        'kind',
        'Broken.fromJson recibió un discriminador que no es el suyo',
      );
    }
    return Broken(
      component: json['component']! as String,
      error: json['error']! as String,
      context: json['context']! as String,
    );
  }
}

/// El desenlace de aplicar un candidato: **tres variantes cerradas**, porque
/// la transición tiene exactamente tres finales y ninguno es un caso de error
/// genérico.
///
/// **Por qué no es una excepción con dos casos felices.** Que la rama se haya
/// movido no es un fallo de la herramienta: es la respuesta correcta de un
/// compare-and-swap, y el trabajo ajeno que lo provocó sobrevive intacto.
/// Modelarlo como excepción deja que quien llama se olvide de atraparlo y
/// reporte éxito. Con un tipo sellado el `switch` no compila si falta un caso.
///
/// **[LocalInconsistent] es un final, no una advertencia.** El commit existe y
/// no se deshace; lo que no quedó es el índice del usuario al día. Devolver
/// [Committed] ahí sería afirmar un estado que no se comprobó, y lanzar
/// perdería la revisión que sí se creó.
sealed class CommitOutcome {
  CommitOutcome();
}

/// El candidato quedó en la rama, y el índice del usuario al día.
final class Committed extends CommitOutcome {
  final String revision;
  Committed(this.revision) {
    if (revision.trim().isEmpty) {
      throw ArgumentError.value(
        revision,
        'revision',
        'Un commit aplicado sin revisión no nombra lo que se aplicó.',
      );
    }
  }
}

/// Por qué no se aplicó. **Son dos hechos distintos y se nombran distinto.**
///
/// Antes los dos viajaban en un `headObservado` que unas veces traía una
/// revisión y otras una frase sobre la rama. Un campo que cambia de tipo de
/// contenido según el caso obliga a quien lo lee a adivinar cuál tiene.
enum CausaDeNoAplicacion {
  /// La base se movió: el compare-and-swap fue rechazado.
  baseMovida,

  /// La rama puesta ya no es aquella sobre la que se preparó. No se intentó
  /// mover ninguna referencia.
  ramaCambiada,
}

/// No se aplicó: **la rama no se movió**.
///
/// El objeto commit existe y queda inalcanzable; eso no es daño, es basura que
/// `git gc` recoge. [revision] siempre nombra ese objeto — se crea antes de
/// cualquier intento de mover una referencia, así que no hay ningún camino por
/// el que este desenlace se produzca sin ella.
final class NotApplied extends CommitOutcome {
  /// La revisión que se creó y **no** se aplicó. Inalcanzable desde toda rama.
  final String revision;

  final CausaDeNoAplicacion causa;

  /// Sobre qué base se preparó el candidato.
  final String baseEsperada;

  /// Dónde está `HEAD` ahora. **Siempre una revisión**, nunca una descripción.
  final String headObservado;

  /// Qué rama se encontró puesta, cuando la causa es [CausaDeNoAplicacion
  /// .ramaCambiada]. Vacía si `HEAD` está suelto; nula si la causa es otra.
  final String? ramaObservada;

  NotApplied({
    required this.revision,
    required this.causa,
    required this.baseEsperada,
    required this.headObservado,
    this.ramaObservada,
  }) {
    if (revision.trim().isEmpty) {
      throw ArgumentError.value(
        revision,
        'revision',
        'Sin revisión no se puede decir qué fue lo que no se aplicó.',
      );
    }
    if (baseEsperada.trim().isEmpty || headObservado.trim().isEmpty) {
      throw ArgumentError(
        'La base esperada y el HEAD observado nombran revisiones: ninguna '
        'puede ir en blanco, porque juntas son la explicación del rechazo.',
      );
    }
    if ((causa == CausaDeNoAplicacion.ramaCambiada) !=
        (ramaObservada != null)) {
      throw ArgumentError(
        'La rama observada acompaña a `ramaCambiada`, y solo a ella.',
      );
    }
  }
}

/// La rama avanzó y el índice del usuario **no** quedó al día.
///
/// El cambio está commiteado —[revision] es real y alcanzable— pero el estado
/// local quedó a medias y `git status` va a mentir hasta que alguien lo
/// resuelva. Se nombra entero en vez de elegir una de las dos mitades.
final class LocalInconsistent extends CommitOutcome {
  final String revision;
  final String detalle;

  LocalInconsistent({required this.revision, required this.detalle}) {
    if (revision.trim().isEmpty) {
      throw ArgumentError.value(
        revision,
        'revision',
        'El commit existe: sin su revisión nadie puede repararlo.',
      );
    }
    if (detalle.trim().isEmpty) {
      throw ArgumentError.value(
        detalle,
        'detalle',
        'Un estado a medias sin detalle no dice qué hay que reparar.',
      );
    }
  }
}

/// Qué pasó al intentar dejar el candidato en condiciones de ser verificado.
///
/// **Tres desenlaces, y la línea que los separa.** [CandidatoRechazado] es un
/// hecho sobre el candidato; [DerivacionAbortada] es un hecho sobre el
/// instrumento, y no dice nada del candidato. La primera versión del diseño los
/// mezclaba en un solo enum —«el lockfile no satisface» junto a «falta la
/// toolchain»—, que es la misma confusión que ADR-019 cerró del lado de los
/// pasos: un instrumento roto no es un veredicto.
///
/// Las dos variantes que no son [EntornoDerivado] hacen la corrida
/// `noConcluyente`, **nunca roja**.
sealed class ResultadoDeEntorno {
  ResultadoDeEntorno();

  /// Con qué se discrimina la variante al volver del JSON.
  String get kind;

  Map<String, Object?> toJson();

  /// **Recibe el discriminador ya leído, no el mapa.** El verificador de
  /// serialización deriva las claves de los índices que la propia `fromJson`
  /// hace sobre su parámetro, y tiene razón en no seguir ayudantes: quien lee
  /// el JSON tiene que nombrar la clave ahí donde la usa, o un campo puede
  /// perderse a la vuelta sin que nada lo note.
  static void _exigirKind(Object? kind, String propio) {
    if (kind != propio) {
      throw ArgumentError.value(
        kind,
        'kind',
        'fromJson de «$propio» recibió un discriminador que no es el suyo',
      );
    }
  }

  /// Despacha por [kind]. **Estático y no una factory**, igual que
  /// [StepOutcome.fromJson]: una factory sería un constructor, y un
  /// constructor `fromJson` es lo que el verificador lee como «esta clase
  /// serializa» — que contradiría su declaración de opacidad.
  ///
  /// **Un discriminador que no nombra ninguna variante lanza.** Caer en la
  /// más mansa sería inventar un hecho que nadie afirmó.
  static ResultadoDeEntorno fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'derivado' => EntornoDerivado.fromJson(json),
        'rechazado' => CandidatoRechazado.fromJson(json),
        'abortada' => DerivacionAbortada.fromJson(json),
        final otro => throw FormatException(
          'ResultadoDeEntorno con kind «$otro», que no es ninguna variante.',
        ),
      };
}

/// El entorno quedó derivado del candidato.
///
/// Lleva **hechos contables**, del mismo tipo que «cuántos archivos miró» que
/// el testigo ya lleva: sin ellos, «derivado» sería una afirmación sin nada que
/// la respalde.
final class EntornoDerivado extends ResultadoDeEntorno {
  @override
  final String kind = 'derivado';

  /// Entradas de los mapas de paquetes resultantes, sumadas.
  final int paquetes;

  /// Cuántas raíces de resolución se derivaron. **Cero es legítimo**: un
  /// candidato cuyos archivos no cuelgan de ningún manifiesto no tiene nada
  /// que derivar, y eso no lo vuelve defectuoso.
  final int raices;

  final IdentidadDeToolchain toolchain;

  EntornoDerivado({
    required this.paquetes,
    required this.raices,
    required this.toolchain,
  }) {
    if (paquetes < 0 || raices < 0) {
      throw ArgumentError(
        'Las cifras del entorno son cuentas: no pueden ser negativas.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'paquetes': paquetes,
    'raices': raices,
    'toolchain': toolchain.toJson(),
  };

  /// Legible en un fallo de prueba y en un log. Sin esto, el desenlace de una
  /// derivación se lee «Instance of EntornoDerivado» y hay que instrumentar el
  /// código para averiguar qué pasó.
  @override
  String toString() =>
      'EntornoDerivado($paquetes paquetes en $raices raíz/raíces)';

  factory EntornoDerivado.fromJson(Map<String, Object?> json) {
    ResultadoDeEntorno._exigirKind(json['kind'], 'derivado');
    return EntornoDerivado(
      paquetes: json['paquetes']! as int,
      raices: json['raices']! as int,
      toolchain: IdentidadDeToolchain.fromJson(
        json['toolchain']! as Map<String, Object?>,
      ),
    );
  }
}

/// Por qué el candidato no se puede verificar **por lo que es**.
enum CausaDeRechazo {
  /// **El resolvedor dijo que no, y no inventamos por qué.** Puede ser el
  /// lockfile ausente, una resolución inválida, un hash cambiado, un SDK
  /// incompatible o un cache sin el paquete; no hay protocolo estructurado que
  /// los distinga —está medido que un SDK desconocido y un cache frío salen con
  /// el mismo código—, y deducirlo de frases de la salida de error sería
  /// exactamente el parser frágil que este proyecto rechaza en todas partes. La
  /// evidencia va citada, literal.
  pubRechazoLaResolucion,

  /// Una dependencia por ruta resuelve **fuera** del candidato. El lockfile
  /// identifica la ruta, no lo que hay adentro: nada de eso quedó fijado.
  dependenciaPathQueEscapa,

  /// El árbol versiona lo que la derivación genera, así que derivar lo
  /// destruiría. Se detecta **antes** de correr nada.
  elArbolVersionaLoQueSeGenera,
}

/// No se puede verificar **por lo que el candidato es**. Es un hecho sobre él.
final class CandidatoRechazado extends ResultadoDeEntorno {
  @override
  final String kind = 'rechazado';

  final CausaDeRechazo causa;

  /// Lo que la herramienta dijo, tal cual. Nunca en blanco: un rechazo sin
  /// evidencia es una acusación sin prueba.
  final QuotedText evidencia;

  CandidatoRechazado({required this.causa, required this.evidencia}) {
    if (evidencia.content.trim().isEmpty) {
      throw ArgumentError.value(
        evidencia,
        'evidencia',
        'Un rechazo sin evidencia es una acusación sin prueba.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'causa': causa.name,
    'evidencia': evidencia.toJson(),
  };

  /// Legible en un fallo de prueba y en un log. Sin esto, el desenlace de una
  /// derivación se lee «Instance of CandidatoRechazado» y hay que instrumentar el
  /// código para averiguar qué pasó.
  @override
  String toString() =>
      'CandidatoRechazado(${causa.name}): ${evidencia.content}';

  factory CandidatoRechazado.fromJson(Map<String, Object?> json) {
    ResultadoDeEntorno._exigirKind(json['kind'], 'rechazado');
    return CandidatoRechazado(
      causa: CausaDeRechazo.values.byName(json['causa']! as String),
      evidencia: QuotedText.fromJson(
        json['evidencia']! as Map<String, Object?>,
      ),
    );
  }
}

/// Por qué el instrumento no llegó a medir.
///
/// **Son dos hechos distintos y se nombran distinto**, igual que
/// [CausaDeNoAplicacion] separa dos motivos que antes viajaban en un campo que
/// cambiaba de contenido según el caso.
enum CausaDeAborto {
  /// La herramienta no estaba, o no llegó a devolver un resultado.
  laHerramientaNoRespondio,

  /// **La herramienta corrió y no dijo con qué versión.** Salió con un código
  /// distinto de cero, o no dijo nada en ninguna corriente. Un entorno derivado
  /// lleva la identidad de la toolchain citada, y sin ella el testigo no puede
  /// decir con qué se midió — que es lo único que esa identidad existe para
  /// decir. Fabricar un texto para llenar el campo sería exactamente el dato
  /// falso que el tipo existe para impedir.
  laToolchainNoSeIdentifico,
}

/// No se pudo derivar **por lo que pasó al intentarlo**. No dice nada del
/// candidato: dice que el instrumento no llegó a medir.
final class DerivacionAbortada extends ResultadoDeEntorno {
  @override
  final String kind = 'abortada';

  /// Cómo terminó la invocación. **[Termination.completa] solo acompaña a
  /// [CausaDeAborto.laToolchainNoSeIdentifico]**: ahí la herramienta sí corrió
  /// —terminó del todo— y lo que falló fue lo que dijo.
  final Termination terminacion;

  final CausaDeAborto causa;

  final QuotedText evidencia;

  DerivacionAbortada({
    required this.terminacion,
    required this.causa,
    required this.evidencia,
  }) {
    if ((terminacion == Termination.completa) !=
        (causa == CausaDeAborto.laToolchainNoSeIdentifico)) {
      throw ArgumentError(
        'Una terminación completa solo se aborta porque la toolchain no se '
        'identificó: ahí la herramienta corrió y lo que falló fue lo que '
        'dijo. Y si no llegó a responder, su terminación no es completa.',
      );
    }
    if (evidencia.content.trim().isEmpty) {
      throw ArgumentError.value(
        evidencia,
        'evidencia',
        'Un aborto sin evidencia no dice qué falló.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'terminacion': terminacion.name,
    'causa': causa.name,
    'evidencia': evidencia.toJson(),
  };

  /// Legible en un fallo de prueba y en un log. Sin esto, el desenlace de una
  /// derivación se lee «Instance of DerivacionAbortada» y hay que instrumentar el
  /// código para averiguar qué pasó.
  @override
  String toString() =>
      'DerivacionAbortada(${causa.name} · ${terminacion.name}): '
      '${evidencia.content}';

  factory DerivacionAbortada.fromJson(Map<String, Object?> json) {
    ResultadoDeEntorno._exigirKind(json['kind'], 'abortada');
    return DerivacionAbortada(
      terminacion: Termination.values.byName(json['terminacion']! as String),
      causa: CausaDeAborto.values.byName(json['causa']! as String),
      evidencia: QuotedText.fromJson(
        json['evidencia']! as Map<String, Object?>,
      ),
    );
  }
}

/// Cómo terminó una corrida entera. **No es [Verdict]**, y la diferencia es
/// el punto: un veredicto es de un paso, y una corrida puede terminar por
/// cosas que no son veredictos de nadie.
///
/// Faltan estados que el producto va a necesitar —una detención por
/// presupuesto agotado (ADR-014)— y **no se declaran todavía**: no hay
/// presupuestos, y un estado que nada produce es una promesa, no un dato.
enum EstadoDeCorrida {
  verde,
  rojo,

  /// Algo no se pudo observar, o algo quedó sin explicar. Se trata como rojo
  /// (ADR-011).
  noConcluyente,

  /// El arnés se rompió. **Distinto de «el cambio no verificó»**: acá no se
  /// puede afirmar nada sobre el cambio.
  errorInterno,
}
