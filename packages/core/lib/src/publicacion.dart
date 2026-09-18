/// El desenlace de la publicación: el efecto remoto de una corrida.
library;

import 'desenlace.dart';
import 'superficie.dart';

/// Por qué no se pudo publicar. **Cerrada**, y de acá sale `safeReason`: la
/// excepción externa NO se copia nunca, porque puede traer la credencial
/// adentro.
enum CausaDePublicacion {
  red,
  autenticacion,
  permisos,
  rechazoDeLaForja,

  /// El canal por el que iba a viajar la credencial no la protege: la URL
  /// configurada no es `https`. **La credencial NO se envió** — es lo único
  /// que distingue esta causa de [autenticacion], y confundirlas sería
  /// decirle a quien lee que su token fue rechazado cuando nunca salió de
  /// este proceso.
  ///
  /// No es reintentable: el mismo canal vuelve a estar en claro la próxima
  /// vez. Lo que hace falta es corregir la configuración, y por eso su
  /// [AccionSiguiente] es propia y no [AccionSiguiente.reintentarPublicacion].
  ///
  /// **Residuo declarado, y previo a esta causa:** [causa] es un getter de
  /// [PublicacionConCausa], así que TODA causa cabe en TODA variante con
  /// causa — incluidas [PushUnknown] y [PullRequestUnknown]. Un
  /// `PushUnknown(causa: configuracionInsegura)` diría «no sé si llegó» sobre
  /// una credencial que nunca salió del proceso. Hoy no lo produce ningún
  /// sitio —los dos rechazos son [PushFailed]— y es la misma forma que ya
  /// admitía [permisos]: un `PushUnknown` por permisos tampoco significa
  /// nada. Cerrarlo pide partir el enum por variante, que es un cambio de
  /// dominio.
  configuracionInsegura,

  /// La revisión que se iba a empujar no es un OID completo de git. **Nada se
  /// lanzó**: ni un proceso, ni un socket.
  ///
  /// Es una causa propia y no [desconocida] por lo que esta distinción evita.
  /// El `git push` arma el refspec `<revisión>:refs/heads/<rama>`, y con la
  /// revisión vacía eso es `:refs/heads/<rama>`, que en git **borra la
  /// referencia remota** (`git push <remoto> :<rama>` es la forma documentada
  /// de eliminar una rama del remoto). Un desenlace que dijera «no se pudo
  /// determinar la causa» sobre eso sería el falso alivio exacto: lo que
  /// pasó se sabe con precisión, y lo que hay que corregir es quién produjo
  /// esa revisión.
  ///
  /// No es reintentable: el mismo valor vuelve a no ser un OID la próxima
  /// vez. Su [AccionSiguiente] es [AccionSiguiente.corregirConfiguracion] y
  /// no una propia, **y eso es un residuo declarado**: quien tiene que
  /// corregir acá es el código que compuso la solicitud, no una opción que
  /// el usuario haya configurado. Lo que las dos comparten —y es lo que esa
  /// acción promete— es que el mismo intento vuelve a fallar idéntico hasta
  /// que alguien cambie lo que se le pasa; partir la acción por origen del
  /// defecto es un cambio de dominio que esta ronda no hace.
  revisionInvalida,

  /// El proceso que iba a hacer el trabajo **no se pudo lanzar**: no existe,
  /// no está en el `PATH`, o el sistema no pudo crearlo.
  ///
  /// Es una causa propia y no [desconocida], y la distinción vale la pena por
  /// lo que cada una le dice a quien la lee. «No se pudo determinar la causa»
  /// sobre un `git` que no está instalado es falso y no accionable; esto
  /// nombra el hecho y deja una cosa concreta que mirar.
  ///
  /// **Y no arriesga el secreto, que es la objeción que había que contestar.**
  /// Quien produce esta causa es un `catch` que deliberadamente NO mira la
  /// excepción —la de un lanzamiento fallido lleva el argv completo, con la
  /// credencial adentro—. Pero *qué `catch` corrió* es información propia del
  /// código, no del texto de la excepción: saber que se entró por la rama del
  /// lanzamiento imposible no copia ni un byte de lo que esa excepción traiga.
  ///
  /// **Reintentable**, a diferencia de [revisionInvalida]: un `fork` que falló
  /// por recursos puede andar en el próximo intento, y para un `git` que no
  /// está instalado el precio es un reintento de más — nunca una publicación
  /// que se lea como completa.
  noSePudoLanzar,

