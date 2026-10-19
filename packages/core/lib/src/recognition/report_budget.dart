/// Qué cota del reporte derivado se alcanzó.
enum ReportLimitDimension {
  items('items'),
  textBytes('text_bytes'),
  jsonBytes('json_bytes');

  const ReportLimitDimension(this._wireName);

  final String _wireName;

  String toWireName() => _wireName;

  static ReportLimitDimension fromWireName(String wireName) =>
      values.firstWhere(
        (value) => value._wireName == wireName,
        orElse: () => throw FormatException('dimensión desconocida', wireName),
      );
}

/// Las cotas inclusivas del reporte derivado de un perfil. No reservan
/// memoria ni acotan el proceso entero: acotan lo que el reporte retiene.
final class ReportLimits {
  /// El perfil normal, el de omisión.
  const ReportLimits({
    this.maxDerivedItems = 16384,
    this.maxDerivedTextBytes = 1048576,
    this.maxReportJsonBytes = 2097152,
  });

  /// El perfil ampliado, que se elige explícitamente en cada invocación.
  const ReportLimits.extended()
    : this(
        maxDerivedItems: 18432,
        maxDerivedTextBytes: 1835008,
        maxReportJsonBytes: 2359296,
      );

  factory ReportLimits.fromJson(Map<String, Object?> json) => ReportLimits(
    maxDerivedItems: json['maxDerivedItems']! as int,
    maxDerivedTextBytes: json['maxDerivedTextBytes']! as int,
    maxReportJsonBytes: json['maxReportJsonBytes']! as int,
  );

  /// Filas semánticas y posiciones de referencia, cada una por ocurrencia.
  final int maxDerivedItems;

  /// Bytes UTF-8 de los textos retenidos, por ocurrencia.
  final int maxDerivedTextBytes;

  /// La respuesta JSON completa, con su envoltura y el salto final.
  final int maxReportJsonBytes;

  Map<String, Object?> toJson() => {
    'maxDerivedItems': maxDerivedItems,
    'maxDerivedTextBytes': maxDerivedTextBytes,
    'maxReportJsonBytes': maxReportJsonBytes,
  };
}

/// Lo consumido hasta ahora del presupuesto derivado.
final class DerivedUsage {
  const DerivedUsage({this.items = 0, this.textBytes = 0});

  factory DerivedUsage.fromJson(Map<String, Object?> json) => DerivedUsage(
    items: json['items']! as int,
    textBytes: json['textBytes']! as int,
  );

  final int items;
  final int textBytes;

  Map<String, Object?> toJson() => {'items': items, 'textBytes': textBytes};
}

/// Se lanzó al pedir más de lo que admite el perfil: abandona el reporte.
/// No lleva datos del proyecto, sólo qué cota se alcanzó.
final class ReportLimitExceeded implements Exception {
  const ReportLimitExceeded(this.dimension);

  factory ReportLimitExceeded.fromJson(Map<String, Object?> json) =>
      ReportLimitExceeded(
        ReportLimitDimension.fromWireName(json['dimension']! as String),
      );

  final ReportLimitDimension dimension;

  Map<String, Object?> toJson() => {'dimension': dimension.toWireName()};

  @override
  String toString() => 'ReportLimitExceeded(${dimension.toWireName()})';
}

/// [used] más [items] elementos y [textBytes] bytes, o [ReportLimitExceeded]
/// si no caben; elementos se comprueba antes que texto. Se consulta antes de
/// materializar lo que se cobra, nunca después.
DerivedUsage admitDerivedUsage(
  DerivedUsage used,
  ReportLimits limits, {
  required int items,
  required int textBytes,
}) {
  if (items < 0 || textBytes < 0) {
    throw ArgumentError('un cobro no puede ser negativo');
  }
  final nextItems = used.items + items;
  if (nextItems > limits.maxDerivedItems) {
    throw const ReportLimitExceeded(ReportLimitDimension.items);
  }
  final nextText = used.textBytes + textBytes;
  if (nextText > limits.maxDerivedTextBytes) {
    throw const ReportLimitExceeded(ReportLimitDimension.textBytes);
  }
  return DerivedUsage(items: nextItems, textBytes: nextText);
}
