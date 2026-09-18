/// Ida y vuelta con VALORES, no con nombres de campo.
///
/// El verificador de `tool/analisis` compara los nombres de los campos
/// contra las claves del JSON, y declara su residuo: no mira los valores. Un
/// `toJson` que escriba `'path': ''` lo pasa en verde. Esto es ese residuo.
///
/// **Y una lección que costó un sabotaje.** La primera versión de este archivo
/// comparaba `toJson → fromJson → toJson` contra `toJson`. Las dos mitades de
/// esa igualdad salían del mismo `toJson`, así que un campo escrito como
/// constante coincidía consigo mismo y el test pasaba. Era la **clase 1**
/// entera: el instrumento en verde sobre algo que no midió.
///
/// La corrección no es comparar más cosas a mano: es que **la instancia
/// canónica no tenga ningún valor por defecto en ningún campo**. Entonces
/// «ningún valor del JSON es un valor por defecto» se vuelve una aserción
/// derivada, y cualquier campo aplastado a `''`, `0`, `null` o vacío la rompe.
///
/// **Residuo declarado, y es más ancho que cualquier clase de acá abajo.**
/// Casi todas las entradas de `canonicas` arrancan de `unaInstancia.toJson()`,
/// o sea de un objeto YA construido. Un constructor que normalice lo que
/// recibe normaliza las dos mitades de la igualdad por igual, así que este
/// archivo no lo puede ver: el valor sale transformado de la primera
/// serialización y vuelve idéntico. Fue exactamente el falso verde de la
/// ronda 7 con `CandidateIdentity`. Las únicas dos entradas inmunes son las
/// que parten de un JSON escrito a mano —`AfirmacionCubierta` y
/// `CandidateIdentity · hexadecimal en mayúsculas`—; para el resto, la
/// cobertura de esa partición la sostiene hoy una revisión humana. Medido al
/// cerrar la ronda 7: el único constructor de `packages/core/lib/src` que
/// transforma lo que recibe es `PullRequestRequest.revision`, y
/// `PullRequestRequest` no serializa.
///
/// **Y el mismo residuo del otro lado:** la precondición de arriba —ningún
/// valor por defecto— OBLIGA a que todo campo anulable venga con valor en la
/// instancia canónica, así que el lado nulo de esos campos no hace la ida y
/// vuelta nunca. Hoy no se pierde nada —ninguna `fromJson` de `core` tiene un
/// `??` que invente un valor cuando la clave falta—, y `ArtefactoDeRevision`
/// muestra la tensión de frente: su `plan` nulo está declarado como excepción
/// en `rutasExentas`.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Recorre el JSON y devuelve las rutas cuyo valor es un valor por defecto.
List<String> valoresPorDefecto(Object? nodo, [String ruta = '']) {
  if (nodo == null) return [ruta];
  if (nodo is String) return nodo.isEmpty ? [ruta] : const [];
  if (nodo is num) return nodo == 0 ? [ruta] : const [];
  if (nodo is bool) return nodo ? const [] : [ruta];
  if (nodo is List) {
    if (nodo.isEmpty) return [ruta];
    return [
      for (var i = 0; i < nodo.length; i++)
        ...valoresPorDefecto(nodo[i], '$ruta[$i]'),
    ];
  }
  if (nodo is Map) {
    if (nodo.isEmpty) return [ruta];
    return [
      for (final e in nodo.entries)
        ...valoresPorDefecto(
          e.value,
          ruta.isEmpty ? '${e.key}' : '$ruta.${e.key}',
        ),
    ];
  }
  return const [];
}

