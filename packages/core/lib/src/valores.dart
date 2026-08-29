/// Enumeraciones y objetos de valor del dominio.
///
/// Todo lo de este archivo es dato plano y serializable (ADR-002). Los enums
/// serializan por `name`, nunca por índice: reordenarlos no debe cambiar el
/// significado de una traza vieja.
library;

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
  /// Qué se ejecutó, tal como se ejecutó.
  final String invocation;

  /// Sobre qué. **Vacío es un dato**, no un descuido: significa que el paso
  /// corrió sin sujeto, y eso vuelve el resultado no concluyente.
  final List<String> subjects;

  /// Código de salida de la invocación.
  final int exitCode;

  /// Cuándo terminó, en UTC.
  final DateTime finishedAt;

  const Witness({
    required this.invocation,
    required this.subjects,
    required this.exitCode,
    required this.finishedAt,
  });

  /// Un testigo sin sujetos no atestigua nada (ADR-011, corolario 5): no
  /// distingue «no encontré nada» de «no miré ahí».
  bool get attests => subjects.isNotEmpty;

  Map<String, Object?> toJson() => {
        'invocation': invocation,
        'subjects': subjects,
        'exitCode': exitCode,
        'finishedAt': finishedAt.toUtc().toIso8601String(),
      };

  factory Witness.fromJson(Map<String, Object?> json) => Witness(
        invocation: json['invocation']! as String,
        subjects: List<String>.from(json['subjects']! as List<Object?>),
        exitCode: json['exitCode']! as int,
        finishedAt: DateTime.parse(json['finishedAt']! as String),
      );
}
