import 'package:core/core.dart';

/// Un normalizador con un formato propio, deliberadamente trivial.
///
/// **No reimplementa el parseo de ninguna herramienta real**, por la misma
/// razon que la politica falsa no reimplementa patrones: dos copias del mismo
/// error se ponen de acuerdo y la suite lo confirma en verde.
///
/// Lo que SI honra son las cuatro clausulas de [DiagnosticNormalizer], que no
/// son de ninguna herramienta sino del puerto. Que este formato tenga una
/// linea de encabezado no es imitacion: es la clausula 2 hecha sintaxis. Una
/// salida que dice «mire y no encontre nada» necesita algo que escribir cuando
/// no encontro nada, y el vacio no sirve para eso en ningun formato.
///
/// El formato:
///
/// ```
/// NORMALIZADOR FALSO v1
/// bloquea|src/a|12|regla-x|El mensaje
/// reporta|src/b||regla-y|Otro mensaje
/// ```
class NormalizadorFalso implements DiagnosticNormalizer {
  static const encabezado = 'NORMALIZADOR FALSO v1';

  const NormalizadorFalso();

  /// La salida que significa «corri y no habia nada». Se expone para que la
  /// suite de contrato no tenga que conocer el formato de adentro.
  static QuotedText limpio({String source = 'normalizador falso'}) =>
      QuotedText('$encabezado\n', source: source);

  @override
  List<Diagnostic> normalize(QuotedText rawOutput) {
    final fuente = rawOutput.source;
    final texto = rawOutput.content;

    if (texto.trim().isEmpty) {
      throw UnreadableToolOutput(
          fuente, 'Salida vacia: indistinguible de no haber corrido.');
    }

    final lineas = texto.trimRight().split('\n');
    if (lineas.first != encabezado) {
      throw UnreadableToolOutput(
          fuente, 'La primera linea no es «$encabezado».');
    }

    final salida = <Diagnostic>[];
    // Se recorren TODAS. Saltear una linea que no se entiende seria el mismo
    // salto silencioso que la clausula 1 prohibe, en chiquito.
    for (final linea in lineas.skip(1)) {
      final campos = linea.split('|');
      if (campos.length != 5) {
        throw UnreadableToolOutput(
            fuente, 'Linea con ${campos.length} campos y no 5: «$linea».');
      }
      final Severity severidad;
      try {
        severidad = Severity.values.byName(campos[0]);
      } on ArgumentError {
        throw UnreadableToolOutput(
            fuente, 'Severidad desconocida: «${campos[0]}».');
      }
      salida.add(Diagnostic(
        file: campos[1],
        line: campos[2].isEmpty ? null : int.parse(campos[2]),
        severity: severidad,
        ruleId: campos[3],
        // El mensaje viaja tal cual (clausula 4).
        message: QuotedText(campos[4], source: fuente),
      ));
    }
    return List.unmodifiable(salida);
  }
}
