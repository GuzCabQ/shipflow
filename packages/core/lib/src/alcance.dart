/// Lo que el arnés sabe del alcance **antes** de invocar nada.
///
/// Son hechos, no conclusiones. Quién decide que un alcance sin sujetos del
/// stack es un salto no es quien lo observa: eso lo hace la orquestación, y es
/// el corolario 4 de ADR-011 vuelto estructura.
///
/// **La identidad de un sujeto es la cadena tal como se pidió.** Este paquete
/// no puede normalizar rutas porque no puede importar nada, así que la
/// partición se comprueba por igualdad. Un observador que canonice —y debe
/// hacerlo para decidir los hechos— no puede renombrar lo que devuelve.
library;

/// Un sujeto que se **pudo** mirar.
class ObservedSubject {
  final String subject;

  /// Si le incumbe al stack de este plugin.
  final bool ofStack;

  /// Cuántos archivos de fuente hay debajo. Cero solo si no es del stack.
  final int files;

  /// Por qué NO es del stack. Presente si y solo si [ofStack] es falso.
  final String? reason;

  ObservedSubject({
    required this.subject,
    required this.ofStack,
    required this.files,
    this.reason,
  }) {
    if (subject.trim().isEmpty) {
      throw ArgumentError.value(
          subject, 'subject', 'Un sujeto en blanco no nombra nada');
    }
    if (files < 0) {
      throw ArgumentError.value(
          files, 'files', 'Un conteo negativo no significa nada');
    }
    if (ofStack) {
      if (files < 1) {
        throw ArgumentError.value(
            files,
            'files',
            'Un sujeto del stack con cero archivos afirma dos cosas '
                'incompatibles. Si no hay archivos, no es del stack');
      }
      if (reason != null) {
        throw ArgumentError.value(
            reason,
            'reason',
            'El motivo explica por qué un sujeto NO es del stack. Uno que sí '
                'lo es no tiene qué explicar');
      }
    } else {
      if (files != 0) {
        throw ArgumentError.value(files, 'files',
            'Un sujeto ajeno al stack no aporta archivos de fuente');
      }
      if (reason == null || reason!.trim().isEmpty) {
        throw ArgumentError.value(
            reason,
            'reason',
            'Un sujeto que se descarta sin decir por qué es un descarte '
                'silencioso, y el corolario 1 de ADR-011 lo prohíbe');
      }
    }
  }

  Map<String, Object?> toJson() => {
        'subject': subject,
        'ofStack': ofStack,
        'files': files,
        'reason': reason
      };

  factory ObservedSubject.fromJson(Map<String, Object?> json) =>
      ObservedSubject(
        subject: json['subject']! as String,
        ofStack: json['ofStack']! as bool,
        files: json['files']! as int,
        reason: json['reason'] as String?,
      );
}

/// Un sujeto que **no se pudo** mirar. No es lo mismo que uno ajeno al stack:
/// de este no se puede afirmar nada.
class UnobservedSubject {
  final String subject;

  /// Qué lo impidió: no existe, no se deja leer, lo que sea.
  final String cause;

  UnobservedSubject({required this.subject, required this.cause}) {
    if (subject.trim().isEmpty) {
      throw ArgumentError.value(
          subject, 'subject', 'Un sujeto en blanco no nombra nada');
    }
    if (cause.trim().isEmpty) {
      throw ArgumentError.value(cause, 'cause',
          'Sin causa, «no pude mirar» es indistinguible de «no miré»');
    }
  }

  Map<String, Object?> toJson() => {'subject': subject, 'cause': cause};

  factory UnobservedSubject.fromJson(Map<String, Object?> json) =>
      UnobservedSubject(
        subject: json['subject']! as String,
        cause: json['cause']! as String,
      );
}

/// El alcance mirado una sola vez, **particionado**.
class ScopeObservation {
  /// Lo que se pidió, tal como se pidió. Es el denominador de la partición.
  final List<String> requested;

