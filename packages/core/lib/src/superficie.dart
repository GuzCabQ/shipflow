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
  /// El control encontró algo. **Todos sus sujetos**, no solo el del
  /// diagnóstico: el veredicto es global al paso, y está medido que los
  /// diagnósticos no tienen relación validada con los sujetos del testigo.
  hallazgo,

  /// El control declaró que no miró ese sujeto.
  declaradoNoMirado,

  /// Nadie dio cuenta del sujeto: el libro de obligaciones lo dejó abierto.
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
  /// control rojo.
  candidatoAlterado,
}

/// Algo que un revisor humano tiene que mirar, y por qué.
class EntradaDeCriterio {
  /// Qué control la originó, si la originó alguno. Nulo cuando el hecho no es
  /// de ningún control —el entorno, una alteración, un sujeto que nadie tomó—.
  final String? controlId;

  /// Sobre qué sujeto. Nulo cuando el hecho no es de ningún sujeto.
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
/// entrada es [desde], que comprueba las cuatro cosas que la vuelven cierta.
///
/// **Residuo declarado.** Que la única entrada sea [desde] lo sostiene la
/// regla de arquitectura de la tarea 7, no una prueba de este archivo: desde
/// afuera del paquete no hay manera de comprobar que no exista otro
/// constructor público — solo de comprobar que el que se usó funciona. Una
/// prueba que afirmara lo contrario no podría fallar por lo que dice mirar.
class AfirmacionCubierta {
  final String controlId;
  final String sujeto;
  final Afirmacion afirmacion;
  final Witness testigo;

  AfirmacionCubierta._({
    required this.controlId,
    required this.sujeto,
    required this.afirmacion,
    required this.testigo,
  });

  /// La única entrada. Devuelve nulo cuando **no** se puede afirmar, que es lo
  /// más frecuente:
  ///
  /// - el desenlace no ejecutó —no hay testigo del que leer cobertura—;
  /// - el desenlace es **rojo**: el veredicto es global al paso y los
  ///   diagnósticos no tienen relación validada con los sujetos, así que no se
  ///   sabe cuál lo originó;
  /// - el testigo **no cubre** ese sujeto.
  ///
  /// La afirmación y el id salen del control, no de quien llama: así no hay
  /// forma de atribuirle a un control algo que no declara.
  static AfirmacionCubierta? desde({
    required Verifier control,
    required StepOutcome desenlace,
    required String sujeto,
  }) {
    if (desenlace is! Executed) return null;
    if (desenlace.verdict != Verdict.verde) return null;
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

  /// **Reconstruye lo que ya fue validado**, y por eso no vuelve a validar: el
  /// documento viene de una corrida donde la fábrica sí corrió. Volver a
  /// comprobar acá exigiría el control, que un documento no lleva.
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
