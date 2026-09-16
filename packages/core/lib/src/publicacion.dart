/// El desenlace de la publicación: el efecto remoto de una corrida.
library;

/// Por qué no se pudo publicar. **Cerrada**, y de acá sale `safeReason`: la
/// excepción externa NO se copia nunca, porque puede traer la credencial
/// adentro.
enum CausaDePublicacion {
  red,
  autenticacion,
  permisos,
  rechazoDeLaForja,
  desconocida,
}

/// Qué tan entregada quedó la corrida. **Derivado**, nunca asignable.
enum EstadoDeEntrega {
  completa,
  incompletaReintentable,
  incompletaNoReintentable,
}

/// Qué hace quien recibe el desenlace. **Derivado** de la variante y su causa.
enum AccionSiguiente {
  ninguna,
  reintentarPublicacion,
  corregirPermisos,
  entregaNuevaExplicita,
}

/// **Una sola jerarquía**, partida donde importa: lo utilizable no puede caber
/// donde va lo incompleto.
///
/// Dos enums independientes admitían el producto cartesiano —`push: failed,
/// pullRequest: succeeded`— y `succeeded` no distinguía abierto de cerrado ni
/// de fusionado.
sealed class PublicationOutcome {
  PublicationOutcome();

  String get kind;

  Map<String, Object?> toJson();

  bool get retryable;

  EstadoDeEntrega get deliveryStatus;

  AccionSiguiente get nextAction;

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
  /// `StepOutcome.fromJson` y `ResultadoDeEntorno.fromJson`: una factory sería
  /// un constructor, y un constructor `fromJson` es lo que el verificador lee
  /// como «esta clase serializa» — que contradiría la declaración de opacidad
  /// de una base sellada.
  ///
  /// **Un discriminador que no nombra ninguna variante lanza.** Caer en la
  /// más mansa sería inventar un hecho que nadie afirmó.
  static PublicationOutcome fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'prAbierto' => PullRequestOpen.fromJson(json),
        'prFusionado' => PullRequestMerged.fromJson(json),
        'prCerrado' => PullRequestClosed.fromJson(json),
        'pushFallo' => PushFailed.fromJson(json),
        'pushDesconocido' => PushUnknown.fromJson(json),
        'prFallo' => PullRequestFailed.fromJson(json),
        'prDesconocido' => PullRequestUnknown.fromJson(json),
        final otro => throw FormatException(
          'PublicationOutcome con kind «$otro», que no es ninguna variante.',
        ),
      };
}

/// Hay un PR que sirve.
///
/// **`url` es un getter abstracto, no un campo.** El verificador de
/// serialización deriva los campos de una clase de lo que ESA clase declara
/// en su propio cuerpo, no de lo que hereda: si `url` fuera un campo acá,
/// cada variante concreta necesitaría redeclararlo para que
/// `toJson`/`fromJson` lo vieran como propio, y redeclarar un campo que ya
/// existe en la base es exactamente lo que `overridden_fields` señala —bajo
/// `--fatal-infos` ese aviso es rojo. Un getter abstracto no tiene ese costo:
/// cada variante lo implementa con su propio campo, que sí es suyo a los
/// ojos del verificador, y el acceso por [PublicacionUtilizable] sigue
/// despachando al valor real porque un getter siempre es virtual.
sealed class PublicacionUtilizable extends PublicationOutcome {
  PublicacionUtilizable({required String url}) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'Una URL en blanco no identifica ningún pull request, y esta '
            'variante afirma que hay uno.',
      );
    }
  }

  String get url;

  @override
  bool get retryable => false;

  @override
  EstadoDeEntrega get deliveryStatus => EstadoDeEntrega.completa;

  @override
  AccionSiguiente get nextAction => AccionSiguiente.ninguna;
}

/// El PR está abierto.
final class PullRequestOpen extends PublicacionUtilizable {
  @override
  final String kind = 'prAbierto';

  @override
  final String url;

  PullRequestOpen({required this.url}) : super(url: url);

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'url': url};

  factory PullRequestOpen.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prAbierto');
    return PullRequestOpen(url: json['url']! as String);
  }
}

/// El PR se fusionó.
final class PullRequestMerged extends PublicacionUtilizable {
  @override
  final String kind = 'prFusionado';

  @override
  final String url;

  PullRequestMerged({required this.url}) : super(url: url);

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'url': url};

  factory PullRequestMerged.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prFusionado');
    return PullRequestMerged(url: json['url']! as String);
  }
}

