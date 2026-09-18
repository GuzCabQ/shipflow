import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

/// La misma [EntradaDeShip] que produciría `--file lib/a.txt --intent
/// "algo"`: lo mínimo que `previsualizacion` necesita para tener algo que
/// mostrar.
EntradaDeShip entradaDePrueba() => EntradaDeShip(
  intent: 'algo',
  archivos: ['lib/a.txt'],
  rutaDeLaRebanada: null,
  branch: null,
  base: null,
  dryRun: false,
  yes: false,
  allowIncomplete: false,
);

/// Un [ArtefactoDeRevision] mínimo pero válido: una afirmación cubierta sobre
/// `lib/a.txt`, sin nada que requiera criterio, en una corrida verde.
ArtefactoDeRevision artefactoDePrueba() {
  final cubierto = AfirmacionCubierta.fromJson({
    'controlId': 'formateo',
    'sujeto': 'lib/a.txt',
    'afirmacion': {
      'id': 'formateo-limpio',
      'demuestra': 'el archivo está formateado',
      'noDemuestra': 'que el archivo compile',
    },
    'testigo': {
      'invocation': 'dart format --output=none lib/a.txt',
      'subjects': ['lib/a.txt'],
      'exitCode': 0,
      'omitted': <Object?>[],
      'finishedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    },
  });

  return ArtefactoDeRevision(
    superficie: SuperficieDeVerificacion(
      cubierto: [cubierto],
      requiereCriterio: const [],
      estado: EstadoDeCorrida.verde,
    ),
    candidato: CandidateIdentity(
      contentRevision: 'a' * 40,
      baseRevision: 'b' * 40,
    ),
    intent: 'algo',
    plan: null,
    sinPlanPorque: 'la rebanada es de un solo archivo trivial',
    alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
  );
}

void main() {
  test('la compuerta, estado por estado', () {
    expect(
      autoriza(estado: EstadoDeCorrida.verde, allowIncomplete: false),
      isTrue,
    );
    for (final e in [EstadoDeCorrida.rojo, EstadoDeCorrida.noConcluyente]) {
      expect(
        autoriza(estado: e, allowIncomplete: false),
        isFalse,
        reason: e.name,
      );
      expect(
        autoriza(estado: e, allowIncomplete: true),
        isTrue,
        reason: e.name,
      );
    }
    expect(
      autoriza(estado: EstadoDeCorrida.errorInterno, allowIncomplete: true),
      isFalse,
      reason: '--allow-incomplete no autoriza el arnés roto',
    );
  });

  test('la compuerta cubre TODOS los estados', () {
    // Un estado nuevo tiene que obligar a decidir si publica.
    for (final e in EstadoDeCorrida.values) {
      expect(
        () => autoriza(estado: e, allowIncomplete: false),
        returnsNormally,
      );
    }
  });

  test('la previsualización muestra la evidencia, no un resumen', () {
    final p = previsualizacion(
      entrada: entradaDePrueba(),
      rama: 'feature/x',
      base: 'main',
      artefacto: artefactoDePrueba(),
      cambiosAjenos: ['notas.txt'],
    );
    for (final esperado in ['feature/x', 'main', 'lib/a.txt', 'notas.txt']) {
      expect(p, contains(esperado), reason: esperado);
    }
  });

  test('los cambios ajenos se muestran LOCALMENTE y no van al artefacto', () {
    final artefacto = artefactoDePrueba();
    final p = previsualizacion(
      entrada: entradaDePrueba(),
      rama: 'feature/x',
      base: 'main',
      artefacto: artefacto,
      cambiosAjenos: ['notas.txt'],
    );
    expect(p, contains('notas.txt'));
    expect(
      jsonEncode(artefacto.toJson()),
      isNot(contains('notas.txt')),
      reason:
          'publicarle al revisor remoto rutas que no puede ver filtra '
          'nombres de trabajo local y no es accionable',
    );
  });
}