  desconocida,
}

/// Los DOS largos que puede tener un OID completo de git, **medidos, no
/// supuestos**, con `git rev-parse HEAD` sobre dos repositorios recién
/// creados con git 2.50.1:
///
/// - `--object-format=sha1` → 40 caracteres hexadecimales (160 bits).
/// - `--object-format=sha256` → 64 caracteres hexadecimales (256 bits).
///
/// Las dos familias entran porque el repositorio que se empuja puede ser de
/// cualquiera de las dos y `core` no elige por el usuario: aceptar solo
/// SHA-1 rechazaría revisiones perfectamente válidas de un repositorio
/// SHA-256, que es el mismo tipo de falso rechazo que esta validación existe
/// para no cometer.
///
/// **Mayúsculas incluidas, y también está medido**: `git rev-parse` y
/// `git cat-file -t` resuelven sin chistar un OID escrito en mayúsculas y
/// devuelven el objeto. O sea que un OID en mayúsculas ES un OID completo
/// válido; rechazarlo sería afirmar «esto no identifica ningún objeto» sobre
/// algo que sí lo identifica. Lo que producen nuestros propios adapters es
/// minúscula —es lo que git imprime—, así que esta tolerancia no relaja
/// ninguna ruta de este repositorio: solo evita mentir sobre una entrada
/// legítima.
///
/// **Y tolerar dos escrituras no es dejarlas circular:** quien acepta un OID
/// en mayúsculas lo canonicaliza a minúsculas en la frontera —ver
/// [PullRequestRequest.revision]—, porque río abajo hay comparaciones
/// literales contra lo que devuelve la forja, y dos formas del mismo objeto
/// ahí adentro se leen como dos objetos distintos.
final RegExp _patronDeOidCompleto = RegExp(
  r'^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$',
);

