/// El documento autoritativo de una corrida de `ship`.
///
/// **Uno solo.** `intent` y el JSON de la revisión son proyecciones suyas, no
/// fuentes paralelas: dos documentos del mismo hecho divergen siempre.
library;

import 'corrida.dart';
import 'publicacion.dart';

enum EstadoDelDocumento {
  prepared,
  committed,
  publicationComplete,
  publicationIncomplete,
  notApplied,
  localInconsistent,
}

/// Lee un [EstadoDelDocumento] por su nombre, y **lanza [FormatException]** si
/// no hay ninguno con ese nombre.
///
/// `values.byName` lanza `ArgumentError`, que es la familia de «me pasaron mal
/// un argumento», no la de «este JSON no se puede leer». El agujero estaba
/// cerrado igual —ese documento sí se rechazaba— pero por un tipo distinto del
/// que usa el resto de esta lectura: la versión anterior mezclaba las dos
/// familias adentro del mismo método, con `byName` tres líneas arriba de la
/// comprobación de coherencia que sí lanza `FormatException`. Dos familias
/// para una sola condición obligan a quien lea un documento a atrapar las dos
/// para no dejar pasar ninguna.
EstadoDelDocumento _estadoPorNombre(Object? leido) {
  for (final estado in EstadoDelDocumento.values) {
    if (estado.name == leido) return estado;
  }
  throw FormatException(
    'El documento de la corrida dice estado «$leido», que no es ninguno de: '
    '${EstadoDelDocumento.values.map((e) => e.name).join(", ")}.',
  );
}

class DocumentoDeCorrida {
  /// **Del documento, no del envelope de salida.** Son dos contratos con
  /// ciclos de vida distintos.
  ///
  /// **Por qué seguir en `1` es seguro, hoy.** Esta clase y su forma son de
  /// una PILA de TRES rebanadas que llegan juntas, no de una sola: 4a —la del
  /// desenlace y su documento—, 4b —la que compone `ship`— y 4c —
  /// `--retry-publication`, la que agrega el campo de la lista de abajo—.
  /// Ninguna de las tres se mergeó todavía: no existe ningún documento
  /// escrito por una corrida real con una forma más vieja que la de hoy, y
  /// por lo tanto no hay ningún lector para el que esta versión tenga que
  /// seguir sirviendo. Corregir la forma en el lugar, sin subir el número, es
  /// correcto exactamente porque nada publicado depende de la forma anterior.
  ///
  /// **Los cambios de forma que entraron adentro de esta ventana, con su
  /// fecha.** Es esta lista, y no la promesa de arriba sola, lo que hace
  /// auditable la excepción:
  /// - 2026-09-18 — `NoAplicado` ganó el campo `causa`: antes confundía «la
  ///   base se movió» con «te cambiaste de rama» debajo de un solo
  ///   `headObservado`, y las dos se corrigen distinto.
  /// - 2026-09-19 — `PullRequestDraft` ganó el campo `rutas` (4c, tarea 3):
  ///   las rutas que la rebanada declaró, persistidas para que el paso 4 de
  ///   la reconciliación pueda acotar a ellas la comparación del índice.
  ///
  /// **Cuándo deja de serlo.** El día que llegue la pila entera —4a, 4b y
  /// 4c, integradas—, esa garantía desaparece: cualquier corrida de `ship`
  /// que haya corrido después —en cualquier repositorio, de cualquiera— pudo
  /// haber escrito un documento con la forma de ese día, y ese documento pasa
  /// a ser un lector real. Desde ese día, el PRÓXIMO cambio de forma —agregar
  /// un campo, sacar uno, volverlo obligatorio— tiene que subir este número:
  /// ya no es «nadie lo vio todavía» sino «alguien puede tenerlo en el
  /// disco».
  ///
  /// **Por qué no alcanza con acordarse.** Esta nota tiene que vivir acá y no
  /// en la cabeza de quien integró la pila: dentro de un año, quien le
  /// agregue un campo a un desenlace no tiene por qué saber que hubo una
  /// ventana —antes de ese merge— donde cambiar su forma no pagaba versión,
  /// ni qué cambios entraron mientras estuvo abierta, ni en qué commit se
  /// cerró. El día del merge, lo que tiene que pasar es borrar este párrafo
  /// entero —lista incluida— y tratar la forma de ese momento como la primera
  /// que alguien puede tener guardada — y eso solo se puede seguir si queda
  /// escrito acá, no si depende de que alguien se acuerde.
  static const versionActual = 1;

