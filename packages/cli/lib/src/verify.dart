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
import 'uso.dart';

const nombreDelComando = 'verify';

/// Los pasos, en orden de costo creciente.
///
/// **El orden es política de quien compone**, no del plugin. Formatear es más
/// barato que analizar, así que va primero — pero los dos corren igual: no hay
/// corte temprano todavía, y su ausencia está declarada en `orchestration`.
///
/// **Hueco declarado:** `docs/03` §6 le asigna el orden a `orchestration`, y
/// hoy vive acá como una lista literal. Para derivarlo allá haría falta que
/// `Verifier` declare su costo, y ese campo no existe. Se cierra cuando el
/// costo importe, no antes.
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
///
/// **No interpreta banderas**: eso ya lo hizo la frontera, una sola vez. Acá
/// solo se resuelve el alcance y se rechaza lo que ningún subcomando puede
/// aceptar. Dos intérpretes para las mismas banderas fue lo que dejó la
/// frontera aceptando `--inventada`.
class OpcionesDeVerify {
  final List<String> sujetos;
  final bool json;
  final bool silencioso;
  final bool detallado;
  final bool ayuda;

  OpcionesDeVerify({
    required List<String> sujetos,
    this.json = false,
    this.silencioso = false,
    this.detallado = false,
    this.ayuda = false,
  }) : sujetos = List.unmodifiable(sujetos);
}

const ayudaDeVerify = r'''
shipflow verify [rutas...] — corre la cascada y reporta con testigo.

  --json        Protocolo de salida: eventos y resultado en JSON Lines por la
                salida estándar, incluidos los diagnósticos.
  --verbose     Incluye el testigo de cada paso: qué corrió, sobre qué, y qué
                omitió.
  --quiet, -q   Solo errores: lo que bloquea.
  --help, -h    Esto.

Sin rutas, el alcance es el directorio actual.''';

/// Resuelve el alcance a partir de lo que la frontera ya interpretó.
///
/// **`verify` no tiene banderas propias**, así que cualquier bandera que haya
/// sobrado no la puede aceptar nadie.
OpcionesDeVerify opcionesDe(Globales g) {
  final sobrante = g.restantes.where((a) => a.startsWith('-')).toList();
  if (sobrante.isNotEmpty) {
    throw UsoInvalido('bandera desconocida: «${sobrante.first}»',
        'Corré `shipflow verify --help` para ver las que hay.');
  }
  final sujetos = g.restantes.where((a) => !a.startsWith('-')).toList();

  // **Sin alcance explícito, el directorio actual.** No es un default cómodo:
  // es el único alcance que se puede nombrar sin adivinar, y de todos modos el
  // testigo va a decir qué cubrió de verdad.
  return OpcionesDeVerify(
    sujetos: sujetos.isEmpty ? const ['.'] : sujetos,
    json: g.json,
    silencioso: g.silencioso,
    detallado: g.detallado,
    ayuda: g.ayuda,
  );
}

