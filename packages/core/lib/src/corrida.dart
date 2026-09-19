/// El desenlace de una corrida de `ship`: qué pasó con el trabajo local y con
/// el efecto remoto, como **un solo tipo cerrado**.
///
/// **Por qué un tipo y no una conjunción de banderas.** La versión anterior del
/// diseño tenía una tabla que no era función: sus causas se solapaban —una
/// corrida sin confirmar puede además traer un secreto, y el arnés roto
/// coincidía con dos códigos a la vez— y admitía combinaciones que no
/// significan nada, como un pull request abierto sobre una corrida donde el
/// arnés se rompió.
library;

import 'desenlace.dart';
import 'publicacion.dart';

/// La versión del formato del payload de `ship`: el payload de máquina que
/// imprime el CLI y el cuerpo del pull request que lo resume para quien
/// revisa.
///
/// **El documento que persiste [ShipOutcome] no la lleva, y no es la misma
/// relación.** Ese documento se versiona con su propio campo —ajeno a este
/// número, y con su propio ciclo de vida—, así que buscar acá un acoplamiento
/// con lo persistido sería buscar una relación que no existe.
///
/// **Vive acá y no en `cli` ni en `forge`, porque los dos la necesitan y
/// ninguno de los dos es dueño del otro.** El payload del CLI la imprime como
/// dato de máquina; el cuerpo del PR, en `forge`, la imprime como dato visible
/// para un humano — y `forge` no puede depender de `cli` para leerla, porque
/// las flechas del grafo van hacia `core`. Ponerla en cualquiera de los dos
/// adapters obligaría al otro a llevar su propia copia del número, que es la
/// forma exacta en que dos «versión 1» dejan de significar lo mismo — y hoy
/// mismo hay otra «versión 1» viviendo al lado de esta, la de
/// [DocumentoDeCorrida.versionActual]: son dos contratos distintos, pero las
/// tres razones que siguen son las mismas de las dos, porque las dos están en
/// la misma situación por el mismo motivo.
///
/// **Por qué seguir en `1` es seguro, hoy.** 4b —esta rebanada, la que compone
/// `ship`— le agregó una clave a este payload y renombró otras dos sin subir
/// este número. Es seguro porque 4b todavía no se integró: no hay ningún
/// script ni integración leyendo hoy la forma anterior del payload —la que
/// tenía antes de este cambio—, así que no hay a quién romperle un contrato
/// que todavía no existe.
///
/// **Cuándo deja de serlo.** El día que 4b se integre, cualquier consumidor
/// que empiece a leer este payload —el propio `forge`, o algo externo— pasa a
/// depender de la forma de ese día. Desde ese momento, el PRÓXIMO cambio de
/// forma —una clave nueva, una que desaparece, una que cambia de nombre— paga
/// su propia versión: ya no es «nadie lo lee todavía» sino «algo puede estar
/// leyéndolo ahora mismo».
///
/// **Por qué no alcanza con acordarse.** La misma razón que
/// [DocumentoDeCorrida.versionActual] documenta para sí: dentro de un año,
/// quien le cambie una clave a este payload no tiene por qué saber que hubo
/// una ventana, antes de este merge, donde ese cambio no pagaba versión. Que
/// la garantía dependa del calendario del merge y no de la memoria de quien
/// escribió esto es precisamente lo que hay que dejar escrito, porque la
/// memoria no sobrevive al año y este párrafo sí.
const payloadVersionDeShip = 1;

/// Los estados desde los que **se puede publicar**.
///
/// `errorInterno` no está, y esa ausencia es el mecanismo: sin él en el tipo,
/// una publicación sobre una corrida donde el arnés se rompió deja de ser
/// escribible. No hay que acordarse de comprobarlo.
enum EstadoPublicable {
  verde,
  rojo,
  noConcluyente;

  /// El publicable que le corresponde a un estado de corrida, o nulo si ese
  /// estado no autoriza publicar nada.
  ///
  /// **Devuelve nulo en vez de lanzar** porque «no se puede publicar» es un
  /// hecho del dominio que el llamador tiene que poder ramificar, no un error
  /// de programación.
  static EstadoPublicable? desde(EstadoDeCorrida estado) => switch (estado) {
    EstadoDeCorrida.verde => EstadoPublicable.verde,
    EstadoDeCorrida.rojo => EstadoPublicable.rojo,
    EstadoDeCorrida.noConcluyente => EstadoPublicable.noConcluyente,
    EstadoDeCorrida.errorInterno => null,
  };

