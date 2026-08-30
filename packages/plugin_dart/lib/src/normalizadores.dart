/// Los dos normalizadores del stack: uno por herramienta.
///
/// Ambos cumplen las cuatro clausulas de [DiagnosticNormalizer], y la primera
/// —no interpretar nunca se devuelve como lista vacia— es la unica razon por
/// la que este archivo es tan estricto. Un normalizador permisivo es la forma
/// mas barata de fabricar un verde: se come lo que no entiende y devuelve
/// cero hallazgos, que es exactamente lo que devuelve cuando todo esta bien.
///
/// **No hace falta que ninguno verifique que le dieron la salida correcta.**
/// Los dos formatos son mutuamente ilegibles: la salida de uno no es JSON, y
/// la del otro no tiene linea de resumen. Cablear el normalizador equivocado
/// da [UnreadableToolOutput], no una lista corta.
library;

import 'dart:convert';

import 'package:core/core.dart';

/// Lee la salida de `dart analyze --format=json`.
///
/// **El formato se eligio por su caso vacio, no por comodidad.** El formato
/// `machine` es mas facil de parsear y escribe CERO BYTES cuando no encontro
/// nada; cero bytes es tambien lo que deja una herramienta que no esta
/// instalada, que murio por presupuesto de tiempo, o que corrio sobre un
/// directorio inexistente. `{"version":1,"diagnostics":[]}` afirma haber
/// mirado. La diferencia entre las dos cosas es todo ADR-011.
class NormalizadorDeAnalisis implements DiagnosticNormalizer {
  /// La invocacion cuya salida sabe leer. Se declara para que quede escrito
  /// que el formato es parte del contrato con la herramienta, no un detalle.
  static const invocacion = 'dart analyze --format=json';

  /// La unica version de esquema que sabe leer.
  ///
  /// Que la herramienta numere su esquema es lo que permite que el dia que
  /// cambie, esto se ponga NO CONCLUYENTE en vez de leer un formato nuevo con
  /// reglas viejas y devolver una lista mas corta de lo que corresponde.
  static const versionSoportada = 1;

  const NormalizadorDeAnalisis();

  /// `--fatal-warnings` viene encendido por defecto en la herramienta, asi que
  /// una advertencia detiene igual que un error. Lo informativo anota.
  ///
  /// **Una severidad desconocida no cae en `reporta`.** Caer en el caso benigno
  /// seria degradar en silencio algo que quiza detenia: la herramienta agrego
  /// una categoria y nosotros la estariamos leyendo como la mas suave.
  static Severity _severidad(String cruda, String fuente) => switch (cruda) {
        'ERROR' => Severity.bloquea,
        'WARNING' => Severity.bloquea,
        'INFO' => Severity.reporta,
        _ => throw UnreadableToolOutput(
            fuente,
            'Severidad desconocida: «$cruda». Mapeala en el normalizador; '
            'adivinar la mas suave degradaria en silencio algo que quiza '
            'detiene.'),
      };

  @override
  List<Diagnostic> normalize(QuotedText rawOutput) {
    final fuente = rawOutput.source;

    // Clausula 2, explicita y no heredada del decodificador. Que `jsonDecode`
    // tambien falle ante el vacio es una casualidad util, no una garantia: un
    // control que depende del efecto colateral de otro no esta instalado.
    if (rawOutput.content.trim().isEmpty) {
      throw UnreadableToolOutput(
          fuente,
          'Salida vacia. No es «no encontro nada»: es indistinguible de que '
          'la herramienta no llego a correr. Verificalo con el testigo del '
          'paso, no con esta lista.');
    }

    final Object? crudo;
    try {
      crudo = jsonDecode(rawOutput.content);
    } on FormatException catch (e) {
      throw UnreadableToolOutput(
          fuente, 'La salida no es JSON valido: ${e.message}');
    }

    if (crudo is! Map<String, Object?>) {
      throw UnreadableToolOutput(fuente,
          'Se esperaba un objeto JSON en la raiz, llego ${crudo.runtimeType}.');
    }

    final version = crudo['version'];
    if (version != versionSoportada) {
      throw UnreadableToolOutput(
          fuente,
          'Esquema version «$version»; este normalizador solo sabe leer la '
          '$versionSoportada. Actualizalo antes de confiar en lo que lea: '
          'leer un esquema nuevo con reglas viejas devuelve menos '
          'hallazgos, no un error.');
    }

    final lista = crudo['diagnostics'];
    if (lista is! List) {
      throw UnreadableToolOutput(
          fuente, '«diagnostics» no es una lista: ${lista.runtimeType}.');
    }

    return List.unmodifiable([
      for (final entrada in lista) _uno(entrada, fuente),
    ]);
  }

