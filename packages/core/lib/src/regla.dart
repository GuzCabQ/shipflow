/// La regla y sus requisitos de instalación.
library;

import 'valores.dart';

/// Se lanza cuando alguien intenta construir una [Rule] que no se puede
/// instalar. Lleva el id del invariante que la rechazó y **qué hacer**.
class RuleNotInstallable implements Exception {
  /// `INV-3`, `INV-4`, `INV-8`, `INV-10` o `INV-11`.
  final String invariant;

  /// Qué falta, y qué hacer para que la regla sea instalable.
  final String reason;

  const RuleNotInstallable(this.invariant, this.reason);

  @override
  String toString() => 'RuleNotInstallable($invariant): $reason';
}

/// Una regla del arnés.
///
/// Los seis campos de docs/03 §4.1 son [origin], [loadLevel], [signalType],
/// [severity], [knownEvasions] y [alternative]. **Los dos últimos son
/// requisitos de instalación, no metadatos opcionales**, y este tipo los trata
/// como tales: una regla que no cumple sus invariantes **no se puede
/// construir**.
///
/// Que el rechazo esté en el constructor y no en un validador aparte es
/// deliberado. Un validador se puede no llamar; ya pasó. Acá no hay camino que
/// lo esquive: [fromJson] pasa por el mismo constructor, así que una regla
/// cargada de un archivo de configuración se valida igual que una escrita a
/// mano.
///
/// **Lo que este tipo NO puede verificar**, y queda declarado: que la
/// [alternative] sea *útil*, que las [knownEvasions] estén *completas*, o que
/// el [statement] describa lo que la regla realmente hace. Eso es del piso
/// inferencial (docs/03 §5.1) y del revisor.
class Rule {
  final String id;

  /// El enunciado de la regla, en la forma en que se proyecta a la capa C.
  final String statement;

  /// Derivada de un fallo observado, o intencional.
  final RuleOrigin origin;

  /// A qué artefacto se proyecta (`D-008`).
  final LoadLevel loadLevel;

  /// Qué clase de señal produce. **Es un hecho: no se mueve** (`D-009`).
  final SignalType signalType;

  /// Qué hace con esa señal. **Se mueve con evidencia** (ADR-013).
  final Severity severity;

  /// Vías alternativas conocidas por las que el control se evita.
  /// **Sin ellas no se instala en la capa de ganchos** (INV-3, `D-006`).
  final List<String> knownEvasions;

  /// El «hacé esto» que acompaña a toda prohibición (INV-11, `D-007`).
  final String? alternative;

  /// Dónde corre.
  final ControlLayer layer;

  /// `true` si la regla prohíbe algo. Una prohibición sin [alternative] está
  /// incompleta y no se instala.
  final bool prohibitive;

  Rule({
    required this.id,
    required this.statement,
    required this.origin,
    required this.loadLevel,
    required this.signalType,
    required this.severity,
    required this.layer,
    this.knownEvasions = const [],
    this.alternative,
    this.prohibitive = false,
  }) {
    final tieneAlternativa = (alternative ?? '').trim().isNotEmpty;

    if (prohibitive && !tieneAlternativa) {
      throw const RuleNotInstallable(
          'INV-11',
          'Una regla prohibitiva sin alternativa no se instala. '
              'Escribí el «hacé esto» que acompaña al «no hagas aquello».');
    }
    if (severity == Severity.bloquea && !tieneAlternativa) {
      throw const RuleNotInstallable(
          'INV-8',
          'Se bloquea solo si se puede decir QUÉ HACER. '
              'Una regla que bloquea sin alternativa deja a quien la choca sin salida.');
    }
    if (signalType == SignalType.inferencial && severity == Severity.bloquea) {
      throw const RuleNotInstallable(
          'INV-4',
          'Un control inferencial nunca detiene (ADR-006). '
              'Bajá la severidad a `reporta`, o convertí el control en determinista.');
    }
    if (layer == ControlLayer.ganchos && knownEvasions.isEmpty) {
      throw const RuleNotInstallable(
          'INV-3',
          'Ningún gancho se instala sin sus evasiones declaradas. '
              'Enumerá por dónde se lo esquiva, aunque la lista sea incómoda.');
    }
    if (layer == ControlLayer.ganchos && severity == Severity.bloquea) {
      throw const RuleNotInstallable(
          'INV-10',
          'Si bloquea, su ausencia es inaceptable, y lo inaceptable no se funda '
              'en la capa de ganchos: se desactiva con una bandera (ADR-018). '
              'Movelo a la cascada o a integración continua.');
    }
  }

  /// Una regla **recién agregada**, con la severidad que le corresponde por
  /// ADR-013: entra reportando, **salvo que su tipo de señal sea instrumento**.
  ///
  /// Un instrumento roto sí bloquea desde el primer día, porque su silencio es
  /// indistinguible de un verde: no medir se lee igual que medir y no encontrar
  /// nada. Promover cualquier otra regla a [Severity.bloquea] exige evidencia y
  /// pasa por el constructor normal.
  factory Rule.entering({
    required String id,
    required String statement,
    required RuleOrigin origin,
    required LoadLevel loadLevel,
    required SignalType signalType,
    required ControlLayer layer,
    List<String> knownEvasions = const [],
    String? alternative,
    bool prohibitive = false,
  }) =>
      Rule(
        id: id,
        statement: statement,
        origin: origin,
        loadLevel: loadLevel,
        signalType: signalType,
        severity: signalType == SignalType.instrumento
            ? Severity.bloquea
            : Severity.reporta,
        layer: layer,
        knownEvasions: knownEvasions,
        alternative: alternative,
        prohibitive: prohibitive,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'statement': statement,
        'origin': origin.name,
        'loadLevel': loadLevel.name,
        'signalType': signalType.name,
        'severity': severity.name,
        'knownEvasions': knownEvasions,
        'alternative': alternative,
        'layer': layer.name,
        'prohibitive': prohibitive,
      };

  factory Rule.fromJson(Map<String, Object?> json) => Rule(
        id: json['id']! as String,
        statement: json['statement']! as String,
        origin: RuleOrigin.values.byName(json['origin']! as String),
        loadLevel: LoadLevel.values.byName(json['loadLevel']! as String),
        signalType: SignalType.values.byName(json['signalType']! as String),
        severity: Severity.values.byName(json['severity']! as String),
        knownEvasions:
            List<String>.from(json['knownEvasions']! as List<Object?>),
        alternative: json['alternative'] as String?,
        layer: ControlLayer.values.byName(json['layer']! as String),
        prohibitive: json['prohibitive']! as bool,
      );
}
