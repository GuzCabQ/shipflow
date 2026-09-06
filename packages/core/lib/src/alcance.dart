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