  final List<ObservedSubject> observed;
  final List<UnobservedSubject> unobserved;
  final DateTime observedAt;

  ScopeObservation({
    required List<String> requested,
    required List<ObservedSubject> observed,
    required List<UnobservedSubject> unobserved,
    required this.observedAt,
  })  : requested = List.unmodifiable(requested),
        observed = List.unmodifiable(observed),
        unobserved = List.unmodifiable(unobserved) {
    final vistos = <String>[
      for (final o in this.observed) o.subject,
      for (final u in this.unobserved) u.subject,
    ];
    final unicos = vistos.toSet();
    if (unicos.length != vistos.length) {
      throw ArgumentError.value(
          vistos,
          'observed/unobserved',
          'Hay un sujeto clasificado dos veces. Un sujeto se pudo mirar o no '
              'se pudo, y no las dos cosas');
    }
    final pedidos = this.requested.toSet();
    if (pedidos.length != this.requested.length) {
      throw ArgumentError.value(requested, 'requested',
          'Hay un sujeto pedido dos veces. La partición no tendría denominador');
    }
    final faltan = pedidos.difference(unicos);
    if (faltan.isNotEmpty) {
      throw ArgumentError.value(
          faltan.toList(),
          'observed/unobserved',
          'Estos sujetos se pidieron y no se clasificaron. Un sujeto que '
              'desaparece acá no lo ve ninguna guardia posterior, y la corrida '
              'puede salir verde sobre algo que nadie miró');
    }
    final sobran = unicos.difference(pedidos);
    if (sobran.isNotEmpty) {
      throw ArgumentError.value(
          sobran.toList(),
          'observed/unobserved',
          'Estos sujetos se clasificaron y no se pidieron. La identidad es la '
              'cadena tal como se pidió: si el observador canoniza, no puede '
              'renombrar lo que devuelve');
    }
  }

  /// Los sujetos sobre los que tiene sentido invocar algo.
  List<String> usable() => List.unmodifiable([
        for (final o in observed)
          if (o.ofStack) o.subject
      ]);

  Map<String, Object?> toJson() => {
        'requested': requested,
        'observed': [for (final o in observed) o.toJson()],
        'unobserved': [for (final u in unobserved) u.toJson()],
        'observedAt': observedAt.toUtc().toIso8601String(),
      };

  factory ScopeObservation.fromJson(Map<String, Object?> json) =>
      ScopeObservation(
        requested: List<String>.from(json['requested']! as List<Object?>),
        observed: [
          for (final o in json['observed']! as List<Object?>)
            ObservedSubject.fromJson(Map<String, Object?>.from(o! as Map)),
        ],
        unobserved: [
          for (final u in json['unobserved']! as List<Object?>)
            UnobservedSubject.fromJson(Map<String, Object?>.from(u! as Map)),
        ],
        observedAt: DateTime.parse(json['observedAt']! as String),
      );
}

/// **Lo único que un [Verifier] ve del alcance: lo suyo.**
///
/// Existe porque una corrección abrió un agujero. Para que la observación se
/// hiciera una sola vez por corrida, `Verifier.run` pasó a recibir la
/// [ScopeObservation] entera — y con ella los sujetos ajenos y los que no se
/// pudieron mirar. El `README` decía, y con razón, que un verificador «ni
/// siquiera recibe los sujetos ajenos, así que estructuralmente no tiene sobre
/// qué declararse incompetente»; ese *estructuralmente* dejó de ser cierto sin
/// que nadie tocara la frase.
///
/// Con la observación entera a mano, un paso que escriba `requested` donde
/// quería `usable()` certifica un archivo que el observador declaró ajeno.
/// Reproducido: alcance esperado `[lib]`, testigo `[lib, README.md]`, cero
/// obligaciones abiertas, corrida VERDE. Es un error de una palabra, no de
/// mala fe, y esa es exactamente la clase que un tipo tiene que hacer
/// imposible.
///
/// **Cláusulas del contrato:**
///
/// 1. **Solo sujetos utilizables.** Quien lo construye ya decidió la
///    partición; acá no hay nada que clasificar y no hay ajenos que confundir.
/// 2. **Nunca vacío.** Un alcance sin sujetos no es un desenlace de nadie: es
///    precondición violada de quien llama. Vivía como un `throw` adentro de
///    `run`, que es «comprobado después de invocar»; acá es «no se puede
///    construir», que es lo que aquel comentario decía querer.
/// 3. **Sin repetidos y sin sujetos en blanco.** Un repetido haría contar dos
///    veces la misma obligación; uno en blanco no nombra nada.
class VerificationScope {
  /// Los sujetos sobre los que invocar, tal como se pidieron.
  final List<String> subjects;