/// No hay PR utilizable confirmado.
sealed class PublicacionNoUtilizable extends PublicationOutcome {
  PublicacionNoUtilizable();

  @override
  EstadoDeEntrega get deliveryStatus => retryable
      ? EstadoDeEntrega.incompletaReintentable
      : EstadoDeEntrega.incompletaNoReintentable;
}

/// Las cuatro que fallaron o no se supieron. **`unknown` no es un lujo**: es
/// la distinción entre `Skipped` y `Unobservable`. Sin él, una respuesta
/// perdida se reporta como `failed` y un reintento crea un segundo PR.
///
/// **`causa` es un getter abstracto, no un campo.** Mismo motivo que
/// [PublicacionUtilizable.url]: un campo compartido acá obligaría a cada
/// variante a redeclararlo para que el verificador de serialización lo viera
/// como propio, y esa redeclaración es lo que `overridden_fields` marca bajo
/// `--fatal-infos`.
sealed class PublicacionConCausa extends PublicacionNoUtilizable {
  PublicacionConCausa();

  CausaDePublicacion get causa;

  /// **Nunca copia la excepción externa.** Sale de la causa cerrada, que es
  /// lo único que se puede publicar sin arriesgar el secreto.
  String get safeReason => switch (causa) {
    CausaDePublicacion.red => 'la red falló',
    CausaDePublicacion.autenticacion => 'la credencial no fue aceptada',
    CausaDePublicacion.permisos =>
      'la credencial no alcanza para esta operación',
    CausaDePublicacion.rechazoDeLaForja => 'la forja rechazó la operación',
    CausaDePublicacion.desconocida => 'no se pudo determinar la causa',
  };

  @override
  bool get retryable => causa != CausaDePublicacion.permisos;

  @override
  AccionSiguiente get nextAction => causa == CausaDePublicacion.permisos
      ? AccionSiguiente.corregirPermisos
      : AccionSiguiente.reintentarPublicacion;
}

/// El `git push` falló.
final class PushFailed extends PublicacionConCausa {
  @override
  final String kind = 'pushFallo';

  @override
  final CausaDePublicacion causa;

  PushFailed({required this.causa});

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'causa': causa.name};

  factory PushFailed.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'pushFallo');
    return PushFailed(
      causa: CausaDePublicacion.values.byName(json['causa']! as String),
    );
  }
}

/// No se supo si el `git push` funcionó.
final class PushUnknown extends PublicacionConCausa {
  @override
  final String kind = 'pushDesconocido';

  @override
  final CausaDePublicacion causa;

  PushUnknown({required this.causa});

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'causa': causa.name};

  factory PushUnknown.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'pushDesconocido');
    return PushUnknown(
      causa: CausaDePublicacion.values.byName(json['causa']! as String),
    );
  }
}

/// La apertura del PR falló.
final class PullRequestFailed extends PublicacionConCausa {
  @override
  final String kind = 'prFallo';

  @override
  final CausaDePublicacion causa;

  PullRequestFailed({required this.causa});

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'causa': causa.name};

  factory PullRequestFailed.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prFallo');
    return PullRequestFailed(
      causa: CausaDePublicacion.values.byName(json['causa']! as String),
    );
  }
}

/// No se supo si el PR se llegó a abrir.
final class PullRequestUnknown extends PublicacionConCausa {
  @override
  final String kind = 'prDesconocido';

  @override
  final CausaDePublicacion causa;

  PullRequestUnknown({required this.causa});

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'causa': causa.name};

  factory PullRequestUnknown.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prDesconocido');
    return PullRequestUnknown(
      causa: CausaDePublicacion.values.byName(json['causa']! as String),
    );
  }
}

/// El PR existió y está cerrado. **Terminal pero NO completo**: no se
/// reintenta, se entrega de nuevo y explícitamente.
final class PullRequestClosed extends PublicacionNoUtilizable {
  @override
  final String kind = 'prCerrado';

  final String url;

  PullRequestClosed({required this.url}) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(
        url,
        'url',
        'Una URL en blanco no identifica ningún pull request, y esta '
            'variante afirma que hubo uno.',
      );
    }
  }

  @override
  bool get retryable => false;

  @override
  AccionSiguiente get nextAction => AccionSiguiente.entregaNuevaExplicita;

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'url': url};

  factory PullRequestClosed.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prCerrado');
    return PullRequestClosed(url: json['url']! as String);
  }
}
