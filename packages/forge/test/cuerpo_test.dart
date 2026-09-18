/// El render del cuerpo y el título del pull request de GitHub.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

/// La revisión de estas solicitudes. **Un OID completo de verdad**: desde la
/// ronda de revisión del autor, `PullRequestRequest` rechaza cualquier otra
/// cosa, porque una revisión vacía termina en el refspec
/// `:refs/heads/<rama>`, que BORRA la rama del remoto.
const revisionDePrueba = 'a4e66d50d152b67d451a9028fd1cf54c71e18e79';

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
      revision: revisionDePrueba,
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

// Las dos listas vacías a la vez: es la única forma de que el cuerpo muestre
// los DOS textos de lista vacía en la misma corrida, que es lo que hace falta
// para poder decir cuál va bajo qué sección.
PullRequestRequest solicitudSinNadaQueMostrar() =>
    _solicitud(_artefacto(estado: EstadoDeCorrida.verde));

// La entrada CON sujeto va primera en la lista de entrada, a propósito: si
// `_sinSujetoPrimero` devolviera las entradas tal cual —o si invirtiera sus
// dos `where`—, el cuerpo saldría en este mismo orden, y la prueba de abajo
// lo nota. Con la lista ya ordenada «como corresponde», las tres mutaciones
// de `_sinSujetoPrimero` quedarían verdes.
PullRequestRequest solicitudConSujetoYSinSujeto() => _solicitud(
  _artefacto(
    estado: EstadoDeCorrida.noConcluyente,
    requiereCriterio: [
      EntradaDeCriterio(
        controlId: 'formateador',
        sujeto: 'lib/uno',
        motivo: MotivoDeCriterio.declaradoNoMirado,
        detalle: 'El control declaró que no miró este archivo.',
      ),
      EntradaDeCriterio(
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
    // Antes de las DOS secciones, no solo de la que quedó primera. Con la
    // aserción atada a «## Qué quedó cubierto» y el criterio adelante, una
    // advertencia colocada entre las dos secciones habría pasado en verde:
    // la prueba habría seguido midiendo el orden viejo.
    expect(
      cuerpo.indexOf('> [!WARNING]'),
      lessThan(cuerpo.indexOf('## Qué requiere criterio humano')),
    );
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

  test('lo que requiere criterio va ANTES de lo cubierto', () {
    // **Esta prueba exigía lo contrario, y se lo atribuía a ADR-016.** La
    // norma real dice al revés: la propuesta aceptada, §13, «requiere
    // criterio, completo y antes que lo cubierto», y ADR-022 lo dice por el
    // otro lado —lo que requiere criterio no va después de una conclusión
    // tranquilizadora—. Lo que el comentario viejo afirmaba sobre ADR-016 no
    // está en ADR-016: ese ADR regula que la advertencia preceda a lo verde
    // y que lo que requiere criterio salga completo, no este orden.
    //
    // Es el caso exacto que este repositorio persigue: una prueba en verde
    // que PROTEGÍA la violación, con una cita que la hacía parecer
    // deliberada. Invertir las dos llamadas de `cuerpoDeGitHub` no rompía
    // ninguna otra prueba de este archivo; lo único que había que romper
    // para arreglarlo era esta.
    final cuerpo = cuerpoDeGitHub(solicitudConCriterio());
    expect(
      cuerpo.indexOf('## Qué requiere criterio humano'),
      lessThan(cuerpo.indexOf('## Qué quedó cubierto')),
      reason:
          'un revisor que lee primero lo cubierto ya decidió saltar cuando '
          'llega a lo que tendría que mirar él',
    );
  });

  test('cada afirmación cubierta muestra lo que DEMUESTRA y lo que NO', () {
    // El commit que agregó este render se llama «El render de lo cubierto
    // muestra la afirmación, no solo el control», y era exactamente lo que
    // ninguna prueba sostenía: reemplazar el `writeln` por uno que escribiera
    // solo `- **${'\$'}{c.sujeto}**` dejaba la suite en verde. `demuestra` y
    // `noDemuestra` son lo que ADR-016 regula en esta sección —lo que
    // habilita a un revisor a saltar—, así que se afirma sobre la LÍNEA
    // entera y no sobre una palabra suelta.
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    expect(
      cuerpo,
      contains(
        '- **lib** (control `formateador`, afirmación `formato.conforme`): '
        'coincide con la salida del formateador. No demuestra: '
        'comportamiento, lógica ni criterios.',
      ),
    );
  });

  test('el texto de lista vacía de cada sección va bajo SU sección', () {
    // Intercambiar los dos textos de lista vacía es un cambio de dos líneas
    // que ninguna prueba notaba, y el resultado es un cuerpo que, bajo «Qué
    // requiere criterio humano», le dice al revisor que ningún sujeto quedó
    // cubierto. Por eso se afirma sobre el TRAMO de cada sección y no sobre
    // el cuerpo entero: buscar las dos cadenas en el cuerpo completo pasa
    // igual con los textos cambiados de lugar.
    final cuerpo = cuerpoDeGitHub(solicitudSinNadaQueMostrar());
    final inicioCriterio = cuerpo.indexOf('## Qué requiere criterio humano');
    final inicioCubierto = cuerpo.indexOf('## Qué quedó cubierto');
    expect(inicioCriterio, greaterThanOrEqualTo(0));
    expect(
      inicioCubierto,
      greaterThan(inicioCriterio),
      reason: 'el orden lo fija la prueba de arriba: criterio primero',
    );

    final seccionCriterio = cuerpo.substring(inicioCriterio, inicioCubierto);
    final seccionCubierto = cuerpo.substring(inicioCubierto);

    expect(
      seccionCubierto,
      contains('Ningún sujeto quedó cubierto en esta corrida.'),
    );
    expect(
      seccionCriterio,
      contains('Nada quedó pendiente de criterio humano en esta corrida.'),
    );
    expect(
      seccionCubierto,
      isNot(contains('Nada quedó pendiente de criterio humano')),
    );
    expect(seccionCriterio, isNot(contains('Ningún sujeto quedó cubierto')));
  });

  test('la entrada con sujeto lo muestra en el sufijo, y va DESPUÉS de las '
      'que no tienen ninguno', () {
    // Esto no es cobertura suelta. La corrección del hallazgo crítico de la
    // tarea 10 se justifica POR ESCRITO, en el doc comment de
    // `_nombreDeMotivo`: dice que la prosa del motivo no necesita nombrar al
    // sujeto porque «la entrada que sí tiene sujeto ya lo muestra por
    // separado, en el sufijo `— sujeto ...` que arma
    // `_escribirLoQueRequiereCriterio`». Hasta acá ningún fixture construía
    // una `EntradaDeCriterio` con `sujeto:`, así que la justificación de un
    // arreglo crítico se apoyaba en un mecanismo que no probaba nadie.
    final cuerpo = cuerpoDeGitHub(solicitudConSujetoYSinSujeto());

    expect(
      cuerpo,
      contains(
        '- **el control declaró que no lo miró** — sujeto `lib/uno` — '
        'control `formateador`: El control declaró que no miró este archivo.',
      ),
      reason: 'el sufijo del sujeto es lo que sostiene esa justificación',
    );

    final sinSujeto = cuerpo.indexOf('**el entorno no se derivó**');
    final conSujeto = cuerpo.indexOf('**el control declaró que no lo miró**');
    expect(sinSujeto, greaterThanOrEqualTo(0));
    expect(conSujeto, greaterThanOrEqualTo(0));
    expect(
      sinSujeto,
      lessThan(conSujeto),
      reason:
          'las entradas sin sujeto hablan de la corrida entera y preceden a '
          'las que nombran una: la lista de entrada las trae al revés a '
          'propósito, así que si `_sinSujetoPrimero` no reordena —o '
          'reordena al revés— esto tiene que ponerse rojo',
    );
  });

  test('el marcador estable es la última línea y lleva runId y revisión', () {
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    final ultima = cuerpo.trimRight().split('\n').last;
    expect(ultima, startsWith('<!-- shipflow:pr formatVersion=1'));
    expect(ultima, contains('runId=corrida-1'));
    expect(ultima, contains('revision=$revisionDePrueba'));
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