  /// El estado de corrida equivalente. **Total y sin pérdida**: los tres
  /// publicables son estados de corrida.
  EstadoDeCorrida get comoCorrida => switch (this) {
    EstadoPublicable.verde => EstadoDeCorrida.verde,
    EstadoPublicable.rojo => EstadoDeCorrida.rojo,
    EstadoPublicable.noConcluyente => EstadoDeCorrida.noConcluyente,
  };
}

/// Si [estado] autoriza publicar. **`switch` exhaustivo, sin comodín**: un
/// [EstadoDeCorrida] nuevo no compila hasta que alguien decida acá si publica
/// o no.
///
/// **Es la ÚNICA compuerta, y por eso vive al lado de [ShipOutcome.derivar].**
/// Estaba escrita dos veces: exhaustiva del lado de la previsualización, y
/// como un `!= verde` del lado de la fábrica. Nada sostenía que las dos
/// contestaran lo mismo, y la asimetría era la peligrosa: un estado nuevo NO
/// compila del lado exhaustivo y SÍ del otro, donde cae en «compuerta
/// cerrada» por omisión. Quien agregara un estado y decidiera —en lo único
/// que el compilador le iba a pedir— que publica, se llevaba una corrida que
/// pasaba la compuerta, creaba el directorio de corridas, promovía,
/// commiteaba, movía la rama, abría el pull request, y recién ahí recibía de
/// la fábrica un «no intentado» que no encaja con nada de eso. Es el mismo
/// defecto que el predicado del canal seguro ya cerró en otro lado: dos
/// decisiones que no pueden divergir porque son una sola función.
///
/// **Dos exhaustivas siguen siendo dos.** Por eso la previsualización no
/// tiene la suya: llama a esta.
///
/// `--yes` no participa de esta decisión: autoriza a escribir, no a publicar
/// algo que no concluyó, y por eso ni siquiera es un parámetro. La única
/// bandera que sí importa acá es `--allow-incomplete`, y solo importa para lo
/// que **concluyó mal** —`rojo`, `noConcluyente`—, nunca para el instrumento
/// roto: ahí no hay nada que el arnés pueda afirmar sobre el cambio, con o
/// sin la bandera.
bool autoriza({
  required EstadoDeCorrida estado,
  required bool allowIncomplete,
}) => switch (estado) {
  EstadoDeCorrida.verde => true,
  EstadoDeCorrida.rojo || EstadoDeCorrida.noConcluyente => allowIncomplete,
  EstadoDeCorrida.errorInterno => false,
};

/// Por qué una corrida no intentó publicar.
///
/// **Son cuatro y `errorInterno` no es una de ellas**: es un ESTADO, y entra
/// por [verificationGate]. Ver el ruling del plan de esta rebanada. Con cinco,
/// la fila «gate con errorInterno» de la tabla de códigos quedaría
/// inalcanzable, y una fila que no se puede producir se lee como cobertura de
/// un caso que no existe.
enum CausaDeNoIntento {
  /// El detector encontró un secreto en el diff de la rebanada.
  secretDetected,

  /// La compuerta por estado no autorizó: rojo o no concluyente sin
  /// `--allow-incomplete`, o el arnés roto, que no se autoriza con nada.
  verificationGate,

  /// Falta `--yes`. Sin él la corrida se comporta como una previsualización.
  confirmationMissing,

  /// `--dry-run`: no se pidió efecto ninguno.
  previewOnly,
}

/// El desenlace de una corrida de `ship`, como **un solo tipo cerrado**.
///
/// **Cubre la corrida que LLEGÓ A EXISTIR, y solo esa.** Una que no llegó a
/// arrancar —la invocación que no se pudo interpretar, el preflight que
/// rechazó, el directorio de corridas desprotegido— no tiene desenlace que
/// describir: no hay candidato, no hay superficie y no hay efecto. Esas
/// detenciones salen tipadas por su cuenta, desde quien orquesta, y **no se
/// les fabrica una quinta causa**: con ella, la fila «gate con `errorInterno`»
/// de la tabla de códigos quedaría inalcanzable, que es una cobertura de un
/// caso que no existe.
///
/// **Los constructores son privados y la única entrada real es
/// [ShipOutcome.derivar]**, más abajo en este mismo archivo.
/// Las entradas `…ParaLaPrueba` existen para que la suite pueda construir
/// variantes sin pasar por la derivación; es el mismo precedente que
/// `RepositorioGit.identidadCapturadaParaLaPrueba`.
sealed class ShipOutcome {
  const ShipOutcome();

  /// El discriminador. **Estable**: es lo que un consumidor automático lee.
  String get kind;