  Diagnostic _uno(Object? entrada, String fuente) {
    if (entrada is! Map<String, Object?>) {
      throw UnreadableToolOutput(
          fuente, 'Un diagnostico no es un objeto: ${entrada.runtimeType}.');
    }

    final codigo = entrada['code'];
    final severidad = entrada['severity'];
    final mensaje = entrada['problemMessage'];
    if (codigo is! String || severidad is! String || mensaje is! String) {
      throw UnreadableToolOutput(
          fuente,
          'Un diagnostico sin «code», «severity» o «problemMessage» legibles. '
          'Descartarlo dejaria un hallazgo real fuera de la cuenta.');
    }

    final ubicacion = entrada['location'];
    if (ubicacion is! Map<String, Object?>) {
      throw UnreadableToolOutput(
          fuente, 'Un diagnostico sin «location» legible: no se sabe donde.');
    }
    final archivo = ubicacion['file'];
    if (archivo is! String) {
      throw UnreadableToolOutput(
          fuente, 'Un diagnostico sin «location.file» legible.');
    }

    // La linea SI puede faltar: hay diagnosticos de archivo entero. Que falte
    // es un dato, y `Diagnostic.line` es nulo justamente para eso.
    final rango = ubicacion['range'];
    final inicio = rango is Map<String, Object?> ? rango['start'] : null;
    final linea = inicio is Map<String, Object?> ? inicio['line'] : null;

    return Diagnostic(
      file: archivo,
      line: linea is int ? linea : null,
      severity: _severidad(severidad, fuente),
      // El identificador de la herramienta viaja tal cual. Prefijarlo seria
      // reescribirlo, y el codigo es lo que hace rastreable un hallazgo hasta
      // la documentacion de quien lo emitio.
      ruleId: codigo,
      message: QuotedText(mensaje, source: fuente),
      // Escotilla `D-015`: lo que solo entiende el normalizador. La correccion
      // sugerida vive aca y no en el mensaje porque el mensaje es de la
      // herramienta y no se toca (INV-6).
      sourceMetadata: {
        'tipo': entrada['type'],
        'correccion': entrada['correctionMessage'],
        'documentacion': entrada['documentation'],
      },
    );
  }
}

/// Lee la salida combinada de `dart format --output=none`.
///
/// **Necesita las dos corrientes.** La herramienta escribe el resumen y los
/// archivos cambiados por la salida estandar, y los errores de parseo por la
/// de error. Quien la invoque las concatena en ese orden —primero estandar,
/// despues error— y este normalizador cuenta con eso.
///
/// **El resumen es obligatorio.** Es el denominador: dice cuantos archivos
/// miro de verdad. Sin el, cero hallazgos no significa nada, porque esta
/// herramienta sale con codigo 0 y sin una sola queja cuando el directorio que
/// le pasaron no existe. Eso esta medido, y es la razon de que esta clase se
/// niegue a interpretar una salida sin resumen.
class NormalizadorDeFormato implements DiagnosticNormalizer {
  /// La invocacion cuya salida sabe leer.
  static const invocacion = 'dart format --output=none';

  const NormalizadorDeFormato();

  /// `Formatted 3 files (1 changed) in 0.05 seconds.` y `Formatted no files
  /// in 0.00 seconds.` La cuenta se captura porque es el denominador.
  static final _resumen = RegExp(
      r'^Formatted (?:(no) files|(\d+) files?(?: \((\d+) changed\))?) in ',
      multiLine: true);

  static final _cambiado = RegExp(r'^Changed (.+)$', multiLine: true);

  /// `line 2, column 1 of lib/roto.dart: Expected to find '}'.`
  static final _noParsea =
      RegExp(r'^line (\d+), column \d+ of (.+?): (.+)$', multiLine: true);

  static final _encabezadoNoParsea = RegExp(
      r'^Could not format because the source could not be parsed:$',
      multiLine: true);

  @override
  List<Diagnostic> normalize(QuotedText rawOutput) {
    final fuente = rawOutput.source;
    final texto = rawOutput.content;

    if (texto.trim().isEmpty) {
      throw UnreadableToolOutput(
          fuente,
          'Salida vacia. Esta herramienta siempre escribe su resumen, asi que '
          'el vacio significa que no llego a correr.');
    }

    if (!_resumen.hasMatch(texto)) {
      throw UnreadableToolOutput(
          fuente,
          'Falta la linea de resumen «Formatted ... in ...». Es el denominador: '
          'sin ella, cero hallazgos no distingue «todo formateado» de «no '
          'miro ningun archivo», y esta herramienta sale con codigo 0 en '
          'el segundo caso.');
    }

    final salida = <Diagnostic>[];

    for (final m in _cambiado.allMatches(texto)) {
      final ruta = m.group(1)!;
      salida.add(Diagnostic(
        file: ruta,
        // La herramienta no emite codigo propio para esto: no hay ninguno que
        // preservar, asi que se acuña uno. Donde SI hay codigo —el analizador—
        // se usa el suyo.
        ruleId: 'formato/sin-formatear',
        // Se detiene porque puede decir QUE HACER, que es la condicion de
        // INV-8. La alternativa va en la escotilla, no en el mensaje.
        severity: Severity.bloquea,
        message: QuotedText(m.group(0)!, source: fuente),
        sourceMetadata: const {
          'alternativa': 'Corre el formateador del stack.'
        },
      ));
    }

    final fallosDeParseo = _noParsea.allMatches(texto).toList();
    for (final m in fallosDeParseo) {
      salida.add(Diagnostic(
        file: m.group(2)!,
        line: int.parse(m.group(1)!),
        ruleId: 'formato/no-parsea',
        severity: Severity.bloquea,
        message: QuotedText(m.group(0)!, source: fuente),
      ));
    }

    // S4. Si la herramienta dijo que algo no parsea y de ese bloque no salio
    // ni un diagnostico, el archivo corrupto se convirtio en silencio: es
    // literalmente el salto silencioso que el sabotaje busca.
    if (_encabezadoNoParsea.hasMatch(texto) && fallosDeParseo.isEmpty) {
      throw UnreadableToolOutput(
          fuente,
          'La herramienta reporto codigo que no parsea y ninguna de sus lineas '
          'pudo leerse. Devolver la lista sin esos hallazgos convertiria un '
          'archivo corrupto en un salto silencioso.');
    }

    return List.unmodifiable(salida);
  }
}
