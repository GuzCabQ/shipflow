/// El render del cuerpo y el título del pull request de GitHub.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

/// Un control que solo declara: no ejecuta. Igual que en la suite de la
/// superficie de verificación, en `core` — la fábrica de [AfirmacionCubierta]
/// recibe el desenlace ya producido, así que `run` no hace falta para estas
/// pruebas.
class _ControlDeclarado implements Verifier {
  @override
  final String id;
  @override
  final Afirmacion afirmacion;

  _ControlDeclarado(this.id, this.afirmacion);

  @override
  Future<VerificationOutcome> run(VerificationScope alcance) =>
      throw UnsupportedError('este doble solo declara');
}

AfirmacionCubierta _cubierta(String sujeto) {
  final afirmacion = Afirmacion(
    id: 'formato.conforme',
    demuestra: 'coincide con la salida del formateador',
    noDemuestra: 'comportamiento, lógica ni criterios',
  );
  final desenlace = Executed(
    witness: Witness(
      invocation: 'herramienta --sobre $sujeto',
      subjects: [sujeto],
      exitCode: 0,
      finishedAt: DateTime.utc(2026),
      omitted: const [],
    ),
    diagnostics: const [],
  );
  return AfirmacionCubierta.desde(
    control: _ControlDeclarado('formateador', afirmacion),
    desenlace: desenlace,
    sujeto: sujeto,
  )!;
}

ArtefactoDeRevision _artefacto({
  required EstadoDeCorrida estado,
  List<AfirmacionCubierta> cubierto = const [],
  List<EntradaDeCriterio> requiereCriterio = const [],
  String intent = 'probar el render del cuerpo del PR',
  String? plan,
}) => ArtefactoDeRevision(
  superficie: SuperficieDeVerificacion(
    cubierto: cubierto,
    requiereCriterio: requiereCriterio,
    estado: estado,
  ),
  candidato: CandidateIdentity(
    contentRevision: 'arbol-1',
    baseRevision: 'base-1',
  ),
  intent: intent,
  plan: plan,
  sinPlanPorque: plan == null ? 'no hay elementos de trabajo' : null,
  alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
);

PullRequestRequest _solicitud(ArtefactoDeRevision artefacto) =>
    PullRequestRequest(
      draft: PullRequestDraft(
        runId: 'corrida-1',
        branch: 'rama-1',
        base: 'main',
        artefacto: artefacto,
      ),
      revision: 'commit-1',
      arbolDeLaRevision: 'arbol-1',
    );

PullRequestRequest solicitudVerde() => _solicitud(
  _artefacto(estado: EstadoDeCorrida.verde, cubierto: [_cubierta('lib')]),
);

PullRequestRequest solicitudIncompleta() => _solicitud(
  _artefacto(
    estado: EstadoDeCorrida.noConcluyente,
    requiereCriterio: [
      EntradaDeCriterio(
        motivo: MotivoDeCriterio.entornoNoDerivado,
        detalle: 'El entorno no se derivó, así que la cascada nunca corrió.',
      ),
    ],
  ),
);

// Dos entradas sin sujeto, cada una con un motivo distinto, para que la
// prueba pueda pedir el `detalle` de las dos sin ambigüedad sobre cuál
// entrada lo trae.
PullRequestRequest solicitudConCriterio() => _solicitud(
  _artefacto(
    estado: EstadoDeCorrida.noConcluyente,
    requiereCriterio: [
      EntradaDeCriterio(
        motivo: MotivoDeCriterio.nadieDioCuenta,
        detalle:
            'La cascada corrió sin cascada registrada: ningún control tomó '
            'este sujeto.',
      ),
      EntradaDeCriterio(
        controlId: 'entorno',
        motivo: MotivoDeCriterio.entornoNoDerivado,
        detalle: 'El entorno no se derivó, así que la cascada nunca corrió.',
      ),
    ],
  ),
);

PullRequestRequest solicitudIncompletaConIntencionLarga() => _solicitud(
  _artefacto(
    estado: EstadoDeCorrida.noConcluyente,
    intent: 'x' * 400,
    requiereCriterio: [
      EntradaDeCriterio(
        motivo: MotivoDeCriterio.entornoNoDerivado,
        detalle: 'El entorno no se derivó.',
      ),
    ],
  ),
);