  /// Cuántos archivos del stack contó la observación en ellos. Es con lo que
  /// un paso reconcilia lo que la herramienta dice haber mirado.
  final int files;

  VerificationScope({required List<String> subjects, required this.files})
      : subjects = List.unmodifiable(subjects) {
    if (this.subjects.isEmpty) {
      throw ArgumentError.value(
          subjects,
          'subjects',
          'Un alcance de verificación no puede estar vacío. Verificar nada no '
              'es ni verde ni no concluyente: es precondición violada de '
              'quien llama');
    }
    if (this.subjects.any((s) => s.trim().isEmpty)) {
      throw ArgumentError.value(subjects, 'subjects',
          'Hay un sujeto en blanco. Un sujeto en blanco no nombra nada');
    }
    if (this.subjects.toSet().length != this.subjects.length) {
      throw ArgumentError.value(
          subjects,
          'subjects',
          'Hay un sujeto repetido. El libro de obligaciones cuenta por par '
              'paso-sujeto: un repetido pediría cuenta dos veces de lo mismo');
    }
    if (files < 0) {
      throw ArgumentError.value(
          files, 'files', 'No se pueden haber contado archivos negativos');
    }
    // **Cada sujeto utilizable aporta uno como mínimo.** No es una regla
    // nueva: es la de [ObservedSubject] llegando hasta acá. Un sujeto solo
    // entra a `usable()` desde un `ObservedSubject(ofStack: true)`, y ése
    // rechaza el conteo cero con estas palabras — «si no hay archivos, no es
    // del stack». Sin esto, el tipo aceptaba estados que su propia fuente no
    // puede producir: `subjects: ['lib'], files: 0` afirma a la vez que `lib`
    // es utilizable y que no tiene nada adentro, y un paso lo reconciliaba
    // contra cero archivos y salía verde. Lo encontró un review.
    //
    // `files >= 1` a secas no alcanza: dos sujetos con un archivo entre los
    // dos incumple lo mismo y pasaría. El piso es la cantidad de sujetos.
    if (files < this.subjects.length) {
      throw ArgumentError.value(
          files,
          'files',
          'Hay ${this.subjects.length} sujeto(s) utilizable(s) y solo $files '
              'archivo(s) contado(s). Un sujeto del stack tiene al menos uno: '
              'si no tiene ninguno, no es del stack y no debería estar acá');
    }
  }

  /// El alcance de un paso, sacado de la observación de la corrida. **Es el
  /// único camino**: quien compone tiene la observación, el verificador no.
  factory VerificationScope.de(ScopeObservation observacion) =>
      VerificationScope(
        subjects: observacion.usable(),
        files: observacion.observed
            .where((o) => o.ofStack)
            .fold(0, (n, o) => n + o.files),
      );

  Map<String, Object?> toJson() => {'subjects': subjects, 'files': files};

  factory VerificationScope.fromJson(Map<String, Object?> json) =>
      VerificationScope(
        subjects: List<String>.from(json['subjects']! as List<Object?>),
        files: json['files']! as int,
      );
}