void main() {
  final cita = QuotedText('texto de afuera', source: 'sistema-externo');

  final criterio = AcceptanceCriterion(
    id: 'AC-1',
    statement: QuotedText(
      'el saldo no puede quedar negativo',
      source: 'ticket',
    ),
    assertionForm: 'forma-de-aserción-7',
  );

  final item = WorkItem(
    id: 'W-1',
    title: QuotedText('título', source: 'ticket'),
    description: QuotedText('descripción larga', source: 'ticket'),
    criteria: [criterio],
    sourceMetadata: {
      'campoDelAdapter': 'valor',
      'anidado': {'a': 1},
    },
  );

  final diagnostico = Diagnostic(
    file: 'lib/algo.fuente',
    line: 42,
    severity: Severity.bloquea,
    ruleId: 'R-9',
    message: QuotedText('mensaje de la herramienta', source: 'analizador'),
    sourceMetadata: {'columna': 7},
  );

  // exitCode 3 y no 0: un cero sería el valor por defecto, y entonces este
  // campo no probaría nada.
  final omision = Omission(
    subject: 'lib/ilegible.fuente',
    reason: 'no se pudo leer',
  );

  final testigo = Witness(
    invocation: 'verificador --sobre lib/',
    subjects: const ['lib/algo.fuente'],
    omitted: [omision],
    exitCode: 3,
    finishedAt: DateTime.utc(2026, 8, 29, 12, 34, 56),
  );

  final intento = Attempt(
    invocation: 'verificador --sobre lib/',
    subjects: const ['lib/algo.fuente'],
    termination: Termination.tiempoAgotado,
    exitCode: 124,
    note: 'se cortó por presupuesto de tiempo',
    finishedAt: DateTime.utc(2026, 8, 29, 12, 34, 56),
  );

  final traza = Trace(
    runId: 'run-1',
    startedAt: DateTime.utc(2026, 8, 29, 12, 0, 0),
    operational: OperationalSurface(
      toolsUsed: ['leer', 'escribir'],
      inputTokens: 1234,
      outputTokens: 567,
      elapsed: Duration(seconds: 89),
    ),
    cognitive: CognitiveSurface(
      available: true,
      decisions: ['eligió el camino corto'],
      planSummary: 'resumen',
    ),
    contextual: ContextualSurface(
      revision: 'abc123',
      filesInContext: ['lib/algo.fuente'],
      dirtyWorktree: true,
    ),
  );

  final regla = Rule(
    id: 'R-1',
    statement: 'no hagas aquello',
    origin: RuleOrigin.derivada,
    loadLevel: LoadLevel.bajoDemanda,
    signalType: SignalType.deterministaSobreElCambio,
    severity: Severity.bloquea,
    layer: ControlLayer.integracionContinua,
    knownEvasions: const ['se lo saltea con una bandera'],
    alternative: 'hacé esto otro',
    prohibitive: true,
  );

  final rebanada = PullRequestSlice(
    id: 'PR-1',
    intent: 'por qué existe',
    files: ['a.txt'],
  );

  final candidato = CandidateIdentity(
    contentRevision: 'arbol-del-candidato',
    baseRevision: 'commit-de-base',
  );

  /// **La partición que la instancia canónica no tocaba.**
  ///
  /// `CandidateIdentity` declara su representación OPACA, y ADR-002 le exige a
  /// todo tipo de puerto ida y vuelta sin pérdida. Durante una ronda el
  /// constructor canonicalizó los dos campos a minúsculas cuando la cadena
  /// tenía 40 o 64 caracteres hexadecimales, y el control quedó VERDE igual:
  /// `'arbol-del-candidato'` no es hexadecimal, así que la instancia canónica
  /// nunca entraba en esa rama. `ABCDEF…` entraba por `fromJson` y `abcdef…`
  /// salía por `toJson`, y nadie lo veía.
  ///
  /// **Y es un MAPA escrito a mano, no `unaInstancia.toJson()`.** Ahí está la
  /// otra mitad de la lección: si el punto de partida sale de un objeto ya
  /// construido, la normalización del constructor ya ocurrió antes de la
  /// primera serialización y la ida y vuelta la confirma en vez de cazarla
  /// —las dos mitades de la igualdad vuelven a salir del mismo lado, que es el
  /// sabotaje que cuenta la cabecera de este archivo—. Partiendo del JSON, la
  /// igualdad exacta que exige el grupo de ADR-002 se pone roja apenas alguien
  /// vuelva a transformar el valor adentro de `CandidateIdentity`.
  const candidatoHexEnMayusculas = {
    'contentRevision': 'ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD',
    'baseRevision':
        'FEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFEDCBAFEDC',
  };

  final noMaterializada = RutaNoMaterializada(
    ruta: 'enlace-que-escapa',
    motivo: MotivoDeNoMaterializacion.enlaceQueNoQuedaAdentro,
    detalle: 'el destino es absoluto',
  );

  final toolchain = IdentidadDeToolchain(
    version: QuotedText('SDK version: 3.12.0 (stable)', source: 'toolchain'),
  );

  final alteracion = AlteracionDelCandidato(
    ruta: 'tool/x/lockfile',
    tipo: TipoDeAlteracion.borrada,
  );

  final derivado = EntornoDerivado(
    paquetes: 9,
    raices: 2,
    toolchain: toolchain,
  );

  final rechazado = CandidatoRechazado(
    causa: CausaDeRechazo.dependenciaPathQueEscapa,
    evidencia: QuotedText('../afuera no queda adentro', source: 'lockfile'),
  );

  final abortada = DerivacionAbortada(
    terminacion: Termination.tiempoAgotado,
    causa: CausaDeAborto.laHerramientaNoRespondio,
    evidencia: QuotedText('presupuesto agotado', source: 'resolver'),
  );

  final afirmacion = Afirmacion(
    id: 'formato.conforme',
    demuestra: 'que coincide con la salida del formateador',
    noDemuestra: 'comportamiento ni criterios',
  );

  final entradaDeCriterio = EntradaDeCriterio(
    controlId: 'FormatCheck',
    sujeto: 'lib/algo.fuente',
    motivo: MotivoDeCriterio.declaradoNoMirado,
    detalle: 'la herramienta no informó este archivo',
  );

  // **El sujeto es uno que el testigo CUBRE.** Decía `'lib'` mientras el
  // testigo certifica `lib/algo.fuente`: el caso canónico de la ida y vuelta
  // era exactamente la contradicción que `fromJson` ahora rechaza, y una
  // revisión lo encontró. Sigue sin ser un valor por defecto, que es lo que
  // este archivo exige de cada campo.
  final afirmacionCubierta = AfirmacionCubierta.fromJson({
    'controlId': 'FormatCheck',
    'sujeto': 'lib/algo.fuente',
    'afirmacion': afirmacion.toJson(),
    'testigo': testigo.toJson(),
  });

  final superficie = SuperficieDeVerificacion(
    cubierto: [afirmacionCubierta],
    requiereCriterio: [entradaDeCriterio],
    estado: EstadoDeCorrida.noConcluyente,
  );

  // **`plan: null`, no `sinPlanPorque: null`.** Los dos son excluyentes por
  // invariante del tipo —ver `ArtefactoDeRevision`—, así que uno de los dos
  // tiene que salir nulo, y `null` es un valor por defecto para la prueba de
  // más abajo. Se resuelve exactamente como ya resuelve `ScopeObservation` su
  // `reason` forzoso: una ruta declarada como excepción, con el motivo al
  // lado (`rutasExentas`, más abajo), en vez de inventar un segundo mecanismo.
  final artefacto = ArtefactoDeRevision(
    superficie: superficie,
    candidato: candidato,
    intent: 'por qué existe esta rebanada',
    plan: null,
    sinPlanPorque: 'el modo solo-PR no tiene tareas',
    alcanceDeLoAfirmado: 'propiedades de herramienta, nada de comportamiento',
  );

  /// Cada entrada: la instancia canónica y cómo se la reconstruye.
  final canonicas =
      <String, (Map<String, Object?>, Object Function(Map<String, Object?>))>{
        'QuotedText': (cita.toJson(), QuotedText.fromJson),
        'Witness': (testigo.toJson(), Witness.fromJson),
        'AcceptanceCriterion': (
          criterio.toJson(),
          AcceptanceCriterion.fromJson,
        ),
        'WorkItem': (item.toJson(), WorkItem.fromJson),
        'ChangeClass': (
          const ChangeClass('clase-opaca').toJson(),
          ChangeClass.fromJson,
        ),
        'Diagnostic': (diagnostico.toJson(), Diagnostic.fromJson),
        'CandidateIdentity': (candidato.toJson(), CandidateIdentity.fromJson),
        'CandidateIdentity · hexadecimal en mayúsculas': (
          candidatoHexEnMayusculas,
          CandidateIdentity.fromJson,
        ),
        'RutaNoMaterializada': (
          noMaterializada.toJson(),
          RutaNoMaterializada.fromJson,
        ),
        'IdentidadDeToolchain': (
          toolchain.toJson(),
          IdentidadDeToolchain.fromJson,
        ),
        'AlteracionDelCandidato': (
          alteracion.toJson(),
          AlteracionDelCandidato.fromJson,
        ),
        'EntornoDerivado': (derivado.toJson(), EntornoDerivado.fromJson),
        'CandidatoRechazado': (rechazado.toJson(), CandidatoRechazado.fromJson),
        'DerivacionAbortada': (abortada.toJson(), DerivacionAbortada.fromJson),
        'Package': (
          Package(name: 'p', path: 'packages/p', dependsOn: ['core']).toJson(),
          Package.fromJson,
        ),
        'PullRequestSlice': (rebanada.toJson(), PullRequestSlice.fromJson),
        'Plan': (
          Plan(
            workItemId: 'W-1',
            files: ['lib/algo.fuente'],
            tests: ['test/algo_prueba.fuente'],
            slices: [rebanada],
          ).toJson(),
          Plan.fromJson,
        ),
        'OperationalSurface': (
          traza.operational.toJson(),
          OperationalSurface.fromJson,
        ),
        'CognitiveSurface': (
          traza.cognitive.toJson(),
          CognitiveSurface.fromJson,
        ),
        'ContextualSurface': (
          traza.contextual.toJson(),
          ContextualSurface.fromJson,
        ),
        'Trace': (traza.toJson(), Trace.fromJson),
        'Finding': (
          Finding(
            sensorId: 'S-1',
            criterionId: 'C-1',
            file: 'lib/algo.fuente',
            line: 9,
            note: cita,
          ).toJson(),
          Finding.fromJson,
        ),
        'Rule': (regla.toJson(), Rule.fromJson),
        'Omission': (omision.toJson(), Omission.fromJson),
        'Attempt': (intento.toJson(), Attempt.fromJson),
        'Executed': (
          Executed(witness: testigo, diagnostics: [diagnostico]).toJson(),
          Executed.fromJson,
        ),
        'Aborted': (Aborted(attempt: intento).toJson(), Aborted.fromJson),
        // **`Skipped` NO entra acá.** `Skipped` ahora rechaza cualquier sujeto
        // que el observador haya declarado del stack (invariante nueva, ver la
        // suite de verificación), así que la única instancia válida de
        // `notOfStack` trae exclusivamente sujetos ajenos — y esos SIEMPRE traen
        // `files: 0` y `ofStack: false` por el invariante de `ObservedSubject`.
        // Ninguna instancia canónica válida puede entonces hacer viajar esos dos
        // campos con un valor no default, así que este check —que exige
        // exactamente eso— no se le puede aplicar. Antes esta entrada usaba una
        // segunda instancia con un sujeto contradictorio (del stack) para
        // esquivarlo; era el síntoma del hallazgo crítico de la ronda 1,
        // convertido en dato de prueba. Ver el caso dedicado más abajo, que hace
        // lo mismo que ya hace `ScopeObservation` con su propio campo forzoso.
        'Unobservable': (
          Unobservable(
            causes: [
              UnobservedSubject(
                subject: 'no/existe',
                cause: 'no existe en el árbol',
              ),
            ],
          ).toJson(),
          Unobservable.fromJson,
        ),
        'Broken': (
          Broken(
            component: 'analizador-x',
            error: 'no se pudo invocar el binario',
            context: 'paso lib/algo.fuente',
          ).toJson(),
          Broken.fromJson,
        ),
        'ObservedSubject · del stack': (
          ObservedSubject(
            subject: 'lib/codigo',
            ofStack: true,
            files: 2,
          ).toJson(),
          ObservedSubject.fromJson,
        ),
        'ObservedSubject · ajeno al stack': (
          ObservedSubject(
            subject: 'lib/ajeno',
            ofStack: false,
            files: 0,
            reason: 'está fuera del stack',
          ).toJson(),
          ObservedSubject.fromJson,
        ),
        'UnobservedSubject': (
          UnobservedSubject(
            subject: 'no/existe',
            cause: 'no existe en el árbol',
          ).toJson(),
          UnobservedSubject.fromJson,
        ),
        // **Lo único que ve un `Verifier`.** Cada campo con un valor
        // distinguible: dos sujetos con nombres distintos entre sí y un conteo
        // que no coincide con la cantidad de sujetos, para que una serialización
        // que confunda «cuántos sujetos» con «cuántos archivos» no cuadre.
        'VerificationScope': (
          VerificationScope(subjects: const ['lib', 'test'], files: 7).toJson(),
          VerificationScope.fromJson,
        ),
        'ScopeObservation · con sujetos del stack': (
          ScopeObservation(
            requested: const ['lib', 'no/existe'],
            observed: [
              ObservedSubject(subject: 'lib', ofStack: true, files: 2),
            ],
            unobserved: [
              UnobservedSubject(
                subject: 'no/existe',
                cause: 'no existe en el árbol',
              ),
            ],
            observedAt: DateTime.utc(2026, 9, 5),
          ).toJson(),
          ScopeObservation.fromJson,
        ),
        'ScopeObservation · con sujetos ajenos': (
          ScopeObservation(
            requested: const ['lib', 'LEEME.md'],
            observed: [
              ObservedSubject(
                subject: 'lib',
                ofStack: false,
                files: 0,
                reason: 'está fuera del stack',
              ),
            ],
            unobserved: [
              UnobservedSubject(
                subject: 'LEEME.md',
                cause: 'no es código fuente',
              ),
            ],
            observedAt: DateTime.utc(2026, 9, 5),
          ).toJson(),
          ScopeObservation.fromJson,
        ),
        'Afirmacion': (afirmacion.toJson(), Afirmacion.fromJson),
        'EntradaDeCriterio': (
          entradaDeCriterio.toJson(),
          EntradaDeCriterio.fromJson,
        ),
        'AfirmacionCubierta': (
          afirmacionCubierta.toJson(),
          AfirmacionCubierta.fromJson,
        ),
        'SuperficieDeVerificacion': (
          superficie.toJson(),
          SuperficieDeVerificacion.fromJson,
        ),
        'ArtefactoDeRevision': (
          artefacto.toJson(),
          ArtefactoDeRevision.fromJson,
        ),
        'PullRequestOpen': (
          PullRequestOpen(url: 'https://forja.ejemplo/o/r/pull/1').toJson(),
          PullRequestOpen.fromJson,
        ),
        'PullRequestMerged': (
          PullRequestMerged(url: 'https://forja.ejemplo/o/r/pull/2').toJson(),
          PullRequestMerged.fromJson,
        ),
        'PullRequestClosed': (
          PullRequestClosed(url: 'https://forja.ejemplo/o/r/pull/3').toJson(),
          PullRequestClosed.fromJson,
        ),
        'PushFailed': (
          PushFailed(causa: CausaDePublicacion.red).toJson(),
          PushFailed.fromJson,
        ),
        'PushUnknown': (
          PushUnknown(causa: CausaDePublicacion.desconocida).toJson(),
          PushUnknown.fromJson,
        ),
        'PullRequestFailed': (
          PullRequestFailed(
            causa: CausaDePublicacion.rechazoDeLaForja,
          ).toJson(),
          PullRequestFailed.fromJson,
        ),
        'PullRequestUnknown': (
          PullRequestUnknown(causa: CausaDePublicacion.autenticacion).toJson(),
          PullRequestUnknown.fromJson,
        ),
      };

  /// Clases cuyos campos son EXCLUYENTES: ninguna instancia puede tenerlos
  /// todos con valor, así que la precondición se cumple **sobre el conjunto**
  /// de sus instancias canónicas y no dentro de una.
  ///
  /// Es una excepción declarada, no un silencio: si mañana alguien agrega un
  /// tercer campo excluyente y no suma su instancia, este check lo caza igual
  /// —el campo nuevo quedaría en su default en TODAS—.
  const excluyentes = {'ObservedSubject', 'ScopeObservation'};

  /// Rutas cuyo valor por defecto en el JSON **es el dato**, no una pérdida
  /// silenciosa: la instancia canónica no puede demostrar lo contrario sin
  /// violar el invariante del tipo que la propia ruta sostiene.
  ///
  /// **Indexado por clase, igual que `excluyentes`.** Una ruta suelta —sin su
  /// clase al lado— eximiría al campo homónimo de cualquier otra clase que lo
  /// llegue a tener, y debilitaría la prueba exactamente para el caso que
  /// existe para cazar: un campo aplastado que coincide consigo mismo sin que
  /// nadie lo note.
  const rutasExentas = {
    'ArtefactoDeRevision': {
      // `plan`: `plan` y `sinPlanPorque` son excluyentes por invariante del
      // tipo —uno de los dos siempre es nulo—, y la instancia canónica elige
      // dejar `sinPlanPorque` con contenido. `plan` nulo acá no es un campo
      // que se perdió en el viaje: es el que el invariante obliga a que
      // falte. `sinPlanPorque` sí queda cubierto por la comprobación
      // general, y demuestra que ese lado del par no viaja aplastado en
      // silencio.
      'plan',
    },
  };

  group('la instancia canónica no trae valores por defecto', () {
    // Es la precondición de todo lo demás. Sin esto, un campo aplastado a `''`
    // o a `0` coincide consigo mismo en la ida y vuelta y no lo nota nadie.
    for (final e in canonicas.entries) {
      final clase = e.key.split(' · ').first;
      if (excluyentes.contains(clase)) continue;
      test(e.key, () {
        final exentas = rutasExentas[clase] ?? const <String>{};
        final enDefecto = valoresPorDefecto(
          e.value.$1,
        ).where((ruta) => !exentas.contains(ruta)).toList();
        expect(
          enDefecto,
          isEmpty,
          reason:
              'estos campos salen con su valor por defecto, así que no '
              'distinguen «viajó» de «se perdió»',
        );
      });
    }

    for (final clase in excluyentes) {
      test('$clase · entre todas sus instancias', () {
        final instancias = [
          for (final e in canonicas.entries)
            if (e.key.split(' · ').first == clase) e.value.$1,
        ];
        expect(
          instancias,
          hasLength(greaterThan(1)),
          reason:
              'una clase con campos excluyentes necesita más de una '
              'instancia canónica, o la precondición no se puede cumplir',
        );
        final enDefectoEnTodas = valoresPorDefecto(instancias.first)
            .where(
              (ruta) =>
                  instancias.every((i) => valoresPorDefecto(i).contains(ruta)),
            )
            .toList();
        expect(
          enDefectoEnTodas,
          isEmpty,
          reason:
              'estos campos salen con su valor por defecto en TODAS las '
              'instancias, así que no distinguen «viajó» de «se perdió»',
        );
      });
    }
  });

  group('ida y vuelta sin pérdida (ADR-002)', () {
    for (final e in canonicas.entries) {
      test(e.key, () {
        final (original, reconstruir) = e.value;
        final texto = jsonEncode(original);
        final vuelto = reconstruir(jsonDecode(texto) as Map<String, Object?>);
        expect(
          jsonEncode((vuelto as dynamic).toJson()),
          equals(texto),
          reason: 'algún campo de ${e.key} no sobrevivió el viaje',
        );
      });
    }
  });

  test('la escotilla de metadatos transporta sin interpretar (D-015)', () {
    final ida = WorkItem.fromJson(
      jsonDecode(jsonEncode(item.toJson())) as Map<String, Object?>,
    );
    expect(ida.sourceMetadata['anidado'], equals({'a': 1}));
  });

  test('un enum viaja por nombre, no por índice', () {
    // Reordenar un enum no debe cambiar el significado de una traza vieja.
    expect(diagnostico.toJson()['severity'], equals('bloquea'));
  });

  test('la observación de alcance no pierde nada, y no trae vacíos', () {
    final o = ScopeObservation(
      requested: const ['lib', 'no/existe'],
      observed: [ObservedSubject(subject: 'lib', ofStack: true, files: 3)],
      unobserved: [
        UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol'),
      ],
      observedAt: DateTime.utc(2026, 9, 5),
    );
    // `reason` es nulo cuando el sujeto SÍ es del stack, y eso es correcto:
    // se excluye de la comprobación de vacíos porque su ausencia es el dato.
    final json = o.toJson();
    for (final e in json['observed']! as List) {
      (e as Map).remove('reason');
    }
    expect(valoresPorDefecto(json), isEmpty);
    expect(ScopeObservation.fromJson(o.toJson()).toJson(), o.toJson());
  });

  test("'Skipped' no pierde nada, y no trae vacíos que no sean forzosos", () {
    // Mismo caso que el de arriba, para el mismo motivo: `notOfStack` solo
    // admite sujetos ajenos al stack (la invariante que cerró el hallazgo
    // crítico de la ronda 1), y esos siempre traen `files: 0` y
    // `ofStack: false` — no hay ninguna instancia VÁLIDA de `Skipped` que
    // pueda demostrar que esos dos campos no son un valor por defecto
    // aplastado. Se excluyen de la comprobación de vacíos por la misma razón
    // que arriba excluye `reason`, y el round-trip se verifica a mano en vez
    // de por la lista `canonicas`.
    final s = Skipped(
      notOfStack: [
        ObservedSubject(
          subject: 'lib/ajeno-a',
          ofStack: false,
          files: 0,
          reason: 'motivo a',
        ),
        ObservedSubject(
          subject: 'lib/ajeno-b',
          ofStack: false,
          files: 0,
          reason: 'motivo b',
        ),
      ],
    );
    final json = s.toJson();
    for (final e in json['notOfStack']! as List) {
      (e as Map)
        ..remove('files')
        ..remove('ofStack');
    }
    expect(valoresPorDefecto(json), isEmpty);
    expect(Skipped.fromJson(s.toJson()).toJson(), s.toJson());
  });
}
