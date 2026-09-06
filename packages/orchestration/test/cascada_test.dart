/// La cascada: el registro, la cuenta y la precedencia.
///
/// El doble vive acá y no en `plugin_fake` a propósito: `orchestration` no
/// puede depender de ningún plugin —esa es la regla que lo mantiene ignorante
/// del stack— así que su prueba trae el suyo. Vale también para
/// [ObservadorDeAlcanceFalso]: es la segunda implementación de `ScopeObserver`
/// que ya existe en `plugin_fake`, pero esta suite necesita la propia, no esa.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

/// Un testigo de que un paso corrió, sobre qué sujetos.
Witness _testigo({List<String> sujetos = const ['lib']}) => Witness(
      invocation: 'herramienta',
      subjects: sujetos,
      exitCode: 0,
      omitted: const [],
      finishedAt: DateTime.utc(2026),
    );

/// Un observador de alcance que responde de una tabla, y cuenta cuántas veces
/// lo llamaron. **No toca el disco**: existe para que esta suite pruebe la
/// clasificación de la cascada sin toolchain ni árbol.
class ObservadorDeAlcanceFalso implements ScopeObserver {
  /// Qué se sabe de cada sujeto que sí se pudo mirar.
  final Map<String, ObservedSubject> observados;

  /// Sujeto a causa, para los que no se pudieron mirar.
  final Map<String, String> noObservados;

  /// Qué se le pidió en cada llamada, para poder comprobar la cláusula 4 del
  /// contrato: se observa UNA vez por corrida.
  final List<List<String>> llamadas = [];

  ObservadorDeAlcanceFalso({
    required Map<String, ObservedSubject> observados,
    Map<String, String> noObservados = const {},
  })  : observados = Map.unmodifiable(observados),
        noObservados = Map.unmodifiable(noObservados);

  @override
  Future<ScopeObservation> observe(List<String> requested) async {
    llamadas.add(List.unmodifiable(requested));
    final vistos = <ObservedSubject>[];
    final ciegos = <UnobservedSubject>[];
    for (final s in requested) {
      final causa = noObservados[s];
      if (causa != null) {
        ciegos.add(UnobservedSubject(subject: s, cause: causa));
        continue;
      }
      final o = observados[s];
      // Un sujeto que la tabla no declara no se inventa como ajeno: sería el
      // fake decidiendo, que es justo lo que el puerto vino a impedir.
      if (o == null) {
        throw ArgumentError.value(
            s,
            'requested',
            'El fake no tiene declarado este sujeto. Declaralo en `observados` '
                'o en `noObservados`: adivinar sería clasificar por su cuenta');
      }
      vistos.add(o);
    }
    return ScopeObservation(
      requested: requested,
      observed: vistos,
      unobserved: ciegos,
      observedAt: DateTime.utc(2026),
    );
  }
}

/// Un observador que ya tiene `lib` declarado como del stack.
ObservadorDeAlcanceFalso _obsDeLib() => ObservadorDeAlcanceFalso(observados: {
      'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
    });

/// Un paso al que se le declara qué devolver, o que se rompe.
class _Paso implements Verifier {
  @override
  final String id;
  final VerificationOutcome? devuelve;
  final Object? lanza;
  var corrio = false;

  _Paso(this.id, {this.devuelve, this.lanza});

  /// Un paso verde, con testigo.
  factory _Paso.verde(String id) =>
      _Paso(id, devuelve: Executed(witness: _testigo(), diagnostics: const []));

  /// Un paso rojo: un diagnóstico que bloquea.
  factory _Paso.rojo(String id) => _Paso(id,
      devuelve: Executed(
        witness: _testigo(),
        diagnostics: [
          Diagnostic(
              file: 'a',
              severity: Severity.bloquea,
              ruleId: 'r',
              message: const QuotedText('m', source: 'test')),
        ],
      ));

