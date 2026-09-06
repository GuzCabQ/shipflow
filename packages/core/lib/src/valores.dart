/// Enumeraciones y objetos de valor del dominio.
///
/// Todo lo de este archivo es dato plano y serializable (ADR-002). Los enums
/// serializan por `name`, nunca por índice: reordenarlos no debe cambiar el
/// significado de una traza vieja.
library;

import 'desenlace.dart';

/// Severidad de un control determinista (ADR-013).
///
/// **Se mueve con evidencia**, a diferencia de [SignalType], que es un hecho.
enum Severity {
  /// Corta el paso. Solo se permite si la regla puede decir QUÉ HACER (INV-8).
  bloquea,

  /// Anota y sigue.
  reporta,

  /// Registra para telemetría y no se muestra.
  silencia,
}

/// Tipo de señal de un control (`D-009`).
///
/// **Es un hecho sobre el control, no una política: no cambia.** Confundirlo
/// con [Severity] fue lo que dejó reglas «promovidas» que en realidad nunca
/// habían cambiado de naturaleza.
enum SignalType {
  /// Mide el propio arnés. Un instrumento roto no reporta: bloquea, porque su
  /// silencio es indistinguible de un verde (ADR-013).
  instrumento,

  /// Determinista sobre el cambio: mismo diff, mismo resultado.
  deterministaSobreElCambio,

  /// Inferencial. **Nunca bloquea** (ADR-006). Ver [SignalType] en [Rule].
  inferencial,
}

/// Nivel de carga de contexto (`D-008`). Determina a qué artefacto se proyecta
/// una regla en la capa C.
enum LoadLevel {
  /// Siempre cargado.
  siempre,

  /// Siempre cargado, pero acotado a un subárbol.
  siempreAcotado,

  /// Bajo demanda, por enrutamiento explícito.
  bajoDemanda,

  /// Solo cuando el paso lo pide.
  soloAlPedirlo,
}

/// De dónde salió una regla.
enum RuleOrigin {
  /// Derivada de un fallo observado.
  derivada,

  /// Declarada por el equipo al configurar el proyecto.
  intencional,
}

/// Dónde corre un control (docs/03 §5.2).
///
/// **Ningún control cuya ausencia sea inaceptable se funda en [ganchos]**
/// (INV-10, ADR-018). Los ganchos se desactivan con una bandera.
enum ControlLayer {
  /// Ciclo de vida del CLI ajeno. No garantiza nada: solo acelera.
  ganchos,

  /// Nuestro propio proceso de verificación.
  cascada,

  /// Fuera de la máquina del operador. Lo único que le sobrevive.
  integracionContinua,
}

/// El veredicto de un paso de verificación.
///
/// **[noConcluyente] no es un tercer color amable: se trata como [rojo]**
/// (INV-2, `D-001`, `D-003`). Existe como valor propio para que la razón del
/// rojo sea legible: «no había testigo» no es lo mismo que «encontré fallas».
enum Verdict { verde, rojo, noConcluyente }

/// Cómo terminó una invocación. **No es lo mismo que su resultado.**
///
/// Un analizador que sale con código 1 porque encontró problemas SÍ se
/// ejecutó: su resultado es rojo y su terminación es [completa]. Uno que no
/// estaba instalado no produjo resultado alguno, y eso no puede leerse como
/// «no encontró nada».
///
/// Confundir las dos cosas es el agujero exacto que ADR-011 nombra —
/// «herramienta ausente, timeout» — y por eso la terminación es un campo y no
/// una interpretación del código de salida.
enum Termination {
  /// La herramienta corrió y produjo un resultado, cualquiera sea.
  completa,

  /// No estaba, o no se pudo invocar.
  herramientaAusente,

  /// Se cortó por presupuesto de tiempo.
  tiempoAgotado,

  /// Se interrumpió por cualquier otra causa antes de terminar.
  interrumpida,
}

/// Texto que vino de afuera, encapsulado como dato citado (INV-6, `ASI01`).
///
/// El punto no es el tipo: es que el texto externo **nunca se concatena a una
/// instrucción**. Quien lo reciba ve un [QuotedText] y sabe que lo que tiene
/// entre manos es un dato, no algo que deba obedecer.
class QuotedText {
  /// El texto, tal cual llegó. No se normaliza ni se recorta.
  final String content;

  /// De dónde vino. Identifica la fuente, no la interpreta.
  final String source;

  const QuotedText(this.content, {required this.source});

  Map<String, Object?> toJson() => {'content': content, 'source': source};

