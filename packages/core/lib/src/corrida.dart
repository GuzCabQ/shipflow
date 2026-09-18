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
/// **Los constructores son privados y la única entrada real es la fábrica de
/// la tarea 3** (`ShipOutcome.derivar`, todavía no escrita en esta rebanada).
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

  /// **La única entrada real.** Cada variante tiene constructor privado, así
  /// que nadie puede ensamblar un desenlace eligiendo la combinación que le
  /// convenga: se derivan de los hechos.
  ///
  /// **La precedencia es por gravedad del hecho, no por el camino de
  /// autorización.** Que el usuario no fuera a confirmar no vuelve menos cierto
  /// que hay un secreto:
  ///
  ///     errorInterno > secretDetected > verificationGate
  ///                  > confirmationMissing > previewOnly
  ///
  /// `errorInterno` está en esa lista como ESTADO y sale por
  /// [CausaDeNoIntento.verificationGate]; no es una causa. Con una causa propia,
  /// la combinación «gate con arnés roto» quedaría inalcanzable.
  static ShipOutcome derivar({
    required EstadoDeCorrida verificacion,
    required bool huboSecreto,
    required bool seConfirmo,
    required bool soloPreview,
    required bool autorizaIncompleto,
    PublicationOutcome? remoto,
    String? headQueRechazoElCas,
    String? revisionConIndiceSucio,
  }) {
    NoIntentado sinIntentar(CausaDeNoIntento causa) =>
        NoIntentado._(causa: causa, verificacion: verificacion);

    // 1 · El arnés roto. No lo autoriza ninguna bandera.
    if (verificacion == EstadoDeCorrida.errorInterno) {
      return sinIntentar(CausaDeNoIntento.verificationGate);
    }
    // 2 · El secreto, antes que cualquier camino de autorización.
    if (huboSecreto) return sinIntentar(CausaDeNoIntento.secretDetected);
    // 3 · La compuerta por estado.
    if (verificacion != EstadoDeCorrida.verde && !autorizaIncompleto) {
      return sinIntentar(CausaDeNoIntento.verificationGate);
    }
    // 4 · La confirmación, antes que la previsualización: quien no confirmó
    //     pidió escribir y no llegó a autorizarlo; quien previsualiza no lo
    //     pidió nunca.
    if (!seConfirmo) return sinIntentar(CausaDeNoIntento.confirmationMissing);
    if (soloPreview) return sinIntentar(CausaDeNoIntento.previewOnly);

    // A partir de acá la corrida sí intentó escribir.
    if (headQueRechazoElCas != null) {
      return NoAplicado._(headObservado: headQueRechazoElCas);
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

  static NoAplicado noAplicadoParaLaPrueba({required String headObservado}) =>
      NoAplicado._(headObservado: headObservado);

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
      causa: CausaDeNoIntento.values.byName(json['causa']! as String),
      verificacion: EstadoDeCorrida.values.byName(
        json['verificacion']! as String,
      ),
    );
  }
}

/// El CAS fue rechazado porque `HEAD` se movió. **Nada más lo produce**: un
/// fallo de permisos o de entrada y salida no es una detención benigna.
///
/// La garantía es «la rama y `HEAD` no se movieron», **no «cero commit»**:
/// `commit-tree` corre antes del CAS, así que cuando el CAS falla el objeto
/// existe, inalcanzable desde cualquier referencia y recogible por el `gc`.
final class NoAplicado extends ShipOutcome {
  /// Qué `HEAD` se encontró. Es lo que le permite a quien reintente saber
  /// sobre qué se va a reconstruir el candidato.
  final String headObservado;

  const NoAplicado._({required this.headObservado});

  @override
  final String kind = 'noAplicado';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'headObservado': headObservado,
  };

  factory NoAplicado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'noAplicado');
    return NoAplicado._(headObservado: json['headObservado']! as String);
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
      verificacion: EstadoPublicable.values.byName(
        json['verificacion']! as String,
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
      verificacion: EstadoPublicable.values.byName(
        json['verificacion']! as String,
      ),
    );
  }
}