  /// Un paso que empezó y no llegó a terminar.
  factory _Paso.abortado(String id) => _Paso(id,
      devuelve: Aborted(
        attempt: Attempt(
          invocation: 'herramienta',
          subjects: const ['lib'],
          termination: Termination.tiempoAgotado,
          exitCode: -1,
          note: 'la herramienta no llegó a producir un resultado',
          finishedAt: DateTime.utc(2026),
        ),
      ));

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    corrio = true;
    if (lanza != null) throw lanza!;
    return devuelve!;
  }
}

/// Anota qué alcance le llegó, y atestigua justo sobre eso.
class _Espia implements Verifier {
  @override
  final String id;
  List<String>? recibio;
  _Espia(this.id);

  @override
  Future<VerificationOutcome> run(List<String> subjects) async {
    recibio = List.of(subjects);
    return Executed(
        witness: _testigo(sujetos: subjects), diagnostics: const []);
  }
}

/// Un paso que declara exactamente qué sujetos cubrió, y qué omitió.
class _PasoQueCubre implements Verifier {
  @override
  final String id;
  final List<String> cubiertos;
  final List<Omission> omite;

  _PasoQueCubre(this.id, this.cubiertos, {this.omite = const []});

  @override
  Future<VerificationOutcome> run(List<String> subjects) async => Executed(
        witness: Witness(
          invocation: 'herramienta',
          subjects: cubiertos,
          exitCode: 0,
          omitted: omite,
          finishedAt: DateTime.utc(2026),
        ),
        diagnostics: const [],
      );
}

