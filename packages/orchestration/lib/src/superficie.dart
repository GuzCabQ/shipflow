/// De dónde sale la superficie de verificación.
///
/// **Vive acá y no en `core` por una sola razón:** recibe `ResultadoDeCascada`,
/// que es de este paquete, y `core` no puede verlo. Los otros tres tipos de
/// entrada sí son de `core` y viajan sin problema.
library;

import 'package:core/core.dart';

import 'cascada.dart';

/// Las entradas que nombran cada alteración del candidato.
///
/// **Vive aparte porque se emite en los dos caminos que las pueden ver**: con
/// el entorno derivado, y con el entorno NO derivado — donde la derivación
/// devuelve temprano y antes las descartaba sin nombrarlas. Vaciar `cubierto` y
/// no nombrar el hecho son cosas distintas: ese camino ya vaciaba `cubierto`
/// por su cuenta, y por eso el descarte no se veía. Una alteración del
/// candidato es el hecho más alarmante que una corrida puede producir; que se
/// pierda porque otro hecho salió primero es exactamente la desaparición en
/// silencio que este archivo existe para cerrar.
List<EntradaDeCriterio> _entradasDeAlteracion(
  List<AlteracionDelCandidato> alteraciones,
) => [
  for (final a in alteraciones)
    EntradaDeCriterio(
      sujeto: a.ruta,
      motivo: MotivoDeCriterio.candidatoAlterado,
      detalle:
          'El candidato dejó de coincidir con el árbol que dice '
          'representar: ${a.ruta} está ${a.tipo.name}.',
    ),
];