  /// **Campo fijo, no un parámetro del constructor** —el mismo motivo que ya
  /// usa `kind` en cada variante sellada del desenlace: un valor literal por
  /// clase no es un segundo campo independiente que pueda discrepar del
  /// primero, así que declararlo acá no es lo que la restricción de «nada
  /// derivable es además un campo asignable» prohíbe. Que sea un campo de
  /// verdad —y no solo una clave que `toJson` escribe de memoria— es lo que
  /// deja que el verificador de serialización compare `toJson`/`fromJson`
  /// campo por campo, en vez de aceptar una clave que ninguna propiedad de la
  /// clase respalda.
  final int formatVersion = versionActual;

  final EstadoDelDocumento estado;

  /// El commit candidato. **Ya existe cuando este documento se escribe.**
  ///
  /// La versión anterior del diseño persistía `prepared` ANTES de
  /// `commit-tree`, y dejaba una ventana sin cerrar: había un objeto commit
  /// cuyo OID no quedaba en ningún lado, y la recuperación hablaba de «la
  /// revisión candidata» sin tener identidad que consultar. Crear el objeto no
  /// mueve la rama, así que escribirlo antes de persistir no tiene efecto
  /// observable.
  final String revision;

  /// El borrador completo, para que la recuperación reconstruya la solicitud
  /// **sin volver a correr la cascada**.
  final PullRequestDraft draft;

  /// El desenlace, cuando ya hay uno. Nulo mientras la corrida sigue.
  ///
  /// **No es independiente de [estado]: lo determina.** Ver
  /// [estadoQueAfirma] y el chequeo del constructor.
  final ShipOutcome? desenlace;

  /// El estado del documento que **afirma** un desenlace, o nulo si ese
  /// desenlace no afirma ninguno.
  ///
  /// `estado` y `desenlace` no son dos hechos: son el mismo hecho dicho dos
  /// veces, y el segundo determina al primero. Sin esta función los dos eran
  /// campos independientes, y un documento que dijera «el CAS fue rechazado,
  /// nada se aplicó» podía llevar adentro «hay un pull request abierto y
  /// utilizable». Eso se construía, se persistía y se releía: el estado
  /// contradictorio, un nivel por encima del tipo que se inventó para
  /// cerrarlo.
  ///
  /// **[NoIntentado] devuelve nulo, y no es un olvido.** Es el único desenlace
  /// que no afirma ningún estado de este documento: sus cuatro causas se
  /// resuelven ANTES del CAS —así está ordenada [ShipOutcome.derivar]—, o sea
  /// antes de que exista la revisión candidata sin la cual este documento no
  /// se puede escribir. Un documento con un desenlace [NoIntentado] adentro
  /// afirmaría a la vez que hubo candidato y que nunca se intentó hacer uno,
  /// así que no se construye: nulo acá significa «ningún estado le
  /// corresponde», y el chequeo lo rechaza contra todos.
  static EstadoDelDocumento? estadoQueAfirma(ShipOutcome desenlace) =>
      switch (desenlace) {
        NoIntentado() => null,
        NoAplicado() => EstadoDelDocumento.notApplied,
        LocalInconsistente() => EstadoDelDocumento.localInconsistent,
        Publicado() => EstadoDelDocumento.publicationComplete,
        PublicacionIncompleta() => EstadoDelDocumento.publicationIncomplete,
      };

  /// Por qué [estado] y [desenlace] no pueden ir juntos, o nulo si sí pueden.
  ///
  /// Un desenlace nulo nunca es incoherente: significa «todavía no hay
  /// desenlace», que es exactamente lo que dicen `prepared` y `committed`.
  /// Que un estado TERMINAL pueda seguir llevando desenlace nulo es un
  /// residuo declarado: quién escribe el desenlace en cada paso es 4b.
  static String? _incoherencia(
    EstadoDelDocumento estado,
    ShipOutcome? desenlace,
  ) {
    if (desenlace == null) return null;
    final suyo = estadoQueAfirma(desenlace);
    if (suyo == estado) return null;
    return 'El documento dice «${estado.name}» y lleva un desenlace '
        '«${desenlace.kind}», que ${suyo == null ? "no afirma ningún estado de este documento" : "afirma «${suyo.name}»"}. '
        'Son el mismo hecho dicho dos veces: si discrepan, el documento '
        'afirma dos cosas incompatibles sobre la misma corrida.';
  }

