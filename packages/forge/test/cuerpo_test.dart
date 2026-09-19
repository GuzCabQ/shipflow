/// El render del cuerpo y el título del pull request de GitHub.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

/// La revisión de estas solicitudes. **Un OID completo de verdad**: desde la
/// ronda de revisión del autor, `PullRequestRequest` rechaza cualquier otra
/// cosa, porque una revisión vacía termina en el refspec
/// `:refs/heads/<rama>`, que BORRA la rama del remoto.
const revisionDePrueba = 'a4e66d50d152b67d451a9028fd1cf54c71e18e79';

/// El `runId` de estas solicitudes. Antes vivía repetido como literal en
/// [_solicitud] y en cada prueba que necesitaba comprobarlo; con las pruebas
/// que agrega esta ronda —que lo buscan fuera del marcador— repetirlo a mano
/// en un tercer lugar era el mismo riesgo que ya evitaba `revisionDePrueba`.
const runIdDePrueba = 'corrida-1';

/// Un sujeto larguísimo, para la prueba de que el bloque de testigos no
/// trunca nada. **Sin la extensión del lenguaje del repositorio**: esa cadena
/// solo puede aparecer en su propio plugin y en la raíz de composición, y
/// esta suite no es ninguna de las dos cosas.
final sujetoDelTestigoLargo = 'lib/${'a' * 500}.txt';

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
  String sinPlanPorque = 'no hay elementos de trabajo',
  String alcance = ArtefactoDeRevision.alcanceSoloPR,
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
  sinPlanPorque: plan == null ? sinPlanPorque : null,
  alcanceDeLoAfirmado: alcance,
);