/// Corre `verify` y devuelve el código de proceso.
///
/// **Recibe la impresora**, no la construye: la frontera es una sola y vive en
/// `comando.dart`. Las excepciones tampoco se atrapan acá — suben a esa
/// frontera, que es la que sabe convertirlas en un `70` con su resultado.
Future<int> correrVerify(
  Globales globales, {
  required String directorio,
  required Impresora impresora,
  Cascada Function(String directorio)? construirCascada,
}) async {
  final OpcionesDeVerify o;
  try {
    o = opcionesDe(globales);
  } on UsoInvalido catch (e) {
    impresora.resultado(
      ResultEnvelope(
        command: nombreDelComando,
        exitCode: Codigo.errorDeUso,
        verdict: null,
        nextAction: e.queHacer,
        data: {'error': e.reason},
      ),
      'shipflow verify: ${e.reason}\n  → ${e.queHacer}',
    );
    impresora.cerrar();
    return Codigo.errorDeUso;
  }

  if (o.ayuda) {
    // La ayuda gana sobre `--quiet`, igual que en la frontera: si alguien la
    // pidió, callarla es no hacer lo que se pidió. Y se CIERRA la misma que
    // emitió — cerrar la otra dejaba el resultado emitido en una y la cuenta
    // en cero en la otra, que es justamente lo que el guardia detecta.
    final sinSilencio = Impresora(
        salida: impresora.salida, error: impresora.error, json: o.json);
    sinSilencio.resultado(
      ResultEnvelope(
        command: nombreDelComando,
        exitCode: Codigo.exito,
        verdict: 'ok',
        data: const {'help': ayudaDeVerify},
      ),
      ayudaDeVerify,
    );
    sinSilencio.cerrar();
    return Codigo.exito;
  }

  final imp = impresora;

  final cascada =
      (construirCascada ?? (d) => cascadaPorDefecto(directorio: d))(directorio);

  // **Los eventos salen mientras la corrida ocurre**, no al final. Antes se
  // recorrían los resultados después de que todo había terminado: no había
  // nada que mirar mientras una herramienta tardaba, y la marca de tiempo era
  // la de armar el reporte y no la del paso.
  final r = await cascada.correr(
    o.sujetos,
    alEmpezar: (id) => imp.evento(
      EventEnvelope(
        command: nombreDelComando,
        type: 'progress',
        data: {'verifier': id, 'stage': 'started'},
      ),
      '  ...       $id',
    ),
    alTerminar: (desenlace) {
      // **Cada desenlace se dice como lo que es.** Antes solo se avisaba de
      // los pasos con resultado, así que un salto y un fallo interno dejaban
      // su `started` sin cerrar — y `--verbose`, que promete el testigo de
      // cada paso, no daba nada para los saltos.
      imp.evento(
        EventEnvelope(
          command: nombreDelComando,
          type: 'progress',
          data: switch (desenlace) {
            PasoEjecutado(:final resultado) => {
                'verifier': resultado.verifierId,
                'stage': 'finished',
                'verdict': resultado.verdict.name,
                'diagnostics': resultado.diagnostics.length,
                if (o.detallado) 'witness': resultado.witness?.toJson(),
              },
            PasoSinNadaQueHacer(:final declaracion) => {
                'verifier': desenlace.id,
                'stage': 'skipped',
                'reasons': declaracion.reasons,
                if (o.detallado) 'notApplicable': declaracion.toJson(),
              },
            PasoRoto(:final causa) => {
                'verifier': desenlace.id,
                'stage': 'internalError',
                'cause': causa,
              },
          },
        ),
        _desenlaceEnTexto(desenlace, detallado: o.detallado),
      );
      final diagnosticos = switch (desenlace) {
        PasoEjecutado(:final resultado) => resultado.diagnostics,
        _ => const <Diagnostic>[],
      };
      for (final d in diagnosticos
          .where((d) => seMuestra(d, silencioso: o.silencioso))) {
        imp.evento(
          EventEnvelope(
              command: nombreDelComando, type: 'diagnostic', data: d.toJson()),
          '  ${d.severity.name} ${d.file}${d.line == null ? '' : ':${d.line}'} '
          '· ${d.ruleId} · ${d.message.content}',
        );
      }
    },
  );

  final estado = r.estado;
  imp.resultado(
    ResultEnvelope(
      command: nombreDelComando,
      exitCode: Codigo.deCorrida(estado),
      verdict: veredictoDe(estado),
      nextAction: _queHacer(r),
      data: {
        'registered': r.registrados,
        'executed': r.ejecutados,
        'notExecuted': r.sinEjecutar,
        // **Los saltados van con su motivo, no como una cuenta.** Un consumidor
        // automático tiene que poder distinguir «no tuvo nada que hacer» de «no
        // pudo mirar» sin leer prosa, que es exactamente lo que este campo vino
        // a arreglar un nivel más abajo.
        'skipped': {
          for (final s in r.saltados) s.id: s.motivos,
        },
        'internalFailures': r.fallosInternos,
        'diagnostics': r.diagnosticos.length,
      },
    ),
    _resumenEnTexto(r),
  );
  imp.cerrar();

  return Codigo.deCorrida(estado);
}

