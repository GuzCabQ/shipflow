/// Qué se le muestra a quien corre `ship` antes de preguntar, y qué estados
/// autorizan publicar.
///
/// **La previsualización es texto para una persona, no un protocolo.** Nadie
/// la parsea: la lee quien está por confirmar un `--yes`, y por eso muestra
/// evidencia —qué rama, contra qué base, qué archivos, qué quedó cubierto, qué
/// requiere criterio, qué cambios ajenos se van a dejar afuera— en vez de un
/// resumen que le pida creerle a la corrida. §8 lo dice así: «con la
/// evidencia: archivos, rama, base, superficies y cambios ajenos excluidos».
///
/// **Los cambios ajenos van al canal local y solo ahí.** Este archivo es el
/// canal: [previsualizacion] los recibe aparte de [artefacto] y los imprime
/// en una sección propia. Nunca los mezcla con lo que [artefacto] ya trae ni
/// los agrega a él — el artefacto sale tal cual llegó, porque la superficie
/// se deriva de la cascada, que no conoce esas rutas, y publicarle a un
/// revisor remoto rutas que no puede ver no es accionable y filtra nombres de
/// trabajo local.
library;

import 'package:core/core.dart';

import 'entrada.dart';

/// Arma el texto que se muestra antes de pedir confirmación.
///
/// [entrada] es la invocación ya interpretada —de ahí sale la intención y los
/// archivos declarados—; [rama] y [base] son las que el preflight ya resolvió
/// contra el repositorio, no las que pidió la bandera. [artefacto] es lo que
/// se compuso en memoria para este candidato, y [cambiosAjenos] son las rutas
/// que `apply` dejó intactas por no ser de la rebanada: llegan por su propio
/// parámetro, y no por el artefacto, precisamente para que no puedan colarse
/// en él.
String previsualizacion({
  required EntradaDeShip entrada,
  required String rama,
  required String base,
  required ArtefactoDeRevision artefacto,
  required List<String> cambiosAjenos,
}) {
  final superficie = artefacto.superficie;
  final b = StringBuffer()
    ..writeln('ship: ${entrada.intent}')
    ..writeln('rama: $rama → $base')
    ..writeln()
    ..writeln('archivos de la rebanada (${entrada.archivos.length}):');
  for (final archivo in entrada.archivos) {
    b.writeln('  - $archivo');
  }

  b
    ..writeln()
    ..writeln('estado de la corrida: ${superficie.estado.name}')
    ..writeln('cubierto (${superficie.cubierto.length}):');
  if (superficie.cubierto.isEmpty) {
    b.writeln('  (nada)');
  }
  for (final c in superficie.cubierto) {
    b.writeln(
      '  - ${c.sujeto} — ${c.controlId}: ${c.afirmacion.demuestra} '
      '(no demuestra: ${c.afirmacion.noDemuestra})',
    );
  }

  b.writeln(
    'requiere criterio humano (${superficie.requiereCriterio.length}):',
  );
  if (superficie.requiereCriterio.isEmpty) {
    b.writeln('  (nada)');
  }
  for (final e in superficie.requiereCriterio) {
    final sujeto = e.sujeto ?? '(sin sujeto)';
    b.writeln('  - $sujeto — ${e.motivo.name}: ${e.detalle}');
  }

  // Sección aparte y con su propia advertencia: es la línea que un revisor
  // remoto nunca ve, así que quien confirma acá es la única persona a la que
  // se le puede mostrar.
  b
    ..writeln()
    ..writeln(
      'cambios ajenos a la rebanada (${cambiosAjenos.length}) — quedan en '
      'el árbol de trabajo, NO se publican y NO están en el artefacto de '
      'revisión:',
    );
  if (cambiosAjenos.isEmpty) {
    b.writeln('  (ninguno)');
  }
  for (final ajeno in cambiosAjenos) {
    b.writeln('  - $ajeno');
  }

  b
    ..writeln()
    ..writeln(
      'candidato: ${artefacto.candidato.contentRevision} sobre '
      '${artefacto.candidato.baseRevision}',
    )
    ..writeln('alcance de lo afirmado: ${artefacto.alcanceDeLoAfirmado}');
  final plan = artefacto.plan;
  b.writeln(
    plan != null ? 'plan: $plan' : 'sin plan: ${artefacto.sinPlanPorque}',
  );

  return b.toString();
}

/// Si [estado] autoriza publicar. **`switch` exhaustivo, sin comodín**: un
/// [EstadoDeCorrida] nuevo no compila hasta que alguien decida acá si publica
/// o no — el mismo criterio con el que se escribieron las funciones de código
/// de salida de la rebanada anterior.
///
/// `--yes` no participa de esta decisión: autoriza a escribir, no a publicar
/// algo que no concluyó, y por eso ni siquiera es un parámetro de esta
/// función. La única bandera que sí importa acá es `--allow-incomplete`, y
/// solo importa para lo que **concluyó mal** —`rojo`, `noConcluyente`—, nunca
/// para el instrumento roto.
bool autoriza({
  required EstadoDeCorrida estado,
  required bool allowIncomplete,
}) => switch (estado) {
  EstadoDeCorrida.verde => true,
  EstadoDeCorrida.rojo || EstadoDeCorrida.noConcluyente => allowIncomplete,
  // `--allow-incomplete` autoriza publicar una verificación que concluyó
  // mal, no una que no concluyó porque el instrumento se rompió: acá no
  // hay nada que el arnés pueda afirmar sobre el cambio, con o sin la
  // bandera.
  EstadoDeCorrida.errorInterno => false,
};
