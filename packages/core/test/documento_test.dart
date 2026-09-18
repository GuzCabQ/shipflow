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
    final noAplicado = preparado().avanzarA(EstadoDelDocumento.notApplied);
    expect(
      () => noAplicado.avanzarA(EstadoDelDocumento.committed),
      throwsStateError,
      reason: 'notApplied es terminal',
    );
  });

  test('el documento vuelve a ser él mismo por JSON', () {
    final ida = preparado().avanzarA(EstadoDelDocumento.committed);
    final vuelta = DocumentoDeCorrida.fromJson(ida.toJson());
    expect(vuelta.toJson(), ida.toJson());
  });

  test('un formatVersion que no conocemos NO se lee', () {
    final json = Map<String, Object?>.from(preparado().toJson())
      ..['formatVersion'] = 99;
    expect(() => DocumentoDeCorrida.fromJson(json), throwsFormatException);
  });
}
