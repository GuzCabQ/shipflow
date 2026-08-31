/// La cascada: el registro, la cuenta y la precedencia.
///
/// El doble vive acá y no en `plugin_fake` a propósito: `orchestration` no
/// puede depender de ningún plugin —esa es la regla que lo mantiene ignorante
/// del stack— así que su prueba trae el suyo.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

Witness _testigo({List<String> sujetos = const ['lib/']}) => Witness(
      invocation: 'herramienta',
      subjects: sujetos,
      omitted: const [],
      termination: Termination.completa,
      exitCode: 0,
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
}
