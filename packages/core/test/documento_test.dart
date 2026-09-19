import 'package:core/core.dart';
import 'package:test/test.dart';

PullRequestDraft draftDePrueba() => PullRequestDraft(
  runId: 'corrida-1',
  branch: 'rama',
  base: 'develop',
  artefacto: ArtefactoDeRevision(
    superficie: SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: const [],
      estado: EstadoDeCorrida.verde,
    ),
    candidato: CandidateIdentity(
      contentRevision: 'arbol-1',
      baseRevision: 'base-1',
    ),
    intent: 'sostener el arnés',
    plan: null,
    sinPlanPorque: 'no hay elementos de trabajo',
    alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
  ),
  rutas: const ['a.txt'],
);

/// La identidad opaca del destino de las corridas de prueba. **Opaca de
/// verdad**: `core` no sabe leerla, así que cualquier cadena estable sirve —
/// lo único que se hace con ella es compararla.
const destinoDePrueba = 'forja.ejemplo/duenio/repo';

/// Un documento que ya llegó a [estado], por el único camino que el grafo de
/// §9 declara para llegar ahí. Sin desenlace: los estados no terminales lo
/// llevan nulo sin problema —es «todavía no hay», nunca incoherencia— y para
/// los que sí afirman uno hay otro grupo de pruebas, más abajo, dedicado
/// exactamente a esa correspondencia.
DocumentoDeCorrida documentoDePrueba(EstadoDelDocumento estado) {
  final preparado = DocumentoDeCorrida.preparado(
    revision: 'a' * 40,
    draft: draftDePrueba(),
    destino: destinoDePrueba,
  );
  return switch (estado) {
    EstadoDelDocumento.prepared => preparado,
    EstadoDelDocumento.committed ||
    EstadoDelDocumento.notApplied ||
    EstadoDelDocumento.localInconsistent => preparado.avanzarA(estado),
    EstadoDelDocumento.publicationComplete ||
    EstadoDelDocumento.publicationIncomplete =>
      preparado.avanzarA(EstadoDelDocumento.committed).avanzarA(estado),
  };
}