  factory QuotedText.fromJson(Map<String, Object?> json) => QuotedText(
        json['content']! as String,
        source: json['source']! as String,
      );

  @override
  bool operator ==(Object other) =>
      other is QuotedText && other.content == content && other.source == source;

  @override
  int get hashCode => Object.hash(content, source);

  @override
  String toString() => 'QuotedText($source: ${content.length} car.)';
}

/// Testigo de que un paso corrió, y sobre qué (ADR-011).
///
/// Sin esto no hay verde. La atestación no es higiene: es **habilitante**,
/// porque la superficie «cubierto» le pide al revisor que NO mire algo, y un
/// verde sin testigo le estaría pidiendo que se saltee lo que nadie miró.
class Witness {
  /// Qué se ejecutó, tal como se ejecutó. **Vacío no atestigua nada.**
  final String invocation;

  /// Sobre qué. **Vacío es un dato**, no un descuido: significa que el paso
  /// corrió sin sujeto propio, y por eso tiene que venir acompañado de al
  /// menos una omisión que lo explique (ver el invariante del constructor).
  final List<String> subjects;

  /// Código de salida de la invocación. **Es dato, no veredicto**: muchas
  /// herramientas salen con código distinto de cero cuando encuentran algo,
  /// y eso significa que corrieron. Quien lo interprete es el verificador que
  /// conoce esa herramienta, no este tipo.
  final int exitCode;

  /// **Qué NO cubrió, y por qué**, una [Omission] por residuo. Vacía
  /// significa «nada quedó afuera», y es una afirmación, no un silencio.
  ///
  /// ADR-011 pide un testigo de «qué corrió, sobre qué alcance, **qué omitió y
  /// por qué**». Es el corolario 5 vuelto dato: cada control declara si puede
  /// detectar una omisión. Un paso que no puede, lo dice acá.
  final List<Omission> omitted;

  /// Cuándo terminó, en UTC.
  final DateTime finishedAt;

  /// Las listas se copian a una vista inmodificable. Sin esto el invariante
  /// no es del tipo: quien conservara la lista original podía vaciarla
  /// después de construir el testigo y cambiarle el veredicto al resultado.
  ///
  /// **Sin sujetos y sin omisiones no se construye.** Es la acción imposible
  /// que este tipo cierra: un testigo que no cubrió nada y no dice por qué
  /// deja al reporte mandando a leer una lista vacía.
  ///
  /// **Una invocación en blanco tampoco.** Un testigo existe para decir qué
  /// se ejecutó; uno que no nombra nada no atestigua ninguna invocación.
  Witness({
    required this.invocation,
    required List<String> subjects,
    required this.exitCode,
    required this.finishedAt,
    required List<Omission> omitted,
  })  : subjects = List.unmodifiable(subjects),
        omitted = List.unmodifiable(omitted) {
    if (invocation.trim().isEmpty) {
      throw ArgumentError.value(invocation, 'invocation',
          'Una invocación en blanco no atestigua nada');
    }
    if (this.subjects.isEmpty && this.omitted.isEmpty) {
      throw ArgumentError.value(
          omitted,
          'omitted',
          'Un testigo que no cubre nada y no dice por qué deja al reporte '
              'mandando a leer una lista vacía. Si no cubriste, escribí qué '
              'quedó afuera');
    }
    final cubiertos = this.subjects.toSet();
    final contradictorios = [
      for (final o in this.omitted)
        if (o.subject != null && cubiertos.contains(o.subject)) o.subject!,
    ];
    if (contradictorios.isNotEmpty) {
      throw ArgumentError.value(
          contradictorios,
          'omitted',
          'Estos sujetos están en subjects Y en omitted: el testigo afirma '
              '«lo cubrí» y «no lo cubrí» del mismo sujeto a la vez');
    }
  }

  Map<String, Object?> toJson() => {
        'invocation': invocation,
        'subjects': subjects,
        'exitCode': exitCode,
        'omitted': [for (final o in omitted) o.toJson()],
        'finishedAt': finishedAt.toUtc().toIso8601String(),
      };

  factory Witness.fromJson(Map<String, Object?> json) => Witness(
        invocation: json['invocation']! as String,
        subjects: List<String>.from(json['subjects']! as List<Object?>),
        exitCode: json['exitCode']! as int,
        omitted: [
          for (final o in json['omitted']! as List<Object?>)
            Omission.fromJson(Map<String, Object?>.from(o! as Map)),
        ],
        finishedAt: DateTime.parse(json['finishedAt']! as String),
      );
}
