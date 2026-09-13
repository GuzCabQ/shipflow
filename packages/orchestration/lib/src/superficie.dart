/// De dónde sale la superficie de verificación.
///
/// **Vive acá y no en `core` por una sola razón:** recibe `ResultadoDeCascada`,
/// que es de este paquete, y `core` no puede verlo. Los otros tres tipos de
/// entrada sí son de `core` y viajan sin problema.
library;

import 'package:core/core.dart';

import 'cascada.dart';

/// Deriva la superficie de los **tres** hechos de una corrida.
///
/// La primera versión del diseño derivaba solo de [cascada], y la rebanada del
/// entorno de verificación la falsificó: el desenlace del entorno y las
/// alteraciones del candidato son hechos que la cascada no conoce, y los dos
/// vuelven la corrida no concluyente.
///
/// **El orden importa.** Entorno, integridad, cascada: los dos primeros pueden
/// vaciar `cubierto` entero, así que decidirlos después sería armar una lista
/// para tirarla.
///
/// [cascada] es nulo cuando **no llegó a correr**, que es lo que pasa cuando el
/// entorno no se derivó. [controles] mapea id de paso al control, porque el
/// resultado guarda desenlaces por id y la fábrica necesita el objeto para
/// leerle su afirmación.
SuperficieDeVerificacion derivarSuperficie({
  required ResultadoDeEntorno entorno,
  required List<AlteracionDelCandidato> alteraciones,
  required ResultadoDeCascada? cascada,
  required Map<String, Verifier> controles,
}) {
  final criterio = <EntradaDeCriterio>[];

  // 1 · El entorno. Si no se derivó, no hay nada más que mirar: la cascada no
  //     corrió, y lo que haya en disco no se verificó contra nada.
  if (entorno is! EntornoDerivado) {
    final evidencia = switch (entorno) {
      CandidatoRechazado(:final causa, :final evidencia) =>
        '${causa.name}: ${evidencia.content}',
      DerivacionAbortada(:final causa, :final evidencia) =>
        '${causa.name}: ${evidencia.content}',
      EntornoDerivado() => '',
    };
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.entornoNoDerivado,
          detalle:
              'El entorno de verificación no se pudo derivar, así que ningún '
              'control llegó a correr. $evidencia',
        ),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  // 2 · La integridad. Una alteración no dice cuál de los dos árboles vio cada
  //     control, así que ninguno se puede dar por cubierto.
  if (alteraciones.isNotEmpty) {
    for (final a in alteraciones) {
      criterio.add(
        EntradaDeCriterio(
          sujeto: a.ruta,
          motivo: MotivoDeCriterio.candidatoAlterado,
          detalle:
              'El candidato dejó de coincidir con el árbol que dice '
              'representar: ${a.ruta} está ${a.tipo.name}.',
        ),
      );
    }
    if (cascada != null) {
      for (final registro in cascada.registrados) {
        for (final sujeto in registro.expectedScope) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: sujeto,
              motivo: MotivoDeCriterio.candidatoAlterado,
              detalle:
                  'No se sabe cuál árbol miró este control, así que lo que '
                  'haya afirmado no se puede sostener.',
            ),
          );
        }
      }
    }
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: criterio,
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  // 3 · La cascada. Sin entorno no llega acá; con entorno y sin cascada, la
  //     corrida no verificó nada y eso es un hecho, no un vacío.
  if (cascada == null) {
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.nadieDioCuenta,
          detalle:
              'El entorno se derivó y ningún control corrió, así que nadie '
              'dio cuenta de nada.',
        ),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  final cubierto = <AfirmacionCubierta>[];
  for (final registro in cascada.registrados) {
    final desenlace = cascada.desenlaces[registro.id]!;
    final control = controles[registro.id];
    switch (desenlace) {
      case Executed(:final witness, :final verdict):
        if (verdict == Verdict.rojo) {
          for (final sujeto in witness.subjects) {
            criterio.add(
              EntradaDeCriterio(
                controlId: registro.id,
                sujeto: sujeto,
                motivo: MotivoDeCriterio.hallazgo,
                detalle:
                    'El control encontró algo. El veredicto es global al '
                    'paso y los diagnósticos no se atribuyen a un sujeto, '
                    'así que ninguno de los suyos queda cubierto.',
              ),
            );
          }
        } else if (verdict == Verdict.verde && control != null) {
          for (final sujeto in witness.subjects) {
            final a = AfirmacionCubierta.desde(
              control: control,
              desenlace: desenlace,
              sujeto: sujeto,
            );
            if (a != null) cubierto.add(a);
          }
        }
        for (final o in witness.omitted) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: o.subject,
              motivo: o.subject == null
                  ? MotivoDeCriterio.residuoGeneral
                  : MotivoDeCriterio.declaradoNoMirado,
              detalle: o.reason,
            ),
          );
        }
      case Aborted(:final attempt):
        criterio.add(
          EntradaDeCriterio(
            controlId: registro.id,
            motivo: MotivoDeCriterio.intentoIncompleto,
            detalle: attempt.note,
          ),
        );
      case Skipped(:final notOfStack):
        for (final s in notOfStack) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: s.subject,
              motivo: MotivoDeCriterio.ajenoAlStack,
              detalle: s.reason ?? 'no es de este stack',
            ),
          );
        }
      case Unobservable(:final causes):
        for (final c in causes) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: c.subject,
              motivo: MotivoDeCriterio.noSePudoMirar,
              detalle: c.cause,
            ),
          );
        }
      case Broken(:final component, :final error, :final context):
        criterio.add(
          EntradaDeCriterio(
            controlId: registro.id,
            motivo: MotivoDeCriterio.instrumentoFallo,
            detalle: '$component: $error ($context)',
          ),
        );
    }
  }

  for (final o in cascada.obligacionesSinSaldar) {
    criterio.add(
      EntradaDeCriterio(
        controlId: o.paso,
        sujeto: o.sujeto,
        motivo: MotivoDeCriterio.nadieDioCuenta,
        detalle:
            'El alcance esperado de este control incluía este sujeto y su '
            'testigo no lo cubrió ni lo nombró como omisión.',
      ),
    );
  }

  return SuperficieDeVerificacion(
    cubierto: cubierto,
    requiereCriterio: criterio,
    estado: cascada.estado,
  );
}
