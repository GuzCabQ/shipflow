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
DocumentoDeCorrida documentoPreparado({
  required String base,
  required String revision,
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
}