  Map<String, Object?> toJson();

  static ShipOutcome fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    return switch (kind) {
      'noIntentado' => NoIntentado.fromJson(json),
      'noAplicado' => NoAplicado.fromJson(json),
      'localInconsistente' => LocalInconsistente.fromJson(json),
      'publicado' => Publicado.fromJson(json),
      'publicacionIncompleta' => PublicacionIncompleta.fromJson(json),
      final otro => throw FormatException(
        'ShipOutcome.fromJson no conoce el desenlace «$otro». Un '
        'discriminador que nadie declaró no se adivina: un desenlace mal '
        'leído decide qué se publica.',
      ),
    };
  }

  /// Lanza si [leido] no es [propio]. La llama cada fábrica de variante, con
  /// el valor que ella misma leyó de `json['kind']`.
  static void _exigirKind(Object? leido, String propio) {
    if (leido != propio) {
      throw FormatException(
        '$propio.fromJson recibió un discriminador que no es el suyo: '
        '«$leido».',
      );
    }
  }

  /// Lee un valor de enumeración por su nombre, y **lanza [FormatException]**
  /// si no hay ninguno con ese nombre.
  ///
  /// `values.byName` lanza `ArgumentError`, que es la familia de «me pasaron
  /// mal un argumento», no la de «este JSON no se puede leer». El agujero
  /// estaba cerrado igual —el documento se rechazaba— pero por un tipo
  /// distinto del que usa el resto de este archivo para la misma condición, y
  /// dos familias para una sola condición obligan a quien lea un documento a
  /// atrapar las dos para no dejar pasar ninguna.
  static T _porNombre<T extends Enum>(
    List<T> valores,
    Object? leido,
    String campo,
    String deQuien,
  ) {
    for (final valor in valores) {
      if (valor.name == leido) return valor;
    }
    throw FormatException(
      '$deQuien.fromJson recibió «$leido» en «$campo», que no es ninguno de: '
      '${valores.map((v) => v.name).join(", ")}.',
    );
  }

  /// **La única entrada real.** Cada variante tiene constructor privado, así
  /// que nadie puede ensamblar un desenlace eligiendo la combinación que le
  /// convenga: se derivan de los hechos.
  ///
  /// **La precedencia es por gravedad del hecho, no por el camino de
  /// autorización.** Que el usuario no fuera a confirmar no vuelve menos cierto
  /// que hay un secreto:
  ///
  ///     errorInterno > secretDetected > verificationGate
  ///                  > previewOnly > confirmationMissing
  ///
  /// `errorInterno` está en esa lista como ESTADO y sale por
  /// [CausaDeNoIntento.verificationGate]; no es una causa. Con una causa propia,
  /// la combinación «gate con arnés roto» quedaría inalcanzable.
  ///
  /// **[soloPreview] va antes que la confirmación porque pedir una
  /// previsualización no es no haber confirmado.** Significa que no se pidió
  /// efecto ninguno, y no se puede faltar una autorización que nadie
  /// necesitaba. Con el orden contrario, `previewOnly` solo era alcanzable si
  /// el llamador declaraba una confirmación que nunca ocurrió —un hecho falso
  /// viajando hacia la fábrica cuya razón de existir es derivar de los
  /// hechos—, y quien pedía un ensayo se llevaba el consejo de volver a
  /// correrlo con `--yes`.
  static ShipOutcome derivar({
    required EstadoDeCorrida verificacion,
    required bool huboSecreto,
    required bool seConfirmo,
    required bool soloPreview,
    required bool autorizaIncompleto,
    PublicationOutcome? remoto,

    /// El rechazo tal como lo informó quien intentó aplicar, **entero y no
    /// una mitad**. Antes acá entraba solo el `HEAD` observado, y con eso el
    /// desenlace perdía la causa —el único dato que distingue «la rama
    /// avanzó» de «te cambiaste de rama»— antes de que nadie la pudiera
    /// leer. Pasar el desenlace medido en vez de un campo suelto es también
    /// lo que hace imposible armar acá una combinación que nadie midió.
    NotApplied? casRechazado,
    String? revisionConIndiceSucio,
  }) {
    NoIntentado sinIntentar(CausaDeNoIntento causa) =>
        NoIntentado._(causa: causa, verificacion: verificacion);

    // 1 · El arnés roto. No lo autoriza ninguna bandera.
    //
    // **Esto es PRECEDENCIA, no una segunda compuerta.** [autoriza] ya
    // contesta que no para `errorInterno`, y el paso 3 lo volvería a
    // rechazar; lo que este paso decide es que gane sobre el secreto, que es
    // lo único que el paso 3 —que corre después— no puede decidir.
    if (verificacion == EstadoDeCorrida.errorInterno) {
      return sinIntentar(CausaDeNoIntento.verificationGate);
    }
    // 2 · El secreto, antes que cualquier camino de autorización.
    if (huboSecreto) return sinIntentar(CausaDeNoIntento.secretDetected);
    // 3 · La compuerta por estado. **Es [autoriza] y no un `!= verde`
    //     escrito acá**: esto se preguntaba en dos lados que nada obligaba a
    //     contestar igual. Ver el doc de [autoriza].
    if (!autoriza(estado: verificacion, allowIncomplete: autorizaIncompleto)) {
      return sinIntentar(CausaDeNoIntento.verificationGate);
    }
    // 4 · La previsualización, antes que la confirmación: quien previsualiza
    //     no pidió efecto ninguno, así que no hay autorización que pueda
    //     faltarle. Quien no confirmó sí pidió escribir y no llegó a
    //     autorizarlo.
    if (soloPreview) return sinIntentar(CausaDeNoIntento.previewOnly);
    if (!seConfirmo) return sinIntentar(CausaDeNoIntento.confirmationMissing);

    // A partir de acá la corrida sí intentó escribir.
    if (casRechazado != null) {
      return NoAplicado._(
        causa: casRechazado.causa,
        headObservado: casRechazado.headObservado,
      );
    }
    if (revisionConIndiceSucio != null) {
      return LocalInconsistente._(revision: revisionConIndiceSucio);
    }

    final publicable = EstadoPublicable.desde(verificacion);
    if (remoto == null || publicable == null) {
      throw ArgumentError(
        'La corrida pasó todas las compuertas y no hay desenlace remoto que '
        'informar. Devolver algo acá inventaría un hecho: nadie sabe qué pasó '
        'con la publicación.',
      );
    }
    return switch (remoto) {
      PublicacionUtilizable() => Publicado._(
        pr: remoto,
        verificacion: publicable,
      ),
      PublicacionNoUtilizable() => PublicacionIncompleta._(
        remoto: remoto,
        verificacion: publicable,
      ),
    };
  }

  // Entradas para la suite. La derivación real es `ShipOutcome.derivar`.
  static NoIntentado noIntentadoParaLaPrueba({
    required CausaDeNoIntento causa,
    required EstadoDeCorrida verificacion,
  }) => NoIntentado._(causa: causa, verificacion: verificacion);

  static NoAplicado noAplicadoParaLaPrueba({
    required CausaDeNoAplicacion causa,
    required String headObservado,
  }) => NoAplicado._(causa: causa, headObservado: headObservado);

  static LocalInconsistente localInconsistenteParaLaPrueba({
    required String revision,
  }) => LocalInconsistente._(revision: revision);

  static Publicado publicadoParaLaPrueba({
    required PublicacionUtilizable pr,
    required EstadoPublicable verificacion,
  }) => Publicado._(pr: pr, verificacion: verificacion);

  static PublicacionIncompleta publicacionIncompletaParaLaPrueba({
    required PublicacionNoUtilizable remoto,
    required EstadoPublicable verificacion,
  }) => PublicacionIncompleta._(remoto: remoto, verificacion: verificacion);
}