/// ¿[revision] es un OID completo de git?
///
/// **Es una función del dominio y no un detalle del adapter** porque el
/// dominio es donde nace la revisión que después se interpola en un refspec:
/// [PullRequestRequest] la exige al construirse, y `EmpujeAislado` la vuelve
/// a exigir justo antes de lanzar el proceso. Son dos fronteras distintas —un
/// invariante de construcción y una precondición de ejecución—, y ninguna de
/// las dos puede delegar en la otra: la primera no sabe si alguien llegará
/// por otro camino, y la segunda no puede confiar en que su llamador validó.
///
/// **Lo que NO dice**: que el objeto exista en el repositorio. Eso solo lo
/// sabe git, y averiguarlo desde acá sería lanzar un proceso adentro de una
/// validación sincrónica del dominio. Un OID bien formado que no existe lo
/// rechaza `git push` con su propio mensaje, y ESE rechazo no borra nada;
/// el que borra es el refspec sin revisión, que es justamente lo que esta
/// función impide construir.
bool esOidCompleto(String revision) => _patronDeOidCompleto.hasMatch(revision);

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

  /// Hay que corregir la CONFIGURACIÓN antes de volver a intentar. Distinta
  /// de [corregirPermisos] —que es sobre la credencial— y de
  /// [reintentarPublicacion] —que promete que el mismo intento puede salir
  /// bien—: acá el mismo intento vuelve a fallar igual hasta que alguien
  /// cambie lo que está configurado.
  corregirConfiguracion,

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
    // **No nombra la URL.** La URL que se rechazó es justamente la que iba a
    // llevar la credencial adjunta; copiarla acá sería filtrar el secreto por
    // el único texto de este archivo que se publica.
    CausaDePublicacion.configuracionInsegura =>
      'el canal configurado no es https, así que la credencial no se envió',
    // Tampoco nombra la revisión. No lleva secreto —es un OID o basura—,
    // pero esta cadena se publica y el hecho que importa es el mismo sin
    // ella: lo que se pasó no identifica ningún objeto, así que no se lanzó
    // nada.
    CausaDePublicacion.revisionInvalida =>
      'la revisión a empujar no es un identificador de objeto completo de '
          'git, así que no se lanzó ningún proceso',
    // Nombra el hecho —el programa no se pudo lanzar— y no el programa: el
    // nombre del ejecutable llega por configuración y esta cadena se
    // publica. Que el proceso no arrancara es lo accionable.
    CausaDePublicacion.noSePudoLanzar =>
      'no se pudo lanzar el programa que hacía falta, así que nada llegó a '
          'ocurrir del otro lado',
    CausaDePublicacion.desconocida => 'no se pudo determinar la causa',
  };

  /// **No es `causa != permisos`.** Dos causas no se arreglan reintentando, y
  /// escribirlo como una negación de una sola dejaba que la próxima causa
  /// nueva naciera reintentable por omisión.
  @override
  bool get retryable => switch (causa) {
    CausaDePublicacion.permisos => false,
    CausaDePublicacion.configuracionInsegura => false,
    CausaDePublicacion.revisionInvalida => false,
    CausaDePublicacion.red ||
    CausaDePublicacion.autenticacion ||
    CausaDePublicacion.rechazoDeLaForja ||
    CausaDePublicacion.noSePudoLanzar ||
    CausaDePublicacion.desconocida => true,
  };

  @override
  AccionSiguiente get nextAction => switch (causa) {
    CausaDePublicacion.permisos => AccionSiguiente.corregirPermisos,
    CausaDePublicacion.configuracionInsegura =>
      AccionSiguiente.corregirConfiguracion,
    CausaDePublicacion.revisionInvalida =>
      AccionSiguiente.corregirConfiguracion,
    CausaDePublicacion.red ||
    CausaDePublicacion.autenticacion ||
    CausaDePublicacion.rechazoDeLaForja ||
    CausaDePublicacion.noSePudoLanzar ||
    CausaDePublicacion.desconocida => AccionSiguiente.reintentarPublicacion,
  };
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

/// Antes del commit. **No tiene revisión porque todavía no existe.**
class PullRequestDraft {
  final String runId;
  final String branch;
  final String base;
  final ArtefactoDeRevision artefacto;

  PullRequestDraft({
    required this.runId,
    required this.branch,
    required this.base,
    required this.artefacto,
  });

  /// **Derivado.** El artefacto ya lleva la intención de la rebanada; llevarla
  /// también acá serían dos cadenas independientes para una cosa, y la que el
  /// adapter eligiera decidiría qué lee el revisor.
  String get intent => artefacto.intent;
}

/// Después del commit.
class PullRequestRequest {
  /// Lo que antecede al título cuando la superficie no está verde. **Es una
  /// constante y no un literal suelto**: el adapter la necesita para truncar
  /// sin comerse la advertencia.
  static const prefijoIncompleto = '[verificación incompleta] ';

  final PullRequestDraft draft;

  /// El commit al que la rama va a apuntar. **En minúsculas siempre**, sea
  /// cual sea la forma en que se lo haya pasado al constructor.
  ///
  /// **Canonicalizar es el arreglo, y la frontera del dominio es dónde.**
  /// [esOidCompleto] acepta mayúsculas a propósito —git resuelve el mismo
  /// objeto, así que rechazarlas sería afirmar que un OID válido no lo es—,
  /// pero aceptar DOS escrituras del mismo objeto y dejarlas circular hace
  /// que cada comparación literal río abajo sea un defecto latente. Ya hubo
  /// uno reproducido: el adapter de la forja comparaba
  /// `cabeza['sha'] != request.revision`, la solicitud traía el OID en
  /// mayúsculas y el pull request que ya existía lo tenía en minúsculas, así
  /// que la búsqueda idempotente no lo encontraba y se creaba un SEGUNDO
  /// pull request — que es lo único que esa búsqueda existe para impedir.
  ///
  /// Se hace acá y no en el adapter porque río abajo hay TRES lugares que
  /// tienen que decir lo mismo —la comparación con lo que devuelve la forja,
  /// el marcador estable que se escribe en el cuerpo y se busca después, y el
  /// refspec `<revisión>:refs/heads/<rama>`—, y con la canonicalización en
  /// uno solo de ellos los otros dos siguen pudiendo discrepar. Minúscula y
  /// no mayúscula porque es lo que imprime git y lo que devuelve la forja:
  /// canonicalizar hacia la otra forma obligaría a convertir en cada
  /// comparación con un valor ajeno.
  final String revision;

