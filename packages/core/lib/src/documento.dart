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

class DocumentoDeCorrida {
  /// **Del documento, no del envelope de salida.** Son dos contratos con
  /// ciclos de vida distintos.
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
  final ShipOutcome? desenlace;

  const DocumentoDeCorrida._({
    required this.estado,
    required this.revision,
    required this.draft,
    this.desenlace,
  });

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
    return DocumentoDeCorrida._(
      estado: EstadoDelDocumento.values.byName(json['estado']! as String),
      revision: json['revision']! as String,
      draft: PullRequestDraft.fromJson(
        Map<String, Object?>.from(json['draft']! as Map),
      ),
      desenlace: crudo == null
          ? null
          : ShipOutcome.fromJson(Map<String, Object?>.from(crudo as Map)),
    );
  }
}