  /// **No es `const`, y ese es el punto**: acá es donde [estado] y [desenlace]
  /// se juntan, así que acá se exige que digan lo mismo. Todas las entradas
  /// —[preparado], [avanzarA] y [fromJson]— pasan por este constructor, y no
  /// hay ninguna otra.
  ///
  /// Lanza `ArgumentError` porque la incoherencia es un defecto de quien
  /// compone el documento. La lectura de JSON comprueba lo mismo ANTES de
  /// llegar acá y lanza `FormatException`, para que «este JSON no se puede
  /// leer» siga siendo una sola familia de excepción.
  DocumentoDeCorrida._({
    required this.estado,
    required this.revision,
    required this.draft,
    this.desenlace,
  }) {
    final mal = _incoherencia(estado, desenlace);
    if (mal != null) throw ArgumentError(mal);
  }

  /// El primer estado. **La única forma de crear un documento desde cero**:
  /// los demás se alcanzan con [avanzarA].
  factory DocumentoDeCorrida.preparado({
    required String revision,
    required PullRequestDraft draft,
  }) => DocumentoDeCorrida._(
    estado: EstadoDelDocumento.prepared,
    revision: revision,
    draft: draft,
  );

  /// El grafo de §9, como dato. Lo que no está acá no es un camino.
  ///
  /// **`publicationIncomplete → publicationComplete` está, aunque el diagrama
  /// de §9 no la dibuje.** El texto de la spec dice que `--retry-publication`
  /// «solo publica desde `committed` o `publicationIncomplete`», y sin esta
  /// arista una publicación que quedó a medias no tendría adónde avanzar
  /// cuando el reintento sí completa. El diagrama está incompleto, no este
  /// mapa.
  static const _transiciones = <EstadoDelDocumento, Set<EstadoDelDocumento>>{
    EstadoDelDocumento.prepared: {
      EstadoDelDocumento.committed,
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.localInconsistent,
    },
    EstadoDelDocumento.committed: {
      EstadoDelDocumento.publicationComplete,
      EstadoDelDocumento.publicationIncomplete,
    },
    EstadoDelDocumento.publicationIncomplete: {
      EstadoDelDocumento.publicationComplete,
    },
    EstadoDelDocumento.publicationComplete: {},
    EstadoDelDocumento.notApplied: {},
    EstadoDelDocumento.localInconsistent: {},
  };