void main() {
  test('el alcance va textual y la advertencia va antes de lo verde', () {
    final cuerpo = cuerpoDeGitHub(solicitudIncompleta());
    expect(cuerpo, contains(ArtefactoDeRevision.alcanceSoloPR));
    expect(cuerpo, contains('> [!WARNING]'));
    expect(
      cuerpo.indexOf('> [!WARNING]'),
      lessThan(cuerpo.indexOf('## Qué quedó cubierto')),
    );
  });

  test('sin advertencia cuando la superficie está verde', () {
    expect(cuerpoDeGitHub(solicitudVerde()), isNot(contains('[!WARNING]')));
  });

  test('cada entrada que requiere criterio aparece con su motivo', () {
    final cuerpo = cuerpoDeGitHub(solicitudConCriterio());
    expect(cuerpo, contains('sin cascada'));
    expect(cuerpo, contains('el entorno no se derivó'));
  });

  test('el motivo «nadie dio cuenta» no le agrega un sujeto que no tiene', () {
    // Ronda de arreglo 1: la entrada de `solicitudConCriterio()` con este
    // motivo se construye SIN sujeto —tal como dos de los tres hechos que
    // agrupa `MotivoDeCriterio.nadieDioCuenta` no lo tienen—, así que la
    // prosa del motivo no puede decir «de este sujeto»: sería afirmar que
    // el fallo es acotado cuando el propio caso de esta prueba demuestra
    // que es de la corrida entera. Es una prueba sobre la PROSA del
    // motivo, no sobre el `detalle` — la anterior podía pasar aunque la
    // prosa mintiera, porque el `detalle` de la prueba de arriba también
    // contiene las mismas palabras clave por su cuenta.
    final cuerpo = cuerpoDeGitHub(solicitudConCriterio());
    expect(cuerpo, contains('**nadie dio cuenta**'));
    expect(cuerpo, isNot(contains('nadie dio cuenta de')));
  });

  test('lo cubierto va antes de lo que requiere criterio', () {
    // ADR-016 regula este orden puntual, no solo que la advertencia preceda
    // a lo verde: invertir las dos llamadas dentro de `cuerpoDeGitHub` es un
    // cambio de una línea que ninguna otra prueba de este archivo detecta.
    final cuerpo = cuerpoDeGitHub(solicitudConCriterio());
    expect(
      cuerpo.indexOf('## Qué quedó cubierto'),
      lessThan(cuerpo.indexOf('## Qué requiere criterio humano')),
    );
  });

  test('el marcador estable es la última línea y lleva runId y revisión', () {
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    final ultima = cuerpo.trimRight().split('\n').last;
    expect(ultima, startsWith('<!-- shipflow:pr formatVersion=1'));
    expect(ultima, contains('runId=corrida-1'));
    expect(ultima, contains('revision=commit-1'));
  });

  test('no filtra nada local', () {
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    expect(cuerpo, isNot(contains(Directory.systemTemp.path)));
    expect(cuerpo.toLowerCase(), isNot(contains('excludedlocalchanges')));
  });

  test(
    'el título sale de la solicitud y se trunca sin comerse la advertencia',
    () {
      final larga = solicitudIncompletaConIntencionLarga();
      final titulo = tituloDeGitHub(larga);
      expect(titulo.length, lessThanOrEqualTo(256));
      expect(titulo, startsWith(PullRequestRequest.prefijoIncompleto));
    },
  );

  test(
    'la intención completa está en el cuerpo aunque el título se trunque',
    () {
      // El JSON de la corrida es local y `git` lo ignora: el cuerpo del PR
      // es la única superficie donde un revisor remoto puede leer algo que
      // no entró en el título. Sin esto, una intención larga se perdía a
      // mitad de camino y no había dónde leerla entera.
      final larga = solicitudIncompletaConIntencionLarga();
      final intencionCompleta = 'x' * 400;
      expect(
        tituloDeGitHub(larga).length,
        lessThan(intencionCompleta.length),
        reason: 'esta prueba solo tiene sentido si el título SÍ se trunca',
      );
      expect(cuerpoDeGitHub(larga), contains(intencionCompleta));
    },
  );
}
