/// Lo que el ejecutable recibe **de verdad**, medido con un script que lo
/// imprime.
///
/// No se comprueba contra el mapa que le pasamos: se comprueba contra lo que el
/// proceso hijo ve en su propio entorno, que es lo único que importa.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;
  late File imprimeEntorno;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('ejecutor_');
    imprimeEntorno = File('${raiz.path}/entorno.sh')
      ..writeAsStringSync('#!/bin/sh\nenv\n');
    Process.runSync('chmod', ['755', imprimeEntorno.path]);
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  Future<ResultadoDeProceso> correr(EjecutorDeProceso e) => e.correr(
    imprimeEntorno.path,
    const [],
    directorio: raiz.path,
    presupuesto: const Duration(seconds: 30),
  );

  /// Qué variables ve el hijo, como mapa.
  ///
  /// **No se exige que sean exactamente las de la lista blanca**, y eso no es
  /// laxitud: está medido que el propio intérprete agrega `PWD`, `SHLVL` y `_`
  /// por su cuenta, y cuáles agrega depende de qué `sh` sea —acá uno, en el
  /// runner otro—. Una prueba de igualdad exacta mediría el intérprete, no el
  /// saneamiento. Lo que la regla promete es lo que se comprueba abajo: que
  /// ninguna variable del padre fuera de la lista llegue.
  Map<String, String> visto(ResultadoDeProceso r) => {
    for (final linea in r.salidaEstandar.trim().split('\n'))
      if (linea.contains('=')) linea.split('=').first: linea.split('=').last,
  };

  test('el ejecutable recibe la lista blanca, y no el token', () async {
    final r = await correr(
      EjecutorDelSistema(
        entornoDelPadre: EntornoDelProceso(const {
          'PATH': '/usr/bin:/bin',
          'HOME': '/home/u',
          'PUB_CACHE': '/home/u/.cache-de-paquetes',
          'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
        }),
      ),
    );
    expect(r.terminacion, Termination.completa);
    final v = visto(r);
    expect(v['PATH'], '/usr/bin:/bin');
    expect(v['HOME'], '/home/u');
    expect(v['PUB_CACHE'], '/home/u/.cache-de-paquetes');
    expect(
      v.containsKey('SHIPFLOW_GITHUB_TOKEN'),
      isFalse,
      reason: 'el token del padre no puede llegar a una herramienta ajena',
    );
    expect(r.salidaEstandar, isNot(contains('secreto-de-prueba')));
  });

  test('sin PUB_CACHE en el padre, el hijo tampoco la tiene', () async {
    final r = await correr(
      EjecutorDelSistema(
        entornoDelPadre: EntornoDelProceso(const {'PATH': '/usr/bin:/bin'}),
      ),
    );
    expect(visto(r).containsKey('PUB_CACHE'), isFalse);
    expect(visto(r)['PATH'], '/usr/bin:/bin');
  });

  test('sin entorno declarado se usa el del proceso, saneado', () async {
    final r = await correr(const EjecutorDelSistema());
    final claves = visto(r).keys.toSet();
    expect(claves, contains('PATH'));
    expect(visto(r)['PATH'], Platform.environment['PATH']);

    // **Qué se agrega el intérprete solo se MIDE, no se enumera.** Con un
    // padre vacío, todo lo que el hijo muestre lo puso él: `PWD` y `SHLVL`
    // aparecen así, y cuáles sean depende de qué `sh` haya. Medirlo en la misma
    // corrida y con el mismo intérprete hace la aserción exacta en cualquier
    // máquina, en vez de escribir una lista que envejece sola.
    final soloDelInterprete = visto(
      await correr(
        EjecutorDelSistema(entornoDelPadre: EntornoDelProceso(const {})),
      ),
    ).keys.toSet();
    expect(
      claves.difference(listaBlanca).difference(soloDelInterprete),
      isEmpty,
      reason:
          'el hijo no vio nada que no esté en la lista o que no se '
          'agregue el intérprete',
    );
  });
}