  /// Avanza, o lanza. **Devuelve un documento nuevo** en vez de mutar este:
  /// con un campo mutable, alguien escribe `committed` sin pasar por acá y la
  /// comprobación deja de ser un invariante para ser una costumbre.
  ///
  /// **Dos comprobaciones, no una.** El grafo dice si el camino existe; el
  /// constructor dice si el estado de llegada y el desenlace afirman lo
  /// mismo. Sin la segunda, `avanzarA(notApplied, desenlace: Publicado(…))`
  /// se construía, se persistía y se releía.
  ///
  /// El desenlace que no se pasa **se arrastra**, y la comprobación es sobre
  /// el arrastrado: avanzar de `publicationIncomplete` a
  /// `publicationComplete` sin dar el desenlace nuevo deja adentro el que
  /// dice «la publicación no se completó», y eso ya no pasa.
  DocumentoDeCorrida avanzarA(
    EstadoDelDocumento destino, {
    ShipOutcome? desenlace,
  }) {
    final permitidos = _transiciones[estado]!;
    if (!permitidos.contains(destino)) {
      throw StateError(
        'De ${estado.name} no se va a ${destino.name}. Los caminos desde acá '
        'son: ${permitidos.isEmpty ? "ninguno, es terminal" : permitidos.map((e) => e.name).join(", ")}.',
      );
    }
    return DocumentoDeCorrida._(
      estado: destino,
      revision: revision,
      draft: draft,
      desenlace: desenlace ?? this.desenlace,
    );
  }

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'estado': estado.name,
    'revision': revision,
    'draft': draft.toJson(),
    'desenlace': desenlace?.toJson(),
  };

  /// **Exige la versión que conocemos.** Leer un documento de otra versión y
  /// actuar sobre él es peor que no leerlo: las decisiones que salen de acá
  /// deciden si se commitea y si se publica.
  ///
  /// **`factory`, no un método estático.** El verificador de serialización
  /// deriva las claves de `fromJson` de un `ConstructorDeclaration` con ese
  /// nombre, y un método estático homónimo no lo es —quedaría sin comprobar
  /// en las dos direcciones—. Eso no contradice el patrón de la base sellada
  /// de un desenlace: ahí un `factory` en la base leería como «esta clase
  /// serializa» sobre un tipo declarado opaco a propósito. Acá no hay esa
  /// tensión: `DocumentoDeCorrida` no es una base sellada, no despacha hacia
  /// variantes, y SÍ tiene que serializar sus propios campos.
  factory DocumentoDeCorrida.fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version != versionActual) {
      throw FormatException(
        'El documento de la corrida dice formatVersion «$version» y esta '
        'versión solo sabe leer $versionActual.',
      );
    }
    final crudo = json['desenlace'];
    final estado = _estadoPorNombre(json['estado']);
    ShipOutcome? desenlace;
    if (crudo != null) {
      try {
        desenlace = ShipOutcome.fromJson(
          Map<String, Object?>.from(crudo as Map),
        );
      } on FormatException catch (e) {
        // **Nombra la versión, para que esto no lea como «JSON roto».**
        // `formatVersion` compara por igualdad exacta contra un solo número,
        // y hoy ese número no distingue formas: un campo puede agregarse a un
        // desenlace sin subir [versionActual] —es la misma decisión que esta
        // ronda tomó con `causa` en `NoAplicado`, ver su doc— porque todavía
        // no hay ningún lector de la forma vieja allá afuera. Un documento
        // escrito con esa forma vieja coincide en `formatVersion` igual, así
        // que pasa el portón de arriba entero y explota acá, más adentro. Sin
        // nombrar la versión en ESTE mensaje, lo único que le llega a quien
        // lo lee es un `FormatException` que no distingue «esto se corrompió»
        // de «esto es de antes de que este campo existiera» — y acordarse de
        // esa diferencia no alcanza: quien relee un documento meses después
        // no tiene por qué recordar en qué commit se agregó cada campo.
        throw FormatException(
          'El desenlace de este documento (formatVersion $version) no tiene '
          'la forma que este código exige: ${e.message} Como formatVersion '
          'no subió con ese campo, esto no es necesariamente un documento '
          'corrupto: puede ser una forma más vieja que un campo nuevo dejó '
          'atrás.',
        );
      }
    }
    // **Antes de construir, y con `FormatException`.** Es la misma exigencia
    // que el constructor, por el camino por el que de verdad llegaba el
    // estado contradictorio: un documento que ya está en el disco. Que salga
    // por la misma familia que el resto de los rechazos de lectura es lo que
    // deja atrapar «este JSON no se puede leer» una sola vez.
    final mal = _incoherencia(estado, desenlace);
    if (mal != null) throw FormatException(mal);
    PullRequestDraft draft;
    try {
      draft = PullRequestDraft.fromJson(
        Map<String, Object?>.from(json['draft']! as Map),
      );
    } on FormatException catch (e) {
      // **El mismo envoltorio que ya usa el desenlace, arriba, y por el mismo
      // motivo.** `PullRequestDraft.fromJson` nombra la PALABRA
      // «formatVersion» en su propio mensaje, pero no el NÚMERO: no conoce
      // cuál trae este documento —conocerlo exigiría importar este archivo
      // desde el suyo, y ya es este archivo el que importa a `publicacion`—.
      // Sin agregarlo acá, los dos caminos de «esta es una forma más vieja»
      // del mismo documento —el del desenlace y el del borrador— quedaban
      // dando diagnósticos distintos ante el mismo tipo de forma vieja.
      throw FormatException(
        'El borrador de este documento (formatVersion $version) no tiene la '
        'forma que este código exige: ${e.message}',
      );
    }
    return DocumentoDeCorrida._(
      estado: estado,
      revision: json['revision']! as String,
      draft: draft,
      desenlace: desenlace,
    );
  }
}
