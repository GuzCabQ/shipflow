import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('lo utilizable no cabe donde va lo incompleto', () {
    expect(PullRequestOpen(url: 'u'), isA<PublicacionUtilizable>());
    expect(PullRequestMerged(url: 'u'), isA<PublicacionUtilizable>());
    expect(
      PullRequestClosed(url: 'u'),
      isNot(isA<PublicacionUtilizable>()),
      reason: 'cerrado es terminal y NO completo',
    );
  });

  test('la acción siguiente se deriva de la variante y su causa', () {
    expect(
      PushFailed(causa: CausaDePublicacion.red).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PushUnknown(causa: CausaDePublicacion.desconocida).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PushFailed(causa: CausaDePublicacion.permisos).nextAction,
      AccionSiguiente.corregirPermisos,
      reason: 'reintentar no ayuda',
    );
    expect(
      PullRequestFailed(causa: CausaDePublicacion.red).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PullRequestUnknown(causa: CausaDePublicacion.red).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
    expect(
      PullRequestClosed(url: 'u').nextAction,
      AccionSiguiente.entregaNuevaExplicita,
    );
    expect(PullRequestOpen(url: 'u').nextAction, AccionSiguiente.ninguna);
    expect(PullRequestMerged(url: 'u').nextAction, AccionSiguiente.ninguna);
    // El canal inseguro NO se arregla reintentando —la URL sigue siendo la
    // misma— ni corrigiendo permisos: lo que hay que cambiar es lo que está
    // configurado.
    expect(
      PushFailed(causa: CausaDePublicacion.configuracionInsegura).nextAction,
      AccionSiguiente.corregirConfiguracion,
    );
  });

  test('un canal inseguro no es reintentable, y su razón no dice que la '
      'credencial fue rechazada', () {
    // La distinción importa porque el modo de fallo contrario es
    // TRANQUILIZADOR: decir «la credencial no fue aceptada» sobre un token
    // que nunca salió de este proceso le reporta al usuario un problema de
    // su token cuando el problema es de la configuración.
    final r = PushFailed(causa: CausaDePublicacion.configuracionInsegura);
    expect(r.retryable, isFalse);
    expect(r.deliveryStatus, EstadoDeEntrega.incompletaNoReintentable);
    expect(r.safeReason, contains('https'));
    expect(r.safeReason, isNot(contains('no fue aceptada')));
  });

  test('permisos no es reintentable y el cerrado tampoco', () {
    expect(PushFailed(causa: CausaDePublicacion.permisos).retryable, isFalse);
    expect(PullRequestClosed(url: 'u').retryable, isFalse);
    expect(PushFailed(causa: CausaDePublicacion.red).retryable, isTrue);
    expect(PushUnknown(causa: CausaDePublicacion.red).retryable, isTrue);
  });

  test('solo lo utilizable es entrega completa', () {
    expect(PullRequestOpen(url: 'u').deliveryStatus, EstadoDeEntrega.completa);
    expect(
      PullRequestMerged(url: 'u').deliveryStatus,
      EstadoDeEntrega.completa,
    );
    expect(
      PullRequestClosed(url: 'u').deliveryStatus,
      EstadoDeEntrega.incompletaNoReintentable,
    );
    expect(
      PushFailed(causa: CausaDePublicacion.red).deliveryStatus,
      EstadoDeEntrega.incompletaReintentable,
    );
    expect(
      PushFailed(causa: CausaDePublicacion.permisos).deliveryStatus,
      EstadoDeEntrega.incompletaNoReintentable,
    );
  });

  test('la razón segura sale de la causa, no de un texto externo', () {
    for (final c in CausaDePublicacion.values) {
      final razon = PushFailed(causa: c).safeReason;
      expect(razon, isNotEmpty);
      expect(razon.contains('ghp_'), isFalse);
    }
  });

  test('una URL en blanco no identifica ningún PR', () {
    expect(() => PullRequestOpen(url: '  '), throwsArgumentError);
    expect(() => PullRequestClosed(url: ''), throwsArgumentError);
  });

  test('un kind que no nombra ninguna variante lanza', () {
    expect(
      () => PublicationOutcome.fromJson(const {'kind': 'inventado'}),
      throwsFormatException,
    );
  });

  test('cada fromJson rechaza un discriminador ajeno: las SIETE', () {
    // Era una tabla de una fila con nombre de tabla: cubría `PullRequestOpen`
    // y nada más, y `_exigirKind` se llama POR SEPARADO en cada una de las
    // siete `fromJson` — borrarlo de las otras seis no rompía nada. El
    // precio de ese hueco es una variante que se deserializa como otra sin
    // que nada se entere.
    final variantes =
        <String, PublicationOutcome Function(Map<String, Object?>)>{
          'prAbierto': PullRequestOpen.fromJson,
          'prFusionado': PullRequestMerged.fromJson,
          'prCerrado': PullRequestClosed.fromJson,
          'pushFallo': PushFailed.fromJson,
          'pushDesconocido': PushUnknown.fromJson,
          'prFallo': PullRequestFailed.fromJson,
          'prDesconocido': PullRequestUnknown.fromJson,
        };
    expect(
      variantes,
      hasLength(7),
      reason:
          'si nace una octava variante y esta tabla no crece, la tabla '
          'vuelve a prometer «cada fromJson» cubriendo menos',
    );

    for (final entrada in variantes.entries) {
      // Un discriminador que es de OTRA variante, no uno inventado: el caso
      // inventado ya lo cubre la prueba de arriba, y el que de verdad
      // confunde una variante con otra es éste.
      final ajeno = entrada.key == 'prAbierto' ? 'prFusionado' : 'prAbierto';
      // El mismo cuerpo para todas: las que llevan `url` lo encuentran, las
      // que llevan `causa` también, y ninguna falla por un campo faltante
      // antes de llegar a mirar el discriminador —que es lo que se prueba.
      final cuerpo = <String, Object?>{
        'url': 'https://forja/pr/1',
        'causa': CausaDePublicacion.red.name,
      };

      expect(
        () => entrada.value({...cuerpo, 'kind': ajeno}),
        throwsArgumentError,
        reason:
            'la fromJson de «${entrada.key}» aceptó el discriminador '
            '«$ajeno», que es de otra variante',
      );
      // Control positivo, en la misma vuelta: sin esto, una `fromJson` que
      // lanzara SIEMPRE pasaría la aserción de arriba.
      expect(entrada.value({...cuerpo, 'kind': entrada.key}).kind, entrada.key);
    }
  });

  group('el borrador y la solicitud', () {
    ArtefactoDeRevision artefacto({
      required EstadoDeCorrida estado,
      String arbol = 'arbol-1',
    }) => ArtefactoDeRevision(
      superficie: SuperficieDeVerificacion(
        cubierto: const [],
        requiereCriterio: const [],
        estado: estado,
      ),
      candidato: CandidateIdentity(
        contentRevision: arbol,
        baseRevision: 'base-1',
      ),
      intent: 'sostener el arnés',
      plan: null,
      sinPlanPorque: 'no hay elementos de trabajo',
      alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
    );

    PullRequestDraft borrador(EstadoDeCorrida estado) => PullRequestDraft(
      runId: 'corrida-1',
      branch: 'rama',
      base: 'develop',
      artefacto: artefacto(estado: estado),
    );

    test('la intención no se repite: sale del artefacto', () {
      expect(borrador(EstadoDeCorrida.verde).intent, 'sostener el arnés');
    });

    test('el commit tiene que llevar el árbol que vieron los controles', () {
      expect(
        () => PullRequestRequest(
          draft: borrador(EstadoDeCorrida.verde),
          revision: 'commit-1',
          arbolDeLaRevision: 'OTRO-arbol',
        ),
        throwsArgumentError,
        reason: 'si no, el cuerpo afirma sobre contenido que el PR no tiene',
      );
    });

    test('con el árbol correcto, construye', () {
      final s = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: 'commit-1',
        arbolDeLaRevision: 'arbol-1',
      );
      expect(s.revision, 'commit-1');
      expect(s.incompleto, isFalse);
    });

    test('incompleto se deriva del estado, y no hay dónde escribirlo', () {
      for (final estado in EstadoDeCorrida.values) {
        final s = PullRequestRequest(
          draft: borrador(estado),
          revision: 'commit-1',
          arbolDeLaRevision: 'arbol-1',
        );
        expect(s.incompleto, estado != EstadoDeCorrida.verde);
      }
    });

    test('el título se deriva, y cuando está incompleto lo dice', () {
      final verde = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: 'c',
        arbolDeLaRevision: 'arbol-1',
      );
      expect(verde.titulo, 'sostener el arnés');

      final rojo = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.noConcluyente),
        revision: 'c',
        arbolDeLaRevision: 'arbol-1',
      );
      expect(rojo.titulo, startsWith(PullRequestRequest.prefijoIncompleto));
      expect(rojo.titulo, contains('sostener el arnés'));
    });
  });
}