/// Qué diagnósticos se muestran. **La decisión es de la severidad, no del tipo
/// de evento.**
///
/// `Severity.silencia` dice de sí misma «registra para telemetría y no se
/// muestra»: no se imprime nunca, ni siquiera sin banderas. Y `--quiet` dice
/// «solo errores», así que deja pasar lo que bloquea y nada más — mostraba lo
/// informativo, y también lo silenciado.
bool seMuestra(Diagnostic d, {required bool silencioso}) =>
    d.severity != Severity.silencia &&
    (!silencioso || d.severity == Severity.bloquea);

/// El desenlace de un paso, en texto. **Los tres se dicen distinto**: un salto
/// que se imprimiera como un veredicto sería exactamente la confusión que el
/// tipo vino a deshacer.
String _desenlaceEnTexto(DesenlaceDePaso d, {required bool detallado}) =>
    switch (d) {
      PasoEjecutado(:final resultado) =>
        _pasoEnTexto(resultado, detallado: detallado),
      PasoSinNadaQueHacer(:final declaracion) => [
          '  SALTADO   ${d.id}',
          if (detallado)
            for (final m in declaracion.reasons) '            motivo: $m',
        ].join('\n'),
      PasoRoto(:final causa) => '  ROTO      ${d.id}\n            $causa',
    };

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
      // Una cascada vacía NO es «algún paso no pudo observar»: no hay pasos ni
      // testigos que mirar. Mandaba a correr `--verbose` para leer testigos
      // que no existen — un error indicando una acción imposible.
      EstadoDeCorrida.noConcluyente => r.registrados.isEmpty
          ? 'No hay ningún verificador registrado, así que no se miró nada. '
              'Los pasos se registran en el composition root: `cli`.'
          : r.sinEjecutar.isNotEmpty
              ? 'Estos pasos están registrados y no se ejecutaron: '
                  '${r.sinEjecutar.join(", ")}. Un paso que no corre no es un '
                  'paso que no encontró nada.'
              : r.resultados.isEmpty
                  // **Todos los pasos se saltaron.** Cada uno por separado es
                  // legítimo; todos juntos es una corrida que no verificó
                  // nada. Decir «no pudo observar» acá era falso: observaron, y
                  // no había nada suyo.
                  ? 'Ningún paso tuvo nada que hacer sobre este alcance: '
                      '${r.saltados.map((s) => s.id).join(", ")}. No es un '
                      'fallo, pero tampoco se verificó nada. Revisá el alcance '
                      'que le diste a `verify`.'
                  : 'Algún paso no pudo observar su alcance. Mirá lo que omitió '
                      'cada testigo con `--verbose`; no hay verde sin alguien '
                      'que haya mirado.',
      EstadoDeCorrida.rojo =>
        'Hay diagnósticos bloqueantes. Arreglalos y volvé a correr `verify`.',
    };

String _resumenEnTexto(ResultadoDeCascada r) {
  final estado = r.estado;
  // **Los saltados se nombran en el resumen.** El meta-check del corpus los
  // cuenta aparte —«registrados: 7 · ejecutados: 6 · saltados: 1 con motivo»—
  // y esconderlos dejaría la resta sin explicar: quien lea «0 de 2» tiene que
  // poder saber si faltaron o si no tenían nada que hacer.
  final saltos =
      r.saltados.isEmpty ? '' : '${r.saltados.length} saltado(s) con motivo, ';
  final cabeza = 'verify: ${veredictoDe(estado)} — '
      '${r.ejecutados.length} de ${r.registrados.length} pasos ejecutados, '
      '$saltos${r.diagnosticos.length} diagnóstico(s).';
  final accion = _queHacer(r);
  return accion == null ? cabeza : '$cabeza\n  → $accion';
}
