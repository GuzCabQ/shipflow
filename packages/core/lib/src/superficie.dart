/// La superficie de verificación: **qué quedó demostrado y qué requiere
/// criterio humano**.
///
/// «Cubierto» habilita a un revisor a **saltar**, así que todo lo que entra ahí
/// tiene que ser algo que se pueda no mirar sin perder información. Una
/// traducción mala le dice al revisor que se saltee lo que nadie verificó: es
/// el peor fallo que ADR-016 nombra, y por eso las reglas de acá son
/// restrictivas por construcción y no por criterio de quien compone.
library;

import 'desenlace.dart';
import 'entidades.dart';
import 'puertos.dart';
import 'regla.dart';
import 'valores.dart';

/// Por qué algo no se puede dar por cubierto. **Enum cerrado de diez.**
///
/// Ocho salen de la derivación original; las dos últimas entraron con la
/// rebanada del entorno de verificación, que produjo hechos que la cascada no
/// conoce y que igual vuelven la corrida no concluyente.
enum MotivoDeCriterio {
  /// El control encontró algo: **cualquier diagnóstico, bloqueante o no**. Un
  /// informativo deja el veredicto en verde y sin embargo es un hallazgo, así
  /// que también emite este motivo — si no, un sujeto de ese paso quedaba
  /// cubierto y el revisor leía que podía no mirarlo.
  ///
  /// Se emite sobre **todos los sujetos del paso**, no solo el del
  /// diagnóstico: el veredicto es global al paso, y está medido que los
  /// diagnósticos no tienen relación validada con los sujetos del testigo.
  ///
  /// **Y sobre ninguno cuando el testigo no cubre ninguno**, con la entrada
  /// sin sujeto: un control puede encontrar algo y no certificar nada —el
  /// formateador sobre un archivo que no parsea sale con diagnósticos y sin
  /// sujetos formateados—, y ahí el hallazgo es del control. Recorrer solo los
  /// sujetos del testigo lo perdía entero.
  hallazgo,

  /// El control declaró que no miró ese sujeto.
  declaradoNoMirado,

  /// Nadie dio cuenta. **Tres hechos bajo un motivo**, y va escrito: el libro
  /// de obligaciones dejó el sujeto abierto —un control lo tenía en su alcance
  /// esperado y su testigo no lo cubrió ni lo nombró como omisión—; o el
  /// entorno se derivó y **ningún control corrió**, donde no hay libro ni
  /// sujeto y la entrada va sin los dos; o la cascada corrió **sin ningún
  /// control registrado**, donde sí hay alcance observado y el libro está
  /// vacío porque no hay paso que contraiga una obligación. Lo que comparten
  /// es lo que el motivo nombra: nadie dio cuenta. El detalle de la entrada
  /// dice cuál de los tres es.
  nadieDioCuenta,

  /// El sujeto no es de este stack.
  ajenoAlStack,

  /// No se pudo establecer qué era.
  noSePudoMirar,

  /// El control empezó y no llegó a terminar.
  intentoIncompleto,

  /// El arnés se rompió.
  instrumentoFallo,

  /// El control declaró un residuo que no ata a ningún sujeto.
  residuoGeneral,

  /// **El entorno no se pudo derivar, así que la cascada nunca corrió.** No
  /// hay nada que la corrida pueda afirmar, y no hay un resultado de cascada
  /// del cual derivarlo.
  entornoNoDerivado,

  /// **El candidato dejó de ser el árbol que dice representar.** Una
  /// alteración no dice cuál de los dos árboles vio cada control, así que
  /// ningún sujeto se puede dar por cubierto — el mismo argumento que el
  /// control que encontró algo, aplicado al árbol en vez de al paso.
  candidatoAlterado,
}

/// Algo que un revisor humano tiene que mirar, y por qué.
class EntradaDeCriterio {
  /// Qué control la originó, si la originó alguno. Nulo cuando el hecho no es
  /// de ningún control —el entorno, una alteración, un sujeto que nadie tomó—.
  final String? controlId;

