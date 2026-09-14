/// La derivación de la superficie, motivo por motivo.
///
/// **Tres entradas, no una.** El desenlace del entorno y las alteraciones del
/// candidato son hechos que la cascada no conoce, y los dos pueden vaciar
/// «cubierto» entero. Derivar solo de la cascada publicaba afirmaciones sobre
/// un árbol que había dejado de ser el que se fijó.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

// El doble de observador de la suite de la cascada. Se reusa en vez de
// duplicarlo: el caso de «una cascada sin verificadores» tiene que correr la
// cascada DE VERDAD —`cascada: null` es otro camino— y para eso hace falta un
// `ScopeObserver`, que este paquete no puede tomar de ningún plugin.
import 'cascada_test.dart' show ObservadorDeAlcanceFalso;

final _afirmacion = Afirmacion(
  id: 'ctrl.limpio',
  demuestra: 'que la herramienta no encontró nada',
  noDemuestra: 'comportamiento',
);

class _Control implements Verifier {
  @override
  final String id;
  @override
  Afirmacion get afirmacion => _afirmacion;
  _Control(this.id);
  @override
  Future<VerificationOutcome> run(VerificationScope alcance) =>
      throw UnsupportedError('doble');
}

Witness _testigo(List<String> sujetos, {List<Omission> omite = const []}) =>
    Witness(
      invocation: 'herramienta --sobre ${sujetos.join(" ")}',
      subjects: sujetos,
      exitCode: 0,
      finishedAt: DateTime.utc(2026),
      omitted: omite,
    );

ScopeObservation _observacion(List<String> sujetos) => ScopeObservation(
  requested: sujetos,
  observed: [
    for (final s in sujetos)
      ObservedSubject(subject: s, ofStack: true, files: 1),
  ],
  unobserved: const [],
  observedAt: DateTime.utc(2026),
);

ResultadoDeCascada _cascada(
  Map<String, StepOutcome> desenlaces,
  List<String> sujetos,
) => ResultadoDeCascada(
  registrados: [
    for (final id in desenlaces.keys)
      RegisteredStep(id: id, expectedScope: sujetos),
  ],
  alcance: _observacion(sujetos),
  desenlaces: desenlaces,
);

/// Como [_cascada], pero con una [ScopeObservation] propia en vez de una
/// donde todo sujeto es del stack: es lo que hace falta para reproducir un
/// alcance mixto —un sujeto usable y uno ajeno, o uno usable y uno no
/// observable— que `Cascada.correr` nunca produce de por sí, pero que un
/// `ResultadoDeCascada` armado a mano sí puede representar.
ResultadoDeCascada _cascadaConAlcance(
  Map<String, StepOutcome> desenlaces,
  ScopeObservation alcance,
) => ResultadoDeCascada(
  registrados: [
    for (final id in desenlaces.keys)
      RegisteredStep(id: id, expectedScope: alcance.usable()),
  ],
  alcance: alcance,
  desenlaces: desenlaces,
);

final _entornoOk = EntornoDerivado(
  paquetes: 3,
  raices: 1,
  toolchain: IdentidadDeToolchain(
    version: QuotedText('SDK 3.12.0', source: 'toolchain'),
  ),
);

