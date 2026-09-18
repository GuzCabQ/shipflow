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
    // Una revisión que no es un OID tampoco se arregla reintentando: el
    // mismo valor vuelve a no serlo. `retryable` ya estaba fijado por la
    // prueba de abajo, pero la ACCIÓN —lo único que este desenlace le dice a
    // quien lo recibe sobre qué hacer— no la fijaba nada, a diferencia de su
    // hermana de arriba.
    expect(
      PushFailed(causa: CausaDePublicacion.revisionInvalida).nextAction,
      AccionSiguiente.corregirConfiguracion,
    );
    // Y no poder lanzar el programa SÍ se reintenta: un `fork` que falló por
    // recursos puede andar en el próximo intento.
    expect(
      PushFailed(causa: CausaDePublicacion.noSePudoLanzar).nextAction,
      AccionSiguiente.reintentarPublicacion,
    );
  });

  test('no poder lanzar el programa no se reporta como causa desconocida', () {
    // La causa existe para no decirle «no se pudo determinar la causa» a
    // alguien que no tiene el programa en el `PATH`: eso es falso y no deja
    // nada que mirar. Y su razón no nombra el programa —llega por
    // configuración y esta cadena se publica—, ni deja de ser reintentable.
    final r = PushFailed(causa: CausaDePublicacion.noSePudoLanzar);
    expect(r.retryable, isTrue);
    expect(r.safeReason, isNot(contains('no se pudo determinar')));
    expect(r.safeReason, contains('lanzar'));
    expect(r.deliveryStatus, EstadoDeEntrega.incompletaReintentable);
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
    expect(
      PushFailed(causa: CausaDePublicacion.revisionInvalida).retryable,
      isFalse,
      reason: 'la misma revisión vuelve a no ser un OID la próxima vez',
    );
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
    // OIDs de verdad, no cadenas con forma de nombre. Salen de dos
    // repositorios recién creados y medidos: `git init --object-format=sha1`
    // da 40 caracteres hexadecimales, `--object-format=sha256` da 64.
    const oidSha1 = 'a4e66d50d152b67d451a9028fd1cf54c71e18e79';
    const oidSha256 =
        'b9050a8da2fe144803f3f92b87ce78319d12e16999cd6976c6b047a5b77e0d83';

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
          revision: oidSha1,
          arbolDeLaRevision: 'OTRO-arbol',
        ),
        throwsArgumentError,
        reason: 'si no, el cuerpo afirma sobre contenido que el PR no tiene',
      );
    });

    test('el árbol escrito en otra caja es el MISMO árbol, y construye', () {
      // **El hallazgo de la ronda 6.** La ronda anterior canonicalizó la
      // revisión y dejó esta guarda, dos líneas más abajo, comparando literal
      // entre dos OIDs. Con el árbol del commit escrito en mayúsculas y el
      // `contentRevision` del candidato en minúsculas —el mismo árbol— el
      // constructor lanzaba afirmando que el commit lleva un árbol que los
      // controles no vieron. Es falso, y corta la publicación entera.
      final arbolEnMinuscula = oidSha1;
      final arbolEnMayuscula = oidSha1.toUpperCase();

      // El candidato en minúscula, el parámetro en mayúscula…
      expect(
        PullRequestRequest(
          draft: PullRequestDraft(
            runId: 'corrida-1',
            branch: 'rama',
            base: 'develop',
            artefacto: artefacto(
              estado: EstadoDeCorrida.verde,
              arbol: arbolEnMinuscula,
            ),
          ),
          revision: oidSha256,
          arbolDeLaRevision: arbolEnMayuscula,
        ).revision,
        oidSha256,
      );

      // …y al revés, que es el caso que una canonicalización puesta en un solo
      // lado dejaría roto.
      expect(
        PullRequestRequest(
          draft: PullRequestDraft(
            runId: 'corrida-1',
            branch: 'rama',
            base: 'develop',
            artefacto: artefacto(
              estado: EstadoDeCorrida.verde,
              arbol: arbolEnMayuscula,
            ),
          ),
          revision: oidSha256,
          arbolDeLaRevision: arbolEnMinuscula,
        ).revision,
        oidSha256,
      );
    });

    test('dos árboles DISTINTOS siguen sin construir, y una identidad opaca '
        'conserva su caja', () {
      // Los dos controles negativos de la canonicalización del árbol.
      //
      // Uno: dos OIDs distintos siguen siendo distintos — sin esto, una
      // comparación que devolviera «iguales» siempre pasaría la prueba de
      // arriba y borraría la guarda entera.
      expect(
        () => PullRequestRequest(
          draft: borrador(EstadoDeCorrida.verde),
          revision: oidSha1,
          arbolDeLaRevision: oidSha256,
        ),
        throwsArgumentError,
      );

      // Dos: `CandidateIdentity` declara su representación OPACA, y un doble
      // puede identificar el contenido con una cadena donde la caja signifique
      // algo. `canonicalizarOid` solo toca lo que ES un OID completo, así que
      // «arbol-A» y «arbol-a» siguen siendo dos identidades distintas.
      expect(
        () => PullRequestRequest(
          draft: PullRequestDraft(
            runId: 'corrida-1',
            branch: 'rama',
            base: 'develop',
            artefacto: artefacto(
              estado: EstadoDeCorrida.verde,
              arbol: 'arbol-A',
            ),
          ),
          revision: oidSha1,
          arbolDeLaRevision: 'arbol-a',
        ),
        throwsArgumentError,
        reason:
            'bajar de caja a ciegas fundiría dos identidades opacas distintas '
            'en una',
      );
      expect(
        CandidateIdentity(
          contentRevision: 'arbol-A',
          baseRevision: 'base-B',
        ).contentRevision,
        'arbol-A',
        reason: 'lo que no es un OID vuelve intacto',
      );
      expect(
        CandidateIdentity(
          contentRevision: oidSha1.toUpperCase(),
          baseRevision: oidSha256.toUpperCase(),
        ).contentRevision,
        oidSha1,
        reason: 'lo que sí es un OID queda en la forma canónica',
      );
    });

    test('un runId que rompe el marcador no construye el borrador', () {
      // **El marcador estable es un comentario HTML Y la clave de la búsqueda
      // idempotente.** Un `-->` en el runId lo cierra antes de tiempo: lo que
      // siga queda escrito al pie del cuerpo del pull request como si lo
      // afirmara la corrida, y puede abrir otro `<!--` que se trague el resto.
      // Un salto de línea parte el marcador en dos, y como la búsqueda es
      // `contains` sobre el cuerpo que devuelve la forja —que vuelve con
      // `\r\n`—, ese marcador no se encuentra nunca: el reintento abre un
      // SEGUNDO pull request.
      //
      // Se rechaza en la frontera y no se escapa en el render porque adentro
      // de un comentario HTML las entidades no se decodifican: escapar sería
      // cambiar la clave de búsqueda, y los pull requests ya abiertos dejarían
      // de coincidir.
      for (final hostil in <String>[
        'corrida--> ¡verificación completa! <!--',
        '-->',
        '<!--',
        'corrida\n1',
        'corrida\r\n1',
      ]) {
        expect(
          () => PullRequestDraft(
            runId: hostil,
            branch: 'rama',
            base: 'develop',
            artefacto: artefacto(estado: EstadoDeCorrida.verde),
          ),
          throwsArgumentError,
          reason: 'se aceptó «$hostil» como runId',
        );
      }
    });

    test('un runId de los que este árbol produce sigue construyendo', () {
      // El control negativo: una guarda que rechazara cualquier cosa pasaría
      // la prueba de arriba y rompería toda corrida. La forma es la que
      // produce el generador del comando —microsegundos, un guion y un
      // contador—, escrita acá porque `core` no ve a `cli`; la prueba de que
      // el generador produce esa forma vive en la suite de `cli`.
      expect(
        PullRequestDraft(
          runId: '1789456321987654-3',
          branch: 'rama',
          base: 'develop',
          artefacto: artefacto(estado: EstadoDeCorrida.verde),
        ).runId,
        '1789456321987654-3',
      );
    });

    test('con el árbol correcto, construye', () {
      final s = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: oidSha1,
        arbolDeLaRevision: 'arbol-1',
      );
      expect(s.revision, oidSha1);
      expect(s.incompleto, isFalse);
    });

    test('incompleto se deriva del estado, y no hay dónde escribirlo', () {
      for (final estado in EstadoDeCorrida.values) {
        final s = PullRequestRequest(
          draft: borrador(estado),
          revision: oidSha1,
          arbolDeLaRevision: 'arbol-1',
        );
        expect(s.incompleto, estado != EstadoDeCorrida.verde);
      }
    });

    test(
      'una revisión que no es un OID completo no construye la solicitud',
      () {
        // Esto no es higiene de tipos: es lo que separa una publicación de un
        // BORRADO. `EmpujeAislado` arma el refspec
        // `<revisión>:refs/heads/<rama>`, y `:refs/heads/<rama>` es la forma
        // documentada de eliminar esa rama del remoto. El constructor validaba
        // la relación de la revisión con el árbol y no la revisión misma, así
        // que `revision: ''` se construía sin una queja.
        for (final invalida in <String>[
          '',
          '   ',
          'commit-1',
          'HEAD',
          'a4e66d5',
          // 39 y 41: los dos vecinos del largo de SHA-1, para que la prueba
          // falle si alguien escribe `>= 40` o `{40,}`.
          'a4e66d50d152b67d451a9028fd1cf54c71e18e7',
          'a4e66d50d152b67d451a9028fd1cf54c71e18e790',
          // 63 y 65: los dos vecinos del largo de SHA-256.
          'b9050a8da2fe144803f3f92b87ce78319d12e16999cd6976c6b047a5b77e0d8',
          'b9050a8da2fe144803f3f92b87ce78319d12e16999cd6976c6b047a5b77e0d833',
          // Largo correcto, alfabeto equivocado.
          'z4e66d50d152b67d451a9028fd1cf54c71e18e79',
          'a4e66d50d152b67d451a9028fd1cf54c71e18e7 ',
        ]) {
          expect(
            () => PullRequestRequest(
              draft: borrador(EstadoDeCorrida.verde),
              revision: invalida,
              arbolDeLaRevision: 'arbol-1',
            ),
            throwsArgumentError,
            reason: 'se aceptó «$invalida» como revisión de un pull request',
          );
        }
      },
    );

    test('las DOS familias de OID construyen: SHA-1 y SHA-256', () {
      // El control positivo, y no es una formalidad: una validación que
      // conociera solo los 40 caracteres de SHA-1 rechazaría todas las
      // revisiones de un repositorio SHA-256 —un rechazo falso sobre una
      // revisión perfectamente válida—, y la prueba de arriba pasaría igual.
      // Los dos largos están medidos con `git rev-parse HEAD` sobre
      // repositorios creados con cada `--object-format`.
      expect(oidSha1, hasLength(40));
      expect(oidSha256, hasLength(64));
      for (final valida in <String>[
        oidSha1,
        oidSha256,
        // Mayúsculas: medido con `git cat-file -t`, git resuelve el mismo
        // objeto. Rechazarlas sería afirmar que un OID válido no lo es.
        oidSha1.toUpperCase(),
        oidSha256.toUpperCase(),
      ]) {
        expect(esOidCompleto(valida), isTrue, reason: '«$valida» es un OID');
        expect(
          PullRequestRequest(
            draft: borrador(EstadoDeCorrida.verde),
            revision: valida,
            arbolDeLaRevision: 'arbol-1',
          ).revision,
          // **Canonicalizada, y esta aserción decía lo contrario.** Exigía que
          // la revisión saliera tal como entró, o sea que las mayúsculas
          // circularan: y circulando rompieron la búsqueda idempotente del
          // adapter de la forja, que compara literal contra el `sha` que
          // devuelve la forja —siempre en minúsculas— y contra el marcador
          // estable. Reproducido por el autor: solicitud en mayúsculas, pull
          // request existente en minúsculas, y se creaba un SEGUNDO pull
          // request. Aceptar las dos escrituras sigue siendo correcto —git
          // resuelve el mismo objeto—; dejarlas circular no lo era.
          valida.toLowerCase(),
          reason:
              'un OID en mayúsculas se acepta y se guarda en la forma '
              'canónica: una sola escritura río abajo',
        );
      }
    });

    test('un OID en mayúsculas es la MISMA solicitud que el mismo en '
        'minúsculas', () {
      // La prueba del efecto, no de la forma: lo que la canonicalización
      // existe para sostener es que las tres cosas que se derivan de la
      // revisión —la comparación con lo que devuelve la forja, el marcador
      // estable del cuerpo y el refspec del push— no puedan discrepar según
      // cómo alguien haya escrito el OID.
      final mayusculas = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: oidSha1.toUpperCase(),
        arbolDeLaRevision: 'arbol-1',
      );
      final minusculas = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: oidSha1,
        arbolDeLaRevision: 'arbol-1',
      );
      expect(mayusculas.revision, minusculas.revision);
      expect(
        mayusculas.revision,
        isNot(contains(RegExp('[A-F]'))),
        reason: 'la forma canónica es la que imprime git: minúscula',
      );
    });

    test('el título se deriva, y cuando está incompleto lo dice', () {
      final verde = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: oidSha1,
        arbolDeLaRevision: 'arbol-1',
      );
      expect(verde.titulo, 'sostener el arnés');

      final rojo = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.noConcluyente),
        revision: oidSha256,
        arbolDeLaRevision: 'arbol-1',
      );
      expect(rojo.titulo, startsWith(PullRequestRequest.prefijoIncompleto));
      expect(rojo.titulo, contains('sostener el arnés'));
    });
  });
}