  /// Sobre qué sujeto. Nulo cuando el hecho no es de ningún sujeto **o no se
  /// le puede atribuir a ninguno** —un control que encontró algo y no
  /// certificó nada—. Nulo no significa que no haya nada que mirar: significa
  /// que lo que hay que mirar no se reduce a un sujeto.
  final String? sujeto;

  final MotivoDeCriterio motivo;

  /// Qué pasó, en concreto. **Nunca en blanco**: el motivo dice la categoría,
  /// y esto dice el caso. Sin él, una entrada le pide a alguien que mire algo
  /// sin decirle qué.
  final String detalle;

  EntradaDeCriterio({
    this.controlId,
    this.sujeto,
    required this.motivo,
    required this.detalle,
  }) {
    if (detalle.trim().isEmpty) {
      throw ArgumentError.value(
        detalle,
        'detalle',
        'Una entrada de criterio sin detalle le pide a alguien que mire algo '
            'sin decirle qué.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'controlId': controlId,
    'sujeto': sujeto,
    'motivo': motivo.name,
    'detalle': detalle,
  };

  factory EntradaDeCriterio.fromJson(Map<String, Object?> json) =>
      EntradaDeCriterio(
        controlId: json['controlId'] as String?,
        sujeto: json['sujeto'] as String?,
        motivo: MotivoDeCriterio.values.byName(json['motivo']! as String),
        detalle: json['detalle']! as String,
      );
}

/// Un sujeto que un control demostró, con el testigo que lo sostiene.
///
/// **No se ensambla a mano.** Un constructor público dejaría armar una
/// afirmación cubierta con cualquier afirmación y cualquier testigo; la única
/// entrada es [desde], que niega la afirmación con **tres** condiciones —tres
/// `if`, tres ramas de código—: el desenlace no ejecutó, trae algún
/// diagnóstico, o su testigo no incluye al sujeto pedido.
///
/// **Qué ata la firma, y qué no.** Lo que [desde] garantiza es que la
/// afirmación y el testigo salen **del objeto que se le pasa**: la afirmación
/// es `control.afirmacion` y el testigo es `desenlace.witness`, así que quien
/// llama no puede sustituir ninguno de los dos por el de otro. Lo que **no**
/// garantiza es que ese control y ese desenlace vayan juntos: son dos
/// parámetros independientes, y pasarle el control de un paso con el desenlace
/// de otro construye una afirmación de un control respaldada por la invocación
/// de otro. Una versión anterior de este párrafo lo presentaba como una
/// imposibilidad estructural —«no hay forma de construir el caso que lo
/// rompería»— y una revisión lo rompió en tres líneas.
///
/// **No se cierra en la firma a propósito.** Atarlos de verdad pediría que el
/// desenlace supiera qué control lo produjo, y ADR-019 decidió lo contrario:
/// el desenlace no lleva el id del paso. Quien empareja control con desenlace
/// es la derivación de la superficie, y ahí sí se comprueba: lee el desenlace
/// del registro por id, exige que el mapa de controles tenga ese id y que el
/// control declare ese mismo id, y lanza si alguna de las dos no se cumple.
/// La procedencia depende de que el llamador sea correcto, y eso queda
/// **declarado** acá en vez de prometido como si lo sostuviera el tipo.
///
/// **Residuo declarado, y sin control que lo sostenga.** Que la única entrada
/// sea [desde] **no lo verifica nada**: lo sostiene el código fuente, y punto.
/// Desde afuera del paquete no hay manera de comprobar que no exista otro
/// constructor público —solo de comprobar que el que se usó funciona— porque
/// eso pediría reflexión, y este paquete no puede importar la biblioteca que la
/// trae. Una prueba que dijera vigilarlo no podría fallar por lo que dice
/// mirar, así que no se escribe ninguna: se prefiere el residuo escrito a un
/// guardia que no puede ponerse rojo.
///
/// Una versión anterior de este párrafo decía que lo sostenía una regla de
/// arquitectura. **Era falso** —esa regla se decidió no instalar, justamente
/// porque no puede mirar lo que diría mirar— y lo encontró una revisión: una
/// afirmación sobre un control inexistente, dentro del archivo que existe para
/// cerrar esa clase de afirmación.
class AfirmacionCubierta {
  final String controlId;
  final String sujeto;
  final Afirmacion afirmacion;
  final Witness testigo;

  /// **El invariante del tipo: el testigo tiene que cubrir al sujeto.** Va en
  /// el cuerpo del constructor y no en una sola de las entradas porque es una
  /// propiedad del objeto, no de un camino: una afirmación cubierta cuyo
  /// testigo no nombra al sujeto le dice al revisor que puede saltear algo que
  /// nadie certificó, y eso vale igual venga de la fábrica o de un documento.
  ///
  /// Desde [desde] no puede dispararse —ahí la misma condición devuelve nulo
  /// antes de llegar acá, que es lo que la derivación necesita—; desde
  /// [AfirmacionCubierta.fromJson] sí, y ahí estaba el agujero: un documento
  /// con el sujeto cambiado por uno que el testigo no cubre se deserializaba
  /// sin chistar.
  AfirmacionCubierta._({
    required this.controlId,
    required this.sujeto,
    required this.afirmacion,
    required this.testigo,
  }) {
    if (!testigo.subjects.contains(sujeto)) {
      throw ArgumentError.value(
        sujeto,
        'sujeto',
        'El testigo de esta afirmación no cubre al sujeto: certifica '
            '${testigo.subjects.isEmpty ? '(ninguno)' : testigo.subjects.join(", ")}. '
            'Una afirmación cubierta autoriza a no mirar, y acá el testigo '
            'que tendría que sostenerla dice otra cosa.',
      );
    }
  }

  /// La única entrada. Devuelve nulo cuando **no** se puede afirmar, que es lo
  /// más frecuente:
  ///
  /// - el desenlace no ejecutó —no hay testigo del que leer cobertura—;
  /// - el desenlace trae **cualquier diagnóstico**, bloqueante o no: el
  ///   veredicto es global al paso y los diagnósticos no tienen relación
  ///   validada con los sujetos, así que no se sabe cuál lo originó;
  /// - el testigo **no cubre** ese sujeto.
  ///
  /// La afirmación y el id salen **del control que se le pasa**, y el testigo
  /// **del desenlace que se le pasa**: quien llama no puede sustituir ninguno
  /// de los dos por el de otro objeto. Que ese control y ese desenlace sean
  /// los de un mismo paso no lo puede comprobar esta fábrica —ver el doc de la
  /// clase— y lo comprueba la derivación contra el registro de la corrida.
  static AfirmacionCubierta? desde({
    required Verifier control,
    required StepOutcome desenlace,
    required String sujeto,
  }) {
    if (desenlace is! Executed) return null;
    // **Cualquier diagnóstico, no solo el bloqueante.** [Executed.verdict]
    // solo mira `Severity.bloquea`, así que un paso con un diagnóstico
    // informativo sale verde: rechazar por veredicto dejaba cubierto un
    // sujeto de un control que SÍ encontró algo, y la superficie le decía al
    // revisor que podía no mirarlo. El argumento es el mismo que ya sostenía
    // la regla del rojo y no depende de la severidad: con un informativo
    // tampoco se sabe cuál sujeto lo originó.
    //
    // Y **subsume el chequeo del veredicto**, que por eso ya no está: `rojo`
    // exige un bloqueante, que es un diagnóstico; `noConcluyente` exige
    // `subjects` vacío, y entonces el `if` de abajo rechaza igual. Dejarlo
    // sería una condición que no puede decidir nada — un guardia que no se
    // puede poner rojo, que es justo lo que este archivo se prohíbe.
    if (desenlace.diagnostics.isNotEmpty) return null;
    if (!desenlace.witness.subjects.contains(sujeto)) return null;
    return AfirmacionCubierta._(
      controlId: control.id,
      sujeto: sujeto,
      afirmacion: control.afirmacion,
      testigo: desenlace.witness,
    );
  }

  Map<String, Object?> toJson() => {
    'controlId': controlId,
    'sujeto': sujeto,
    'afirmacion': afirmacion.toJson(),
    'testigo': testigo.toJson(),
  };

  /// **Revalida lo que el documento alcanza a decidir, y declara el resto.**
  ///
  /// - **Sí:** que el testigo cubra al sujeto. Los dos datos están en el
  ///   documento, así que la contradicción es visible acá y se rechaza — la
  ///   comprueba el invariante del constructor. Decía «no se revalida nada»
  ///   y por eso aceptaba un sujeto cambiado por otro que el testigo no
  ///   nombra: una afirmación que autoriza a saltear algo que nadie certificó.
  /// - **No:** que la afirmación y el id sean los que ese control declara. Eso
  ///   sí exigiría el control, que un documento no lleva, y por eso se
  ///   reconstruye tal cual vino de la corrida donde la fábrica sí corrió.
  factory AfirmacionCubierta.fromJson(Map<String, Object?> json) =>
      AfirmacionCubierta._(
        controlId: json['controlId']! as String,
        sujeto: json['sujeto']! as String,
        afirmacion: Afirmacion.fromJson(
          json['afirmacion']! as Map<String, Object?>,
        ),
        testigo: Witness.fromJson(json['testigo']! as Map<String, Object?>),
      );
}

/// Lo que se deriva de una corrida entera: qué quedó demostrado y qué requiere
/// criterio humano.
///
/// **No lleva el candidato ni el identificador de la corrida.** Quien quiera
/// atar la superficie a un contenido usa [ArtefactoDeRevision]; mantenerla sin
/// identidad es lo que permite derivarla de una corrida que no llegó a tener
/// candidato — porque el entorno no se pudo derivar — sin inventar un valor.
class SuperficieDeVerificacion {
  final List<AfirmacionCubierta> cubierto;
  final List<EntradaDeCriterio> requiereCriterio;

  /// **Se deriva de la corrida entera.** No es un reenvío ciego del de la
  /// cascada: cuando el entorno no se derivó o el candidato se alteró, este
  /// campo nombra `noConcluyente` aunque la cascada no haya corrido —no hay
  /// nada que copiar— o haya corrido y dado verde sobre un árbol que ya no es
  /// el que se fijó —copiarlo sería el falso verde que esta superficie existe
  /// para cerrar—. Cuando la cascada es la única fuente que queda —entorno
  /// derivado, candidato intacto— sí **coincide** con `cascada.estado`, y ahí
  /// es correcto que coincida: ningún otro hecho de la corrida lo contradice.
  final EstadoDeCorrida estado;

  SuperficieDeVerificacion({
    required List<AfirmacionCubierta> cubierto,
    required List<EntradaDeCriterio> requiereCriterio,
    required this.estado,
  }) : cubierto = List.unmodifiable(cubierto),
       requiereCriterio = List.unmodifiable(requiereCriterio) {
    // No es una comprobación de más: es el invariante del tipo. Una corrida
    // que no salió verde no puede autorizar a saltear nada sin nombrar qué
    // requiere criterio. Una sola condición, no dos anidadas: el `if` externo
    // por sí solo no afirmaba nada.
    if (estado != EstadoDeCorrida.verde &&
        cubierto.isNotEmpty &&
        requiereCriterio.isEmpty) {
      throw ArgumentError(
        'Una corrida que no salió verde tiene que decir qué requiere '
        'criterio: si no, afirma cobertura sin nombrar lo que falta.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'cubierto': [for (final c in cubierto) c.toJson()],
    'requiereCriterio': [for (final e in requiereCriterio) e.toJson()],
    'estado': estado.name,
  };

  factory SuperficieDeVerificacion.fromJson(Map<String, Object?> json) =>
      SuperficieDeVerificacion(
        cubierto: [
          for (final c in json['cubierto']! as List<Object?>)
            AfirmacionCubierta.fromJson(Map<String, Object?>.from(c! as Map)),
        ],
        requiereCriterio: [
          for (final e in json['requiereCriterio']! as List<Object?>)
            EntradaDeCriterio.fromJson(Map<String, Object?>.from(e! as Map)),
        ],
        estado: EstadoDeCorrida.values.byName(json['estado']! as String),
      );
}

/// Lo que se le publica a un revisor humano.
///
/// **La revisión no está acá, y es a propósito:** este artefacto existe antes
/// de que el commit exista. Lo que lleva revisión es la solicitud, y vive del
/// lado de la forja.
class ArtefactoDeRevision {
  final SuperficieDeVerificacion superficie;

  /// Qué contenido se expuso a los controles.
  final CandidateIdentity candidato;

  /// Por qué existe esta rebanada.
  final String intent;

  /// El plan, si lo hay.
  final String? plan;

  /// Por qué no hay plan. **Presente si y solo si [plan] es nulo.**
  ///
  /// Sin esto, un artefacto sin plan afirmaría por omisión que no hacía falta
  /// ninguno. **Y no se inventan tareas**: un listado fabricado sería una
  /// superficie que se lee como capacidad, que es el diagnóstico que este
  /// repositorio ya se hace a sí mismo con los puertos sin implementación.
  final String? sinPlanPorque;

  /// Qué alcance tiene lo que se afirma. **Requerido**: sin él, «cubierto» se
  /// lee como una afirmación sobre el cambio entero.
  final String alcanceDeLoAfirmado;

  /// El texto para el modo sin elementos de trabajo.
  ///
  /// **La segunda frase no es adorno**: es el límite medido de cómo se
  /// materializa el candidato. Con normalización o filtros de contenido, el
  /// objeto que se commitea puede diferir del archivo tal como se ve en el
  /// editor, y un revisor que no lo sepa lee de más.
  static const alcanceSoloPR =
      'No existen criterios de aceptación ni cobertura funcional. Se '
      'verificaron propiedades de herramienta; el comportamiento y el '
      'propósito de todos los cambios requieren revisión humana. El objeto '
      'commiteado es exactamente el que se expuso a los controles; con '
      'normalización o filtros de contenido, ese objeto puede diferir del '
      'archivo tal como se ve en el editor.';

  ArtefactoDeRevision({
    required this.superficie,
    required this.candidato,
    required this.intent,
    required this.plan,
    required this.sinPlanPorque,
    required this.alcanceDeLoAfirmado,
  }) {
    if ((plan == null) != (sinPlanPorque != null)) {
      throw ArgumentError(
        'O hay plan, o hay un motivo por el que no lo hay: sin ninguno de los '
        'dos el artefacto afirma por omisión que no hacía falta, y con los '
        'dos dice dos cosas incompatibles.',
      );
    }
    // Presente pero en blanco afirma exactamente lo mismo que ausente: un
    // `sinPlanPorque` de `''` le dice al revisor «no hay motivo», que es lo
    // que la ausencia ya dice por omisión y lo que este invariante existe
    // para impedir. Por eso no basta con `!= null`: hay que mirar el
    // contenido.
    if ((plan != null && plan!.trim().isEmpty) ||
        (sinPlanPorque != null && sinPlanPorque!.trim().isEmpty)) {
      throw ArgumentError(
        'Un plan o un motivo de ausencia presentes pero en blanco afirman lo '
        'mismo que su ausencia: exactamente lo que este invariante existe '
        'para impedir.',
      );
    }
    if (intent.trim().isEmpty || alcanceDeLoAfirmado.trim().isEmpty) {
      throw ArgumentError(
        'La intención y el alcance de lo afirmado son lo que un revisor lee '
        'primero: ninguno puede ir en blanco.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'superficie': superficie.toJson(),
    'candidato': candidato.toJson(),
    'intent': intent,
    'plan': plan,
    'sinPlanPorque': sinPlanPorque,
    'alcanceDeLoAfirmado': alcanceDeLoAfirmado,
  };

  factory ArtefactoDeRevision.fromJson(Map<String, Object?> json) =>
      ArtefactoDeRevision(
        superficie: SuperficieDeVerificacion.fromJson(
          json['superficie']! as Map<String, Object?>,
        ),
        candidato: CandidateIdentity.fromJson(
          json['candidato']! as Map<String, Object?>,
        ),
        intent: json['intent']! as String,
        plan: json['plan'] as String?,
        sinPlanPorque: json['sinPlanPorque'] as String?,
        alcanceDeLoAfirmado: json['alcanceDeLoAfirmado']! as String,
      );
}