void main() {
  group('el registro', () {
    test('dos pasos con el mismo id no forman un registro', () {
      // El id es con lo que se arma el libro de obligaciones y se comparan
      // registrados contra ejecutados: uno taparía al otro y un paso podría
      // no correr sin que nadie se entere.
      expect(
          () => Cascada([_Paso.verde('A'), _Paso.verde('A')],
              observador: _obsDeLib()),
          throwsA(isA<CascadaNoRegistrable>()));
    });

    test('un paso sin id tampoco', () {
      expect(() => Cascada([_Paso.verde('  ')], observador: _obsDeLib()),
          throwsA(isA<CascadaNoRegistrable>()));
    });
  });

  test('el alcance se observa UNA vez para toda la corrida', () async {
    final obs = ObservadorDeAlcanceFalso(observados: {
      'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
    });
    await Cascada([_Paso.verde('A'), _Paso.verde('B')], observador: obs)
        .correr(['lib']);
    expect(obs.llamadas, hasLength(1),
        reason: 'dos lecturas del árbol pueden diferir, y el reporte diría '
            'que los dos pasos cubrieron lo mismo');
  });

  test('ningún sujeto del stack: los pasos se SALTAN, y no se los invoca',
      () async {
    final obs = ObservadorDeAlcanceFalso(observados: {
      'LEEME.md': ObservedSubject(
          subject: 'LEEME.md',
          ofStack: false,
          files: 0,
          reason: 'no es de este stack'),
    });
    final a = _Paso.verde('A');
    final r = await Cascada([a], observador: obs).correr(['LEEME.md']);
    expect(a.corrio, isFalse);
    expect(r.desenlaces['A'], isA<Skipped>());
  });

  test('un sujeto que no se pudo mirar y nada utilizable: NO OBSERVABLE',
      () async {
    final obs = ObservadorDeAlcanceFalso(
        observados: const {}, noObservados: const {'no/existe': 'no existe'});
    final r = await Cascada([_Paso.verde('A')], observador: obs)
        .correr(['no/existe']);
    expect(r.desenlaces['A'], isA<Unobservable>());
  });

  test('no pude mirar GANA sobre no era mío', () async {
    // Con un sujeto ajeno y otro inobservable, y nada utilizable, no se puede
    // afirmar que no había nada: es no observable.
    final obs = ObservadorDeAlcanceFalso(
      observados: {
        'LEEME.md': ObservedSubject(
            subject: 'LEEME.md', ofStack: false, files: 0, reason: 'ajeno'),
      },
      noObservados: const {'no/existe': 'no existe'},
    );
    final r = await Cascada([_Paso.verde('A')], observador: obs)
        .correr(['LEEME.md', 'no/existe']);
    expect(r.desenlaces['A'], isA<Unobservable>());
  });

  test('el paso recibe SOLO los sujetos utilizables', () async {
    final obs = ObservadorDeAlcanceFalso(observados: {
      'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
      'LEEME.md': ObservedSubject(
          subject: 'LEEME.md', ofStack: false, files: 0, reason: 'ajeno'),
    });
    final espia = _Espia('A');
    await Cascada([espia], observador: obs).correr(['lib', 'LEEME.md']);
    expect(espia.recibio, ['lib']);
  });

  test('un paso que lanza es Roto, y no detiene a los siguientes', () async {
    final b = _Paso.verde('B');
    final r = await Cascada([_Paso('A', lanza: StateError('x')), b],
            observador: _obsDeLib())
        .correr(['lib']);
    expect(r.desenlaces['A'], isA<Broken>());
    expect(b.corrio, isTrue);
  });

  test('TODO paso registrado recibe exactamente un desenlace', () async {
    final vistos = <String>[];
    final r = await Cascada([
      _Paso.verde('A'),
      _Paso('B', lanza: StateError('x')),
    ], observador: _obsDeLib())
        .correr(['lib'], alTerminar: (id, _) => vistos.add(id));
    expect(vistos, ['A', 'B']);
    expect(r.desenlaces.keys, ['A', 'B']);
  });

  test('el id lo pone el registro: un paso no puede devolver el de otro',
      () async {
    // El impostor dejó de ser representable: el desenlace no lleva id. Lo
    // atribuye la cascada desde su registro.
    final r = await Cascada([_Paso.verde('A')], observador: _obsDeLib())
        .correr(['lib']);
    expect(r.desenlaces.keys.single, 'A');
  });

  // **No alcanza con `throwsArgumentError`.** Con un paso registrado, el
  // `Skipped(notOfStack: [])` que arma el cuerpo de `correr` ya lanzaba un
  // `ArgumentError` por su cuenta —el suyo, sobre `notOfStack`, sin decirle
  // nada a quien llamó— así que un matcher que solo mirara el TIPO habría
  // seguido en verde aunque se sacara la precondición de acá. Se pide el
  // `name` para asegurarse de que el que se atrapó es el de `sujetos`.
  final esPrecondicionDeSujetosVacios =
      isArgumentError.having((e) => e.name, 'name', 'sujetos');

  test('un alcance pedido vacío es precondición violada, no un desenlace', () {
    // Verificar nada no es ni verde ni no concluyente: es un error de quien
    // llama, igual que un alcance sin sujetos utilizables lo es para un paso.
    expect(
        () => Cascada([_Paso.verde('A')], observador: _obsDeLib())
            .correr(const []),
        throwsA(esPrecondicionDeSujetosVacios));
  });

  test(
      'lo mismo vale con el registro vacío: no hay no-concluyente silencioso '
      'sobre la nada', () {
    // Antes esta rama NO lanzaba —devolvía noConcluyente por sinVerificadores,
    // sin que nadie hubiera dicho que verificar sobre una lista vacía era un
    // error—, mientras que con pasos registrados sí lanzaba, aunque con la
    // excepción equivocada. Las dos ramas tienen que comportarse igual.
    expect(() => Cascada(const [], observador: _obsDeLib()).correr(const []),
        throwsA(esPrecondicionDeSujetosVacios));
  });

  test('avisa MIENTRAS corre, no al final', () async {
    final orden = <String>[];
    await Cascada([_Paso.verde('A'), _Paso.verde('B')], observador: _obsDeLib())
        .correr(
      ['lib'],
      alEmpezar: (id) => orden.add('empieza:$id'),
      alTerminar: (id, _) => orden.add('termina:$id'),
    );
    expect(orden, ['empieza:A', 'termina:A', 'empieza:B', 'termina:B'],
        reason: 'B no puede anunciarse antes de que A haya terminado');
  });

  test('un fallo del observador de progreso no se le atribuye al verificador',
      () async {
    // `alTerminar` está fuera del `try` que clasifica fallos del paso: si
    // quien consume el protocolo se rompe, que suba y sea un error del
    // arnés, no un fallo del paso que ya había terminado su trabajo.
    expect(
      () => Cascada([_Paso.verde('A')], observador: _obsDeLib()).correr(
        ['lib'],
        alTerminar: (_, __) => throw StateError('falló el observador'),
      ),
      throwsStateError,
    );
  });

  group('el libro de obligaciones', () {
    test('un paso que cubre un subconjunto SIN explicar el resto no da verde',
        () async {
      // El falso verde reproducido sobre el código anterior: un paso cubría
      // los dos archivos y el otro uno solo, y la corrida salía verde. La
      // unión de los pasos no es la obligación de cada paso.
      final obs = ObservadorDeAlcanceFalso(observados: {
        'a.fuente':
            ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
        'b.fuente':
            ObservedSubject(subject: 'b.fuente', ofStack: true, files: 1),
      });
      final r = await Cascada([
        _PasoQueCubre('A', const ['a.fuente', 'b.fuente']),
        _PasoQueCubre('B', const ['a.fuente']),
      ], observador: obs)
          .correr(['a.fuente', 'b.fuente']);

      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.obligacionesSinSaldar, [(paso: 'B', sujeto: 'b.fuente')]);
      expect(r.causas, contains(CausaNoConcluyente.obligacionSinSaldar));
    });

    test('una omisión que NOMBRA el sujeto sí salda la obligación', () async {
      final obs = ObservadorDeAlcanceFalso(observados: {
        'a.fuente':
            ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
        'b.fuente':
            ObservedSubject(subject: 'b.fuente', ofStack: true, files: 1),
      });
      final r = await Cascada([
        _PasoQueCubre('A', const ['a.fuente'],
            omite: [Omission(subject: 'b.fuente', reason: 'no lo leí')]),
      ], observador: obs)
          .correr(['a.fuente', 'b.fuente']);
      expect(r.obligacionesSinSaldar, isEmpty);
      expect(r.estado, EstadoDeCorrida.verde);
    });

    test('una omisión SIN sujeto no salda ninguna obligación', () async {
      // Es residuo general: el paso cuya herramienta no informa qué leyó no
      // puede atribuirlo a nadie, así que tampoco puede saldar con él.
      final obs = ObservadorDeAlcanceFalso(observados: {
        'a.fuente':
            ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
      });
      final r = await Cascada([
        _PasoQueCubre('A', const [],
            omite: [Omission(reason: 'no informa qué leyó')]),
      ], observador: obs)
          .correr(['a.fuente']);
      expect(r.obligacionesSinSaldar, [(paso: 'A', sujeto: 'a.fuente')]);
    });

    test('un paso saltado o no observable no contrae obligaciones', () async {
      // Su alcance esperado está vacío: no había sujetos utilizables.
      final obs = ObservadorDeAlcanceFalso(observados: {
        'LEEME.md': ObservedSubject(
            subject: 'LEEME.md', ofStack: false, files: 0, reason: 'ajeno'),
      });
      final r = await Cascada([_Paso.verde('A')], observador: obs)
          .correr(['LEEME.md']);
      expect(r.obligacionesSinSaldar, isEmpty);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.causas, contains(CausaNoConcluyente.nadaEjecutado));
    });
  });

  group('la precedencia se deriva', () {
    test('un registro vacío no es verde', () async {
      final r =
          await Cascada(const [], observador: _obsDeLib()).correr(['lib']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.causas, contains(CausaNoConcluyente.sinVerificadores));
    });

    test('lo roto gana sobre todo', () async {
      final r = await Cascada([
        _Paso.rojo('A'),
        _Paso('B', lanza: StateError('x')),
      ], observador: _obsDeLib())
          .correr(['lib']);
      expect(r.estado, EstadoDeCorrida.errorInterno);
    });

    test('lo no concluyente gana sobre el rojo, y el hallazgo se conserva',
        () async {
      final r = await Cascada([_Paso.rojo('A'), _Paso.abortado('B')],
              observador: _obsDeLib())
          .correr(['lib']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.diagnosticos, hasLength(1));
      expect(r.causas, contains(CausaNoConcluyente.pasoAbortado));
    });

    test('un sujeto no observado impide el verde aunque todo lo demás pase',
        () async {
      final obs = ObservadorDeAlcanceFalso(
        observados: {
          'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1)
        },
        noObservados: const {'no/existe': 'no existe'},
      );
      final r = await Cascada([
        _PasoQueCubre('A', const ['lib'])
      ], observador: obs)
          .correr(['lib', 'no/existe']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.causas, contains(CausaNoConcluyente.alcanceNoObservable));
    });

    test(
        'alcance MIXTO —un ajeno y uno inobservable, nada utilizable—: la '
        'primera causa es lo no observable, no nada ejecutado', () async {
      // El caso puro (todo inobservable, ningún ajeno) ya distinguía las dos
      // causas porque `nadaEjecutado` no tenía ningún ajeno que nombrar y el
      // texto de más arriba lo notaba. Este caso es el que un review
      // reprodujo y el puro no cazaba: con un ajeno DE VERDAD en la mezcla,
      // `nadaEjecutado` primero nombra ESE ajeno con total normalidad —no
      // nombra nada ausente— y esconde que además hubo una ruta que ni
      // siquiera se pudo mirar. Es la misma precedencia que ya vale por paso
      // («no pude mirar» gana sobre «no había nada mío»), y antes de este
      // fix no valía también para el agregado de toda la corrida.
      final obs = ObservadorDeAlcanceFalso(
        observados: {
          'LEEME.md': ObservedSubject(
              subject: 'LEEME.md',
              ofStack: false,
              files: 0,
              reason: 'no es de este stack'),
        },
        noObservados: const {'no/existe': 'no existe'},
      );
      final r = await Cascada([_Paso.verde('A')], observador: obs)
          .correr(['LEEME.md', 'no/existe']);
      expect(r.causas.first, CausaNoConcluyente.alcanceNoObservable,
          reason: 'nombrar solo el ajeno callaría la ruta que ni se pudo '
              'mirar: una afirmación parcial, no el bug literal de nombrar '
              'evidencia ausente, pero la misma familia');
      expect(r.causas, contains(CausaNoConcluyente.nadaEjecutado),
          reason: 'las dos causas concurren; lo que cambia es cuál es la '
              'primera');
    });

    test(
        'alcance SANO y todos los pasos ABORTAN: `nadaEjecutado` no dispara '
        '—no hay ningún ajeno que nombrar—', () async {
      // Reordenar `alcanceNoObservable` antes que `nadaEjecutado` cerró la
      // combinación anterior (un ajeno + una ruta inobservable), pero no la
      // CLASE de bug: acá el alcance es enteramente sano —todo de stack,
      // nada inobservable— así que `alcanceNoObservable` ni siquiera entra
      // en juego, y sin embargo `ejecutados` queda vacío porque los dos
      // pasos abortan. Antes de este fix, `nadaEjecutado` disparaba igual y
      // su texto enumeraba una lista de ajenos vacía: el error original
      // exacto, con otra combinación que un reordenamiento no podía cazar.
      final obs = ObservadorDeAlcanceFalso(observados: {
        'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
      });
      final r = await Cascada([_Paso.abortado('A'), _Paso.abortado('B')],
              observador: obs)
          .correr(['lib']);
      expect(r.causas, isNot(contains(CausaNoConcluyente.nadaEjecutado)),
          reason: 'no hay ningún sujeto ajeno al stack que nombrar');
      expect(r.causas, contains(CausaNoConcluyente.pasoAbortado));
      expect(r.causas, isNotEmpty,
          reason: 'sin ajenos, `Skipped` no se pudo haber construido —exige '
              'al menos uno—, así que todo lo que no ejecutó abortó, no '
              'observó o se rompió, y cada uno dispara su propia causa');
    });

    test('verde solo cuando ninguna pregunta negativa se contesta que sí',
        () async {
      final r = await Cascada([
        _PasoQueCubre('A', const ['lib'])
      ], observador: _obsDeLib())
          .correr(['lib']);
      expect(r.estado, EstadoDeCorrida.verde);
      expect(r.causas, isEmpty);
    });
  });

  group('el invariante del alcance esperado', () {
    // `ResultadoDeCascada` ya no confía en que `RegisteredStep.expectedScope`
    // venga bien armado: antes el denominador del libro de obligaciones era
    // literalmente `alcance.usable()`, y su corrección salía gratis de que
    // `ScopeObservation` valida su partición contra lo pedido.
    // `expectedScope` es un campo libre, así que estas pruebas construyen
    // `ResultadoDeCascada` DIRECTAMENTE —sin pasar por `Cascada.correr`, que
    // siempre arma el campo bien— para comprobar que el propio constructor lo
    // rechaza cuando no coincide con lo utilizable.

    ScopeObservation obsConDosUtilizables() => ScopeObservation(
          requested: const ['a.fuente', 'b.fuente'],
          observed: [
            ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
            ObservedSubject(subject: 'b.fuente', ofStack: true, files: 1),
          ],
          unobserved: const [],
          observedAt: DateTime.utc(2026),
        );

    test(
        'un alcance esperado más CHICO que lo utilizable no se deja '
        'construir', () {
      // El falso verde que abrió la puerta el cambio de tipo: con
      // `expectedScope` vacío, un paso que cubre uno solo de los dos sujetos
      // utilizables no debía nada sobre el otro, y la corrida salía verde con
      // cero obligaciones sin saldar.
      expect(
        () => ResultadoDeCascada(
          registrados: [RegisteredStep(id: 'A', expectedScope: const [])],
          alcance: obsConDosUtilizables(),
          desenlaces: {
            'A': Executed(
                witness: _testigo(sujetos: const ['a.fuente']),
                diagnostics: const []),
          },
        ),
        throwsArgumentError,
      );
    });

    test(
        'un alcance esperado con sujetos que la observación no dio como '
        'utilizables no se deja construir', () {
      expect(
        () => ResultadoDeCascada(
          registrados: [
            RegisteredStep(id: 'A', expectedScope: const ['a.fuente', 'zzz'])
          ],
          alcance: obsConDosUtilizables(),
          desenlaces: {
            'A': Executed(
                witness: _testigo(sujetos: const ['a.fuente']),
                diagnostics: const []),
          },
        ),
        throwsArgumentError,
      );
    });

    test('un sujeto esperado en blanco tampoco se deja construir', () {
      // Un blanco en `expectedScope` dispara DOS guardias distintas: la que
      // rechaza cualquier sujeto en blanco, y la de igualdad contra lo
      // utilizable —el blanco nunca puede ser utilizable, así que también es
      // excedente—. `throwsArgumentError` no discrimina cuál de las dos
      // disparó: si se borrara el chequeo de blancos, la de igualdad seguiría
      // rechazando este mismo caso por la MISMA razón de superficie, y la
      // prueba seguiría en verde sin haber probado nada sobre el chequeo que
      // dice aislar. Se verifica el mensaje para que solo la guardia de
      // blancos la haga pasar.
      expect(
        () => ResultadoDeCascada(
          registrados: [
            RegisteredStep(id: 'A', expectedScope: const ['a.fuente', '   '])
          ],
          alcance: obsConDosUtilizables(),
          desenlaces: {
            'A': Executed(
                witness: _testigo(sujetos: const ['a.fuente']),
                diagnostics: const []),
          },
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('espera un sujeto en blanco'),
        )),
      );
    });

    test('el alcance esperado igual al utilizable sí se deja construir', () {
      // El control negativo: sin él, no se sabría si las pruebas de arriba
      // fallan porque el invariante funciona o porque CUALQUIER cosa falla.
      expect(
        () => ResultadoDeCascada(
          registrados: [
            RegisteredStep(
                id: 'A', expectedScope: const ['a.fuente', 'b.fuente'])
          ],
          alcance: obsConDosUtilizables(),
          desenlaces: {
            'A': Executed(
                witness: _testigo(sujetos: const ['a.fuente', 'b.fuente']),
                diagnostics: const []),
          },
        ),
        returnsNormally,
      );
    });
  });

  group('el desenlace no puede contradecir a la observación', () {
    // `Skipped` y `Unobservable` validan su PROPIA forma —la lista no
    // vacía, y que `Skipped` no marque como ajeno a un sujeto que el propio
    // desenlace dice del stack— pero ninguno de los dos sabe, por su
    // cuenta, si lo que declaran es lo que ESTA corrida observó de verdad.
    // Mientras el único productor de `ResultadoDeCascada` sea
    // `Cascada.correr`, la correspondencia sale gratis; construyéndolo
    // directamente —como hacen ya varias pruebas de este archivo, y como
    // va a hacerlo la tarea siguiente para sus propiedades— nada más lo
    // garantiza. Es el mismo error que el alcance esperado ya cerró más
    // arriba, en la otra mitad del tipo.
    ScopeObservation obsConUnSujetoSano() => ScopeObservation(
          requested: const ['lib'],
          observed: [
            ObservedSubject(subject: 'lib', ofStack: true, files: 1),
          ],
          unobserved: const [],
          observedAt: DateTime.utc(2026),
        );

    test(
        'un Skipped no puede declarar ajeno a un sujeto que la observación '
        'no dio como tal — antes daba VERDE', () {
      // El contraejemplo real: alcance sano de un único sujeto, cero ajenos
      // y nada inobservable en la observación de verdad. El único paso se
      // «salta» declarando un ajeno INVENTADO —un sujeto que ni siquiera se
      // pidió—. `ejecutados` queda vacío, `causas` queda vacía (no hay
      // ningún ajeno REAL que la condición de `nadaEjecutado` pueda
      // encontrar), y sin el invariante de este grupo la corrida entera
      // salía verde.
      expect(
        () => ResultadoDeCascada(
          registrados: [
            RegisteredStep(id: 'A', expectedScope: const ['lib'])
          ],
          alcance: obsConUnSujetoSano(),
          desenlaces: {
            'A': Skipped(notOfStack: [
              ObservedSubject(
                  subject: 'ajeno-inventado',
                  ofStack: false,
                  files: 0,
                  reason: 'inventado'),
            ]),
          },
        ),
        throwsArgumentError,
      );
    });

    test(
        'un Unobservable no puede declarar una causa que la observación no '
        'tiene', () {
      expect(
        () => ResultadoDeCascada(
          registrados: [
            RegisteredStep(id: 'A', expectedScope: const ['lib'])
          ],
          alcance: obsConUnSujetoSano(),
          desenlaces: {
            'A': Unobservable(causes: [
              UnobservedSubject(
                  subject: 'inexistente-inventado', cause: 'inventada'),
            ]),
          },
        ),
        throwsArgumentError,
      );
    });

    test(
        'un Skipped que declara EXACTAMENTE los ajenos reales sí se deja '
        'construir', () {
      // El control negativo, otra vez: sin él no se sabría si el invariante
      // funciona o si CUALQUIER `Skipped` se rechaza.
      final obs = ScopeObservation(
        requested: const ['LEEME.md'],
        observed: [
          ObservedSubject(
              subject: 'LEEME.md', ofStack: false, files: 0, reason: 'ajeno'),
        ],
        unobserved: const [],
        observedAt: DateTime.utc(2026),
      );
      expect(
        () => ResultadoDeCascada(
          registrados: [RegisteredStep(id: 'A', expectedScope: const [])],
          alcance: obs,
          desenlaces: {
            'A': Skipped(notOfStack: [
              ObservedSubject(
                  subject: 'LEEME.md',
                  ofStack: false,
                  files: 0,
                  reason: 'ajeno'),
            ]),
          },
        ),
        returnsNormally,
      );
    });
  });
}