void main() {
  test('un control limpio cubre sus sujetos', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada(
        {
          'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
        },
        ['lib'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto.single.sujeto, 'lib');
    expect(s.cubierto.single.afirmacion.id, 'ctrl.limpio');
    expect(s.requiereCriterio, isEmpty);
    expect(s.estado, EstadoDeCorrida.verde);
  });

  test('un control ROJO no cubre ninguno de sus sujetos', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada(
        {
          'ctrl': Executed(
            witness: _testigo(['lib', 'bin']),
            diagnostics: [
              Diagnostic(
                file: 'lib/a.fuente',
                severity: Severity.bloquea,
                ruleId: 'r',
                message: const QuotedText('algo', source: 'herramienta'),
              ),
            ],
          ),
        },
        ['lib', 'bin'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto, isEmpty);
    expect(s.requiereCriterio.map((e) => e.motivo).toSet(), {
      MotivoDeCriterio.hallazgo,
    });
    expect(
      s.requiereCriterio.map((e) => e.sujeto),
      containsAll(['lib', 'bin']),
    );
    expect(s.estado, EstadoDeCorrida.rojo);
  });

  test('un control con un diagnóstico QUE SOLO REPORTA no cubre nada', () {
    // El crítico de la revisión final. `Executed.verdict` solo mira los
    // bloqueantes, así que un paso con un diagnóstico informativo salía verde
    // y la superficie publicaba «estado verde, cubierto 1, criterio 0» para
    // una corrida donde el arnés SÍ había encontrado algo. Es alcanzable
    // desde una corrida real: el normalizador del analizador mapea los
    // informativos a `Severity.reporta`.
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada(
        {
          'ctrl': Executed(
            witness: _testigo(['lib', 'bin']),
            diagnostics: [
              Diagnostic(
                file: 'lib/a.fuente',
                severity: Severity.reporta,
                ruleId: 'r',
                message: const QuotedText('algo menor', source: 'herramienta'),
              ),
            ],
          ),
        },
        ['lib', 'bin'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(
      s.cubierto,
      isEmpty,
      reason: 'el veredicto no ve el informativo, pero la superficie sí',
    );
    expect(s.requiereCriterio.map((e) => e.motivo).toSet(), {
      MotivoDeCriterio.hallazgo,
    });
    expect(
      s.requiereCriterio.map((e) => e.sujeto),
      containsAll(['lib', 'bin']),
      reason: 'todos sus sujetos, porque no se sabe cuál lo originó',
    );
    expect(
      s.estado,
      EstadoDeCorrida.verde,
      reason:
          'el estado es el de la cascada y la cascada no lo ve; lo que esta '
          'superficie corrige es la COBERTURA, no el veredicto',
    );
  });

  test('EL ENTORNO NO DERIVADO: sin cascada, y nada cubierto', () {
    // La cascada nunca corrió, así que no hay resultado del cual derivar. El
    // hecho se nombra en vez de faltar.
    final s = derivarSuperficie(
      entorno: CandidatoRechazado(
        causa: CausaDeRechazo.pubRechazoLaResolucion,
        evidencia: const QuotedText(
          'sin archivo de bloqueo',
          source: 'resolver',
        ),
      ),
      alteraciones: const [],
      cascada: null,
      controles: const {},
    );
    expect(s.cubierto, isEmpty);
    expect(
      s.requiereCriterio.single.motivo,
      MotivoDeCriterio.entornoNoDerivado,
    );
    expect(
      s.requiereCriterio.single.detalle,
      contains('sin archivo de bloqueo'),
    );
    expect(s.estado, EstadoDeCorrida.noConcluyente);
  });

  test(
    'UN ENTORNO NO DERIVADO CON CASCADA NO NULA hace fallar la derivación',
    () {
      // Sin entorno derivado la cascada no pudo correr: una `cascada` no nula
      // en este camino es una composición contradictoria, del mismo tipo que
      // un paso registrado sin control en el mapa. Antes se descartaba en
      // silencio -el `return` temprano ni siquiera la miraba-.
      expect(
        () => derivarSuperficie(
          entorno: CandidatoRechazado(
            causa: CausaDeRechazo.pubRechazoLaResolucion,
            evidencia: const QuotedText(
              'sin archivo de bloqueo',
              source: 'resolver',
            ),
          ),
          alteraciones: const [],
          cascada: _cascada(
            {
              'ctrl': Executed(
                witness: _testigo(['lib']),
                diagnostics: const [],
              ),
            },
            ['lib'],
          ),
          controles: {'ctrl': _Control('ctrl')},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('no se derivó'),
          ),
        ),
      );
    },
  );

  test('UN CANDIDATO ALTERADO vacía «cubierto», aunque la cascada dé verde', () {
    // El falso verde que la enmienda cierra: la cascada no se entera de que el
    // árbol cambió, y publicar «cubierto» le diría al revisor que se saltee lo
    // que se verificó sobre otro árbol.
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: [
        AlteracionDelCandidato(
          ruta: 'lib/nuevo.fuente',
          tipo: TipoDeAlteracion.agregada,
        ),
      ],
      cascada: _cascada(
        {
          'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
        },
        ['lib'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto, isEmpty, reason: 'la cascada dio verde y no alcanza');
    expect(
      s.requiereCriterio.map((e) => e.motivo),
      contains(MotivoDeCriterio.candidatoAlterado),
    );
    expect(s.estado, EstadoDeCorrida.noConcluyente);
  });

  test('una omisión CON sujeto es declaradoNoMirado; sin sujeto, residuo', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada(
        {
          'ctrl': Executed(
            witness: _testigo(
              ['lib'],
              omite: [
                Omission(subject: 'bin', reason: 'no lo miró'),
                Omission(reason: 'no rastrea descendientes'),
              ],
            ),
            diagnostics: const [],
          ),
        },
        ['lib', 'bin'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    final motivos = {for (final e in s.requiereCriterio) e.motivo};
    expect(motivos, contains(MotivoDeCriterio.declaradoNoMirado));
    expect(motivos, contains(MotivoDeCriterio.residuoGeneral));
    expect(s.cubierto.single.sujeto, 'lib');
  });

  test('una obligación sin saldar es nadieDioCuenta', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada(
        {
          'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
        },
        ['lib', 'bin'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    final abierta = s.requiereCriterio.firstWhere(
      (e) => e.motivo == MotivoDeCriterio.nadieDioCuenta,
    );
    expect(abierta.sujeto, 'bin');
    expect(abierta.controlId, 'ctrl');
  });

  test(
    'un paso abortado es intentoIncompleto, y uno roto instrumentoFallo',
    () {
      final s = derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: const [],
        cascada: _cascada(
          {
            'a': Aborted(
              attempt: Attempt(
                invocation: 'herramienta',
                subjects: const ['lib'],
                termination: Termination.tiempoAgotado,
                exitCode: -1,
                note: 'no llegó',
                finishedAt: DateTime.utc(2026),
              ),
            ),
            'b': Broken(
              component: 'ctrl',
              error: 'reventó',
              context: 'al correr',
            ),
          },
          ['lib'],
        ),
        controles: {'a': _Control('a'), 'b': _Control('b')},
      );
      final motivos = {for (final e in s.requiereCriterio) e.motivo};
      expect(motivos, contains(MotivoDeCriterio.intentoIncompleto));
      expect(motivos, contains(MotivoDeCriterio.instrumentoFallo));
      expect(s.estado, EstadoDeCorrida.errorInterno);
    },
  );

  test('toda entrada de criterio trae detalle, en todos los caminos', () {
    // Una entrada sin detalle no se construye; esta prueba comprueba que
    // NINGÚN camino de la derivación lo deja en blanco, que es distinto.
    for (final s in [
      derivarSuperficie(
        entorno: DerivacionAbortada(
          terminacion: Termination.herramientaAusente,
          causa: CausaDeAborto.laHerramientaNoRespondio,
          evidencia: const QuotedText('no estaba', source: 'x'),
        ),
        alteraciones: const [],
        cascada: null,
        controles: const {},
      ),
      derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: [
          AlteracionDelCandidato(ruta: 'a', tipo: TipoDeAlteracion.borrada),
        ],
        cascada: null,
        controles: const {},
      ),
    ]) {
      expect(s.requiereCriterio, isNotEmpty);
      for (final e in s.requiereCriterio) {
        expect(e.detalle.trim(), isNotEmpty);
      }
    }
  });

  test(
    'un sujeto ajeno al stack junto a uno verde: en criterio, sin tapar el verde',
    () {
      // Con un sujeto usable, `Cascada.correr` nunca produce `Skipped`: el
      // ajeno queda sin nombrar en cualquier desenlace, y antes de este
      // arreglo era invisible —ni cubierto ni en criterio—.
      final alcance = ScopeObservation(
        requested: const ['lib', 'docs'],
        observed: [
          ObservedSubject(subject: 'lib', ofStack: true, files: 1),
          ObservedSubject(
            subject: 'docs',
            ofStack: false,
            files: 0,
            reason: 'no es del stack',
          ),
        ],
        unobserved: const [],
        observedAt: DateTime.utc(2026),
      );
      final s = derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: const [],
        cascada: _cascadaConAlcance({
          'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
        }, alcance),
        controles: {'ctrl': _Control('ctrl')},
      );
      expect(s.cubierto.single.sujeto, 'lib');
      final ajeno = s.requiereCriterio.firstWhere(
        (e) => e.motivo == MotivoDeCriterio.ajenoAlStack,
      );
      expect(ajeno.sujeto, 'docs');
      expect(
        ajeno.controlId,
        isNull,
        reason: 'es un hecho de la corrida, no de un control',
      );
      expect(s.estado, EstadoDeCorrida.verde);
    },
  );

  test(
    'un sujeto no observable junto a uno verde: en criterio, y la derivación no lanza',
    () {
      // Reproduce el crítico: sin leer `cascada.alcance` directamente, este
      // caso dejaba `requiereCriterio` vacío con `cubierto` no vacío y
      // `estado` no verde, y el invariante de `SuperficieDeVerificacion`
      // reventaba con `ArgumentError`.
      final alcance = ScopeObservation(
        requested: const ['lib', 'bin'],
        observed: [ObservedSubject(subject: 'lib', ofStack: true, files: 1)],
        unobserved: [UnobservedSubject(subject: 'bin', cause: 'no existe')],
        observedAt: DateTime.utc(2026),
      );
      final s = derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: const [],
        cascada: _cascadaConAlcance({
          'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
        }, alcance),
        controles: {'ctrl': _Control('ctrl')},
      );
      expect(s.cubierto.single.sujeto, 'lib');
      final noObservable = s.requiereCriterio.firstWhere(
        (e) => e.motivo == MotivoDeCriterio.noSePudoMirar,
      );
      expect(noObservable.sujeto, 'bin');
      expect(noObservable.controlId, isNull);
      expect(noObservable.detalle, contains('no existe'));
      expect(s.estado, EstadoDeCorrida.noConcluyente);
    },
  );

  test('UNA ALTERACIÓN se nombra aunque el entorno no se haya derivado', () {
    // La primera rama devolvía temprano sin leer `alteraciones`, y el hecho
    // más alarmante que una corrida puede producir desaparecía. Vaciar
    // «cubierto» y no nombrar el hecho son cosas distintas: el primer camino
    // ya vaciaba, y por eso el descarte no se notaba.
    final s = derivarSuperficie(
      entorno: CandidatoRechazado(
        causa: CausaDeRechazo.pubRechazoLaResolucion,
        evidencia: const QuotedText('sin archivo de bloqueo', source: 'r'),
      ),
      alteraciones: [
        AlteracionDelCandidato(
          ruta: 'lib/nuevo.fuente',
          tipo: TipoDeAlteracion.agregada,
        ),
      ],
      cascada: null,
      controles: const {},
    );
    expect(s.cubierto, isEmpty);
    final motivos = s.requiereCriterio.map((e) => e.motivo).toList();
    expect(motivos, contains(MotivoDeCriterio.entornoNoDerivado));
    expect(motivos, contains(MotivoDeCriterio.candidatoAlterado));
    final alterada = s.requiereCriterio.firstWhere(
      (e) => e.motivo == MotivoDeCriterio.candidatoAlterado,
    );
    expect(alterada.sujeto, 'lib/nuevo.fuente');
    expect(alterada.detalle, contains('agregada'));
    expect(s.estado, EstadoDeCorrida.noConcluyente);
  });

  test(
    'UN PASO REGISTRADO SIN CONTROL en el mapa hace fallar la derivación',
    () {
      // Se instaló como arreglo de un falso verde: con el id ausente, la rama
      // verde no agregaba nada ni a `cubierto` ni a `requiereCriterio`, y la
      // superficie publicaba «verde, nada cubierto, nada que mirar» para una
      // corrida donde ese control sí había afirmado algo.
      expect(
        () => derivarSuperficie(
          entorno: _entornoOk,
          alteraciones: const [],
          cascada: _cascada(
            {
              'ctrl': Executed(
                witness: _testigo(['lib']),
                diagnostics: const [],
              ),
            },
            ['lib'],
          ),
          controles: const {},
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('está registrado y no tiene control'),
          ),
        ),
      );
    },
  );

  test('UN CONTROL BAJO LA CLAVE DE OTRO hace fallar la derivación', () {
    // `AfirmacionCubierta.desde` lee `control.id`, no la clave del mapa, así
    // que un mapa mal armado le atribuiría a un control la afirmación de
    // otro y ningún otro lado lo cacharía.
    expect(
      () => derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: const [],
        cascada: _cascada(
          {
            'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
          },
          ['lib'],
        ),
        controles: {'ctrl': _Control('otro')},
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          contains('declara el id'),
        ),
      ),
    );
  });

  test(
    'UN HALLAZGO SIN COBERTURA no desaparece: el control se nombra sin sujeto '
    'CON EL CONTENIDO de cada diagnóstico',
    () {
      // Reproduce el caso real del formateador sobre un archivo que no parsea:
      // sale con diagnósticos y sin ningún sujeto formateado. Las entradas de
      // `hallazgo` se emitían dentro del bucle sobre los sujetos del testigo,
      // así que con la cobertura vacía no se emitía NINGUNA: los motivos eran
      // {residuoGeneral, nadieDioCuenta} y los errores detectados se perdían.
      //
      // El arreglo anterior cerró la desaparición y no el vaciamiento: la
      // entrada que quedó solo decía CUÁNTOS diagnósticos hubo
      // (`contains('2 diagnóstico')`), y esa prueba pasaba igual si el
      // mensaje, la regla y la localización de cada uno se perdían. Acá se
      // comprueba que los tres SOBREVIVEN, de los dos diagnósticos.
      final s = derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: const [],
        cascada: _cascada(
          {
            'ctrl': Executed(
              witness: _testigo(
                const [],
                omite: [Omission(reason: 'no se pudo atribuir el faltante')],
              ),
              diagnostics: [
                Diagnostic(
                  file: 'lib/roto.fuente',
                  line: 1,
                  severity: Severity.bloquea,
                  ruleId: 'no-parsea',
                  message: const QuotedText(
                    'Unexpected token (1)',
                    source: 'herram',
                  ),
                ),
                Diagnostic(
                  file: 'lib/otro.fuente',
                  line: 7,
                  severity: Severity.bloquea,
                  ruleId: 'otra-regla',
                  message: const QuotedText(
                    'Unexpected token (2)',
                    source: 'herram',
                  ),
                ),
              ],
            ),
          },
          ['lib'],
        ),
        controles: {'ctrl': _Control('ctrl')},
      );
      expect(s.cubierto, isEmpty, reason: 'no se concede ninguna cobertura');
      final hallazgo = s.requiereCriterio.singleWhere(
        (e) => e.motivo == MotivoDeCriterio.hallazgo,
      );
      expect(hallazgo.controlId, 'ctrl');
      expect(
        hallazgo.sujeto,
        isNull,
        reason: 'el testigo no cubre ninguno: el hecho es del control',
      );
      expect(
        hallazgo.detalle,
        allOf([
          contains('lib/roto.fuente:1'),
          contains('no-parsea'),
          contains('Unexpected token (1)'),
          contains('lib/otro.fuente:7'),
          contains('otra-regla'),
          contains('Unexpected token (2)'),
        ]),
        reason:
            'la localización, la regla y el mensaje de CADA diagnóstico '
            'tienen que sobrevivir, no solo la cuenta',
      );
      expect(s.estado, EstadoDeCorrida.noConcluyente);
    },
  );

  test('UN HALLAZGO CON COBERTURA emite el contenido una sola vez, sin '
      'repetirlo en cada sujeto', () {
    // La otra rama del mismo defecto: con sujetos cubiertos por el
    // testigo, la entrada por sujeto decía «El control encontró algo
    // —bloqueante o no—» sin nombrar un solo diagnóstico. Ahora el hecho
    // se nombra una vez —sin sujeto, con el contenido— y las entradas por
    // sujeto solo dicen que no quedan cubiertas, sin repetir los
    // diagnósticos: repetirlos insinuaría una atribución que no existe.
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada(
        {
          'ctrl': Executed(
            witness: _testigo(['lib', 'bin']),
            diagnostics: [
              Diagnostic(
                file: 'lib/a.fuente',
                line: 3,
                severity: Severity.bloquea,
                ruleId: 'r-1',
                message: const QuotedText('mensaje único', source: 'herram'),
              ),
            ],
          ),
        },
        ['lib', 'bin'],
      ),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto, isEmpty);

    final hallazgos = s.requiereCriterio.where(
      (e) => e.motivo == MotivoDeCriterio.hallazgo,
    );
    // Una sin sujeto, con el contenido, más una por cada sujeto del
    // testigo: tres en total, no una por sujeto que repita el contenido.
    expect(hallazgos, hasLength(3));

    final sinSujeto = hallazgos.singleWhere((e) => e.sujeto == null);
    expect(sinSujeto.controlId, 'ctrl');
    expect(
      sinSujeto.detalle,
      allOf([
        contains('lib/a.fuente:3'),
        contains('r-1'),
        contains('mensaje único'),
      ]),
    );

    final porSujeto = hallazgos.where((e) => e.sujeto != null).toList();
    expect(porSujeto.map((e) => e.sujeto), containsAll(['lib', 'bin']));
    for (final e in porSujeto) {
      expect(
        e.detalle,
        isNot(contains('mensaje único')),
        reason:
            'las entradas por sujeto no repiten los diagnósticos: el '
            'veredicto es global al paso y no se atribuyen a un sujeto',
      );
    }
    expect(s.estado, EstadoDeCorrida.rojo);
  });

  test('UNA ALTERACIÓN no borra el fallo del instrumento, el ajeno ni el no '
      'observable', () {
    // La rama de integridad devolvía temprano sin procesar los desenlaces ni
    // la partición del alcance: con esta misma cascada y sin alteraciones
    // los motivos son cuatro, y con una alteración quedaba solo
    // {candidatoAlterado}. Tres hechos que la alteración no explica
    // desaparecían por haber salido segundos.
    final alcance = ScopeObservation(
      requested: const ['lib', 'docs', 'bin'],
      observed: [
        ObservedSubject(subject: 'lib', ofStack: true, files: 1),
        ObservedSubject(
          subject: 'docs',
          ofStack: false,
          files: 0,
          reason: 'no es del stack',
        ),
      ],
      unobserved: [UnobservedSubject(subject: 'bin', cause: 'no existe')],
      observedAt: DateTime.utc(2026),
    );
    ResultadoDeCascada cascada() => _cascadaConAlcance({
      'roto': Broken(component: 'ctrl', error: 'reventó', context: 'al correr'),
    }, alcance);

    final sinAlteracion = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: cascada(),
      controles: {'roto': _Control('roto')},
    );
    final esperados = {
      MotivoDeCriterio.instrumentoFallo,
      MotivoDeCriterio.ajenoAlStack,
      MotivoDeCriterio.noSePudoMirar,
      MotivoDeCriterio.nadieDioCuenta,
    };
    expect(
      sinAlteracion.requiereCriterio.map((e) => e.motivo).toSet(),
      esperados,
      reason: 'la premisa: sin alteración, los cuatro hechos están',
    );

    final conAlteracion = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: [
        AlteracionDelCandidato(
          ruta: 'lib/nuevo.fuente',
          tipo: TipoDeAlteracion.agregada,
        ),
      ],
      cascada: cascada(),
      controles: {'roto': _Control('roto')},
    );
    expect(
      conAlteracion.requiereCriterio.map((e) => e.motivo).toSet(),
      {...esperados, MotivoDeCriterio.candidatoAlterado},
      reason: 'la alteración AGREGA un hecho; no puede quitar los otros cuatro',
    );
    expect(conAlteracion.cubierto, isEmpty);
    expect(conAlteracion.estado, EstadoDeCorrida.noConcluyente);
  });

  test('UNA CASCADA SIN VERIFICADORES, corrida de verdad, dice por qué no '
      'concluyó', () async {
    // **`Cascada.correr` de verdad, no un `cascada: null`**, que es el otro
    // camino: acá la cascada SÍ existe, observó el alcance y no registró
    // ningún paso. Su causa es `sinVerificadores` y su estado no
    // concluyente; la derivación contemplaba el nulo y no esto, así que
    // publicaba `requiereCriterio` vacío — el estado sin su explicación.
    final resultado = await Cascada(
      const [],
      observador: ObservadorDeAlcanceFalso(
        observados: {
          'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
        },
      ),
    ).correr(['lib']);
    expect(resultado.causas, [CausaNoConcluyente.sinVerificadores]);
    expect(resultado.estado, EstadoDeCorrida.noConcluyente);

    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: resultado,
      controles: const {},
    );
    expect(s.cubierto, isEmpty);
    final entrada = s.requiereCriterio.single;
    expect(entrada.motivo, MotivoDeCriterio.nadieDioCuenta);
    expect(entrada.controlId, isNull);
    expect(
      entrada.detalle,
      contains('lib'),
      reason: 'nombra el alcance que nadie verificó',
    );
    expect(s.estado, EstadoDeCorrida.noConcluyente);
  });

  test('una cascada sin verificadores tampoco descarta lo que se observó del '
      'alcance', () async {
    // La entrada que nombra «ningún control verificó» no reemplaza a las
    // observaciones: un sujeto ajeno al stack en la misma corrida sigue
    // nombrándose, porque es un hecho de la corrida y no de un control.
    final resultado = await Cascada(
      const [],
      observador: ObservadorDeAlcanceFalso(
        observados: {
          'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
          'docs': ObservedSubject(
            subject: 'docs',
            ofStack: false,
            files: 0,
            reason: 'no es del stack',
          ),
        },
      ),
    ).correr(['lib', 'docs']);
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: resultado,
      controles: const {},
    );
    expect(s.requiereCriterio.map((e) => e.motivo).toSet(), {
      MotivoDeCriterio.nadieDioCuenta,
      MotivoDeCriterio.ajenoAlStack,
    });
  });

  test(
    'sin cascada y sin alteraciones: nadie dio cuenta de la corrida entera',
    () {
      // El comentario anterior decía que la rama de integridad salía ANTES de
      // llegar acá y que por eso esta era la única forma de ejercitar el
      // camino. Ya no sale antes: con alteraciones, este mismo camino agrega
      // sus entradas Y sigue diciendo que nadie dio cuenta, porque son hechos
      // distintos. Lo que esta prueba fija es el caso solo, que es donde la
      // entrada tiene que quedar única.
      final s = derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: const [],
        cascada: null,
        controles: const {},
      );
      expect(s.cubierto, isEmpty);
      expect(s.requiereCriterio.single.motivo, MotivoDeCriterio.nadieDioCuenta);
      expect(s.requiereCriterio.single.controlId, isNull);
      expect(s.estado, EstadoDeCorrida.noConcluyente);
    },
  );
}