/// No se intentó publicar, y acá está por qué.
///
/// **Lleva `EstadoDeCorrida` entero y no `EstadoPublicable`**: es el camino por
/// donde `errorInterno` sale, así que acotar el tipo acá lo dejaría sin
/// representación.
final class NoIntentado extends ShipOutcome {
  final CausaDeNoIntento causa;
  final EstadoDeCorrida verificacion;

  const NoIntentado._({required this.causa, required this.verificacion});

  @override
  final String kind = 'noIntentado';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'causa': causa.name,
    'verificacion': verificacion.name,
  };

  factory NoIntentado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'noIntentado');
    return NoIntentado._(
      causa: ShipOutcome._porNombre(
        CausaDeNoIntento.values,
        json['causa'],
        'causa',
        'NoIntentado',
      ),
      verificacion: ShipOutcome._porNombre(
        EstadoDeCorrida.values,
        json['verificacion'],
        'verificacion',
        'NoIntentado',
      ),
    );
  }
}

/// La revisión no se aplicó. **Nada más lo produce**: un fallo de permisos o
/// de entrada y salida no es una detención benigna.
///
/// La garantía es «la rama y `HEAD` no se movieron», **no «cero commit»**:
/// `commit-tree` corre antes del CAS, así que cuando no se aplica el objeto
/// existe, inalcanzable desde cualquier referencia y recogible por el `gc`.
///
/// **Lleva la [causa], y eso no es un adorno del payload.** Las dos causas se
/// arreglan distinto y una de las dos ni siquiera intentó el
/// compare-and-swap. Sin ella, este desenlace afirmaba «la rama avanzó a
/// [headObservado]» para las dos —y con `ramaCambiada` la rama NO avanzó: el
/// `HEAD` observado es el de OTRA rama, la que quien corre se puso durante la
/// cascada—. El consejo que salía de ahí era peor que inútil: volver a correr
/// reconstruye el candidato sobre esa otra rama y commitea ahí. Un desenlace
/// derivado no puede afirmar un hecho que nadie midió, y por eso el que sí se
/// midió viaja hasta acá.
final class NoAplicado extends ShipOutcome {
  /// Por qué no se aplicó. Es el mismo valor que informó quien lo intentó, no
  /// una reconstrucción.
  final CausaDeNoAplicacion causa;

