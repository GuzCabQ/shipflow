/// [RegistroDeCorridas]: temporal + `rename`, y lo que la lectura no hace.
///
/// El escritor deja aparecer el nombre final con el contenido entero o no lo
/// deja aparecer. No hay lectura parcial que probar porque no existe: lo que
/// hay para probar es que un temporal huérfano no se confunde con un
/// documento, y que la ausencia de documento es un hecho legible, no un
/// error.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:test/test.dart';

PullRequestDraft _draftDePrueba({
  String base = 'base-1',
  String branch = 'rama',
}) => PullRequestDraft(
  runId: 'corrida-1',
  branch: branch,
  base: 'develop',
  artefacto: ArtefactoDeRevision(
    superficie: SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: const [],
      estado: EstadoDeCorrida.verde,
    ),
    candidato: CandidateIdentity(
      contentRevision: 'arbol-1',
      baseRevision: base,
    ),
    intent: 'sostener el arnés',
    plan: null,
    sinPlanPorque: 'no hay elementos de trabajo',
    alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
  ),
  rutas: const ['a.txt'],
);

/// El destino de todo documento que estas pruebas construyen. **Es una
/// cadena opaca**: nadie de este lado sabe leerla, así que lo único que se
/// mide con ella es la igualdad.
const destinoDeLosDocumentosDePrueba = 'forja.ejemplo/duenio/repo';

DocumentoDeCorrida documentoDePrueba() => DocumentoDeCorrida.preparado(
  revision: 'a' * 40,
  draft: _draftDePrueba(),
  destino: destinoDeLosDocumentosDePrueba,
);

/// Un documento `prepared` con la base y la revisión que pida la prueba —los
/// dos datos que [decidirRecuperacion] compara contra el `HEAD` observado.
///
/// **Los dos parámetros tienen default, y no son obligatorios como antes.**
/// Las pruebas de la reconciliación de los cinco pasos no necesitan una base
/// ni una revisión particulares: solo necesitan UN documento `prepared`
/// coherente, del que leer [ArtefactoDeRevision.candidato] e [intent] para
/// fabricar hechos sanos o desviados. Pedirles que inventen una base y una
/// revisión que no van a usar sería ruido; las que sí comparan un valor
/// concreto contra el `HEAD` —como la de los tres casos— lo siguen pasando
/// explícito, y ese uso no cambia.
DocumentoDeCorrida documentoPreparado({
  String base = 'base-1',
  String revision = 'revision-1',
}) => DocumentoDeCorrida.preparado(
  revision: revision,
  draft: _draftDePrueba(base: base),
  destino: destinoDeLosDocumentosDePrueba,
);

/// La rama de todo documento que [documentoEn] construye. Las pruebas de la
/// puerta del reintento pasan este mismo valor como `ramaActual` cuando
/// quieren que coincida, y otra cosa cuando quieren que no.
const ramaDeLosDocumentosDePrueba = 'feature/x';

/// Un documento en [estado], con el desenlace que ese estado exige cuando lo
/// tiene.
///
/// Vive acá y no repetido en cada prueba porque una de ellas recorre los
/// SEIS valores de [EstadoDelDocumento] y construir cada uno a mano ahí
/// mismo repetiría la misma cascada de [DocumentoDeCorrida.avanzarA] seis
/// veces. Los estados no terminales de esta cascada —`prepared`,
/// `committed`— no llevan desenlace porque el documento real tampoco lo
/// tiene ahí: la corrida todavía no terminó.
DocumentoDeCorrida documentoEn(EstadoDelDocumento estado) {
  final preparado = DocumentoDeCorrida.preparado(
    revision: 'a' * 40,
    draft: _draftDePrueba(branch: ramaDeLosDocumentosDePrueba),
    destino: destinoDeLosDocumentosDePrueba,
  );
  return switch (estado) {
    EstadoDelDocumento.prepared => preparado,
    EstadoDelDocumento.committed => preparado.avanzarA(
      EstadoDelDocumento.committed,
    ),
    EstadoDelDocumento.publicationIncomplete =>
      preparado
          .avanzarA(EstadoDelDocumento.committed)
          .avanzarA(
            EstadoDelDocumento.publicationIncomplete,
            desenlace: ShipOutcome.publicacionIncompletaParaLaPrueba(
              remoto: PushFailed(causa: CausaDePublicacion.red),
              verificacion: EstadoPublicable.verde,
            ),
          ),
    EstadoDelDocumento.publicationComplete =>
      preparado
          .avanzarA(EstadoDelDocumento.committed)
          .avanzarA(
            EstadoDelDocumento.publicationComplete,
            desenlace: ShipOutcome.publicadoParaLaPrueba(
              pr: PullRequestOpen(url: 'https://forja.ejemplo/pr/1'),
              verificacion: EstadoPublicable.verde,
            ),
          ),
    EstadoDelDocumento.notApplied => preparado.avanzarA(
      EstadoDelDocumento.notApplied,
      desenlace: ShipOutcome.noAplicadoParaLaPrueba(
        causa: CausaDeNoAplicacion.baseMovida,
        headObservado: 'b' * 40,
      ),
    ),
    EstadoDelDocumento.localInconsistent => preparado.avanzarA(
      EstadoDelDocumento.localInconsistent,
      desenlace: ShipOutcome.localInconsistenteParaLaPrueba(revision: 'a' * 40),
    ),
  };
}