PullRequestRequest _solicitud(ArtefactoDeRevision artefacto) =>
    PullRequestRequest(
      draft: PullRequestDraft(
        runId: runIdDePrueba,
        branch: 'rama-1',
        base: 'main',
        artefacto: artefacto,
        rutas: const ['a.txt'],
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

// Un solo testigo con un sujeto larguísimo: para la prueba de que el bloque
// de testigos lo muestra entero, no truncado.
PullRequestRequest solicitudConTestigoLargo() => _solicitud(
  _artefacto(
    estado: EstadoDeCorrida.verde,
    cubierto: [_cubierta(sujetoDelTestigoLargo)],
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

/// Los renglones del cuerpo que un revisor LEE de verdad.
///
/// **`contains` no alcanza, y ese es el punto de estas pruebas.** El defecto
/// que el autor reprodujo no borraba la advertencia: la metía adentro de un
/// comentario HTML que abría la intención (`intent: '<!--'`) y recién cerraba
/// en el marcador final. La advertencia seguía estando en el texto y no
/// existía para quien abre el pull request, así que una aserción
/// `contains('> [!WARNING]')` quedaba VERDE sobre un cuerpo que enterraba
/// exactamente lo que la norma dice que no se puede enterrar.
///
/// Esta función saca las dos regiones de Markdown que se tragan lo que tienen
/// adentro —el comentario HTML, de `<!--` a `-->`, y el bloque de código con
/// cerca de acentos o de tildes— y devuelve lo que queda. No es un
/// renderizador: es la respuesta a «¿esto se ve?», que es lo único que estas
/// pruebas necesitan preguntar.
List<String> renglonesVisibles(String cuerpo) {
  final visibles = <String>[];
  var enComentario = false;
  String? cerca;
  for (final renglon in cuerpo.split('\n')) {
    if (cerca != null) {
      if (renglon.trimLeft().startsWith(cerca)) cerca = null;
      continue;
    }
    if (!enComentario) {
      final apertura = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(renglon);
      if (apertura != null) {
        cerca = apertura.group(1)!;
        continue;
      }
    }
    final limpio = StringBuffer();
    var resto = renglon;
    while (resto.isNotEmpty) {
      if (enComentario) {
        final fin = resto.indexOf('-->');
        if (fin < 0) break;
        enComentario = false;
        resto = resto.substring(fin + '-->'.length);
        continue;
      }
      final inicio = resto.indexOf('<!--');
      if (inicio < 0) {
        limpio.write(resto);
        break;
      }
      limpio.write(resto.substring(0, inicio));
      enComentario = true;
      resto = resto.substring(inicio + '<!--'.length);
    }
    visibles.add(limpio.toString());
  }
  return visibles;
}

/// Los valores hostiles, cada uno con el mecanismo que abusa.
const valoresAdversariales = <String, String>{
  'abre un comentario HTML': '<!--',
  'cierra un comentario HTML': '-->',
  'abre una cerca de código': '```',
  'abre una cerca de tildes': '~~~',
  'un acento grave suelto': 'a`b',
  'un encabezado que falsifica una sección':
      'antes\n## Qué quedó cubierto\ndespués',
  'una advertencia falsificada': 'antes\n> [!WARNING]\n> salió todo verde',
  'una lista numerada y una viñeta': '1. uno\n- dos\n',
};

/// Un artefacto incompleto —para que la advertencia sea obligatoria— con
/// [veneno] metido en el campo que nombre [donde].
PullRequestRequest solicitudEnvenenada(String donde, String veneno) {
  Afirmacion afirmacion() => Afirmacion(
    id: donde == 'afirmacion.id' ? veneno : 'formato.conforme',
    demuestra: donde == 'afirmacion.demuestra'
        ? veneno
        : 'coincide con la salida del formateador',
    noDemuestra: donde == 'afirmacion.noDemuestra'
        ? veneno
        : 'comportamiento, lógica ni criterios',
  );
  final sujeto = donde == 'cubierto.sujeto' ? veneno : 'lib';
  final cubierta = AfirmacionCubierta.desde(
    control: _ControlDeclarado(
      donde == 'cubierto.controlId' ? veneno : 'formateador',
      afirmacion(),
    ),
    desenlace: Executed(
      witness: Witness(
        invocation: 'herramienta --sobre $sujeto',
        subjects: [sujeto],
        exitCode: 0,
        finishedAt: DateTime.utc(2026),
        omitted: const [],
      ),
      diagnostics: const [],
    ),
    sujeto: sujeto,
  )!;

  return _solicitud(
    _artefacto(
      estado: EstadoDeCorrida.noConcluyente,
      intent: donde == 'intent' ? veneno : 'probar el render del cuerpo del PR',
      plan: donde == 'plan' ? veneno : null,
      // `sinPlanPorque` es el OTRO lado del par —presente si y solo si no hay
      // plan— así que se envenena cuando el caso no envenena el plan.
      sinPlanPorque: donde == 'sinPlanPorque'
          ? veneno
          : 'no hay elementos de trabajo',
      alcance: donde == 'alcanceDeLoAfirmado'
          ? veneno
          : ArtefactoDeRevision.alcanceSoloPR,
      cubierto: [cubierta],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.declaradoNoMirado,
          sujeto: donde == 'criterio.sujeto' ? veneno : 'lib/uno',
          controlId: donde == 'criterio.controlId' ? veneno : 'formateador',
          detalle: donde == 'criterio.detalle'
              ? veneno
              : 'El control declaró que no miró este archivo.',
        ),
      ],
    ),
  );
}

/// Los campos que llegan de afuera y terminan adentro del Markdown. Es la
/// lista de lo que `cuerpoDeGitHub` interpola: si alguien agrega uno nuevo y
/// no lo agrega acá, esta suite no lo cubre — y ese hueco es el mismo que
/// dejó el defecto original.
const camposQueVienenDeAfuera = <String>[
  'intent',
  'plan',
  // Faltaba, y el hueco lo encontró la ronda 6: se interpola en el cuerpo
  // igual que el plan —es su rama `else`— y el fixture lo tenía fijo, así que
  // la lista que se declara «lo que `cuerpoDeGitHub` interpola» ya nacía
  // incompleta.
  'sinPlanPorque',
  'alcanceDeLoAfirmado',
  'cubierto.sujeto',
  'cubierto.controlId',
  'afirmacion.id',
  'afirmacion.demuestra',
  'afirmacion.noDemuestra',
  'criterio.sujeto',
  'criterio.controlId',
  'criterio.detalle',
];

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
    // norma real dice al revés, y las dos fuentes viven en el repositorio
    // del corpus, no en este árbol —van con su ruta justamente para que se
    // puedan abrir—:
    //
    // - `sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md`, §13
    //   «El cuerpo, el JSON y el directorio», verbatim: «requiere criterio,
    //   completo y antes que lo cubierto».
    // - `sdlc-agentico/adr/ADR-022-forja-y-credencial.md`, decisión 7: la
    //   lista de lo que requiere criterio «no se entierra, no se resume y no
    //   va después de una conclusión tranquilizadora».
    //
    // Lo que el comentario viejo afirmaba sobre ADR-016 no está en ADR-016:
    // ese ADR regula que la advertencia preceda a lo verde y que lo que
    // requiere criterio salga completo, no este orden.
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
        '- **lib** (control <code>formateador</code>, afirmación '
        '<code>formato.conforme</code>): coincide con la salida del '
        'formateador. No demuestra: comportamiento, lógica ni criterios.',
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
        '- **el control declaró que no lo miró** — sujeto '
        '<code>lib/uno</code> — control <code>formateador</code>: El control '
        'declaró que no miró este archivo.',
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

  group(
    'ningún dato de la corrida puede enterrar ni falsificar lo obligatorio',
    () {
      // **Lo que se mide es la VISIBILIDAD, no el escape.** Una suite que
      // exigiera «el texto sale escapado» se podría satisfacer escapando de
      // cualquier manera y seguiría sin decir si el revisor ve la advertencia.
      // Acá cada caso arma el cuerpo con un valor hostil en un campo que viene
      // de afuera y pregunta lo único que la norma exige: que la advertencia
      // obligatoria y las DOS secciones obligatorias se sigan leyendo, una vez
      // y sola una, fuera de todo comentario y de toda cerca.
      for (final campo in camposQueVienenDeAfuera) {
        for (final caso in valoresAdversariales.entries) {
          test('$campo ${caso.key}', () {
            final cuerpo = cuerpoDeGitHub(
              solicitudEnvenenada(campo, caso.value),
            );
            final visibles = renglonesVisibles(cuerpo);

            expect(
              visibles.where((r) => r.startsWith('> [!WARNING]')),
              hasLength(1),
              reason:
                  'la advertencia obligatoria quedó enterrada —o duplicada por '
                  'el dato— con «${caso.value}» en $campo',
            );
            for (final seccion in const [
              '## Qué requiere criterio humano',
              '## Qué quedó cubierto',
            ]) {
              expect(
                visibles.where((r) => r.trimRight() == seccion),
                hasLength(1),
                reason:
                    'la sección «$seccion» no se lee exactamente una vez con '
                    '«${caso.value}» en $campo: o quedó adentro de un '
                    'comentario o de una cerca, o el dato fabricó una segunda',
              );
            }
            expect(
              visibles.indexWhere((r) => r.startsWith('> [!WARNING]')),
              lessThan(
                visibles.indexWhere(
                  (r) => r.trimRight() == '## Qué requiere criterio humano',
                ),
              ),
              reason:
                  'la advertencia va antes de todo lo que se lea como verde',
            );
          });
        }
      }

      test('ningún campo puede meter una imagen ni un enlace en el cuerpo', () {
        // **La baliza.** `![](http://atacante/x.png)` en el cuerpo de un pull
        // request es una imagen remota: se pide sola cuando el revisor abre la
        // página, sin que él haga nada. Enterrar no entierra —por eso las
        // pruebas de visibilidad la daban por buena—, pero una imagen y un
        // enlace SON estructura, y el render los tiene que neutralizar.
        for (final campo in camposQueVienenDeAfuera) {
          final cuerpo = cuerpoDeGitHub(
            solicitudEnvenenada(
              campo,
              '![](http://atacante/x.png) y '
              '[un enlace](http://atacante/y)',
            ),
          );
          expect(
            cuerpo,
            isNot(contains('](http://atacante')),
            reason: 'el campo $campo dejó la sintaxis de enlace intacta',
          );
          expect(
            cuerpo,
            isNot(contains('![')),
            reason: 'el campo $campo dejó la sintaxis de imagen intacta',
          );
          expect(
            cuerpo,
            contains('http://atacante'),
            reason:
                'la URL tiene que seguir LEYÉNDOSE: neutralizar la sintaxis no '
                'es borrar lo que el dato decía',
          );
        }
      });

      test(
        'un dato con `**` no descuadra la negrita del ítem que lo contiene',
        () {
          // El sujeto va adentro de `**…**` que escribe este archivo. Con `a**b`
          // crudo, la negrita cierra donde la abre el dato y el ítem muestra en
          // negrita algo que el render no marcó.
          final cuerpo = cuerpoDeGitHub(
            solicitudEnvenenada('cubierto.sujeto', 'a**b'),
          );
          expect(cuerpo, contains('- **a&#42;&#42;b** (control '));
          expect(
            cuerpo,
            isNot(contains('**a**b**')),
            reason: 'la negrita del ítem la marca el render, no el dato',
          );
        },
      );
      test('el dato hostil se sigue LEYENDO: neutralizar no es borrar', () {
        // El control negativo del grupo. Un render que tirara los caracteres
        // raros —o el campo entero— pasaría todas las pruebas de arriba y le
        // escondería al revisor parte de lo que la corrida dijo, que es el otro
        // lado del mismo defecto.
        final cuerpo = cuerpoDeGitHub(
          solicitudEnvenenada('criterio.detalle', 'el marcador <!-- de acá'),
        );
        expect(cuerpo, contains('&lt;!--'));
        expect(
          cuerpo,
          contains('el marcador &lt;!-- de acá'),
          reason: 'el detalle tiene que seguir completo, solo que sin sintaxis',
        );
      });

      test('el identificador hostil se muestra entero y adentro de su '
          'código', () {
        // El identificador va en `<code>` justamente para que su contenido sea
        // HTML y las entidades lo neutralicen. Entre acentos graves no
        // alcanzaría: en CommonMark el HTML crudo tiene precedencia sobre el
        // tramo de código, así que un `<!--` en un identificador y un `-->` en
        // otro forman un comentario que se traga el detalle que hay entre los
        // dos — enterrar lo que requiere criterio es justamente lo prohibido.
        final cuerpo = cuerpoDeGitHub(
          solicitudEnvenenada('criterio.sujeto', 'lib/``raro`` <!--'),
        );
        expect(
          cuerpo,
          contains('sujeto <code>lib/&#96;&#96;raro&#96;&#96; &lt;!--</code>'),
          reason:
              'el identificador tiene que salir entero, con sus acentos y su '
              'comentario neutralizados como entidades',
        );
      });

      test(
        'un texto sin nada hostil sale IGUAL que antes del render seguro',
        () {
          // La prueba de que neutralizar no ensucia el caso normal: el cuerpo de
          // una corrida común no puede llenarse de barras invertidas ni de
          // entidades.
          final cuerpo = cuerpoDeGitHub(solicitudVerde());
          expect(cuerpo, isNot(contains('&amp;')));
          expect(cuerpo, isNot(contains('\\')));
          expect(
            cuerpo,
            contains(
              '- **lib** (control <code>formateador</code>, afirmación '
              '<code>formato.conforme</code>): ',
            ),
          );
        },
      );
    },
  );

  group('el truncado del título no parte un carácter', () {
    /// Una intención que pone un emoji justo encima del límite: el relleno
    /// llega hasta una unidad UTF-16 antes del corte, así que la primera
    /// pareja sustituta arranca pegada al límite y `substring` la parte al
    /// medio.
    PullRequestRequest solicitudConEmojiEnElBorde() {
      final relleno =
          'x' * (256 - PullRequestRequest.prefijoIncompleto.length - 1);
      return _solicitud(
        _artefacto(
          estado: EstadoDeCorrida.noConcluyente,
          intent: '$relleno${'😀' * 20}',
          requiereCriterio: [
            EntradaDeCriterio(
              motivo: MotivoDeCriterio.entornoNoDerivado,
              detalle: 'El entorno no se derivó.',
            ),
          ],
        ),
      );
    }

    test('el título truncado se puede codificar tal como está', () {
      final titulo = tituloDeGitHub(solicitudConEmojiEnElBorde());

      expect(
        titulo.length,
        lessThanOrEqualTo(256),
        reason: 'el límite del proveedor sigue siendo el que era',
      );
      expect(
        utf8.decode(utf8.encode(titulo)),
        titulo,
        reason:
            'el título terminó en media pareja sustituta: al codificarlo a '
            'UTF-8 se vuelve «�», o sea un carácter que la intención no '
            'tenía. Con `substring` sobre unidades UTF-16 el corte cae adentro '
            'del emoji.',
      );
      expect(
        titulo,
        isNot(contains('�')),
        reason: 'el reemplazo es la marca de un carácter partido',
      );
      expect(
        titulo,
        startsWith(PullRequestRequest.prefijoIncompleto),
        reason: 'el corte se come la intención, nunca la advertencia',
      );
    });

    test('el corte no tira un carácter que sí entraba', () {
      // El control negativo: truncar de más —cortar en la runa anterior aunque
      // la siguiente entrara justa— también pasaría la prueba de arriba.
      final titulo = tituloDeGitHub(solicitudConEmojiEnElBorde());
      expect(
        titulo.length,
        greaterThanOrEqualTo(255),
        reason:
            'con el emoji en el borde entran 255 unidades: la 256 sería media '
            'pareja, y la runa entera no entra',
      );
    });
  });

  test('el marcador estable es la última línea y lleva runId y revisión', () {
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    final ultima = cuerpo.trimRight().split('\n').last;
    expect(ultima, startsWith('<!-- shipflow:pr formatVersion=1'));
    expect(ultima, contains('runId=$runIdDePrueba'));
    expect(ultima, contains('revision=$revisionDePrueba'));
  });

  group('lo que §13 exige y el marcador no le mostraba al revisor', () {
    // **El hallazgo.** El marcador estable lleva la revisión y el `runId`,
    // pero ADENTRO de un comentario HTML: la forja no lo muestra, así que
    // para el revisor humano no están — que es exactamente para quien §13
    // dice que el cuerpo tiene que ser autosuficiente. `contains` sobre el
    // cuerpo entero no alcanzaría para probar esto: los dos valores YA
    // estaban ahí, dentro del comentario, y esa aserción habría dado verde
    // desde antes de este cambio. Por eso se filtra por `renglonesVisibles`
    // primero.
    test('la revisión y el runId se VEN, no solo en el marcador', () {
      final visible = renglonesVisibles(
        cuerpoDeGitHub(solicitudVerde()),
      ).join('\n');
      expect(visible, contains(revisionDePrueba));
      expect(visible, contains(runIdDePrueba));
    });

    test('payloadVersion viaja en el cuerpo, visible', () {
      final visible = renglonesVisibles(
        cuerpoDeGitHub(solicitudVerde()),
      ).join('\n');
      expect(visible, contains('$payloadVersionDeShip'));
    });

    // El brief original le pedía a `cuerpoDeGitHub` un parámetro
    // `accionSiguiente` compuesto por `cli` con `accionDe(ShipOutcome)`. No
    // se hizo: `forge` no puede ver a `cli` —las flechas van hacia `core`—, y
    // encima la operación que arma este cuerpo corre ANTES de que exista un
    // `ShipOutcome` que dar, porque ese desenlace depende de lo que ELLA
    // misma devuelva. La acción que sí puede llevar el cuerpo es la de la
    // VERIFICACIÓN, no la de la publicación, y se deriva de
    // `PullRequestRequest.incompleto`, que la solicitud ya tiene.
    test(
      'la acción siguiente aparece cuando la corrida se publica incompleta',
      () {
        final visible = renglonesVisibles(
          cuerpoDeGitHub(solicitudIncompleta()),
        ).join('\n');
        expect(visible, contains('## Qué hacer'));
      },
    );

    test('sin corrida incompleta no se inventa una sección "Qué hacer"', () {
      expect(cuerpoDeGitHub(solicitudVerde()), isNot(contains('## Qué hacer')));
    });

    test('los testigos van en un bloque plegable, y no se truncan', () {
      final cuerpo = cuerpoDeGitHub(solicitudConTestigoLargo());
      expect(cuerpo, contains('<details>'));
      expect(cuerpo, contains(sujetoDelTestigoLargo));
      expect(
        cuerpo,
        isNot(contains('…')),
        reason: 'nunca se truncan en silencio',
      );
    });

    test('el bloque plegable va DESPUÉS de las dos secciones obligatorias', () {
      final cuerpo = cuerpoDeGitHub(solicitudVerde());
      expect(
        cuerpo.indexOf('## Qué quedó cubierto'),
        lessThan(cuerpo.indexOf('<details>')),
      );
    });

    test('sin nada cubierto no hay bloque de testigos', () {
      // El mismo principio que ya vale para las dos listas obligatorias —no
      // se inventa una sección sobre una lista vacía— llevado al bloque
      // plegable: acá ni siquiera hay una sección fija que rellenar.
      final cuerpo = cuerpoDeGitHub(solicitudSinNadaQueMostrar());
      expect(cuerpo, isNot(contains('<details>')));
    });

    test('un testigo con datos hostiles no rompe la estructura del cuerpo', () {
      // El mismo control negativo que ya corre sobre los demás campos
      // externos, aplicado al testigo: `invocation` y `subjects` llegan del
      // control que ejecutó, no de este archivo, así que pasan por el mismo
      // render seguro que todo lo demás.
      final testigoHostil = Witness(
        invocation: '<!-- de un testigo',
        subjects: const ['a**b'],
        exitCode: 0,
        finishedAt: DateTime.utc(2026),
        omitted: const [],
      );
      final cubierta = AfirmacionCubierta.desde(
        control: _ControlDeclarado(
          'formateador',
          Afirmacion(id: 'formato.conforme', demuestra: 'x', noDemuestra: 'y'),
        ),
        desenlace: Executed(witness: testigoHostil, diagnostics: const []),
        sujeto: 'a**b',
      )!;
      final cuerpo = cuerpoDeGitHub(
        _solicitud(
          _artefacto(estado: EstadoDeCorrida.verde, cubierto: [cubierta]),
        ),
      );
      final visibles = renglonesVisibles(cuerpo);
      expect(
        visibles.where((r) => r.trimRight() == '## Qué quedó cubierto'),
        hasLength(1),
      );
      expect(cuerpo, contains('&lt;!-- de un testigo'));
      expect(cuerpo, contains('a&#42;&#42;b'));
    });
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