/// Deriva la superficie de los **tres** hechos de una corrida.
///
/// La primera versión del diseño derivaba solo de [cascada], y la rebanada del
/// entorno de verificación la falsificó: el desenlace del entorno y las
/// alteraciones del candidato son hechos que la cascada no conoce, y los dos
/// vuelven la corrida no concluyente.
///
/// **El orden importa, y decide qué se VACÍA, no qué se NOMBRA.** Entorno,
/// integridad, cascada: los dos primeros pueden vaciar `cubierto` entero, así
/// que decidirlos después sería armar una lista para tirarla. Pero **invalidar
/// la cobertura nunca justifica perder una señal**: vaciar `cubierto` y no
/// nombrar el hecho son cosas distintas, y esta función no descarta ningún
/// hecho que haya podido ver por el solo motivo de que otro salió primero.
///
/// Es una regla de la derivación entera y no de un camino. Nació en el del
/// entorno no derivado —que devolvía temprano y perdía las alteraciones— y
/// gobierna por igual al del candidato alterado, que ya no devuelve temprano:
/// vacía la cobertura y sigue procesando los desenlaces y la partición del
/// alcance, porque un fallo del instrumento, un sujeto ajeno o uno no
/// observable son hechos independientes de la alteración. Un revisor que no
/// los ve no sabe que están.
///
/// [cascada] es nulo cuando **no llegó a correr**, que es lo que pasa cuando el
/// entorno no se derivó. [controles] mapea id de paso al control, porque el
/// resultado guarda desenlaces por id y la fábrica necesita el objeto para
/// leerle su afirmación. **Todo id registrado tiene que estar en este mapa**:
/// quien compone la corrida es quien lo arma, y un id que falte es un error
/// suyo, no un hecho de la corrida — se lanza en vez de desaparecer en
/// silencio.
///
/// [alteraciones] **vacía significa que la integridad se comprobó y el
/// candidato está intacto**, no que no se comprobó. Esta función no puede
/// distinguir los dos casos porque la firma no lleva ese tercer estado
/// todavía: el compositor que produciría «no comprobado» no existe.
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
        // El entorno caído no borra la integridad: si el control de integridad
        // alcanzó a correr y vio una alteración, ese hecho se nombra acá
        // también. No hay `cubierto` que vaciar en este camino — ya está
        // vacío—, y por eso el descarte pasaba inadvertido.
        ..._entradasDeAlteracion(alteraciones),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  // 2 · La integridad. Una alteración no dice cuál de los dos árboles vio cada
  //     control, así que ninguno se puede dar por cubierto.
  //
  // **Ya no devuelve temprano, y ese era el descarte.** Salir acá dejaba la
  // superficie con un solo motivo —`candidatoAlterado`— para una corrida donde
  // además se había roto el instrumento, había un sujeto ajeno al stack y otro
  // que no se pudo mirar: tres hechos que la alteración no explica y que
  // desaparecían por haber salido segundos. Lo que la alteración decide es que
  // NADA queda cubierto y que el estado es no concluyente; el resto de la
  // corrida se sigue leyendo igual.
  final candidatoAlterado = alteraciones.isNotEmpty;
  criterio.addAll(_entradasDeAlteracion(alteraciones));

  // 3 · La cascada. Sin entorno no llega acá; con entorno y sin cascada, la
  //     corrida no verificó nada y eso es un hecho, no un vacío.
  if (cascada == null) {
    criterio.add(
      EntradaDeCriterio(
        motivo: MotivoDeCriterio.nadieDioCuenta,
        detalle:
            'El entorno se derivó y ningún control corrió, así que nadie '
            'dio cuenta de nada.',
      ),
    );
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: criterio,
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  // **Una cascada que existe con el registro vacío no es una cascada nula.**
  // `Cascada([]).correr(...)` observa el alcance, no registra ningún paso y
  // devuelve la causa `sinVerificadores` con estado no concluyente. La
  // derivación contemplaba el nulo y no este caso: los dos `for` de abajo no
  // tienen sobre qué iterar, el libro de obligaciones está vacío porque no hay
  // paso que las contraiga, y la superficie salía con `requiereCriterio` vacío
  // — el estado no concluyente sin su explicación, que es justo lo que esta
  // mitad existe para dar.
  //
  // No devuelve temprano: las observaciones de ESE alcance —sujetos ajenos, no
  // observables— son hechos de la corrida y se nombran más abajo aunque no
  // haya ningún control que las haya producido.
  if (cascada.registrados.isEmpty) {
    final pedido = cascada.alcance.requested;
    criterio.add(
      EntradaDeCriterio(
        motivo: MotivoDeCriterio.nadieDioCuenta,
        detalle:
            'La cascada corrió sin ningún control registrado: nadie verificó '
            'el alcance de esta corrida (${pedido.join(", ")}). No hay '
            'obligación que quedara sin saldar porque no hay control que la '
            'contrajera, y eso no es lo mismo que no haber nada que mirar.',
      ),
    );
  }

  final cubierto = <AfirmacionCubierta>[];
  // Qué sujetos ya quedaron nombrados por un desenlace POR PASO, para no
  // duplicarlos cuando el bloque de más abajo los vuelva a nombrar leyendo
  // `cascada.alcance` directamente. Solo se llena en el caso degenerado que
  // `Skipped`/`Unobservable` pueden representar —ver el comentario de ese
  // bloque—, pero un `ResultadoDeCascada` armado a mano (no por
  // `Cascada.correr`) sí puede combinar un paso `Skipped`/`Unobservable` con
  // otro `Executed` sobre el mismo alcance, y ahí sí hace falta la cuenta.
  final ajenosPorPaso = <String>{};
  final noObservablesPorPaso = <String>{};
  for (final registro in cascada.registrados) {
    final desenlace = cascada.desenlaces[registro.id]!;
    final control = controles[registro.id];
    // **Un paso registrado sin control en el mapa es un error de quien
    // compone, y este repositorio falla cerrado ante eso.** Antes, un id
    // ausente hacía que la rama verde no agregara nada — ni a `cubierto` ni a
    // `requiereCriterio` — y la superficie publicaba «verde, nada cubierto,
    // nada que mirar» para una corrida donde ese control sí había afirmado
    // algo. Desaparecer en silencio es exactamente lo que ADR-011 prohíbe en
    // el otro sentido (que un verificador se exima solo); acá es la
    // composición la que se eximiría sola.
    if (control == null) {
      throw ArgumentError.value(
        registro.id,
        'controles',
        'El paso «${registro.id}» está registrado y no tiene control en '
            '`controles`. Quien compone la corrida tiene que declarar el '
            'control de cada paso registrado: sin él, la superficie no '
            'puede atribuirle lo que afirmó.',
      );
    }
    // Un mapa mal armado —un control bajo la clave de otro— atribuiría la
    // afirmación de un control a otro distinto. `AfirmacionCubierta.desde`
    // lee `control.id`, no la clave del mapa, así que esto no lo cachearía
    // ningún otro lado.
    if (control.id != registro.id) {
      throw ArgumentError.value(
        control.id,
        'controles',
        'El control mapeado al paso «${registro.id}» declara el id '
            '«${control.id}»: un mapa mal armado atribuiría la afirmación a '
            'otro control.',
      );
    }
    // Con el candidato alterado, lo que este control haya afirmado no se
    // sostiene sobre ninguno de los sujetos que tenía a cargo, y eso se dice
    // sujeto por sujeto. Convive con lo que el desenlace nombre más abajo: las
    // dos cosas son ciertas a la vez y las dos piden que un humano mire.
    if (candidatoAlterado) {
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
    switch (desenlace) {
      // **La bifurcación es «con diagnósticos / sin diagnósticos», no
      // «rojo / verde».** `Executed.verdict` solo mira `Severity.bloquea`, así
      // que un paso con un diagnóstico informativo salía por la rama verde y
      // sus sujetos quedaban cubiertos: la superficie publicaba «verde,
      // cubierto 1, criterio 0» para una corrida donde el arnés SÍ había
      // encontrado algo, y le decía al revisor que podía saltear ese sujeto.
      // Es alcanzable desde una corrida real — un informativo del analizador
      // se normaliza a `Severity.reporta`.
      //
      // La regla del rojo se extiende en vez de agregarse una tercera rama, y
      // con el mismo argumento que ya la sostenía: el veredicto es global al
      // paso y los diagnósticos no tienen relación validada con los sujetos
      // del testigo, así que con un informativo tampoco se sabe cuál lo
      // originó. Dejar un sujeto cubierto Y en criterio sería contradictorio
      // para quien decide si saltear.
      //
      // **Y el hallazgo se emite aunque el testigo no cubra ningún sujeto.**
      // Los dos `for` recorren `witness.subjects`, así que con la cobertura
      // vacía los dos no hacían nada y el hallazgo entero se perdía: es lo que
      // pasa de verdad cuando el formateador corre sobre un archivo que no
      // parsea —sale con diagnósticos y sin sujetos formateados—, y la
      // superficie publicaba el residuo y la obligación sin saldar sin decir
      // en ningún lado que el control había encontrado errores. Que la corrida
      // quede no concluyente es correcto; perder los errores detectados, no.
      // Por eso la entrada va **sin sujeto**: nombra el hecho y su control, y
      // dice que no se pudo atribuir a ninguno. No concede cobertura.
      case Executed(:final witness, :final diagnostics):
        if (diagnostics.isNotEmpty) {
          if (witness.subjects.isEmpty) {
            criterio.add(
              EntradaDeCriterio(
                controlId: registro.id,
                motivo: MotivoDeCriterio.hallazgo,
                detalle:
                    'El control encontró ${diagnostics.length} '
                    'diagnóstico(s) y su testigo no cubre ningún sujeto, así '
                    'que no se pueden atribuir a ninguno. El hecho es del '
                    'control, no de un sujeto.',
              ),
            );
          }
          for (final sujeto in witness.subjects) {
            criterio.add(
              EntradaDeCriterio(
                controlId: registro.id,
                sujeto: sujeto,
                motivo: MotivoDeCriterio.hallazgo,
                detalle:
                    'El control encontró algo —bloqueante o no—. El veredicto '
                    'es global al paso y los diagnósticos no se atribuyen a '
                    'un sujeto, así que ninguno de los suyos queda cubierto.',
              ),
            );
          }
        } else if (!candidatoAlterado) {
          // Con el candidato alterado no se llama a la fábrica: no hay sujeto
          // que pueda quedar cubierto, y ya se nombró por qué.
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
          ajenosPorPaso.add(s.subject);
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
          noObservablesPorPaso.add(c.subject);
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

  // La partición del alcance es un hecho de LA CORRIDA, no de cada paso, y
  // hasta acá solo se la veía de refilón, a través de los desenlaces
  // `Skipped`/`Unobservable`. Esos dos SOLO salen de `Cascada.correr` en el
  // caso degenerado donde no hay NINGÚN sujeto utilizable: en cuanto hay uno
  // solo, todos los pasos ejecutan —hoy comparten el mismo alcance
  // esperado— y ningún desenlace nombra a los sujetos ajenos o no
  // observables que quedaron afuera. Sin esto, un sujeto no observable
  // mezclado con uno verde vaciaba `requiereCriterio` entero y hacía
  // reventar el invariante de [SuperficieDeVerificacion] —no verde, cubierto
  // no vacío, criterio vacío—; y un sujeto ajeno al stack mezclado con uno
  // verde quedaba invisible: ni cubierto ni en criterio, que un revisor lee
  // como «nada que mirar» sobre algo que sí pidió.
  //
  // No llevan `controlId`: no son de ningún control, son de la corrida. Y no
  // duplican lo que un desenlace por paso ya nombró —alcanzable solo
  // armando el resultado a mano, no desde `Cascada.correr`— gracias a las
  // dos cuentas de arriba.
  for (final o in cascada.alcance.observed) {
    if (!o.ofStack && !ajenosPorPaso.contains(o.subject)) {
      criterio.add(
        EntradaDeCriterio(
          sujeto: o.subject,
          motivo: MotivoDeCriterio.ajenoAlStack,
          detalle: o.reason ?? 'no es de este stack',
        ),
      );
    }
  }
  for (final u in cascada.alcance.unobserved) {
    if (!noObservablesPorPaso.contains(u.subject)) {
      criterio.add(
        EntradaDeCriterio(
          sujeto: u.subject,
          motivo: MotivoDeCriterio.noSePudoMirar,
          detalle: u.cause,
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

  // El estado no es un reenvío del de la cascada cuando el candidato se
  // alteró: la cascada no sabe que el árbol cambió, así que su verde —o su
  // rojo— es sobre otra cosa. `cubierto` ya quedó vacío por la misma razón.
  return SuperficieDeVerificacion(
    cubierto: cubierto,
    requiereCriterio: criterio,
    estado: candidatoAlterado ? EstadoDeCorrida.noConcluyente : cascada.estado,
  );
}