  /// Qué `HEAD` se encontró. **Qué significa depende de [causa]**: con
  /// `baseMovida` es dónde quedó la rama de la corrida; con `ramaCambiada` es
  /// el `HEAD` de la rama que está puesta ahora, que es otra.
  final String headObservado;

  const NoAplicado._({required this.causa, required this.headObservado});

  @override
  final String kind = 'noAplicado';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'causa': causa.name,
    'headObservado': headObservado,
  };

  factory NoAplicado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'noAplicado');
    return NoAplicado._(
      causa: ShipOutcome._porNombre(
        CausaDeNoAplicacion.values,
        json['causa'],
        'causa',
        'NoAplicado',
      ),
      headObservado: json['headObservado']! as String,
    );
  }
}

/// El commit existe y el índice quedó sin sincronizar.
///
/// **La revisión viaja como dato y no dentro de un mensaje**: quien recupere
/// tiene que poder comprobar si el índice ya coincide, y eso no se hace
/// parseando texto.
final class LocalInconsistente extends ShipOutcome {
  final String revision;

  const LocalInconsistente._({required this.revision});

  @override
  final String kind = 'localInconsistente';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'revision': revision};

  factory LocalInconsistente.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'localInconsistente');
    return LocalInconsistente._(revision: json['revision']! as String);
  }
}

/// Hay un pull request utilizable.
final class Publicado extends ShipOutcome {
  final PublicacionUtilizable pr;
  final EstadoPublicable verificacion;

  const Publicado._({required this.pr, required this.verificacion});

  @override
  final String kind = 'publicado';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'pr': pr.toJson(),
    'verificacion': verificacion.name,
  };

  factory Publicado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'publicado');
    final pr = PublicationOutcome.fromJson(
      Map<String, Object?>.from(json['pr']! as Map),
    );
    if (pr is! PublicacionUtilizable) {
      throw FormatException(
        'Publicado.fromJson recibió un desenlace remoto que no es '
        'utilizable: «${pr.kind}». Reconstruirlo dejaría escribible por JSON '
        'exactamente lo que el tipo impide construir en memoria.',
      );
    }
    return Publicado._(
      pr: pr,
      verificacion: ShipOutcome._porNombre(
        EstadoPublicable.values,
        json['verificacion'],
        'verificacion',
        'Publicado',
      ),
    );
  }
}

/// El trabajo local se completó y el efecto remoto no.
final class PublicacionIncompleta extends ShipOutcome {
  final PublicacionNoUtilizable remoto;
  final EstadoPublicable verificacion;

  const PublicacionIncompleta._({
    required this.remoto,
    required this.verificacion,
  });

  @override
  final String kind = 'publicacionIncompleta';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'remoto': remoto.toJson(),
    'verificacion': verificacion.name,
  };

  factory PublicacionIncompleta.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'publicacionIncompleta');
    final remoto = PublicationOutcome.fromJson(
      Map<String, Object?>.from(json['remoto']! as Map),
    );
    if (remoto is! PublicacionNoUtilizable) {
      throw FormatException(
        'PublicacionIncompleta.fromJson recibió un desenlace remoto '
        'utilizable: «${remoto.kind}». Un pull request abierto no es una '
        'publicación incompleta.',
      );
    }
    return PublicacionIncompleta._(
      remoto: remoto,
      verificacion: ShipOutcome._porNombre(
        EstadoPublicable.values,
        json['verificacion'],
        'verificacion',
        'PublicacionIncompleta',
      ),
    );
  }
}
