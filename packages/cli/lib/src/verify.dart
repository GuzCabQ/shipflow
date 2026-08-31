/// El comando `verify`: corre la cascada sobre un alcance y reporta.
///
/// **Es el composition root de la cascada.** Acá y solo acá se sabe qué pasos
/// existen: `orchestration` los recibe como `Verifier` y no puede ver ningún
/// plugin. Cambiar de stack cambia esta lista y nada más.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_dart/plugin_dart.dart';

import 'salida.dart';

const nombreDelComando = 'verify';

/// Los pasos, en orden de costo creciente.
///
/// **El orden es política de quien compone**, no del plugin. Formatear es más
/// barato que analizar, así que va primero — pero los dos corren igual: no hay
/// corte temprano todavía, y su ausencia está declarada en `orchestration`.
Cascada cascadaPorDefecto({
  required String directorio,
  EjecutorDeProceso ejecutor = const EjecutorDelSistema(),
  Duration presupuesto = const Duration(minutes: 5),
}) =>
    Cascada([
      PasoDeFormato(
          ejecutor: ejecutor, directorio: directorio, presupuesto: presupuesto),
      PasoDeAnalisis(
          ejecutor: ejecutor, directorio: directorio, presupuesto: presupuesto),
    ]);

/// Lo que `verify` entendió de la línea de comandos.
class OpcionesDeVerify {
  final List<String> sujetos;
  final bool json;
  final bool silencioso;
  final bool detallado;

  OpcionesDeVerify({
    required List<String> sujetos,
    this.json = false,
    this.silencioso = false,
    this.detallado = false,
  }) : sujetos = List.unmodifiable(sujetos);
}

/// Se lanza cuando la invocación no se puede interpretar. Es el código `5`.
class UsoInvalido implements Exception {
  final String reason;
  final String queHacer;
  const UsoInvalido(this.reason, this.queHacer);
}

/// Interpreta los argumentos. **No adivina**: lo que no reconoce, lo rechaza.
OpcionesDeVerify interpretar(List<String> args) {
  final sujetos = <String>[];
  var json = false, silencioso = false, detallado = false;

  for (final a in args) {
    switch (a) {
      case '--json':
        json = true;
      case '--quiet' || '-q':
        silencioso = true;
      case '--verbose':
        detallado = true;
      default:
        if (a.startsWith('-')) {
          throw UsoInvalido('bandera desconocida: «$a»',
              'Corré `shipflow verify --help` para ver las que hay.');
        }
        sujetos.add(a);
    }
  }

  if (silencioso && detallado) {
    throw const UsoInvalido('`--quiet` y `--verbose` se contradicen',
        'Elegí una: `--quiet` para solo errores, `--verbose` para los testigos.');
  }

  // **Sin alcance explícito, el directorio actual.** No es un default cómodo:
  // es el único alcance que se puede nombrar sin adivinar, y de todos modos el
  // testigo va a decir qué cubrió de verdad.
  return OpcionesDeVerify(
    sujetos: sujetos.isEmpty ? const ['.'] : sujetos,
    json: json,
    silencioso: silencioso,
    detallado: detallado,
  );
}

/// Corre `verify` y devuelve el código de proceso.
Future<int> correrVerify(
  List<String> args, {
  required String directorio,
  required StringSink destino,
  Cascada Function(String directorio)? construirCascada,
}) async {
  final OpcionesDeVerify o;
  try {
    o = interpretar(args);
  } on UsoInvalido catch (e) {
    destino.writeln('shipflow verify: ${e.reason}\n  → ${e.queHacer}');
    return Codigo.errorDeUso;
  }

  final impresora = Impresora(destino,
      json: o.json, silencioso: o.silencioso, detallado: o.detallado);

  final cascada =
      (construirCascada ?? (d) => cascadaPorDefecto(directorio: d))(directorio);

  final r = await cascada.correr(o.sujetos);

  for (final paso in r.resultados) {
    impresora.evento(
      EventEnvelope(
        command: nombreDelComando,
        type: 'progress',
        data: {
          'verifier': paso.verifierId,
          'verdict': paso.verdict.name,
          'diagnostics': paso.diagnostics.length,
          if (o.detallado) 'witness': paso.witness?.toJson(),
        },
      ),
      _pasoEnTexto(paso, detallado: o.detallado),
    );
    for (final d in paso.diagnostics) {
      impresora.evento(
        EventEnvelope(
            command: nombreDelComando, type: 'diagnostic', data: d.toJson()),
        '  ${d.severity.name} ${d.file}${d.line == null ? '' : ':${d.line}'} '
        '· ${d.ruleId} · ${d.message.content}',
      );
    }
  }

  final estado = r.estado;
  impresora.resultado(
    ResultEnvelope(
      command: nombreDelComando,
      exitCode: Codigo.deCorrida(estado),
      verdict: veredictoDe(estado),
      nextAction: _queHacer(r),
      data: {
        'registered': r.registrados,
        'executed': r.ejecutados,
        'notExecuted': r.sinEjecutar,
        'internalFailures': r.fallosInternos,
        'diagnostics': r.diagnosticos.length,
      },
    ),
    _resumenEnTexto(r),
  );

  return Codigo.deCorrida(estado);
}

String _pasoEnTexto(VerificationOutcome paso, {required bool detallado}) {
  final marca = switch (paso.verdict) {
    Verdict.verde => 'ok        ',
    Verdict.rojo => 'FALLA     ',
    Verdict.noConcluyente => 'NO CONCL. ',
  };
  final linea = '  $marca${paso.verifierId}';
  final w = paso.witness;
  if (!detallado || w == null) return linea;
  return [
    linea,
    '            invocación: ${w.invocation.isEmpty ? "(ninguna)" : w.invocation}',
    '            terminación: ${w.termination.name} · código ${w.exitCode}',
    '            cubrió: ${w.subjects.isEmpty ? "(nada)" : w.subjects.join(", ")}',
    for (final m in w.omitted) '            omitió: $m',
  ].join('\n');
}

/// **Toda salida que no sea verde dice qué hacer.** Es lo mismo que INV-8 le
/// exige a una regla que bloquea: detener sin poder decir qué hacer deja a
/// quien lo choca sin salida.
String? _queHacer(ResultadoDeCascada r) => switch (r.estado) {
      EstadoDeCorrida.verde => null,
      EstadoDeCorrida.errorInterno =>
        'Se rompió un paso del arnés, no la verificación del cambio. '
            'Revisá: ${r.fallosInternos.keys.join(", ")}.',
      EstadoDeCorrida.noConcluyente => r.sinEjecutar.isNotEmpty
          ? 'Estos pasos están registrados y no se ejecutaron: '
              '${r.sinEjecutar.join(", ")}. Un paso que no corre no es un paso '
              'que no encontró nada.'
          : 'Algún paso no pudo observar su alcance. Mirá lo que omitió cada '
              'testigo con `--verbose`; no hay verde sin alguien que haya mirado.',
      EstadoDeCorrida.rojo =>
        'Hay diagnósticos bloqueantes. Arreglalos y volvé a correr `verify`.',
    };

String _resumenEnTexto(ResultadoDeCascada r) {
  final estado = r.estado;
  final cabeza = 'verify: ${veredictoDe(estado)} — '
      '${r.ejecutados.length} de ${r.registrados.length} pasos ejecutados, '
      '${r.diagnosticos.length} diagnóstico(s).';
  final accion = _queHacer(r);
  return accion == null ? cabeza : '$cabeza\n  → $accion';
}
