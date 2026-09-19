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

void main() {
  DocumentoDeCorrida preparado() =>
      DocumentoDeCorrida.preparado(revision: 'a' * 40, draft: draftDePrueba());

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

  test('los TRES estados terminales lo son, y ninguno tiene salida', () {
    // Esta prueba cubría solo `notApplied`. El mapa declara los tres con
    // conjunto vacío, pero lo que demostraba que `publicationComplete` y
    // `localInconsistent` fueran terminales era la lectura del mapa, no una
    // aserción: cambiarle a `publicationComplete` el conjunto vacío por
    // `{committed}` dejaba la suite entera en verde, y `publicationComplete`
    // terminal es lo único que impide que `--retry-publication` vuelva a
    // publicar una corrida ya publicada.
    final terminales = <EstadoDelDocumento, DocumentoDeCorrida>{
      EstadoDelDocumento.notApplied: preparado().avanzarA(
        EstadoDelDocumento.notApplied,
      ),
      EstadoDelDocumento.localInconsistent: preparado().avanzarA(
        EstadoDelDocumento.localInconsistent,
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
