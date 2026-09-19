import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('HEAD suelto es preflight, no una rama vacía', () {
    final r = preflight(
      ramaActual: '',
      branchPedida: null,
      baseExplicita: 'main',
      credencial: const Credential('ghp_x', label: 'x'),
    );
    expect(r, isA<PreflightFallo>());
    expect((r as PreflightFallo).causa, CausaDePreflight.headSuelto);
  });

  test('--branch es una ASERCIÓN: si no coincide, falla', () {
    final r = preflight(
      ramaActual: 'feature/a',
      branchPedida: 'feature/b',
      baseExplicita: 'main',
      credencial: const Credential('ghp_x', label: 'x'),
    );
    expect((r as PreflightFallo).causa, CausaDePreflight.ramaNoCoincide);
    expect(
      r.queHacer,
      contains('feature/b'),
      reason: 'la acción tiene que nombrar la rama que se pidió',
    );
  });

  test('la rama actual igual a la base falla', () {
    // Commitear sobre la base y pedir un PR contra ella misma no es una
    // entrega: es un cambio directo sin revisión.
    final r = preflight(
      ramaActual: 'main',
      branchPedida: null,
      baseExplicita: 'main',
      credencial: const Credential('ghp_x', label: 'x'),
    );
    expect((r as PreflightFallo).causa, CausaDePreflight.baseIgualALaRama);
  });

  test('sin credencial falla ANTES de cualquier escritura', () {
    final r = preflight(
      ramaActual: 'feature/a',
      branchPedida: null,
      baseExplicita: 'main',
      credencial: null,
    );
    expect((r as PreflightFallo).causa, CausaDePreflight.credencialAusente);
  });

  test('una base que no se puede determinar falla en vez de adivinarse', () {
    final r = preflight(
      ramaActual: 'feature/a',
      branchPedida: null,
      baseExplicita: null,
      baseConfigurada: null,
      baseDeLaForja: null,
      credencial: const Credential('ghp_x', label: 'x'),
    );
    expect((r as PreflightFallo).causa, CausaDePreflight.baseIndeterminada);
  });

  test('la cadena de la base respeta su orden', () {
    expect(
      (preflight(
                ramaActual: 'feature/a',
                branchPedida: null,
                baseExplicita: 'explicita',
                baseConfigurada: 'configurada',
                baseDeLaForja: 'deLaForja',
                credencial: const Credential('ghp_x', label: 'x'),
              )
              as PreflightOk)
          .base,
      'explicita',
    );
    expect(
      (preflight(
                ramaActual: 'feature/a',
                branchPedida: null,
                baseExplicita: null,
                baseConfigurada: 'configurada',
                baseDeLaForja: 'deLaForja',
                credencial: const Credential('ghp_x', label: 'x'),
              )
              as PreflightOk)
          .base,
      'configurada',
    );
    expect(
      (preflight(
                ramaActual: 'feature/a',
                branchPedida: null,
                baseExplicita: null,
                baseConfigurada: null,
                baseDeLaForja: 'deLaForja',
                credencial: const Credential('ghp_x', label: 'x'),
              )
              as PreflightOk)
          .base,
      'deLaForja',
    );
  });

  test('el preflight NO comprueba el directorio de corridas', () {
    // Comprobarlo acá impediría el primer uso: el directorio no existe
    // todavía. Se crea y se comprueba DESPUÉS de la compuerta y ANTES de
    // persistir `prepared`.
    final r = preflight(
      ramaActual: 'feature/a',
      branchPedida: null,
      baseExplicita: 'main',
      credencial: const Credential('ghp_x', label: 'x'),
    );
    expect(r, isA<PreflightOk>());
  });
}