void main() {
  DocumentoDeCorrida preparado() => DocumentoDeCorrida.preparado(
    revision: 'a' * 40,
    draft: draftDePrueba(),
    destino: destinoDePrueba,
  );

  test('prepared LLEVA la revisión, porque commit-tree ya corrió', () {
    // La versión anterior del diseño lo persistía antes de `commit-tree`, y
    // dejaba una ventana: existía un objeto commit cuyo OID no quedaba en
    // ningún lado, así que la recuperación hablaba de «la revisión candidata»
    // sin tener identidad que consultar.
    expect(preparado().revision, isNotEmpty);
    expect(preparado().estado, EstadoDelDocumento.prepared);
  });

  test('las transiciones del grafo de §9 se aceptan', () {
    final desde = preparado();
    for (final destino in [
      EstadoDelDocumento.committed,
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.localInconsistent,
    ]) {
      expect(
        () => desde.avanzarA(destino),
        returnsNormally,
        reason: destino.name,
      );
    }
    final comiteado = desde.avanzarA(EstadoDelDocumento.committed);
    for (final destino in [
      EstadoDelDocumento.publicationComplete,
      EstadoDelDocumento.publicationIncomplete,
    ]) {
      expect(
        () => comiteado.avanzarA(destino),
        returnsNormally,
        reason: destino.name,
      );
    }
  });

  test(
    'publicationIncomplete avanza a publicationComplete: --retry-publication '
    'reintenta desde ahí',
    () {
      // El diagrama de §9 no dibuja esta arista, pero el texto de la spec
      // dice que `--retry-publication` «solo publica desde `committed` o
      // `publicationIncomplete`»: sin este camino, una publicación que quedó
      // a medias y que el reintento sí completa no tendría adónde avanzar. El
      // diagrama está incompleto, no el mapa de transiciones.
      final incompleta = preparado()
          .avanzarA(EstadoDelDocumento.committed)
          .avanzarA(EstadoDelDocumento.publicationIncomplete);
      final completa = incompleta.avanzarA(
        EstadoDelDocumento.publicationComplete,
      );
      expect(completa.estado, EstadoDelDocumento.publicationComplete);
    },
  );

  test('una transición que el grafo no tiene LANZA', () {
    expect(
      () => preparado().avanzarA(EstadoDelDocumento.publicationComplete),
      throwsStateError,
      reason: 'publicar sin commitear no es un camino',
    );
  });

  test('ya NO son tres los estados terminales sin salida: localInconsistent '
      'dejó de serlo, porque el reintento lo promueve a committed', () {
    // Esta prueba decía «los TRES terminales lo son» y cubría
    // `localInconsistent` entre ellos. Quedó falsa cuando esta tarea abrió
    // `localInconsistent → committed`: §9 exige que el reintento, al
    // comprobar que el índice ya coincide con la revisión, promueva ese
    // estado en vez de dejarlo varado. Corregirla en vez de borrarla es lo
    // que deja registrado CUÁL estado cambió de categoría y POR QUÉ, para
    // quien la lea después sin haber visto esta ronda.
    //
    // Sigue cubriendo solo `notApplied` con una aserción de verdad: el mapa
    // declara los dos con conjunto vacío, pero lo que demuestra que
    // `publicationComplete` también es terminal es esta prueba, no la
    // lectura del mapa. Cambiarle a `publicationComplete` el conjunto vacío
    // por `{committed}` dejaría la suite entera en verde si esta prueba no
    // existiera, y `publicationComplete` terminal es lo único que impide
    // que `--retry-publication` vuelva a publicar una corrida ya publicada.
    final terminales = <EstadoDelDocumento, DocumentoDeCorrida>{
      EstadoDelDocumento.notApplied: preparado().avanzarA(
        EstadoDelDocumento.notApplied,
      ),
      EstadoDelDocumento.publicationComplete: preparado()
          .avanzarA(EstadoDelDocumento.committed)
          .avanzarA(EstadoDelDocumento.publicationComplete),
    };
    for (final terminal in terminales.entries) {
      for (final destino in EstadoDelDocumento.values) {
        expect(
          () => terminal.value.avanzarA(destino),
          throwsStateError,
          reason: 'de ${terminal.key.name} se llegó a ${destino.name}',
        );
      }
    }
  });

  test('desde el estado inconsistente se puede promover a commiteado', () {
    // CON su desenlace puesto, no el documento sin desenlace de
    // [documentoDePrueba]: ese solo prueba la forma del grafo, y esta arista
    // tiene un defecto que un desenlace nulo no puede delatar —medido—.
    // `avanzarA` arrastraba el desenlace anterior sin mirar el destino, así
    // que promover a `committed` con `LocalInconsistente` todavía puesto
    // construía un documento que afirmaba los dos estados a la vez, y el
    // constructor lo rechazaba SIEMPRE: la arista estaba en el mapa y no se
    // podía tomar sobre ningún documento real, el único que
    // `--retry-publication` encuentra en el disco.
    final d = preparado().avanzarA(
      EstadoDelDocumento.localInconsistent,
      desenlace: ShipOutcome.localInconsistenteParaLaPrueba(revision: 'a' * 40),
    );
    final promovido = d.avanzarA(EstadoDelDocumento.committed);
    expect(promovido.estado, EstadoDelDocumento.committed);
    expect(
      promovido.desenlace,
      isNull,
      reason:
          '`committed` no admite desenlace: el que traía se descarta, '
          'no se arrastra',
    );
  });

  test('y NADA MÁS: sigue sin ir a ningún otro lado', () {
    final d = documentoDePrueba(EstadoDelDocumento.localInconsistent);
    for (final destino in [
      EstadoDelDocumento.prepared,
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.localInconsistent,
      EstadoDelDocumento.publicationComplete,
      EstadoDelDocumento.publicationIncomplete,
    ]) {
      expect(() => d.avanzarA(destino), throwsStateError, reason: destino.name);
    }
  });

  test('los terminales ahora son DOS, y eso queda fijado', () {
    final terminales = EstadoDelDocumento.values
        .where((e) => DocumentoDeCorrida.destinosDe(e).isEmpty)
        .toSet();
    expect(terminales, {
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.publicationComplete,
    });
  });

  test('los dos despachos exhaustivos sobre la misma relación se CRUZAN', () {
    // **Son imagen inversa uno del otro y nada los obligaba a coincidir.**
    // `estadoQueAfirma` dice qué estado afirma cada desenlace;
    // `admiteDesenlace` dice qué destino puede llevar uno. Los dos son
    // `switch` exhaustivos sin comodín, así que el compilador fuerza que
    // alguien DECIDA en cada uno — pero no que las dos decisiones digan lo
    // mismo. Si un desenlace nuevo afirmara un estado que hoy no admite
    // ninguno, todo sigue compilando y `avanzarA` descarta ese desenlace en
    // silencio: el documento llegaría a un estado terminal sin el desenlace
    // que lo afirma, que es exactamente la ausencia que esta clase existe
    // para no tener.
    //
    // **La lista de desenlaces es a mano, y no se puede derivar.**
    // `ShipOutcome` es sellada y no expone sus variantes, así que recorrer su
    // imagen pide construir una de cada una. Lo que impide que esta lista
    // envejezca en silencio es que una variante nueva no compila hasta que
    // alguien la agregue al `switch` de `estadoQueAfirma`, y su doc manda
    // acá. Se dice en vez de prometer que está completa por sí sola.
    final desenlaces = <ShipOutcome>[
      ShipOutcome.noIntentadoParaLaPrueba(
        causa: CausaDeNoIntento.previewOnly,
        verificacion: EstadoDeCorrida.verde,
      ),
      ShipOutcome.noAplicadoParaLaPrueba(
        causa: CausaDeNoAplicacion.baseMovida,
        headObservado: 'b' * 40,
      ),
      ShipOutcome.localInconsistenteParaLaPrueba(revision: 'a' * 40),
      ShipOutcome.publicadoParaLaPrueba(
        pr: PullRequestOpen(url: 'https://forja.invalida/pr/1'),
        verificacion: EstadoPublicable.verde,
      ),
      ShipOutcome.publicacionIncompletaParaLaPrueba(
        remoto: PushUnknown(causa: CausaDePublicacion.red),
        verificacion: EstadoPublicable.verde,
      ),
    ];

    final afirmados = desenlaces
        .map(DocumentoDeCorrida.estadoQueAfirma)
        .nonNulls
        .toSet();

    for (final estado in EstadoDelDocumento.values) {
      expect(
        DocumentoDeCorrida.admiteDesenlace(estado),
        afirmados.contains(estado),
        reason:
            'los dos despachos discrepan sobre «${estado.name}»: uno dice '
            'que admite desenlace y el otro que ningún desenlace lo afirma, '
            'o al revés',
      );
    }
  });

  group('el estado y el desenlace son el mismo hecho', () {
    // `estado` y `desenlace` se asignaban por separado y el segundo determina
    // al primero, así que esto se construía, se persistía y se releía: un
    // documento que dice «el CAS fue rechazado, nada se aplicó» llevando
    // adentro «hay un pull request abierto y utilizable». Es el estado
    // contradictorio, un nivel por encima del tipo que se inventó para
    // cerrarlo.
    final porEstado = <EstadoDelDocumento, ShipOutcome>{
      EstadoDelDocumento.notApplied: ShipOutcome.noAplicadoParaLaPrueba(
        causa: CausaDeNoAplicacion.baseMovida,
        headObservado: 'c' * 40,
      ),
      EstadoDelDocumento.localInconsistent:
          ShipOutcome.localInconsistenteParaLaPrueba(revision: 'd' * 40),
      EstadoDelDocumento.publicationComplete: ShipOutcome.publicadoParaLaPrueba(
        pr: PullRequestOpen(url: 'https://forja/pr/1'),
        verificacion: EstadoPublicable.verde,
      ),
      EstadoDelDocumento.publicationIncomplete:
          ShipOutcome.publicacionIncompletaParaLaPrueba(
            remoto: PushUnknown(causa: CausaDePublicacion.red),
            verificacion: EstadoPublicable.verde,
          ),
    };

    DocumentoDeCorrida llegarA(EstadoDelDocumento destino, ShipOutcome? d) =>
        switch (destino) {
          EstadoDelDocumento.notApplied ||
          EstadoDelDocumento.localInconsistent ||
          EstadoDelDocumento.committed => preparado().avanzarA(
            destino,
            desenlace: d,
          ),
          EstadoDelDocumento.publicationComplete ||
          EstadoDelDocumento.publicationIncomplete =>
            preparado()
                .avanzarA(EstadoDelDocumento.committed)
                .avanzarA(destino, desenlace: d),
          EstadoDelDocumento.prepared => preparado(),
        };

    test('la correspondencia es total sobre las cinco variantes', () {
      // `NoIntentado` es la quinta y no afirma ningún estado del documento:
      // sus causas se resuelven antes del CAS, o sea antes de que exista la
      // revisión candidata sin la cual este documento no se escribe.
      expect(
        DocumentoDeCorrida.estadoQueAfirma(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.previewOnly,
            verificacion: EstadoDeCorrida.verde,
          ),
        ),
        isNull,
      );
      for (final par in porEstado.entries) {
        expect(
          DocumentoDeCorrida.estadoQueAfirma(par.value),
          par.key,
          reason: par.value.kind,
        );
      }
      expect(
        porEstado.values.map((d) => d.runtimeType).toSet(),
        hasLength(4),
        reason: 'las cuatro que sí afirman un estado, más NoIntentado: cinco',
      );
    });

    test('cada estado acepta EL desenlace que le corresponde', () {
      for (final par in porEstado.entries) {
        final doc = llegarA(par.key, par.value);
        expect(doc.estado, par.key);
        expect(doc.desenlace, same(par.value));
      }
    });

    test('un desenlace que afirma OTRO estado no se construye', () {
      for (final destino in porEstado.keys) {
        for (final ajeno in porEstado.entries) {
          if (ajeno.key == destino) continue;
          expect(
            () => llegarA(destino, ajeno.value),
            throwsArgumentError,
            reason: '${destino.name} aceptó un desenlace ${ajeno.value.kind}',
          );
        }
      }
    });

    test('NoIntentado no lo acepta NINGÚN estado', () {
      final sinIntentar = ShipOutcome.noIntentadoParaLaPrueba(
        causa: CausaDeNoIntento.secretDetected,
        verificacion: EstadoDeCorrida.verde,
      );
      for (final destino in [EstadoDelDocumento.committed, ...porEstado.keys]) {
        expect(
          () => llegarA(destino, sinIntentar),
          throwsArgumentError,
          reason: destino.name,
        );
      }
    });

    test('el desenlace que se arrastra también se comprueba', () {
      // `avanzarA` conserva el desenlace anterior cuando no se pasa uno
      // nuevo. Sin la comprobación sobre el arrastrado, completar una
      // publicación a medias dejaba adentro el desenlace que dice que no se
      // completó.
      final incompleta = llegarA(
        EstadoDelDocumento.publicationIncomplete,
        porEstado[EstadoDelDocumento.publicationIncomplete],
      );
      expect(
        () => incompleta.avanzarA(EstadoDelDocumento.publicationComplete),
        throwsArgumentError,
        reason: 'el desenlace arrastrado sigue diciendo «no se completó»',
      );
      expect(
        incompleta
            .avanzarA(
              EstadoDelDocumento.publicationComplete,
              desenlace: porEstado[EstadoDelDocumento.publicationComplete],
            )
            .estado,
        EstadoDelDocumento.publicationComplete,
      );
    });

    test('el documento incoherente tampoco entra por JSON, y sale por '
        'FormatException', () {
      // Es el camino por el que de verdad llegaba: un archivo en el disco.
      // `fromJson` reconstruye cualquier estado —y eso es correcto— así que
      // la comprobación tiene que estar también acá.
      final valido = llegarA(
        EstadoDelDocumento.notApplied,
        porEstado[EstadoDelDocumento.notApplied],
      ).toJson();
      expect(
        DocumentoDeCorrida.fromJson(valido).estado,
        EstadoDelDocumento.notApplied,
        reason: 'control positivo: el coherente SÍ se lee',
      );
      for (final ajeno in porEstado.entries) {
        if (ajeno.key == EstadoDelDocumento.notApplied) continue;
        final roto = Map<String, Object?>.from(valido)
          ..['desenlace'] = ajeno.value.toJson();
        expect(
          () => DocumentoDeCorrida.fromJson(roto),
          throwsFormatException,
          reason: 'notApplied se releyó con un desenlace ${ajeno.value.kind}',
        );
      }
    });

    test('un NoAplicado sin causa es una forma más vieja del documento, y '
        'el error NOMBRA la versión', () {
      // La forma vieja de `NoAplicado` no tenía `causa` —ver su historia en
      // el archivo del desenlace—, y `versionActual` no subió cuando el campo
      // se agregó porque nadie había publicado esa forma todavía (ver el doc
      // de [DocumentoDeCorrida.versionActual]). Un documento con esa forma vieja
      // hoy PASA el portón de `formatVersion` entero —es el mismo número— y
      // recién explota releyendo el desenlace. Sin nombrar la versión ahí, el
      // error que sale lee como «este JSON está roto» y no como lo que es:
      // una forma que a este código todavía le falta, o le sobra, describir.
      final valido = llegarA(
        EstadoDelDocumento.notApplied,
        porEstado[EstadoDelDocumento.notApplied],
      ).toJson();
      final desenlaceSinCausa = Map<String, Object?>.from(
        valido['desenlace']! as Map,
      )..remove('causa');
      final json = Map<String, Object?>.from(valido)
        ..['desenlace'] = desenlaceSinCausa;
      expect(
        () => DocumentoDeCorrida.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'nombra formatVersion',
            contains('formatVersion ${DocumentoDeCorrida.versionActual}'),
          ),
        ),
      );
    });

    test('un borrador sin rutas es una forma más vieja del documento, y el '
        'error NOMBRA la versión', () {
      // Mismo motivo que el análogo de arriba con el desenlace: `rutas` es un
      // campo nuevo (`--retry-publication`, tarea 3) y `versionActual` no
      // subió cuando se agregó, porque nadie había publicado la forma vieja
      // del borrador todavía. `PullRequestDraft.fromJson` ya nombra la
      // PALABRA «formatVersion» en su propio mensaje —no puede nombrar el
      // NÚMERO: no conoce cuál trae este documento, y conocerlo exigiría
      // importar este archivo desde el suyo—. Sin envolverlo acá con el
      // número concreto, los dos caminos de «esta es una forma más vieja» del
      // mismo documento —el del desenlace, arriba, y este— quedaban dando
      // diagnósticos distintos ante el mismo tipo de forma vieja.
      final valido = preparado().toJson();
      final draftSinRutas = Map<String, Object?>.from(valido['draft']! as Map)
        ..remove('rutas');
      final json = Map<String, Object?>.from(valido)..['draft'] = draftSinRutas;
      expect(
        () => DocumentoDeCorrida.fromJson(json),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'nombra formatVersion',
            contains('formatVersion ${DocumentoDeCorrida.versionActual}'),
          ),
        ),
      );
    });

    test('un desenlace nulo nunca es incoherente: es «todavía no hay»', () {
      // Residuo declarado: que un estado TERMINAL pueda seguir llevando
      // desenlace nulo NO está impuesto acá. Quién escribe el desenlace en
      // cada paso es 4b.
      for (final destino in [EstadoDelDocumento.committed, ...porEstado.keys]) {
        expect(
          () => llegarA(destino, null),
          returnsNormally,
          reason: destino.name,
        );
      }
    });
  });

  test('el documento vuelve a ser él mismo por JSON', () {
    final ida = preparado().avanzarA(EstadoDelDocumento.committed);
    final vuelta = DocumentoDeCorrida.fromJson(ida.toJson());
    expect(vuelta.toJson(), ida.toJson());
  });

  test('un estado que nadie declaró se rechaza como FormatException', () {
    // `values.byName` lanzaba `ArgumentError`, tres líneas arriba de la
    // comprobación de coherencia que sí lanza `FormatException`: dos familias
    // para una sola condición, adentro del mismo método. Quien lea un
    // documento tendría que atrapar las dos para no dejar pasar ninguna.
    final json = Map<String, Object?>.from(preparado().toJson())
      ..['estado'] = 'unEstadoQueNadieDeclaro';
    expect(() => DocumentoDeCorrida.fromJson(json), throwsFormatException);
  });

  test('un formatVersion que no conocemos NO se lee', () {
    final json = Map<String, Object?>.from(preparado().toJson())
      ..['formatVersion'] = 99;
    expect(() => DocumentoDeCorrida.fromJson(json), throwsFormatException);
  });
}