void main() {
  late Directory temporal;

  setUp(() => temporal = Directory.systemTemp.createTempSync('registro_'));
  tearDown(() => temporal.deleteSync(recursive: true));

  test('lo escrito se vuelve a leer igual', () async {
    final registro = RegistroDeCorridas(raiz: temporal.path);
    final doc = documentoDePrueba();
    await registro.escribir('r-1', doc);
    expect((await registro.leer('r-1'))!.toJson(), doc.toJson());
  });

  test(
    'escribir NO deja ningún temporal atrás: es rename, no copiar',
    () async {
      // El mecanismo es temporal + `rename`. Cambiar el `rename` por un `copy`
      // dejaba las otras tres pruebas en verde: el documento final queda igual
      // de bien escrito, y el `.tmp` residual que la copia deja no lo miraba
      // nadie. Un `.tmp` que sobrevive a una escritura terminada es además un
      // documento a medio escribir que la lectura está obligada a ignorar para
      // siempre, porque no puede distinguirlo de uno que se está escribiendo
      // ahora.
      final registro = RegistroDeCorridas(raiz: temporal.path);
      await registro.escribir('r-4', documentoDePrueba());
      final dir = Directory(rutas.join(temporal.path, 'runs'));
      expect(
        dir.listSync().map((e) => rutas.basename(e.path)).toList(),
        ['r-4.json'],
        reason: 'el temporal se renombra, no se copia',
      );
    },
  );

  test('una corrida que no existe devuelve nulo, no lanza', () async {
    // «No hay documento» es un hecho que la recuperación tiene que poder
    // ramificar: significa que el proceso murió antes de `prepared`, y lo
    // único que quedó es un objeto inalcanzable que el `gc` recoge.
    final registro = RegistroDeCorridas(raiz: temporal.path);
    expect(await registro.leer('nunca-existio'), isNull);
  });

  test('un temporal huérfano NO se lee como documento', () async {
    // El escritor usa temporal + `rename` para que nadie lea a medias. Si el
    // proceso muere entre los dos, el temporal queda; leerlo sería leer un
    // documento a medio escribir.
    final registro = RegistroDeCorridas(raiz: temporal.path);
    await registro.escribir('r-2', documentoDePrueba());
    final dir = Directory(rutas.join(temporal.path, 'runs'));
    final huerfano = File(rutas.join(dir.path, 'r-3.json.tmp'));
    await huerfano.writeAsString('{"formatVersion":1,"estado":"prepared"');
    expect(await registro.leer('r-3'), isNull);
    expect(await huerfano.exists(), isTrue, reason: 'no se borra a escondidas');
  });

  test('los tres casos de HEAD, y ninguno más', () {
    final doc = documentoPreparado(base: 'b' * 40, revision: 'r' * 40);
    expect(
      decidirRecuperacion(documento: doc, headActual: 'b' * 40),
      QueHacerAlRecuperar.reintentarElCas,
    );
    expect(
      decidirRecuperacion(documento: doc, headActual: 'r' * 40),
      QueHacerAlRecuperar.promoverACommitted,
    );
    expect(
      decidirRecuperacion(documento: doc, headActual: 'x' * 40),
      QueHacerAlRecuperar.alguienMasAvanzo,
    );
  });

  test(
    'los SEIS estados tienen respuesta, y ninguna es un error de estado',
    () {
      for (final estado in EstadoDelDocumento.values) {
        expect(
          () => puertaDelReintento(
            documento: documentoEn(estado),
            ramaActual: ramaDeLosDocumentosDePrueba,
            destinoActual: destinoDeLosDocumentosDePrueba,
          ),
          returnsNormally,
          reason: estado.name,
        );
      }
    },
  );

  test('desde commiteado se publica directo', () {
    expect(
      puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.committed),
        ramaActual: ramaDeLosDocumentosDePrueba,
        destinoActual: destinoDeLosDocumentosDePrueba,
      ),
      isA<PublicarDirecto>(),
    );
  });

  test('desde una publicación incompleta también', () {
    expect(
      puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.publicationIncomplete),
        ramaActual: ramaDeLosDocumentosDePrueba,
        destinoActual: destinoDeLosDocumentosDePrueba,
      ),
      isA<PublicarDirecto>(),
    );
  });

  test('desde preparado se reconcilia', () {
    expect(
      puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.prepared),
        ramaActual: ramaDeLosDocumentosDePrueba,
        destinoActual: destinoDeLosDocumentosDePrueba,
      ),
      isA<Reconciliar>(),
    );
  });

  test(
    'desde el estado inconsistente TAMBIÉN se reconcilia, por el otro camino',
    () {
      expect(
        puertaDelReintento(
          documento: documentoEn(EstadoDelDocumento.localInconsistent),
          ramaActual: ramaDeLosDocumentosDePrueba,
          destinoActual: destinoDeLosDocumentosDePrueba,
        ),
        isA<Reconciliar>(),
      );
    },
  );

  test('una publicación completa NO se reintenta, y lo dice', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.publicationComplete),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: destinoDeLosDocumentosDePrueba,
    );
    expect(p, isA<NoSeReintenta>());
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.yaPublicado);
    expect(
      p.detalle,
      contains('https://forja.ejemplo/pr/1'),
      reason:
          'una publicación completa dice dónde quedó, no solo que ya '
          'pasó',
    );
  });

  test('un CAS rechazado NO se reintenta: no hay entrega que recuperar', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.notApplied),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: destinoDeLosDocumentosDePrueba,
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.nadaQueEntregar);
    expect(
      p.detalle,
      contains('ship'),
      reason:
          'la regla dura del proyecto es que ninguna prohibición se '
          'instala sin decir qué hacer en cambio, y acá lo que hay que '
          'hacer es volver a correr ship',
    );
  });

  test('parado en OTRA rama no se reintenta, aunque el HEAD coincida', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.committed),
      ramaActual: 'otra-rama',
      destinoActual: destinoDeLosDocumentosDePrueba,
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.ramaDistinta);
    expect(
      p.detalle,
      allOf(contains(ramaDeLosDocumentosDePrueba), contains('otra-rama')),
      reason: 'un mensaje que no nombra las dos ramas no dice qué hacer',
    );
  });

  test('con el destino cambiado NO se reintenta, y lo dice', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.committed),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: 'otra-forja/otro/repositorio',
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.destinoDistinto);
    expect(
      p.detalle,
      allOf(
        contains(destinoDeLosDocumentosDePrueba),
        contains('otra-forja/otro/repositorio'),
      ),
      reason: 'un mensaje que no nombra los dos destinos no dice cuál devolver',
    );
  });

  test('sin destino que nombrar tampoco se reintenta', () {
    // Nulo nunca es igual al destino de un documento: no hay remoto, o el que
    // hay no nombra ningún destino, y en los dos casos no se puede afirmar
    // que se siga publicando donde se publicaba.
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.committed),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: null,
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.destinoDistinto);
  });

  test('el destino gana sobre el estado en los caminos que publican', () {
    // Los CUATRO estados que despachan a un camino de publicación, contados
    // sobre el `switch` de la puerta: los dos que reconcilian y los dos que
    // publican directo. En los cuatro, el destino manda.
    const publican = [
      EstadoDelDocumento.prepared,
      EstadoDelDocumento.committed,
      EstadoDelDocumento.publicationIncomplete,
      EstadoDelDocumento.localInconsistent,
    ];
    for (final estado in publican) {
      final p = puertaDelReintento(
        documento: documentoEn(estado),
        ramaActual: ramaDeLosDocumentosDePrueba,
        destinoActual: 'otra-forja/otro/repositorio',
      );
      expect(
        (p as NoSeReintenta).causa,
        CausaDeNoReintento.destinoDistinto,
        reason: estado.name,
      );
    }
  });

  test(
    'sobre una corrida YA PUBLICADA el destino movido no la vuelve un fallo',
    () {
      // **Acá no hay ninguna publicación que guardar**: este camino no lee el
      // repositorio ni le pide nada a la forja. Convertirlo en un rechazo
      // cambiaba un hecho cierto —dónde quedó el pull request— por un fallo, y
      // se llevaba puesta la URL, que es justo lo que necesita quien movió el
      // remoto por un motivo ajeno a esta corrida.
      final p = puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.publicationComplete),
        ramaActual: ramaDeLosDocumentosDePrueba,
        destinoActual: 'otra-forja/otro/repositorio',
      );
      expect((p as NoSeReintenta).causa, CausaDeNoReintento.yaPublicado);
      expect(
        p.detalle,
        contains('https://forja.ejemplo/pr/1'),
        reason: 'la URL sigue estando: es la única forma de preguntar',
      );
      expect(
        p.detalle,
        allOf(
          contains(destinoDeLosDocumentosDePrueba),
          contains('otra-forja/otro/repositorio'),
        ),
        reason:
            'y va con su aviso, que es lo que impide leerla como si fuera del '
            'remoto de ahora',
      );
    },
  );

  test('sin remoto, una corrida ya publicada igual dice dónde quedó', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.publicationComplete),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: null,
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.yaPublicado);
    expect(p.detalle, contains('https://forja.ejemplo/pr/1'));
  });

  test('con el destino intacto, la respuesta de siempre y SIN aviso', () {
    // El control negativo del aviso: pegado sin condición, sería ruido en
    // todas las corridas que no movieron nada.
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.publicationComplete),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: destinoDeLosDocumentosDePrueba,
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.yaPublicado);
    expect(p.detalle, isNot(contains('Ojo')));
  });

  test('un CAS rechazado con el destino movido sigue diciendo lo mismo', () {
    // Tampoco publica: la alternativa —volver a correr `ship`— es cierta
    // cualquiera sea el remoto de hoy.
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.notApplied),
      ramaActual: ramaDeLosDocumentosDePrueba,
      destinoActual: 'otra-forja/otro/repositorio',
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.nadaQueEntregar);
  });

  test('la rama se comprueba ANTES que el destino', () {
    // Quien está parado en otra rama tampoco está mirando este documento, y
    // esa es la causa más alcanzable: cambiarse de rama es más común que
    // mudar un remoto.
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.committed),
      ramaActual: 'otra-rama',
      destinoActual: 'otra-forja/otro/repositorio',
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.ramaDistinta);
  });

  test('la rama se comprueba ANTES que el estado', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.publicationComplete),
      ramaActual: 'otra-rama',
      destinoActual: destinoDeLosDocumentosDePrueba,
    );
    expect(
      (p as NoSeReintenta).causa,
      CausaDeNoReintento.ramaDistinta,
      reason:
          'estar en otra rama vuelve irrelevante cualquier cosa que el '
          'estado diga: lo que se leyó no es del repositorio que se mira',
    );
  });

  HechosDeLaRevision hechosSanos(DocumentoDeCorrida d) => HechosDeLaRevision(
    padre: d.draft.artefacto.candidato.baseRevision,
    arbol: d.draft.artefacto.candidato.contentRevision,
    mensaje: d.draft.artefacto.intent,
    rutasQueDifieren: const [],
  );

  test('con los cinco pasos en orden, la reconciliación es inequívoca', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: hechosSanos(d),
    );
    expect(r, isA<Inequivoca>());
    expect((r as Inequivoca).queHacer, QueHacerAlRecuperar.promoverACommitted);
  });

  test('si el padre NO es la base, falla cerrado', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: 'otro' * 10,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.padreDistinto);
  });

  test('si el ÁRBOL difiere, falla cerrado aunque el padre coincida', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        // Superstring del árbol esperado, no una cadena disjunta: si la
        // comparación degradara a `contains` en vez de igualdad de
        // identificador, un árbol que solo CONTIENE al esperado pasaría
        // como si fuera el mismo, y esta prueba seguiría en verde sin medir
        // lo que dice medir. Con una cadena disjunta (p. ej. 40 letras
        // «a»), `contains` y la igualdad coinciden en que difieren, y la
        // mutación queda sin poder matar.
        arbol: '${d.draft.artefacto.candidato.contentRevision}-pero-otro',
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.contenidoDistinto);
  });

  test('si el MENSAJE difiere, falla cerrado', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: 'otra intención',
        rutasQueDifieren: const [],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.mensajeDistinto);
  });

  test(
    'si el índice difiere EN LAS RUTAS, falla cerrado y NOMBRA el comando',
    () {
      final d = documentoPreparado();
      final r = reconciliar(
        documento: d,
        headActual: d.revision,
        hechos: HechosDeLaRevision(
          padre: d.draft.artefacto.candidato.baseRevision,
          arbol: d.draft.artefacto.candidato.contentRevision,
          mensaje: d.draft.artefacto.intent,
          rutasQueDifieren: const ['lib/a.dart'],
        ),
      );
      expect((r as Ambigua).causa, CausaDeAmbiguedad.indiceDistinto);
      expect(
        r.detalle,
        allOf(
          contains('lib/a.dart'),
          contains('git reset'),
          contains(d.revision),
        ),
        reason:
            '«reconciliar a mano» no dice qué correr: es la misma '
            'prohibición sin alternativa que la regla dura del proyecto no '
            'permite, y esta reconciliación repara el índice exactamente '
            'igual que la del estado inconsistente',
      );
    },
  );

  test(
    'con el HEAD en la base, los cinco pasos NO deciden: se reintenta el CAS',
    () {
      final d = documentoPreparado();
      final r = reconciliar(
        documento: d,
        headActual: d.draft.artefacto.candidato.baseRevision,
        hechos: hechosSanos(d),
      );
      expect((r as Inequivoca).queHacer, QueHacerAlRecuperar.reintentarElCas);
    },
  );

  test(
    'con un HEAD ajeno, alguien más avanzó y los cinco pasos son ociosos',
    () {
      final d = documentoPreparado();
      final r = reconciliar(
        documento: d,
        headActual: 'f' * 40,
        hechos: hechosSanos(d),
      );
      expect((r as Inequivoca).queHacer, QueHacerAlRecuperar.alguienMasAvanzo);
    },
  );

  test('la ambigüedad GANA sobre los tres casos: no se promueve lo dudoso', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: 'a' * 40,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect(
      r,
      isA<Ambigua>(),
      reason:
          'el HEAD coincide con la revisión, así que la comparación de '
          'tres casos diría «promover»; promoverlo publicaría sobre un '
          'commit que nadie verificó que sea el nuestro',
    );
  });

  // Las cuatro pruebas de arriba hacen fallar UN solo hecho por vez, y con
  // un solo hecho fallando el orden entre los cuatro chequeos nunca se nota:
  // cualquiera que se evaluara primero iba a fallar cerrado igual. Estas
  // tres pruebas hacen fallar DOS hechos a la vez, en cada uno de los pares
  // ADYACENTES del orden que el doc de `reconciliar` argumenta —de lo más
  // estructural a lo más circunstancial—, y afirman CUÁL de las dos causas
  // sale: la del hecho más estructural, no la del otro. Fijan el orden total
  // porque fijar cada par adyacente fija la cadena entera.

  test('con el PADRE y el ÁRBOL distintos a la vez, gana el padre: es más '
      'estructural', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: 'otro' * 10,
        arbol: '${d.draft.artefacto.candidato.contentRevision}-pero-otro',
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect(
      (r as Ambigua).causa,
      CausaDeAmbiguedad.padreDistinto,
      reason:
          'si la ascendencia ya está mal, el contenido no puede rescatar '
          'esa conclusión: reportar «contenido distinto» mandaría a mirar '
          'un commit que ni siquiera desciende de nuestra base',
    );
  });

  test('con el ÁRBOL y el MENSAJE distintos a la vez, gana el árbol: identidad '
      'de objeto por sobre texto reescribible', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: '${d.draft.artefacto.candidato.contentRevision}-pero-otro',
        mensaje: 'otra intención',
        rutasQueDifieren: const [],
      ),
    );
    expect(
      (r as Ambigua).causa,
      CausaDeAmbiguedad.contenidoDistinto,
      reason:
          'un mensaje se reescribe sin tocar ningún objeto; el contenido '
          'no. Reportar «mensaje distinto» sobre un árbol que además es '
          'otro escondería el hecho que de verdad importa',
    );
  });

  test('con el MENSAJE y el ÍNDICE distintos a la vez, gana el mensaje: habla '
      'de la revisión, el índice habla de quien corre', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: 'otra intención',
        rutasQueDifieren: const ['lib/a.dart'],
      ),
    );
    expect(
      (r as Ambigua).causa,
      CausaDeAmbiguedad.mensajeDistinto,
      reason:
          'el índice sucio es un problema del entorno de quien corre, no '
          'de la revisión; reportarlo primero mandaría a sincronizar el '
          'índice sobre un commit que, además, no es el nuestro',
    );
  });

  test('el índice que coincide deja promover', () {
    // Con SU desenlace puesto —el que [ShipOutcome.derivar] deja en
    // cualquier documento real que llegue a este estado—, no la forma sin
    // desenlace que un helper más viejo usaba para esquivar el problema de
    // la arista de abajo.
    final d = documentoEn(EstadoDelDocumento.localInconsistent);
    expect(
      comprobarIndice(documento: d, rutasQueDifieren: const []),
      isA<IndiceCoincide>(),
    );
  });

  test('el índice que no coincide falla cerrado y NOMBRA las rutas', () {
    final d = documentoEn(EstadoDelDocumento.localInconsistent);
    final r = comprobarIndice(
      documento: d,
      rutasQueDifieren: const ['lib/a.dart', 'lib/b.dart'],
    );
    expect(r, isA<IndiceNoCoincide>());
    expect((r as IndiceNoCoincide).rutas, ['lib/a.dart', 'lib/b.dart']);
  });

  test('el comando de reparación cita cada ruta: un espacio no lo rompe', () {
    // Medido en un repositorio temporal: sin comillas, `git reset` recibe
    // la ruta partida en dos pathspecs, sale con código cero y el índice
    // queda exactamente tan desincronizado como antes de correrlo.
    final d = documentoEn(EstadoDelDocumento.localInconsistent);
    final r =
        comprobarIndice(
              documento: d,
              rutasQueDifieren: const ['ruta con espacio.txt', 'otra.txt'],
            )
            as IndiceNoCoincide;
    expect(
      r.detalle,
      allOf(
        contains("'ruta con espacio.txt'"),
        contains("'otra.txt'"),
        contains('git reset'),
      ),
      reason:
          'cada ruta va citada individualmente, no solo unida con espacios '
          'en una sola cadena sin comillas',
    );
  });

  test('la promoción desde el estado inconsistente es legal', () {
    // Con SU desenlace puesto, y llamando a la función de esta tarea: es la
    // corrección de una ronda de arreglos anterior, que medida encontró que
    // la versión previa —un documento sin desenlace, sin pasar por
    // comprobarIndice— pasaba igual con una arista que ningún documento
    // real de producción podía tomar. `avanzarA` descarta el desenlace de
    // `localInconsistent` porque `committed` no admite ninguno —ver
    // `admiteDesenlace` en el documento—; antes de esa corrección, el
    // desenlace se arrastraba sin mirar el destino y esto lanzaba SIEMPRE.
    final d = documentoEn(EstadoDelDocumento.localInconsistent);
    final r = comprobarIndice(documento: d, rutasQueDifieren: const []);
    expect(r, isA<IndiceCoincide>());
    final promovido = d.avanzarA(EstadoDelDocumento.committed);
    expect(
      promovido.estado,
      EstadoDelDocumento.committed,
      reason:
          'sin la arista de la tarea 4, o con el desenlace de este estado '
          'todavía puesto, esto lanza, y el camino de §9 no sería '
          'construible',
    );
    expect(
      promovido.desenlace,
      isNull,
      reason: '`committed` no admite desenlace: el que traía se descarta',
    );
  });

  test(
    'sobre un documento que NO está en ese estado, no se comprueba nada',
    () {
      expect(
        () => comprobarIndice(
          documento: documentoEn(EstadoDelDocumento.committed),
          rutasQueDifieren: const [],
        ),
        throwsStateError,
        reason:
            'esta comprobación es la puerta de UN estado; usarla en otro '
            'promovería por una arista que ese estado no tiene',
      );
    },
  );

  group('el identificador de una corrida no sale de su directorio', () {
    // **La reproducción del P1-2 de la revisión humana.** Con el
    // identificador concatenado tal cual, «../../fuera» producía
    // `.shipflow/runs/../../fuera.json`: el reintento LEÍA esa ruta y, si
    // encontraba un documento válido, terminaba ESCRIBIÉNDOLA.
    const salidas = {
      'subir dos niveles': '../../fuera',
      'subir uno': '../vecino',
      'un subdirectorio, que tampoco es hijo directo': 'adentro/otro',
      'una ruta absoluta, que se come el directorio entero': '/tmp/ajeno',
    };
    salidas.forEach((queHace, runId) {
      test('«$runId» ($queHace) se rechaza al derivar la ruta', () {
        final registro = RegistroDeCorridas(raiz: temporal.path);
        expect(
          () => registro.documentoDe(runId),
          throwsArgumentError,
          reason: 'la ruta del documento caería fuera del directorio',
        );
        expect(
          () => registro.proyeccionDe(runId),
          throwsArgumentError,
          reason: 'la de la proyección, también',
        );
      });

      test('«$runId» no se puede leer ni escribir', () async {
        final registro = RegistroDeCorridas(raiz: temporal.path);
        await expectLater(registro.leer(runId), throwsArgumentError);
        await expectLater(
          registro.escribir(runId, documentoDePrueba()),
          throwsArgumentError,
        );
      });
    });

    test('un identificador normal sigue derivando su ruta de siempre', () {
      // El control negativo: sin esto, un rechazo que abarcara de más
      // pasaría inadvertido.
      final registro = RegistroDeCorridas(raiz: temporal.path);
      expect(
        registro.documentoDe('1758240000000000-1'),
        rutas.join(temporal.path, 'runs', '1758240000000000-1.json'),
      );
    });
  });

  group('la gramática de un identificador de corrida', () {
    test('lo que emite `generarRunId` la cumple', () {
      // **Derivada de quien los emite, no inventada.** Si esa función
      // cambiara de forma, esta prueba es la que lo dice.
      for (var i = 0; i < 3; i++) {
        final emitido = generarRunId();
        expect(
          esRunIdDeCorrida(emitido),
          isTrue,
          reason: 'el propio árbol emitió «$emitido» y la gramática lo niega',
        );
      }
    });

    const rechazados = [
      '../../fuera',
      '/tmp/ajeno',
      'adentro/otro',
      'r-1',
      '1-1/../../fuera',
      '',
      '1758240000000000',
      '-1',
      '1758240000000000-1\n',
    ];
    for (final candidato in rechazados) {
      test('«$candidato» no es un identificador de corrida', () {
        expect(esRunIdDeCorrida(candidato), isFalse);
      });
    }
  });

  _pruebasDelCitado();
}

