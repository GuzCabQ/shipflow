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

DocumentoDeCorrida documentoDePrueba() =>
    DocumentoDeCorrida.preparado(revision: 'a' * 40, draft: _draftDePrueba());

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
      ),
      isA<PublicarDirecto>(),
    );
  });

  test('desde una publicación incompleta también', () {
    expect(
      puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.publicationIncomplete),
        ramaActual: ramaDeLosDocumentosDePrueba,
      ),
      isA<PublicarDirecto>(),
    );
  });

  test('desde preparado se reconcilia', () {
    expect(
      puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.prepared),
        ramaActual: ramaDeLosDocumentosDePrueba,
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
        ),
        isA<Reconciliar>(),
      );
    },
  );

  test('una publicación completa NO se reintenta, y lo dice', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.publicationComplete),
      ramaActual: ramaDeLosDocumentosDePrueba,
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
    );
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.ramaDistinta);
    expect(
      p.detalle,
      allOf(contains(ramaDeLosDocumentosDePrueba), contains('otra-rama')),
      reason: 'un mensaje que no nombra las dos ramas no dice qué hacer',
    );
  });

  test('la rama se comprueba ANTES que el estado', () {
    final p = puertaDelReintento(
      documento: documentoEn(EstadoDelDocumento.publicationComplete),
      ramaActual: 'otra-rama',
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
