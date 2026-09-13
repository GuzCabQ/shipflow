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