/// Qué hace un shell POSIX de verdad con [linea]: cuántos argumentos ve, y
/// cuáles.
///
/// **Es el parser del shell y no una reimplementación**, que es el punto: lo
/// que hay que medir de una cita no es que «parezca bien citada» sino que el
/// programa que la va a interpretar vea exactamente un argumento y que ese
/// argumento sea el original. Cualquier comprobación escrita acá adentro
/// sería una segunda definición de las reglas de citado, y la que decide es
/// la del intérprete.
///
/// `set --` fija los parámetros posicionales con lo que el shell haya
/// parseado; `$#` dice cuántos quedaron y `$1` es el primero. Si la cita está
/// rota, el shell falla al parsear y el código de salida no es cero.
Future<({int codigo, String cuantos, String primero})> _segunElShell(
  String linea,
) async {
  final guion = 'set -- $linea\necho "\$#"\nprintf %s "\$1"';
  final r = await Process.run('/bin/sh', ['-c', guion]);
  final salida = r.stdout as String;
  final corte = salida.indexOf('\n');
  return (
    codigo: r.exitCode,
    cuantos: corte < 0 ? '' : salida.substring(0, corte),
    primero: corte < 0 ? '' : salida.substring(corte + 1),
  );
}

/// Las pruebas del citado para el shell, juntas y llamadas desde `main`.
///
/// Viven agrupadas en su propia función porque miden una cosa sola —que lo
/// que se le recomienda pegar en una terminal se parsee como lo que dice—, y
/// porque la del comando entero necesita el mismo ayudante que la de los
/// caracteres sueltos.
void _pruebasDelCitado() {
  group('citar para el shell', () {
    // **Los seis caracteres que la revisión humana pidió medir, uno por
    // caso.** Van como casos separados y no como una sola cadena con todos
    // adentro porque, juntos, un solo fallo no dice cuál de los seis lo
    // causó — y el apóstrofo es el único que ROMPE la cita, así que
    // esconderlo entre otros cinco es perder la distinción entre «se cita
    // mal» y «se cita mal justo lo que importa».
    const casos = {
      'el apóstrofo, que es el que cierra la cita': "it's.txt",
      'el espacio': 'ruta con espacio.txt',
      'el salto de línea': 'ruta\ncon salto.txt',
      'el dólar': r'$HOME.txt',
      'la comilla doble': 'ruta"con comilla.txt',
      'la barra invertida': r'ruta\con barra.txt',
      'el cierre de cita con un comando pegado detrás':
          "x'; touch /tmp/shipflow-inyectado; echo '",
      'la cadena vacía, que sin citar desaparece del comando': '',
    };
    casos.forEach((queCaracter, ruta) {
      test('$queCaracter vuelve como UN argumento igual al original', () async {
        final visto = await _segunElShell(citarParaShell(ruta));
        expect(
          visto.codigo,
          0,
          reason:
              'el shell no pudo ni parsear la línea: con una cita sin cerrar '
              'quien la pega se queda esperando el resto',
        );
        expect(visto.cuantos, '1', reason: 'tiene que ser UN solo argumento');
        expect(visto.primero, ruta);
      });
    });
  });

  group('la reparación del índice se puede pegar en una terminal', () {
    /// El comando que la reparación recomienda, sacado de entre las comillas
    /// invertidas del mensaje. **Se extrae del texto que de verdad se
    /// imprime**, no se vuelve a armar acá: lo que una persona pega es ese
    /// texto, y rearmarlo sería medir otra cosa.
    String comandoDe(String detalle) {
      final abre = detalle.indexOf('`');
      final cierra = detalle.indexOf('`', abre + 1);
      expect(abre, isNonNegative);
      expect(cierra, isNonNegative);
      return detalle.substring(abre + 1, cierra);
    }

    test('una ruta con apóstrofo NO rompe el comando recomendado', () async {
      // **La reproducción del P1-1 de la revisión humana sobre este punto.**
      // `it's.txt` es un nombre de archivo válido; con las rutas envueltas a
      // mano entre apóstrofos, el comando termina con una cita sin cerrar y
      // el shell ni siquiera lo parsea.
      final r = comprobarIndice(
        documento: documentoEn(EstadoDelDocumento.localInconsistent),
        rutasQueDifieren: const ["it's.txt"],
      );
      final comando = comandoDe((r as IndiceNoCoincide).detalle);
      final visto = await _segunElShell(comando);
      expect(
        visto.codigo,
        0,
        reason:
            'el comando que le recomendamos a una persona tiene que poder '
            'parsearse: una cita sin cerrar deja la terminal esperando',
      );
    });

    test('la REVISIÓN también va citada, no solo las rutas', () async {
      // **La frontera del comando tiene dos sitios de interpolación, y uno
      // quedaba sin citar.** El arreglo de verdad es que la revisión no pueda
      // ser otra cosa que un OID completo, y eso se rechaza al leer el
      // documento. Esto es lo otro: que la regla de armar un comando
      // recomendado sea TOTAL —todo argumento pasa por `citarParaShell`— y no
      // caso por caso. «Éste no hace falta porque lo valida otro» es
      // exactamente la clase de acoplamiento que se rompe el día que el otro
      // cambia, y acá el precio de romperse es un comando que una persona
      // pega en su terminal porque se lo recomendamos nosotros.
      //
      // El documento se construye en memoria: quien valida es la lectura de
      // JSON, así que ésta es la puerta que esa validación NO cubre.
      final hostil =
          DocumentoDeCorrida.preparado(
            revision:
                "x'; touch /tmp/shipflow-inyectado-por-la-revision; echo '",
            draft: _draftDePrueba(branch: ramaDeLosDocumentosDePrueba),
            destino: destinoDeLosDocumentosDePrueba,
          ).avanzarA(
            EstadoDelDocumento.localInconsistent,
            desenlace: ShipOutcome.localInconsistenteParaLaPrueba(
              revision: 'a' * 40,
            ),
          );
      final r = comprobarIndice(
        documento: hostil,
        rutasQueDifieren: const ['a.txt'],
      );
      final comando = comandoDe((r as IndiceNoCoincide).detalle);
      final guion = 'set -- $comando\nfor a in "\$@"; do echo "[\$a]"; done';
      final visto = await Process.run('/bin/sh', ['-c', guion]);
      expect(visto.exitCode, 0);
      final argumentos = (visto.stdout as String).trim().split('\n');
      expect(
        argumentos,
        contains("[x'; touch /tmp/shipflow-inyectado-por-la-revision; echo ']"),
        reason:
            'la revisión tiene que llegar entera y como UN argumento: sin '
            'citar, cierra la cita y el resto se ejecuta',
      );
      expect(
        File('/tmp/shipflow-inyectado-por-la-revision').existsSync(),
        isFalse,
        reason: 'y nada de eso llegó a correr',
      );
    });

    test('la ruta llega a `git` como UN pathspec, y es la misma', () async {
      final r = comprobarIndice(
        documento: documentoEn(EstadoDelDocumento.localInconsistent),
        rutasQueDifieren: const ["it's.txt", 'con espacio.txt'],
      );
      final comando = comandoDe((r as IndiceNoCoincide).detalle);
      // Lo que el shell ve como argumentos del comando entero: `git`, `reset`,
      // la revisión, `--` y una entrada por ruta. Si la cita fallara, las
      // rutas se partirían o se pegarían entre sí.
      final guion = 'set -- $comando\nfor a in "\$@"; do echo "[\$a]"; done';
      final visto = await Process.run('/bin/sh', ['-c', guion]);
      expect(visto.exitCode, 0);
      final argumentos = (visto.stdout as String).trim().split('\n');
      expect(argumentos.first, '[git]');
      expect(
        argumentos.sublist(argumentos.length - 2),
        ["[it's.txt]", '[con espacio.txt]'],
        reason:
            'las dos rutas tienen que llegar enteras y una por argumento: '
            'partidas, `git` recibe pathspecs que no existen y sale con cero '
            'sin reparar nada',
      );
    });
  });
}
