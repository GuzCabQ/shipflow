/// La cascada: el registro, la cuenta y la precedencia.
///
/// El doble vive acá y no en `plugin_fake` a propósito: `orchestration` no
/// puede depender de ningún plugin —esa es la regla que lo mantiene ignorante
/// del stack— así que su prueba trae el suyo.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

/// **Declara cuántos elementos eran suyos.** Omitirlo deja el conteo en
/// `null`, que significa «no se pudo establecer» y por sí solo impide el
/// verde: un doble que no lo declara estaría probando otra cosa.
Witness _testigo({List<String> sujetos = const ['lib/'], int propios = 2}) =>
    Witness(
      invocation: 'herramienta',
      subjects: sujetos,
      omitted: const [],
      termination: Termination.completa,
      exitCode: 0,
      ownSubjects: propios,
      finishedAt: DateTime.utc(2026),
    );

/// Un paso al que se le declara qué devolver, o que se rompe.
class _Paso implements Verifier {
  @override
  final String id;
  final VerificationOutcome? devuelve;
  final Object? lanza;
  var corrio = false;

  _Paso(this.id, {this.devuelve, this.lanza});

  /// Un paso verde, con testigo.
  factory _Paso.verde(String id) => _Paso(id,
      devuelve: VerificationOutcome(
          verifierId: id, diagnostics: const [], witness: _testigo()));

  /// Un paso rojo: un diagnóstico que bloquea.
  factory _Paso.rojo(String id) => _Paso(id,
      devuelve: VerificationOutcome(
        verifierId: id,
        witness: _testigo(),
        diagnostics: [
          Diagnostic(
              file: 'a',
              severity: Severity.bloquea,
              ruleId: 'r',
              message: const QuotedText('m', source: 'test')),
        ],
      ));

  /// Un paso que no pudo mirar: testigo sin sujetos.
  factory _Paso.ciego(String id) => _Paso(id,
      devuelve: VerificationOutcome(
          verifierId: id,
          diagnostics: const [],
          witness: _testigo(sujetos: const [])));

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    corrio = true;
    if (lanza != null) throw lanza!;
    return devuelve!;
  }
}

/// Lo que declara un paso que **no tuvo nada que hacer**. No es un testigo:
/// no hubo invocación que atestiguar.
NotApplicable _sinNadaSuyo({
  List<String> motivos = const ['lib/: no contiene ningún archivo de fuente'],
}) =>
    NotApplicable(
      subjects: const ['lib/'],
      reasons: motivos,
      decidedAt: DateTime.utc(2026),
    );

/// Un paso que no tiene nada suyo que hacer.
_Paso _pasoSinNadaSuyo(String id) => _Paso(id,
    devuelve: VerificationOutcome(
        verifierId: id, diagnostics: const [], notApplicable: _sinNadaSuyo()));

