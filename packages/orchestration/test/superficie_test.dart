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
}