  /// **El árbol del commit tiene que ser el contenido que vieron los
  /// controles.** No se puede derivar uno del otro —uno es commit y el otro es
  /// árbol—, así que la relación se exige acá, que es lo que queda cuando la
  /// derivación no está disponible. Si discreparan, el cuerpo afirmaría
  /// verificación sobre contenido que el PR no contiene, y el revisor no
  /// tendría desde dónde notarlo.
  PullRequestRequest({
    required this.draft,
    required String revision,
    required String arbolDeLaRevision,
  }) : revision = revision.toLowerCase() {
    // **Antes que la relación con el árbol**, porque esta condición es sobre
    // la revisión misma y la otra es sobre su vínculo con el contenido: una
    // revisión que no identifica ningún objeto no puede tener un árbol
    // correcto ni incorrecto.
    //
    // Lo que esta guarda impide no es un dato feo: es un BORRADO. El adapter
    // arma el refspec `<revisión>:refs/heads/<rama>` y se lo pasa a
    // `git push`; con la revisión vacía eso queda `:refs/heads/<rama>`, que
    // es la forma documentada de ELIMINAR esa rama del remoto. El
    // constructor validaba la relación con el árbol y no la revisión, así
    // que `revision: ''` se aceptaba y el borrado quedaba a una sola llamada
    // de distancia.
    //
    // Se pregunta sobre el valor YA canonicalizado —el campo, no el
    // parámetro— para que lo que se valida y lo que queda guardado sean la
    // misma cadena; lo que se REPORTA, en cambio, es lo que escribió el
    // llamador, que es lo que tiene que corregir.
    if (!esOidCompleto(this.revision)) {
      throw ArgumentError.value(
        revision,
        'revision',
        'La revisión de un pull request tiene que ser un OID completo de git '
            '—40 caracteres hexadecimales con SHA-1, 64 con SHA-256—. Lo que '
            'no lo es termina interpolado en el refspec '
            '«<revisión>:refs/heads/<rama>», y una revisión vacía ahí no '
            'empuja nada: BORRA la rama del remoto.',
      );
    }
    final esperado = draft.artefacto.candidato.contentRevision;
    if (arbolDeLaRevision != esperado) {
      throw ArgumentError.value(
        arbolDeLaRevision,
        'arbolDeLaRevision',
        'El commit «$revision» lleva un árbol que no es el que se expuso a los '
            'controles («$esperado»). Publicar así afirmaría verificación sobre '
            'contenido que el pull request no contiene.',
      );
    }
  }

  /// **Derivado, no asignable.** Con dos campos independientes se construye
  /// `artefacto: noConcluyente, incompleto: false`, y el adapter omite la
  /// advertencia obligatoria.
  bool get incompleto =>
      draft.artefacto.superficie.estado != EstadoDeCorrida.verde;

  /// **También derivado.** Un título es texto con la misma propiedad que el
  /// cuerpo: «✅ verificado» en un título es una afirmación sobre la corrida, y
  /// quien la escriba no es quien la puede sostener. El adapter lo trunca al
  /// límite de su proveedor; la advertencia va adelante para que el truncado
  /// no se la coma.
  String get titulo =>
      incompleto ? '$prefijoIncompleto${draft.intent}' : draft.intent;
}