void main() {
  group('el registro', () {
    test('dos pasos con el mismo id no forman un registro', () {
      // El id es con lo que se comparan registrados contra ejecutados: uno
      // taparía al otro y un paso podría no correr sin que nadie se entere.
      expect(() => Cascada([_Paso.verde('A'), _Paso.verde('A')]),
          throwsA(isA<CascadaNoRegistrable>()));
    });

    test('un paso sin id tampoco', () {
      expect(() => Cascada([_Paso.verde('  ')]),
          throwsA(isA<CascadaNoRegistrable>()));
    });
  });

  group('la cuenta de registrados contra ejecutados', () {
    test('una cascada SIN pasos no es verde', () async {
      // El falso verde más barato de todos: no miró nada y nadie se lo
      // preguntó. ADR-011 corolario 2 en su forma degenerada.
      final r = await Cascada(const []).correr(['lib/']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
    });

    test('un paso que se rompe queda SIN EJECUTAR, y se dice cuál', () async {
      final a = _Paso.verde('A');
      final b = _Paso('B', lanza: StateError('se rompió'));
      final r = await Cascada([a, b]).correr(['lib/']);
      expect(r.registrados, ['A', 'B']);
      expect(r.ejecutados, ['A']);
      expect(r.sinEjecutar, ['B']);
      expect(r.fallosInternos.keys, ['B']);
    });

    test('un paso que se rompe NO detiene a los siguientes', () async {
      // Cortar ahí dejaría a los demás sin ejecutar Y sin explicación, y las
      // dos cosas se confundirían en la cuenta.
      final a = _Paso('A', lanza: StateError('x'));
      final b = _Paso.verde('B');
      await Cascada([a, b]).correr(['lib/']);
      expect(b.corrio, isTrue);
    });

    test('un paso que devuelve el resultado de OTRO rompe la cuenta', () async {
      // Sin esto, «ejecutados» diría que corrió algo que no corrió.
      final impostor = _Paso('A',
          devuelve: VerificationOutcome(
              verifierId: 'B', diagnostics: const [], witness: _testigo()));
      final r = await Cascada([impostor]).correr(['lib/']);
      expect(r.estado, EstadoDeCorrida.errorInterno);
      expect(r.fallosInternos['A'], contains('B'));
    });

    test('un hueco SIN fallo interno tampoco es verde', () {
      // El corolario 2 en su forma pura: registrado, no ejecutado, y nadie se
      // rompió. `Cascada` no puede producirlo hoy —todo paso que no ejecuta
      // queda anotado como fallo— así que se construye el resultado directo.
      // Sin esto el guardia queda tapado por el de fallos internos y no
      // dispara nunca, que es lo mismo que no estar.
      final r = ResultadoDeCascada(
        registrados: const ['A', 'B'],
        resultados: [
          VerificationOutcome(
              verifierId: 'A', diagnostics: const [], witness: _testigo()),
        ],
      );
      expect(r.sinEjecutar, ['B']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
    });
  });

  test('el alcance no puede cambiar entre paso y paso', () async {
    // La lista es del llamador. Si muta durante la corrida, el primer paso
    // verifica un alcance y el segundo otro, y el reporte dice que los dos
    // cubrieron lo mismo. Es el invariante que `PasoDeCascada.run` ya aplicaba
    // un nivel más abajo y que acá faltaba.
    final lista = ['lib/'];
    final espia = _Espia('B');
    await Cascada([_Mutador('A', lista), espia]).correr(lista);
    expect(espia.recibio, ['lib/'],
        reason:
            'el segundo paso tiene que ver el mismo alcance que el primero');
  });

  test('avisa MIENTRAS corre, no al final', () async {
    // Devolvía todo junto y el CLI recorría los resultados después: no había
    // nada que mirar mientras una herramienta tardaba, y la marca de tiempo
    // era la de armar el reporte. La superficie pide que una operación de más
    // de tres segundos muestre el paso en curso.
    final orden = <String>[];
    await Cascada([_Paso.verde('A'), _Paso.verde('B')]).correr(
      ['lib/'],
      alEmpezar: (id) => orden.add('empieza:$id'),
      alTerminar: (d) => orden.add('termina:${d.id}'),
    );
    expect(orden, ['empieza:A', 'termina:A', 'empieza:B', 'termina:B'],
        reason: 'B no puede anunciarse antes de que A haya terminado');
  });

  test('TODO paso avisa su desenlace, incluidos el saltado y el roto',
      () async {
    // Solo se avisaba de los que producían resultado: un salto y un fallo
    // interno dejaban el `started` abierto para siempre, y un consumidor del
    // protocolo en streaming se quedaba esperando. Lo encontró un review.
    final desenlaces = <String>[];
    await Cascada([
      _Paso.verde('A'),
      _pasoSinNadaSuyo('B'),
      _Paso('C', lanza: StateError('se rompió')),
    ]).correr(
      ['lib/'],
      alTerminar: (d) => desenlaces.add('${d.id}:${d.runtimeType}'),
    );
    expect(desenlaces, [
      'A:PasoEjecutado',
      'B:PasoSinNadaQueHacer',
      'C:PasoRoto',
    ]);
  });

  test('un fallo del OBSERVADOR no se le atribuye al verificador', () async {
    // `alTerminar` estaba dentro del `try` que clasifica fallos del paso: el
    // mismo paso quedaba registrado como ejecutado Y como fallido, y el
    // reporte culpaba a quien había hecho su trabajo. Si el observador se
    // rompe, que suba y sea un error del arnés, que es lo que es.
    expect(
      () => Cascada([_Paso.verde('A')]).correr(
        ['lib/'],
        alTerminar: (_) => throw StateError('falló el observador'),
      ),
      throwsStateError,
    );
  });

  group('la precedencia se deriva', () {
    test('verde solo si TODOS corrieron y ninguno objetó', () async {
      final r =
          await Cascada([_Paso.verde('A'), _Paso.verde('B')]).correr(['lib/']);
      expect(r.estado, EstadoDeCorrida.verde);
    });

    test('rojo cuando hay un diagnóstico que bloquea', () async {
      final r =
          await Cascada([_Paso.verde('A'), _Paso.rojo('B')]).correr(['lib/']);
      expect(r.estado, EstadoDeCorrida.rojo);
      expect(r.diagnosticos, hasLength(1));
    });

    test('lo NO CONCLUYENTE gana sobre el rojo', () async {
      // No se puede afirmar que el cambio falló cuando parte de la
      // verificación no se ejecutó. Los diagnósticos igual se reportan.
      final r =
          await Cascada([_Paso.rojo('A'), _Paso.ciego('B')]).correr(['lib/']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.diagnosticos, hasLength(1),
          reason: 'el hallazgo real no se pierde: lo que cambia es qué se '
              'afirma del conjunto');
    });

    test('el error interno gana sobre todo', () async {
      final r = await Cascada([
        _Paso.rojo('A'),
        _Paso.ciego('B'),
        _Paso('C', lanza: StateError('x')),
      ]).correr(['lib/']);
      expect(r.estado, EstadoDeCorrida.errorInterno,
          reason: 'que el arnés se rompa no es un veredicto sobre el cambio');
    });
  });

  group('un paso que no tuvo nada que hacer', () {
    // El tercer estado, distinto de «corrió» y de «no pudo mirar». Confundirlo
    // con el segundo es el falso rojo simétrico del falso verde que ADR-011
    // caza, y estaba ocurriendo: un alcance sin archivos del stack daba «no
    // concluyente: algún paso no pudo observar su alcance», cuando la
    // herramienta había corrido, terminado completa, y no tenía nada suyo.

    test('se cuenta como SALTADO, no como discrepancia', () async {
      final r = await Cascada([_Paso.verde('A'), _pasoSinNadaSuyo('B')])
          .correr(['lib/']);

      expect(r.ejecutados, ['A']);
      expect(r.saltados.map((s) => s.id), ['B']);
      expect(r.sinEjecutar, isEmpty,
          reason: 'un salto está contado: no es una discrepancia');
      expect(r.estado, EstadoDeCorrida.verde);
    });

    test('el salto lleva su MOTIVO, sacado del testigo', () async {
      final r = await Cascada([_Paso.verde('A'), _pasoSinNadaSuyo('B')])
          .correr(['lib/']);
      expect(r.saltados.single.motivos,
          contains('lib/: no contiene ningún archivo de fuente'));
      expect(r.saltados.single.declaracion.subjects, ['lib/']);
    });

    test('si se saltan todos, la corrida NO es verde', () async {
      // Cada salto por separado es legítimo; todos juntos son una corrida que
      // no verificó nada. Es el falso verde de la cascada vacía por la otra
      // puerta: hay pasos registrados y ninguno tuvo nada que hacer.
      final r = await Cascada([_pasoSinNadaSuyo('A'), _pasoSinNadaSuyo('B')])
          .correr(['lib/']);

      expect(r.saltados, hasLength(2));
      expect(r.estado, EstadoDeCorrida.noConcluyente);
    });

    test('un paso que SÍ tenía archivos suyos no se salta', () async {
      // El control negativo, y lo pidió una mutación: sin él, «cero» y «no
      // nulo» eran indistinguibles, y un paso que cubrió tres archivos se
      // habría contado como saltado — un verde que nadie miró, por la puerta
      // que esta rebanada vino a cerrar.
      final conTrabajo = _Paso('A',
          devuelve: VerificationOutcome(
              verifierId: 'A',
              diagnostics: const [],
              witness: Witness(
                invocation: 'herramienta --sobre lib/',
                subjects: const ['lib/a.fuente'],
                omitted: const [],
                termination: Termination.completa,
                exitCode: 0,
                ownSubjects: 3,
                finishedAt: DateTime.utc(2026),
              )));
      final r = await Cascada([conTrabajo]).correr(['lib/']);
      expect(r.saltados, isEmpty);
      expect(r.ejecutados, ['A']);
      expect(r.estado, EstadoDeCorrida.verde);
    });

    test('un paso CON DIAGNÓSTICO nunca se salta', () async {
      // El falso verde que esta rebanada abrió al cerrar el falso rojo, y lo
      // encontró un review: un paso con un diagnóstico bloqueante y cero
      // archivos propios se clasificaba como saltado, su resultado nunca
      // entraba en `resultados`, y la corrida salía VERDE con el diagnóstico
      // desaparecido. Un salto es la ausencia de trabajo, no la desaparición
      // de un hallazgo.
      final conHallazgo = _Paso('B',
          devuelve: VerificationOutcome(
            verifierId: 'B',
            notApplicable: _sinNadaSuyo(),
            diagnostics: [
              Diagnostic(
                  file: 'a',
                  severity: Severity.bloquea,
                  ruleId: 'r',
                  message: QuotedText('rompe todo', source: 'h')),
            ],
          ));
      final r = await Cascada([_Paso.verde('A'), conHallazgo]).correr(['lib/']);

      expect(r.saltados, isEmpty);
      expect(r.diagnosticos, hasLength(1),
          reason: 'el hallazgo no puede desaparecer');
      expect(r.estado, isNot(EstadoDeCorrida.verde));
    });

    test('un salto SIN motivo no es un salto', () async {
      // ADR-011 corolario 1 prohíbe el salto silencioso. La promesa estaba
      // escrita en prosa y el tipo la dejaba romper.
      final mudo = _Paso('B',
          devuelve: VerificationOutcome(
              verifierId: 'B',
              diagnostics: const [],
              witness: Witness(
                invocation: 'herramienta',
                subjects: const [],
                omitted: const [],
                termination: Termination.completa,
                exitCode: 0,
                ownSubjects: 0,
                finishedAt: DateTime.utc(2026),
              )));
      final r = await Cascada([_Paso.verde('A'), mudo]).correr(['lib/']);
      expect(r.saltados, isEmpty);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
    });

    test('y el tipo tampoco deja construir uno mudo', () {
      expect(
          () => PasoSaltado(
              id: 'B', motivos: const ['  '], declaracion: _sinNadaSuyo()),
          throwsArgumentError);
    });

    test('un alcance parcialmente inobservable NO da verde', () async {
      // El plugin calculaba bien el «no sé» y la cascada nunca lo consumía: un
      // paso que cubría `lib/` y no podía mirar `no/existe` atestiguaba igual,
      // y con otro paso en verde la corrida salía VERDE sobre un alcance
      // parcialmente no observado. La seguridad dependía de que OTRO paso
      // tropezara con el mismo obstáculo. Lo encontró un review.
      final parcial = _Paso('B',
          devuelve: VerificationOutcome(
              verifierId: 'B',
              diagnostics: const [],
              witness: Witness(
                invocation: 'herramienta --sobre lib/',
                subjects: const ['lib/'],
                omitted: const ['no/existe: no existe en el árbol'],
                termination: Termination.completa,
                exitCode: 0,
                ownSubjects: null,
                finishedAt: DateTime.utc(2026),
              )));
      final r = await Cascada([_Paso.verde('A'), parcial])
          .correr(['lib/', 'no/existe']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.saltados, isEmpty);
    });

    test('un paso que CUBRIÓ algo no se salta, aunque diga cero propios',
        () async {
      // Dos afirmaciones incompatibles en el mismo testigo. Sin esta guardia
      // se clasificaba como salto y lo cubierto desaparecía del reporte junto
      // con el resultado.
      final incoherente = _Paso('B',
          devuelve: VerificationOutcome(
              verifierId: 'B',
              diagnostics: const [],
              witness: Witness(
                invocation: 'herramienta',
                subjects: const ['lib/a.fuente'],
                omitted: const ['algo'],
                termination: Termination.completa,
                exitCode: 0,
                ownSubjects: 0,
                finishedAt: DateTime.utc(2026),
              )));
      final r = await Cascada([_Paso.verde('A'), incoherente]).correr(['lib/']);
      expect(r.saltados, isEmpty);
      expect(r.ejecutados, ['A', 'B']);
    });

    test('un paso que SÍ invocó algo nunca es un salto', () async {
      // La distinción es de tipo: hay testigo, entonces hubo invocación, y una
      // invocación que no cubrió nada es «no pude», no «no había nada mío».
      // Antes esto se reconstruía desde cuatro campos y cada review encontraba
      // la combinación que faltaba.
      final murio = _Paso('A',
          devuelve: VerificationOutcome(
              verifierId: 'A',
              diagnostics: const [],
              witness: Witness(
                invocation: 'herramienta --sobre lib/',
                subjects: const [],
                omitted: const ['la herramienta no llegó a producir nada'],
                termination: Termination.tiempoAgotado,
                exitCode: -1,
                ownSubjects: 0,
                finishedAt: DateTime.utc(2026),
              )));
      final r = await Cascada([murio]).correr(['lib/']);
      expect(r.saltados, isEmpty);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
    });
  });
}

/// Muta la lista del llamador en medio de la corrida.
class _Mutador implements Verifier {
  @override
  final String id;
  final List<String> lista;
  _Mutador(this.id, this.lista);

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    lista
      ..clear()
      ..add('otro/alcance');
    return VerificationOutcome(
        verifierId: id, diagnostics: const [], witness: _testigo());
  }
}

/// Anota qué alcance le llegó.
class _Espia implements Verifier {
  @override
  final String id;
  List<String>? recibio;
  _Espia(this.id);

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    recibio = List.of(subjects);
    return VerificationOutcome(
        verifierId: id, diagnostics: const [], witness: _testigo());
  }
}
