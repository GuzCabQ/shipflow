# Desenlace cerrado y observador de alcance · plan de implementación

> **ESTADO: ejecutado. Las casillas nunca se usaron, y quedan sin marcar a propósito.**
>
> Las trece tareas se ejecutaron con `superpowers:subagent-driven-development`, que lleva su progreso en un registro aparte —uno por tarea, con sus commits— y no en las casillas de este archivo. Ninguna se marcó, así que las sesenta y ocho de abajo dicen «nada hecho» mientras el `README` dice que la parte de código está terminada. **Lo cierto es el `README` y el `git log`**, no estas casillas: lo encontró un review, que leyó las dos cosas y no pudo decidir cuál valía.
>
> Se dejan sin marcar en vez de marcarlas ahora: marcarlas retroactivamente sería fabricar un registro de ejecución que nadie llevó, que es la misma clase de afirmación sin respaldo que este plan existe para eliminar del código.
>
> **Para quien ejecute esto:** usá `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans`, tarea por tarea. Los pasos llevan casilla (`- [ ]`) para marcarlos.

**Objetivo.** Hacer imposibles por construcción los dos falsos verdes que hoy se pueden ejecutar en la cascada de verificación, moviendo la aplicabilidad fuera del verificador y cerrando el desenlace de un paso en un tipo sellado.

**Arquitectura.** Un puerto nuevo observa el alcance una vez por corrida y devuelve **hechos** por sujeto; la orquestación los convierte en decisiones. El resultado de un paso pasa de campos opcionales a variantes cerradas, donde lo que un verificador puede devolver es un subconjunto propio de lo que la cascada puede producir. Un libro de obligaciones por par paso‑sujeto reemplaza a la guardia de «todos saltados».

**Stack.** Dart 3 con `dart test`. Cuatro paquetes del workspace: `core` sin dependencias, `orchestration`, `plugin_dart`, `plugin_fake`, `cli`. Checks propios en Python y Dart bajo `tool/`.

**Diseño que implementa.** `../sdlc-agentico/borradores/PROPUESTA-verificacion-desenlace-cerrado.md`. Leelo antes de la primera tarea: este plan argumenta desde ahí y no repite sus razones.

## Restricciones globales

Valen para toda tarea. Copiadas del diseño y de las reglas ya instaladas del repositorio.

- **`core` no tiene dependencias externas ni entrada/salida.** No puede importar `package:path` ni nada de la biblioteca de archivos. Dos checks lo hacen cumplir.
- **`orchestration` no puede ver ningún plugin.** Sus dobles de prueba viven en su propia suite.
- **Las cadenas del stack no aparecen fuera de `plugin_dart` y del composition root**, con alcance en `packages/` y extensiones `.dart`, `.yaml`, `.yml`, `.json`, `.sh`, `.bash`, `.md`.
- **En `core`, todo campo de colección se copia a una vista inmodificable en el constructor.** Nunca entra por referencia.
- **En `core`, los campos públicos de una clase son exactamente las claves de su `toJson` y las que lee su `fromJson`.** Ni una de más ni una de menos.
- **Una clase de `core` o serializa, o está declarada opaca con su motivo** en `arquitectura.json`.
- **Ningún veredicto ni estado es un campo asignable.** Se derivan.
- **Ningún motivo, causa o nota se acepta en blanco**, en ningún tipo que los lleve.
- **Cada tarea termina con la suite del paquete que tocó en verde**, y con un commit.

## Refinamientos del diseño que este plan fija

Dos cosas que la propuesta dejó abiertas y que el código obliga a cerrar antes de escribir:

1. **La identidad de un sujeto es la cadena tal como se pidió.** La propuesta pedía «identidad de ruta canónica definida» para la partición. `core` no puede normalizar rutas porque no puede importar nada, así que la partición se comprueba por igualdad de cadena contra lo pedido, y **la canonización queda adentro del observador**, que sí puede hacerla, y solo para decidir hechos — nunca para renombrar el sujeto que devuelve.
2. **Rechazar una lista de motivos vacía es parte de la misma regla.** El invariante «ningún motivo en blanco» se escribe con `any`, y `any` sobre una lista vacía es falso: hay que rechazar el vacío aparte, o el arreglo abre el agujero que venía a cerrar.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `packages/core/lib/src/alcance.dart` **nuevo** | `ObservedSubject`, `UnobservedSubject`, `ScopeObservation`. Los hechos sobre el alcance, y la partición |
| `packages/core/lib/src/desenlace.dart` **nuevo** | `StepOutcome` sellado y sus cinco variantes, `Omission`, `Attempt`. Sale de `observacion.dart` para que ese archivo no crezca a dos responsabilidades |
| `packages/core/lib/src/valores.dart` | `Witness` pierde terminación y conteo, gana su invariante |
| `packages/core/lib/src/observacion.dart` | Pierde `NotApplicable` y `VerificationOutcome`; conserva trazas y hallazgos |
| `packages/core/lib/src/puertos.dart` | `ScopeObserver` nuevo; `Verifier.run` cambia de tipo |
| `packages/orchestration/lib/src/cascada.dart` | Registro con alcance esperado, clasificación, libro de obligaciones, estado derivado |
| `packages/plugin_dart/lib/src/alcance.dart` **nuevo** | El observador del stack. Recibe lo que hoy vive dentro del paso |
| `packages/plugin_dart/lib/src/pasos.dart` | Deja de separar el alcance; devuelve las variantes nuevas |
| `packages/plugin_fake/lib/src/alcance.dart` **nuevo** | Observador en memoria, segunda implementación viva del puerto |
| `packages/cli/lib/src/salida.dart` | Esquema `2`, `runId` |
| `packages/cli/lib/src/verify.dart` | Compone el observador; `switch` de cinco variantes |

---

## Tarea 0 · Un motivo en blanco no es un motivo, en ningún tipo

Cierra el hallazgo de las dos reglas distintas. No rompe nada y no depende de nada.

**Archivos:**
- Modificar: `packages/core/lib/src/observacion.dart` — constructor de `NotApplicable`
- Modificar: `packages/orchestration/lib/src/cascada.dart` — constructor de `PasoSaltado`
- Probar: `packages/core/test/verificacion_test.dart`, `packages/orchestration/test/cascada_test.dart`

**Interfaces:**
- Consume: nada.
- Produce: nada nuevo. Endurece dos constructores existentes.

- [ ] **Paso 1: escribir las pruebas que fallan**

En `packages/core/test/verificacion_test.dart`, dentro de `void main()`:

```dart
  test('un motivo en blanco entre motivos válidos tampoco se acepta', () {
    // `Witness.omitted` rechaza cualquier blanco; esto aceptaba la lista si
    // al menos un motivo era válido. Dos reglas para el mismo hecho.
    expect(
        () => NotApplicable(
              subjects: const ['lib/'],
              reasons: const ['no es de este stack', '   '],
              decidedAt: DateTime.utc(2026),
            ),
        throwsArgumentError);
  });

  test('una lista de motivos vacía sigue sin aceptarse', () {
    // El control negativo del arreglo: `any` sobre una lista vacía es falso,
    // así que cambiar `every` por `any` sin esto abre el agujero que el
    // cambio venía a cerrar.
    expect(
        () => NotApplicable(
              subjects: const ['lib/'],
              reasons: const [],
              decidedAt: DateTime.utc(2026),
            ),
        throwsArgumentError);
  });
```

En `packages/orchestration/test/cascada_test.dart`, dentro del grupo `'un paso que no tuvo nada que hacer'`:

```dart
    test('un salto con un motivo en blanco entre válidos tampoco se construye',
        () {
      expect(
          () => PasoSaltado(
              id: 'B',
              motivos: const ['no es de este stack', '  '],
              declaracion: _sinNadaSuyo()),
          throwsArgumentError);
    });

    test('un salto sin ningún motivo tampoco', () {
      expect(
          () => PasoSaltado(
              id: 'B', motivos: const [], declaracion: _sinNadaSuyo()),
          throwsArgumentError);
    });
```

- [ ] **Paso 2: correr y ver que fallan**

```
dart test packages/core/test/verificacion_test.dart packages/orchestration/test/cascada_test.dart
```

Esperado: fallan los cuatro casos nuevos con «Expected: throws ArgumentError», salvo los dos de lista vacía, que ya pasan porque `every` sobre el vacío es verdadero. Anotá cuáles fallan: son los dos de motivo en blanco entre válidos.

- [ ] **Paso 3: corregir los dos constructores**

En `packages/core/lib/src/observacion.dart`, el constructor de `NotApplicable`:

```dart
    if (this.reasons.isEmpty || this.reasons.any((m) => m.trim().isEmpty)) {
      throw ArgumentError.value(
          reasons,
          'reasons',
          'Un paso que no dice por qué no tuvo nada que hacer es un salto '
              'silencioso. Y un motivo en blanco ocupa lugar en la lista sin '
              'decir nada: sacalo, o escribí por qué');
    }
```

En `packages/orchestration/lib/src/cascada.dart`, el constructor de `PasoSaltado`:

```dart
    if (this.motivos.isEmpty || this.motivos.any((m) => m.trim().isEmpty)) {
      throw ArgumentError.value(
          motivos,
          'motivos',
          'Un salto sin motivo es un salto silencioso, y un motivo en blanco '
              'no es un motivo. Si el paso no supo decir por qué no tenía nada '
              'que hacer, no se puede afirmar que no lo tenía');
    }
```

- [ ] **Paso 4: correr y ver que pasan**

```
dart test packages/core packages/orchestration
```

Esperado: todo verde. Si algo más falla, hay un doble de prueba construyendo una lista de motivos con un blanco: corregí el doble, no el invariante.

- [ ] **Paso 5: commitear**

```bash
git add packages/core packages/orchestration
git commit -m "Un motivo en blanco no es un motivo, en ningún tipo

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 1 · Los hechos sobre el alcance, en `core`

Tipos nuevos y aditivos. Nada existente los usa todavía, así que nada se rompe.

**Archivos:**
- Crear: `packages/core/lib/src/alcance.dart`
- Modificar: `packages/core/lib/core.dart` — exportarlo
- Crear: `packages/core/test/alcance_test.dart`
- Modificar: `packages/core/test/serializacion_test.dart` — la instancia canónica

**Interfaces:**
- Consume: nada.
- Produce: `ObservedSubject({required String subject, required bool ofStack, required int files, String? reason})`; `UnobservedSubject({required String subject, required String cause})`; `ScopeObservation({required List<String> requested, required List<ObservedSubject> observed, required List<UnobservedSubject> unobserved, required DateTime observedAt})` con `List<String> usable()`. Los tres con `toJson()` y `fromJson(Map<String, Object?>)`.

- [ ] **Paso 1: escribir la suite que falla**

Crear `packages/core/test/alcance_test.dart`:

```dart
/// La observación del alcance es una PARTICIÓN de lo que se pidió.
///
/// Sin eso, un sujeto puede desaparecer entre lo pedido y lo utilizable y
/// ninguna guardia posterior lo ve: la corrida sale verde sobre un archivo que
/// nadie miró. Hoy la partición es cierta por construcción y nada la comprueba.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

ObservedSubject delStack(String s, {int archivos = 1}) =>
    ObservedSubject(subject: s, ofStack: true, files: archivos);

ObservedSubject ajeno(String s) => ObservedSubject(
    subject: s, ofStack: false, files: 0, reason: 'no es de este stack');

ScopeObservation obs({
  required List<String> pedidos,
  List<ObservedSubject> observados = const [],
  List<UnobservedSubject> noObservados = const [],
}) =>
    ScopeObservation(
      requested: pedidos,
      observed: observados,
      unobserved: noObservados,
      observedAt: DateTime.utc(2026),
    );

void main() {
  group('la partición es exacta', () {
    test('observados más no observados son exactamente lo pedido', () {
      final o = obs(
        pedidos: const ['lib', 'no/existe'],
        observados: [delStack('lib', archivos: 3)],
        noObservados: [
          UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol')
        ],
      );
      expect(o.usable(), ['lib']);
    });

    test('un sujeto pedido que no aparece en ninguna lista se rechaza', () {
      // El agujero: desaparece antes de calcular lo utilizable y nadie lo ve.
      expect(
          () => obs(pedidos: const ['lib', 'test'], observados: [delStack('lib')]),
          throwsArgumentError);
    });

    test('un sujeto que aparece y no se pidió se rechaza', () {
      expect(
          () => obs(
              pedidos: const ['lib'],
              observados: [delStack('lib'), delStack('test')]),
          throwsArgumentError);
    });

    test('un sujeto en las dos listas se rechaza', () {
      expect(
          () => obs(
                pedidos: const ['lib'],
                observados: [delStack('lib')],
                noObservados: [
                  UnobservedSubject(subject: 'lib', cause: 'no se dejó leer')
                ],
              ),
          throwsArgumentError);
    });

    test('un sujeto repetido dentro de una lista se rechaza', () {
      expect(
          () => obs(
              pedidos: const ['lib'],
              observados: [delStack('lib'), delStack('lib')]),
          throwsArgumentError);
    });

    test('la identidad es la cadena TAL COMO SE PIDIÓ', () {
      // `core` no puede normalizar rutas: no importa nada. Si el observador
      // devolviera `lib` para un pedido `./lib`, la partición no cierra y el
      // rechazo es correcto — la canonización es asunto suyo, y no puede
      // renombrar el sujeto que devuelve.
      expect(() => obs(pedidos: const ['./lib'], observados: [delStack('lib')]),
          throwsArgumentError);
    });
  });

  group('un sujeto observado dice una sola cosa', () {
    test('ajeno al stack no puede traer archivos', () {
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: false, files: 2, reason: 'x'),
          throwsArgumentError);
    });

    test('ajeno al stack sin motivo no dice por qué', () {
      expect(() => ObservedSubject(subject: 'a', ofStack: false, files: 0),
          throwsArgumentError);
    });

    test('ajeno al stack con motivo en blanco tampoco', () {
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: false, files: 0, reason: '  '),
          throwsArgumentError);
    });

    test('del stack con cero archivos es una contradicción', () {
      expect(() => ObservedSubject(subject: 'a', ofStack: true, files: 0),
          throwsArgumentError);
    });

    test('del stack con motivo es una contradicción', () {
      // El motivo existe para explicar por qué NO era suyo.
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: true, files: 1, reason: 'x'),
          throwsArgumentError);
    });

    test('un sujeto en blanco no es un sujeto', () {
      expect(() => ObservedSubject(subject: '  ', ofStack: true, files: 1),
          throwsArgumentError);
    });
  });

  group('un sujeto no observado dice su causa', () {
    test('una causa en blanco no es una causa', () {
      expect(() => UnobservedSubject(subject: 'a', cause: ' '),
          throwsArgumentError);
    });
  });

  test('mutar las listas originales no cambia la observación', () {
    final pedidos = ['lib'];
    final observados = [delStack('lib')];
    final o = obs(pedidos: pedidos, observados: observados);
    pedidos.clear();
    observados.clear();
    expect(o.usable(), ['lib']);
    expect(() => o.observed.add(delStack('otro')), throwsUnsupportedError);
  });

  test('lo utilizable excluye lo ajeno al stack', () {
    final o = obs(
        pedidos: const ['lib', 'LEEME.md'],
        observados: [delStack('lib'), ajeno('LEEME.md')]);
    expect(o.usable(), ['lib']);
  });

  test('ida y vuelta por JSON', () {
    final o = obs(
      pedidos: const ['lib', 'no/existe'],
      observados: [delStack('lib', archivos: 3)],
      noObservados: [
        UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol')
      ],
    );
    final ida = ScopeObservation.fromJson(o.toJson());
    expect(ida.usable(), o.usable());
    expect(ida.unobserved.single.cause, 'no existe en el árbol');
    expect(ida.observed.single.files, 3);
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/core/test/alcance_test.dart
```

Esperado: no compila, «Undefined name 'ObservedSubject'».

- [ ] **Paso 3: escribir los tipos**

Crear `packages/core/lib/src/alcance.dart`:

```dart
/// Lo que el arnés sabe del alcance **antes** de invocar nada.
///
/// Son hechos, no conclusiones. Quién decide que un alcance sin sujetos del
/// stack es un salto no es quien lo observa: eso lo hace la orquestación, y es
/// el corolario 4 de ADR-011 vuelto estructura.
///
/// **La identidad de un sujeto es la cadena tal como se pidió.** Este paquete
/// no puede normalizar rutas porque no puede importar nada, así que la
/// partición se comprueba por igualdad. Un observador que canonice —y debe
/// hacerlo para decidir los hechos— no puede renombrar lo que devuelve.
library;

/// Un sujeto que se **pudo** mirar.
class ObservedSubject {
  final String subject;

  /// Si le incumbe al stack de este plugin.
  final bool ofStack;

  /// Cuántos archivos de fuente hay debajo. Cero solo si no es del stack.
  final int files;

  /// Por qué NO es del stack. Presente si y solo si [ofStack] es falso.
  final String? reason;

  ObservedSubject({
    required this.subject,
    required this.ofStack,
    required this.files,
    this.reason,
  }) {
    if (subject.trim().isEmpty) {
      throw ArgumentError.value(subject, 'subject', 'Un sujeto en blanco no nombra nada');
    }
    if (files < 0) {
      throw ArgumentError.value(files, 'files', 'Un conteo negativo no significa nada');
    }
    if (ofStack) {
      if (files < 1) {
        throw ArgumentError.value(files, 'files',
            'Un sujeto del stack con cero archivos afirma dos cosas '
            'incompatibles. Si no hay archivos, no es del stack');
      }
      if (reason != null) {
        throw ArgumentError.value(reason, 'reason',
            'El motivo explica por qué un sujeto NO es del stack. Uno que sí '
            'lo es no tiene qué explicar');
      }
    } else {
      if (files != 0) {
        throw ArgumentError.value(files, 'files',
            'Un sujeto ajeno al stack no aporta archivos de fuente');
      }
      if (reason == null || reason!.trim().isEmpty) {
        throw ArgumentError.value(reason, 'reason',
            'Un sujeto que se descarta sin decir por qué es un descarte '
            'silencioso, y el corolario 1 de ADR-011 lo prohíbe');
      }
    }
  }

  Map<String, Object?> toJson() =>
      {'subject': subject, 'ofStack': ofStack, 'files': files, 'reason': reason};

  factory ObservedSubject.fromJson(Map<String, Object?> json) => ObservedSubject(
        subject: json['subject']! as String,
        ofStack: json['ofStack']! as bool,
        files: json['files']! as int,
        reason: json['reason'] as String?,
      );
}

/// Un sujeto que **no se pudo** mirar. No es lo mismo que uno ajeno al stack:
/// de este no se puede afirmar nada.
class UnobservedSubject {
  final String subject;

  /// Qué lo impidió: no existe, no se deja leer, lo que sea.
  final String cause;

  UnobservedSubject({required this.subject, required this.cause}) {
    if (subject.trim().isEmpty) {
      throw ArgumentError.value(subject, 'subject', 'Un sujeto en blanco no nombra nada');
    }
    if (cause.trim().isEmpty) {
      throw ArgumentError.value(cause, 'cause',
          'Sin causa, «no pude mirar» es indistinguible de «no miré»');
    }
  }

  Map<String, Object?> toJson() => {'subject': subject, 'cause': cause};

  factory UnobservedSubject.fromJson(Map<String, Object?> json) =>
      UnobservedSubject(
        subject: json['subject']! as String,
        cause: json['cause']! as String,
      );
}

/// El alcance mirado una sola vez, **particionado**.
class ScopeObservation {
  /// Lo que se pidió, tal como se pidió. Es el denominador de la partición.
  final List<String> requested;

  final List<ObservedSubject> observed;
  final List<UnobservedSubject> unobserved;
  final DateTime observedAt;

  ScopeObservation({
    required List<String> requested,
    required List<ObservedSubject> observed,
    required List<UnobservedSubject> unobserved,
    required this.observedAt,
  })  : requested = List.unmodifiable(requested),
        observed = List.unmodifiable(observed),
        unobserved = List.unmodifiable(unobserved) {
    final vistos = <String>[
      for (final o in this.observed) o.subject,
      for (final u in this.unobserved) u.subject,
    ];
    final unicos = vistos.toSet();
    if (unicos.length != vistos.length) {
      throw ArgumentError.value(vistos, 'observed/unobserved',
          'Hay un sujeto clasificado dos veces. Un sujeto se pudo mirar o no '
          'se pudo, y no las dos cosas');
    }
    final pedidos = this.requested.toSet();
    if (pedidos.length != this.requested.length) {
      throw ArgumentError.value(requested, 'requested',
          'Hay un sujeto pedido dos veces. La partición no tendría denominador');
    }
    final faltan = pedidos.difference(unicos);
    if (faltan.isNotEmpty) {
      throw ArgumentError.value(faltan.toList(), 'observed/unobserved',
          'Estos sujetos se pidieron y no se clasificaron. Un sujeto que '
          'desaparece acá no lo ve ninguna guardia posterior, y la corrida '
          'puede salir verde sobre algo que nadie miró');
    }
    final sobran = unicos.difference(pedidos);
    if (sobran.isNotEmpty) {
      throw ArgumentError.value(sobran.toList(), 'observed/unobserved',
          'Estos sujetos se clasificaron y no se pidieron. La identidad es la '
          'cadena tal como se pidió: si el observador canoniza, no puede '
          'renombrar lo que devuelve');
    }
  }

  /// Los sujetos sobre los que tiene sentido invocar algo.
  List<String> usable() =>
      List.unmodifiable([for (final o in observed) if (o.ofStack) o.subject]);

  Map<String, Object?> toJson() => {
        'requested': requested,
        'observed': [for (final o in observed) o.toJson()],
        'unobserved': [for (final u in unobserved) u.toJson()],
        'observedAt': observedAt.toUtc().toIso8601String(),
      };

  factory ScopeObservation.fromJson(Map<String, Object?> json) =>
      ScopeObservation(
        requested: List<String>.from(json['requested']! as List<Object?>),
        observed: [
          for (final o in json['observed']! as List<Object?>)
            ObservedSubject.fromJson(Map<String, Object?>.from(o! as Map)),
        ],
        unobserved: [
          for (final u in json['unobserved']! as List<Object?>)
            UnobservedSubject.fromJson(Map<String, Object?>.from(u! as Map)),
        ],
        observedAt: DateTime.parse(json['observedAt']! as String),
      );
}
```

En `packages/core/lib/core.dart`, agregar junto a los otros:

```dart
export 'src/alcance.dart';
```

- [ ] **Paso 4: correr y ver que pasa**

```
dart test packages/core
```

Esperado: verde, incluidos los diecisiete casos nuevos.

- [ ] **Paso 5: agregar los tipos a la instancia canónica de serialización**

`packages/core/test/serializacion_test.dart` exige que **ningún campo del JSON tenga un valor por defecto**, para que un campo aplastado a vacío rompa la prueba. Agregá al `main()` de ese archivo:

```dart
  test('la observación de alcance no pierde nada, y no trae vacíos', () {
    final o = ScopeObservation(
      requested: const ['lib', 'no/existe'],
      observed: [ObservedSubject(subject: 'lib', ofStack: true, files: 3)],
      unobserved: [
        UnobservedSubject(subject: 'no/existe', cause: 'no existe en el árbol')
      ],
      observedAt: DateTime.utc(2026, 9, 5),
    );
    // `reason` es nulo cuando el sujeto SÍ es del stack, y eso es correcto:
    // se excluye de la comprobación de vacíos porque su ausencia es el dato.
    final json = o.toJson();
    (json['observed']! as List).forEach((e) =>
        (e as Map).remove('reason'));
    expect(valoresPorDefecto(json), isEmpty);
    expect(ScopeObservation.fromJson(o.toJson()).toJson(), o.toJson());
  });
```

- [ ] **Paso 6: correr los checks de arquitectura**

```
python3 tool/checks/capas.py
(cd tool/analisis && dart pub get && dart run bin/check.dart)
```

Esperado: verde. El check de serialización compara campos públicos contra claves del JSON: si falla, hay un campo que no está en `toJson` o al revés. `usable()` es un método y no cuenta.

- [ ] **Paso 7: commitear**

```bash
git add packages/core
git commit -m "Los hechos sobre el alcance son una partición de lo pedido

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 2 · El puerto, y el observador del stack

Extrae del paso las 77 líneas que hoy separan el alcance. Es un movimiento que preserva el comportamiento: nadie lo llama todavía.

**Archivos:**
- Modificar: `packages/core/lib/src/puertos.dart` — puerto nuevo
- Crear: `packages/plugin_dart/lib/src/alcance.dart`
- Modificar: `packages/plugin_dart/lib/plugin_dart.dart` — exportarlo
- Crear: `packages/plugin_dart/test/alcance_test.dart`

**Interfaces:**
- Consume: `ScopeObservation`, `ObservedSubject`, `UnobservedSubject` de la tarea 1.
- Produce: `abstract interface class ScopeObserver { Future<ScopeObservation> observe(List<String> requested); }`; y `ObservadorDeAlcanceDart({required String directorio})` que lo implementa.

- [ ] **Paso 1: escribir la suite que falla**

Crear `packages/plugin_dart/test/alcance_test.dart`:

```dart
/// El observador del stack. Son los casos que hoy vivían dentro del paso, más
/// los que la suite de contrato del puerto va a exigirle a cualquiera.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;
  late ObservadorDeAlcanceDart obs;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('alcance_');
    Directory('${raiz.path}/lib').createSync();
    File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
    obs = ObservadorDeAlcanceDart(directorio: raiz.path);
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  ObservedSubject unico(ScopeObservation o) => o.observed.single;

  test('un directorio con fuentes es del stack, con su conteo', () async {
    final o = await obs.observe(['lib']);
    expect(unico(o).ofStack, isTrue);
    expect(unico(o).files, 1);
    expect(o.usable(), ['lib']);
  });

  test('un archivo de fuente nombrado directo es del stack', () async {
    final o = await obs.observe(['lib/a.dart']);
    expect(unico(o).ofStack, isTrue);
    expect(unico(o).files, 1);
  });

  test('un archivo que no es del stack se descarta CON motivo', () async {
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
    final o = await obs.observe(['LEEME.md']);
    expect(unico(o).ofStack, isFalse);
    expect(unico(o).reason, isNotNull);
    expect(o.usable(), isEmpty);
  });

  test('un directorio real SIN fuentes es ajeno, no inobservable', () async {
    // El falso rojo simétrico: se pudo mirar, y no había nada suyo.
    Directory('${raiz.path}/prosa').createSync();
    File('${raiz.path}/prosa/LEEME.md').writeAsStringSync('# hola\n');
    final o = await obs.observe(['prosa']);
    expect(o.unobserved, isEmpty);
    expect(unico(o).ofStack, isFalse);
    expect(unico(o).files, 0);
  });

  test('una ruta que no existe es INOBSERVABLE, no ajena', () async {
    // «No pude mirar» no es «no había nada mío». Un review lo cobró.
    final o = await obs.observe(['no/existe']);
    expect(o.observed, isEmpty);
    expect(o.unobserved.single.cause, contains('no existe'));
  });

  test('un directorio sin permisos es inobservable', () async {
    final cerrado = Directory('${raiz.path}/cerrado')..createSync();
    File('${cerrado.path}/x.dart').writeAsStringSync('void main() {}\n');
    Process.runSync('chmod', ['000', cerrado.path]);
    addTearDown(() => Process.runSync('chmod', ['700', cerrado.path]));
    final o = await obs.observe(['cerrado']);
    expect(o.unobserved.single.cause, contains('no se pudo mirar'));
  }, onPlatform: const {'windows': Skip('los permisos POSIX no aplican')});

  test('lo que cuelga de una carpeta oculta no se cuenta', () async {
    // Está medido: la herramienta del stack salta los componentes ocultos al
    // recorrer. Contarlos haría que la reconciliación no cerrara nunca.
    Directory('${raiz.path}/lib/.oculto').createSync();
    File('${raiz.path}/lib/.oculto/c.dart').writeAsStringSync('void main() {}\n');
    final o = await obs.observe(['lib']);
    expect(unico(o).files, 1);
  });

  test('un alcance mixto se particiona entero', () async {
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
    final o = await obs.observe(['lib', 'LEEME.md', 'no/existe']);
    expect(o.requested, hasLength(3));
    expect(o.observed.map((e) => e.subject), containsAll(['lib', 'LEEME.md']));
    expect(o.unobserved.single.subject, 'no/existe');
    expect(o.usable(), ['lib']);
  });

  test('el sujeto vuelve TAL COMO SE PIDIÓ, aunque haya que canonizarlo',
      () async {
    // El observador canoniza para decidir el hecho; si además renombrara el
    // sujeto, la partición de `core` no cerraría.
    final o = await obs.observe(['./lib']);
    expect(o.observed.single.subject, './lib');
    expect(o.observed.single.ofStack, isTrue);
  });

  test('un alcance vacío da una observación vacía, no un error', () async {
    final o = await obs.observe(const []);
    expect(o.requested, isEmpty);
    expect(o.usable(), isEmpty);
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/plugin_dart/test/alcance_test.dart
```

Esperado: no compila, «Undefined name 'ObservadorDeAlcanceDart'».

- [ ] **Paso 3: declarar el puerto**

En `packages/core/lib/src/puertos.dart`, en la sección de puertos de stack, justo antes de `Verifier`:

```dart
/// Mira el alcance y devuelve **hechos por sujeto**, no conclusiones.
///
/// Existe porque el corolario 4 de ADR-011 dice que ningún verificador juzga
/// su propia cobertura, y declarar «este archivo no es mío» es exactamente
/// eso. El paso dejaba de ser juez de su ejecución y seguía siendo juez de su
/// incumbencia.
///
/// **Cláusulas del contrato:**
///
/// 1. **La observación es una partición de lo pedido**, y lo hace cumplir el
///    tipo. Un sujeto que se pierde acá no lo ve ninguna guardia posterior.
/// 2. **El sujeto vuelve tal como se pidió.** Canonizar para decidir el hecho
///    es necesario; renombrar lo devuelto rompe la partición.
/// 3. **No se pudo mirar y no era mío son distintos.** Lo primero es un sujeto
///    no observado con su causa; lo segundo, uno observado y ajeno con su
///    motivo. Confundirlos es el falso rojo simétrico del falso verde.
/// 4. **Se llama UNA vez por corrida.** Dos lecturas del árbol pueden diferir,
///    y entonces dos pasos verifican alcances distintos que el reporte declara
///    iguales.
abstract interface class ScopeObserver {
  Future<ScopeObservation> observe(List<String> requested);
}
```

Agregá `import 'alcance.dart';` arriba si el analizador lo pide.

- [ ] **Paso 4: escribir el observador del stack**

Crear `packages/plugin_dart/lib/src/alcance.dart`:

```dart
/// El observador de alcance de este stack.
///
/// Es lo que vivía dentro de `PasoDeCascada` como `_mirar` y `separar`. Salió
/// de ahí por una razón de autoridad y no de orden: mientras el paso decidiera
/// qué era suyo, decidía su propia exención.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;

/// El sufijo de los archivos que las herramientas de este stack leen.
const sufijoDeFuente = '.dart';

class ObservadorDeAlcanceDart implements ScopeObserver {
  final String directorio;

  const ObservadorDeAlcanceDart({required this.directorio});

  @override
  Future<ScopeObservation> observe(List<String> requested) async {
    final observados = <ObservedSubject>[];
    final noObservados = <UnobservedSubject>[];

    // Se congela al entrar: la lista es del llamador.
    for (final pedido in List<String>.unmodifiable(requested)) {
      final r = _mirar(pedido);
      if (r.causa != null) {
        noObservados.add(UnobservedSubject(subject: pedido, cause: r.causa!));
      } else {
        observados.add(ObservedSubject(
          subject: pedido,
          ofStack: r.archivos > 0,
          files: r.archivos,
          reason: r.archivos > 0 ? null : r.motivo,
        ));
      }
    }

    return ScopeObservation(
      requested: requested,
      observed: observados,
      unobserved: noObservados,
      observedAt: DateTime.now().toUtc(),
    );
  }

  /// Cuántos archivos de fuente hay bajo un sujeto; o por qué no es del stack;
  /// o por qué no se pudo establecer.
  ///
  /// **Los componentes ocultos no se cuentan al recorrer un directorio**, y
  /// eso está medido: la herramienta salta todo lo que cuelga de una carpeta
  /// que empieza con punto. Un sujeto nombrado explícitamente sí se procesa
  /// aunque sea oculto, también medido, y por eso la regla se aplica a lo que
  /// hay debajo del sujeto y no al sujeto.
  ({int archivos, String? motivo, String? causa}) _mirar(String pedido) {
    final absoluto =
        rutas.isAbsolute(pedido) ? pedido : rutas.join(directorio, pedido);
    try {
      if (File(absoluto).existsSync()) {
        return absoluto.endsWith(sufijoDeFuente)
            ? (archivos: 1, motivo: null, causa: null)
            : (
                archivos: 0,
                motivo: 'no es un archivo de fuente de este stack',
                causa: null,
              );
      }
      final carpeta = Directory(absoluto);
      if (!carpeta.existsSync()) {
        return (archivos: 0, motivo: null, causa: 'no existe en el árbol');
      }
      final cuantos = carpeta
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith(sufijoDeFuente))
          .where((f) => !rutas
              .split(rutas.relative(f.path, from: absoluto))
              .any((parte) => parte.startsWith('.')))
          .length;
      return cuantos == 0
          ? (
              archivos: 0,
              motivo: 'no contiene ningún archivo de fuente',
              causa: null,
            )
          : (archivos: cuantos, motivo: null, causa: null);
    } on FileSystemException catch (e) {
      // **No poder mirar es un dato, no una excepción que se escapa.** Se
      // atrapa esta familia y no `Object`: un error de programación tiene que
      // seguir subiendo.
      return (
        archivos: 0,
        motivo: null,
        causa: 'no se pudo mirar: ${e.osError?.message ?? e.message}',
      );
    }
  }
}
```

En `packages/plugin_dart/lib/plugin_dart.dart`, agregar:

```dart
export 'src/alcance.dart';
```

- [ ] **Paso 5: correr y ver que pasa**

```
dart test packages/plugin_dart/test/alcance_test.dart
```

Esperado: los once casos en verde.

- [ ] **Paso 6: correr los checks**

```
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart)
```

Esperado: verde. Si `puertos-sin-implementacion` se queja, es porque el puerto quedó declarado sin implementación en `arquitectura.json`: no lo declares, ya la tiene.

- [ ] **Paso 7: commitear**

```bash
git add packages/core packages/plugin_dart
git commit -m "Quién decide qué es del stack deja de ser el verificador

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 3 · La segunda implementación, y la suite de contrato

Sin dos implementaciones el puerto es una indirección que todavía no se contradijo. Y sin suite de contrato, el observador es un componente con autoridad y sin refutador.

**Archivos:**
- Crear: `packages/plugin_fake/lib/src/alcance.dart`
- Modificar: `packages/plugin_fake/lib/plugin_fake.dart`
- Crear: `packages/cli/test/contrato_alcance_test.dart`

**Interfaces:**
- Consume: `ScopeObserver`, `ObservadorDeAlcanceDart`.
- Produce: `ObservadorDeAlcanceFalso({required Map<String, ObservedSubject> observados, Map<String, String> noObservados = const {}})`. El fake responde de una tabla en memoria y no toca el disco.

- [ ] **Paso 1: escribir la suite de contrato que falla**

Crear `packages/cli/test/contrato_alcance_test.dart`. Vive en `cli` porque es el único paquete que puede ver los dos plugins.

```dart
/// Suite de contrato de `ScopeObserver`, contra las DOS implementaciones.
///
/// Lo que se prueba acá vale para cualquier stack. Los formatos y los sufijos
/// son del plugin y no aparecen: cada caso trae su propio escenario.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

/// Cada implementación arma su escenario: un sujeto del stack, uno ajeno y uno
/// que no se puede mirar.
typedef Escenario = ({
  ScopeObserver observador,
  String delStack,
  String ajeno,
  String inobservable,
});

void main() {
  late Directory raiz;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('contrato_alcance_');
    Directory('${raiz.path}/lib').createSync();
    File('${raiz.path}/lib/a.dart').writeAsStringSync('void main() {}\n');
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  final implementaciones = <String, Escenario Function()>{
    'real · stack': () => (
          observador: ObservadorDeAlcanceDart(directorio: raiz.path),
          delStack: 'lib',
          ajeno: 'LEEME.md',
          inobservable: 'no/existe',
        ),
    'falso · en memoria': () => (
          observador: ObservadorDeAlcanceFalso(
            observados: {
              'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
              'LEEME.md': ObservedSubject(
                  subject: 'LEEME.md',
                  ofStack: false,
                  files: 0,
                  reason: 'no es de este stack'),
            },
            noObservados: const {'no/existe': 'no existe en el árbol'},
          ),
          delStack: 'lib',
          ajeno: 'LEEME.md',
          inobservable: 'no/existe',
        ),
  };

  test('la suite corre contra DOS implementaciones', () {
    expect(implementaciones, hasLength(2));
  });

  implementaciones.forEach((nombre, armar) {
    group(nombre, () {
      test('cláusula 1 · la observación particiona lo pedido', () async {
        final e = armar();
        final o = await e.observador
            .observe([e.delStack, e.ajeno, e.inobservable]);
        final clasificados = {
          ...o.observed.map((x) => x.subject),
          ...o.unobserved.map((x) => x.subject),
        };
        expect(clasificados, {e.delStack, e.ajeno, e.inobservable});
      });

      test('cláusula 2 · el sujeto vuelve tal como se pidió', () async {
        final e = armar();
        final o = await e.observador.observe([e.delStack]);
        expect(o.observed.single.subject, e.delStack);
      });

      test('cláusula 3 · no pude mirar y no era mío son distintos', () async {
        final e = armar();
        final o = await e.observador.observe([e.ajeno, e.inobservable]);
        expect(o.unobserved.single.subject, e.inobservable,
            reason: 'lo que no se pudo mirar no puede presentarse como ajeno');
        expect(o.observed.single.subject, e.ajeno);
        expect(o.observed.single.ofStack, isFalse);
        expect(o.observed.single.reason, isNotNull);
      });

      test('y sin embargo SÍ reconoce lo que es del stack', () async {
        // Sin esto, un observador que devolviera todo como inobservable
        // pasaría las tres cláusulas por la vía de no funcionar.
        final e = armar();
        final o = await e.observador.observe([e.delStack]);
        expect(o.usable(), [e.delStack]);
        expect(o.observed.single.files, greaterThan(0));
      });

      test('un alcance vacío no es un error', () async {
        final e = armar();
        final o = await e.observador.observe(const []);
        expect(o.usable(), isEmpty);
      });
    });
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/cli/test/contrato_alcance_test.dart
```

Esperado: no compila, «Undefined name 'ObservadorDeAlcanceFalso'».

- [ ] **Paso 3: escribir el fake**

Crear `packages/plugin_fake/lib/src/alcance.dart`:

```dart
/// Un observador de alcance que responde de una tabla. **No toca el disco.**
///
/// Existe para que `orchestration` y el CLI puedan probar la clasificación sin
/// toolchain ni árbol, y para que el puerto tenga la segunda implementación
/// que lo vuelve un contrato en vez de una indirección.
library;

import 'package:core/core.dart';

class ObservadorDeAlcanceFalso implements ScopeObserver {
  /// Qué se sabe de cada sujeto que sí se pudo mirar.
  final Map<String, ObservedSubject> observados;

  /// Sujeto a causa, para los que no se pudieron mirar.
  final Map<String, String> noObservados;

  /// Qué se le pidió, para poder comprobar que se llamó una sola vez.
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
      // **Un sujeto que la tabla no declara no se inventa como ajeno.** Sería
      // el fake decidiendo, que es justo lo que el puerto vino a impedir.
      if (o == null) {
        throw ArgumentError.value(s, 'requested',
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
```

En `packages/plugin_fake/lib/plugin_fake.dart`, agregar:

```dart
export 'src/alcance.dart';
```

- [ ] **Paso 4: correr y ver que pasa**

```
dart test packages/cli/test/contrato_alcance_test.dart
```

Esperado: once casos en verde, cinco por implementación más el de la cuenta.

- [ ] **Paso 5: commitear**

```bash
git add packages/plugin_fake packages/cli
git commit -m "El observador gana su segunda implementación y su contrato

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 4 · El paso delega, y deja de decidir

Preserva el comportamiento. Su valor es exactamente ese: las pruebas de alcance que hoy pasan tienen que seguir pasando **a través del observador**, y eso demuestra que el reemplazo es equivalente antes de tocar los tipos.

**Archivos:**
- Modificar: `packages/plugin_dart/lib/src/pasos.dart` — borrar `_mirar` y `separar`, recibir el observador
- Modificar: `packages/plugin_dart/test/pasos_test.dart` — mover los casos de alcance
- Modificar: `packages/cli/lib/src/verify.dart` — pasarle el observador a cada paso

**Interfaces:**
- Consume: `ScopeObserver`, `ObservadorDeAlcanceDart`.
- Produce: `PasoDeCascada({required EjecutorDeProceso ejecutor, required String directorio, ScopeObserver? observador, Duration presupuesto})`. Si no se le da observador, usa el del stack sobre el mismo directorio.

- [ ] **Paso 1: agregar el caso que prueba la delegación**

En `packages/plugin_dart/test/pasos_test.dart`:

```dart
  test('el paso NO mira el árbol por su cuenta: le pregunta al observador',
      () async {
    // Si el paso siguiera decidiendo qué es suyo, seguiría siendo juez de su
    // propia incumbencia. Con un observador que declara `lib` ajeno, el paso
    // no puede invocar nada, por más que `lib` exista y tenga fuentes.
    final falso = ObservadorDeAlcanceFalso(observados: {
      'lib': ObservedSubject(
          subject: 'lib',
          ofStack: false,
          files: 0,
          reason: 'el observador dice que no'),
    });
    final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
    final paso = PasoDeFormato(
        ejecutor: ejecutor, directorio: raiz.path, observador: falso);
    await paso.run(['lib']);
    expect(ejecutor.invocaciones, isEmpty);
    expect(falso.llamadas, hasLength(1),
        reason: 'una sola foto del árbol por corrida de paso');
  });
```

Agregá los imports de `plugin_fake` al archivo y a `packages/plugin_dart/pubspec.yaml` bajo `dev_dependencies`:

```yaml
  plugin_fake:
    path: ../plugin_fake
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/plugin_dart/test/pasos_test.dart
```

Esperado: no compila, `PasoDeFormato` no acepta `observador`.

- [ ] **Paso 3: delegar**

En `packages/plugin_dart/lib/src/pasos.dart`:

1. Borrá los métodos `_mirar` y `separar` **enteros**, y la constante `sufijoDeFuente` de la clase: ahora viven en `alcance.dart`.
2. Agregá el campo y el parámetro:

```dart
  /// Quién mira el alcance. **No lo mira el paso**: ADR-011 corolario 4.
  final ScopeObserver observador;

  PasoDeCascada({
    required this.ejecutor,
    required this.directorio,
    ScopeObserver? observador,
    this.presupuesto = const Duration(minutes: 5),
  }) : observador =
            observador ?? ObservadorDeAlcanceDart(directorio: directorio);
```

Dejá de declarar los constructores `const`: el campo se calcula.

3. En `run`, reemplazá `final alcance = separar(pedidos);` por la traducción desde la observación:

```dart
    final observacion = await observador.observe(pedidos);
    final alcance = (
      sanos: observacion.usable(),
      motivos: <String>[
        for (final o in observacion.observed)
          if (!o.ofStack) '${o.subject}: ${o.reason}',
        for (final u in observacion.unobserved) '${u.subject}: ${u.cause}',
      ],
      archivos: observacion.observed
          .where((o) => o.ofStack)
          .fold(0, (n, o) => n + o.files),
      // `null` no es cero: si algo no se pudo mirar, el conteo no se puede
      // establecer. Es la misma distinción, ahora sostenida por el tipo.
      observable: observacion.unobserved.isEmpty,
    );
```

4. En `packages/plugin_dart/lib/src/pasos.dart`, agregá `import 'alcance.dart';`.

- [ ] **Paso 4: mover los casos de alcance**

Sacá de `packages/plugin_dart/test/pasos_test.dart` los cuatro casos que ahora prueban al observador y no al paso: «un sujeto que NO EXISTE deja el conteo en no sé», «un directorio que NO SE DEJA LEER tampoco da cero», «un directorio real SIN archivos del stack: no aplicaba» y «lo que cuelga de una carpeta oculta no se cuenta». Sus equivalentes ya están en `alcance_test.dart`. **No los borres sin comprobar que el equivalente existe**: si alguno no tiene par, movelo en vez de borrarlo.

- [ ] **Paso 5: componer el observador en el CLI**

En `packages/cli/lib/src/verify.dart`, dentro de `cascadaPorDefecto`, agregá el parámetro y pasalo:

```dart
Cascada cascadaPorDefecto({
  required String directorio,
  EjecutorDeProceso ejecutor = const EjecutorDelSistema(),
  ScopeObserver? observador,
  Duration presupuesto = const Duration(minutes: 5),
}) {
  final obs = observador ?? ObservadorDeAlcanceDart(directorio: directorio);
  return Cascada([
    PasoDeFormato(
        ejecutor: ejecutor,
        directorio: directorio,
        observador: obs,
        presupuesto: presupuesto),
    PasoDeAnalisis(
        ejecutor: ejecutor,
        directorio: directorio,
        observador: obs,
        presupuesto: presupuesto),
  ]);
}
```

- [ ] **Paso 6: correr todo**

```
dart test packages/core packages/orchestration packages/plugin_dart packages/cli
```

Esperado: **todo verde, sin cambiar ninguna aserción de comportamiento.** Si alguna falla, el observador no es equivalente a lo que reemplazó: arreglá el observador, no la prueba.

- [ ] **Paso 7: correr los checks y commitear**

```
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart)
```

```bash
git add packages tool
git commit -m "El paso deja de mirar el árbol por su cuenta

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 5 · El desenlace cerrado

La tarea que rompe. A partir de acá el árbol está rojo hasta la tarea 9: hacelas seguidas.

**Archivos:**
- Crear: `packages/core/lib/src/desenlace.dart`
- Modificar: `packages/core/lib/src/valores.dart` — `Witness`
- Modificar: `packages/core/lib/src/observacion.dart` — borrar `NotApplicable` y `VerificationOutcome`
- Modificar: `packages/core/lib/src/puertos.dart` — la firma de `Verifier.run`
- Modificar: `packages/core/lib/core.dart`
- Modificar: `packages/core/test/verificacion_test.dart`

**Interfaces:**
- Consume: `ObservedSubject`, `UnobservedSubject`, `Diagnostic`, `Severity`, `Termination`, `Verdict`.
- Produce:
  - `Omission({String? subject, required String reason})`
  - `Witness({required String invocation, required List<String> subjects, required List<Omission> omitted, required int exitCode, required DateTime finishedAt})` — **sin** `termination` ni `ownSubjects`
  - `Attempt({required String invocation, required List<String> subjects, required Termination termination, required int exitCode, required String note, required DateTime finishedAt})`
  - `sealed class StepOutcome { StepKind get kind; }` con `enum StepKind { executed, aborted, skipped, unobservable, broken }`
  - `sealed class VerificationOutcome extends StepOutcome` — lo único que `run` devuelve
  - `Executed({required Witness witness, required List<Diagnostic> diagnostics})` con `Verdict get verdict`
  - `Aborted({required Attempt attempt})`
  - `Skipped({required List<ObservedSubject> notOfStack})`
  - `Unobservable({required List<UnobservedSubject> causes})`
  - `Broken({required String component, required String error, required String context})`
  - `Verifier.run(List<String> subjects) → Future<VerificationOutcome>`, **sin `verifierId` en el resultado**

- [ ] **Paso 1: escribir la suite que falla**

Reescribí `packages/core/test/verificacion_test.dart`. Lo esencial, que reemplaza a los casos de `VerificationOutcome`:

```dart
Witness testigo({
  List<String> sujetos = const ['lib/a.fuente'],
  String invocacion = 'herramienta --sobre lib',
  int exitCode = 0,
  List<Omission> omitido = const [],
}) =>
    Witness(
      invocation: invocacion,
      subjects: sujetos,
      omitted: omitido,
      exitCode: exitCode,
      finishedAt: DateTime.utc(2026),
    );

void main() {
  group('el veredicto de un paso ejecutado se deriva', () {
    test('con cobertura y sin bloqueantes: verde', () {
      expect(Executed(witness: testigo(), diagnostics: []).verdict, Verdict.verde);
    });

    test('con cobertura y un bloqueante: rojo', () {
      expect(
          Executed(witness: testigo(), diagnostics: [diag(Severity.bloquea)])
              .verdict,
          Verdict.rojo);
    });

    test('lo informativo no lo pone rojo', () {
      expect(
          Executed(witness: testigo(), diagnostics: [diag(Severity.reporta)])
              .verdict,
          Verdict.verde);
    });

    test('sin cobertura: no concluyente, aunque no haya diagnósticos', () {
      expect(
          Executed(
                  witness: testigo(
                      sujetos: const [],
                      omitido: [Omission(reason: 'no miró nada')]),
                  diagnostics: [])
              .verdict,
          Verdict.noConcluyente);
    });

    test('un código de salida distinto de cero NO es no se ejecutó', () {
      // Muchas herramientas salen con 1 cuando encuentran algo: eso significa
      // que corrieron. El resultado lo dan los diagnósticos, no el código.
      expect(Executed(witness: testigo(exitCode: 1), diagnostics: []).verdict,
          Verdict.verde);
    });

    test('el veredicto no es un campo: no hay dónde fijarlo', () {
      expect(
          Executed(witness: testigo(), diagnostics: [])
              .toJson()
              .containsKey('verdict'),
          isFalse);
    });
  });

  group('un testigo que no cubre nada TIENE que decir por qué', () {
    test('sin cobertura y sin omisión no se construye', () {
      // Cierra la acción imposible: hoy un paso queda no concluyente sin decir
      // por qué, y el CLI manda a leer una lista vacía.
      expect(() => testigo(sujetos: const []), throwsArgumentError);
    });

    test('una invocación en blanco no atestigua nada', () {
      expect(() => testigo(invocacion: '  '), throwsArgumentError);
    });

    test('una omisión con motivo en blanco no es una omisión', () {
      expect(() => Omission(subject: 'a', reason: ' '), throwsArgumentError);
    });

    test('una omisión puede no nombrar sujeto: es residuo general', () {
      const o = Omission(reason: 'la herramienta no informa qué archivos leyó');
      expect(o.subject, isNull);
    });

    test('el testigo ya no lleva terminación ni conteo', () {
      // Eran los dos campos con los que se fabricaba un hecho falso.
      final json = testigo().toJson();
      expect(json.containsKey('termination'), isFalse);
      expect(json.containsKey('ownSubjects'), isFalse);
    });
  });

  group('las variantes que un verificador NO puede devolver', () {
    test('un intento nunca es una terminación completa', () {
      expect(
          () => Attempt(
                invocation: 'h',
                subjects: const ['lib'],
                termination: Termination.completa,
                exitCode: 0,
                note: 'x',
                finishedAt: DateTime.utc(2026),
              ),
          throwsArgumentError);
    });

    test('un salto sin sujetos ajenos no es un salto', () {
      expect(() => Skipped(notOfStack: const []), throwsArgumentError);
    });

    test('un salto no tiene dónde llevar un diagnóstico', () {
      // No se puede escribir la prueba: no existe el campo. Este caso queda
      // como aserción sobre el JSON, que es lo que un consumidor ve.
      final s = Skipped(notOfStack: [
        ObservedSubject(
            subject: 'a', ofStack: false, files: 0, reason: 'no es de acá')
      ]);
      expect(s.toJson().containsKey('diagnostics'), isFalse);
    });

    test('lo no observable sin causa tampoco', () {
      expect(() => Unobservable(causes: const []), throwsArgumentError);
    });

    test('un roto sin componente ni error no dice nada', () {
      expect(() => Broken(component: ' ', error: 'x', context: 'y'),
          throwsArgumentError);
      expect(() => Broken(component: 'A', error: '  ', context: 'y'),
          throwsArgumentError);
    });
  });

  test('cada variante declara su clase, y son cinco', () {
    expect(StepKind.values, hasLength(5));
  });

  test('mutar la lista original no cambia el veredicto', () {
    final sujetos = ['lib/a.fuente'];
    final e = Executed(witness: testigo(sujetos: sujetos), diagnostics: []);
    sujetos.clear();
    expect(e.verdict, Verdict.verde);
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/core/test/verificacion_test.dart
```

Esperado: no compila. Es lo que se espera de la tarea que rompe.

- [ ] **Paso 3: escribir los tipos**

Crear `packages/core/lib/src/desenlace.dart` con `Omission`, `Attempt`, `StepKind`, `StepOutcome`, `VerificationOutcome`, `Executed`, `Aborted`, `Skipped`, `Unobservable` y `Broken`. Los puntos que no se pueden aflojar:

```dart
/// Qué NO cubrió un paso, y por qué.
///
/// **El sujeto es opcional, y la diferencia importa.** Con sujeto, la omisión
/// salda la obligación de ese par paso-sujeto: el paso dice que no lo miró y
/// dice por qué. Sin sujeto, es residuo general — el paso cuya herramienta no
/// informa qué archivos leyó no puede atribuirlo a ninguno.
class Omission {
  final String? subject;
  final String reason;

  /// **No es `const`, y no puede serlo:** valida en el cuerpo. Un `assert` no
  /// corre en producción, y este invariante tiene que valer siempre.
  Omission({this.subject, required this.reason}) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason',
          'Una omisión sin motivo no dice qué quedó afuera');
    }
    if (subject != null && subject!.trim().isEmpty) {
      throw ArgumentError.value(subject, 'subject',
          'Un sujeto en blanco no nombra nada. Si la omisión no es de ningún '
          'sujeto, dejalo nulo: eso significa residuo general');
    }
  }

  Map<String, Object?> toJson() => {'subject': subject, 'reason': reason};

  factory Omission.fromJson(Map<String, Object?> json) => Omission(
        subject: json['subject'] as String?,
        reason: json['reason']! as String,
      );
}

/// Los cinco desenlaces posibles de un paso.
enum StepKind { executed, aborted, skipped, unobservable, broken }

/// **No lleva el id del paso.** Lo atribuye la cascada desde su registro, y
/// por eso un paso que devuelve el resultado de otro dejó de ser
/// representable.
sealed class StepOutcome {
  StepKind get kind;
  Map<String, Object?> toJson();
}

/// Lo único que un `Verifier` puede devolver.
///
/// El salto, lo no observable y lo roto **no están acá a propósito**: los
/// produce quien compone la corrida. Un verificador que pudiera devolverlos
/// estaría pidiendo y aprobando su propia exención.
sealed class VerificationOutcome extends StepOutcome {}
```

`Executed.verdict` se deriva y no se guarda:

```dart
  Verdict get verdict {
    if (witness.subjects.isEmpty) return Verdict.noConcluyente;
    return diagnostics.any((d) => d.severity == Severity.bloquea)
        ? Verdict.rojo
        : Verdict.verde;
  }
```

En `valores.dart`, `Witness` pierde `termination` y `ownSubjects`, y gana:

```dart
    if (this.subjects.isEmpty && this.omitted.isEmpty) {
      throw ArgumentError.value(
          omitted,
          'omitted',
          'Un testigo que no cubre nada y no dice por qué deja al reporte '
              'mandando a leer una lista vacía. Si no cubriste, escribí qué '
              'quedó afuera');
    }
```

En `puertos.dart`, `Verifier` queda:

```dart
abstract interface class Verifier {
  String get id;
  Future<VerificationOutcome> run(List<String> subjects);
}
```

y sus cláusulas se reescriben: la primera pasa a decir «siempre devuelve un desenlace tipado; solo el ejecutado lleva testigo», y se agrega «un alcance vacío es precondición violada, no un desenlace».

Borrá de `observacion.dart` las clases `NotApplicable` y `VerificationOutcome`. Exportá `src/desenlace.dart` desde `core.dart`.

- [ ] **Paso 4: correr `core` y ver que pasa**

```
dart test packages/core
```

Esperado: `core` verde. Los otros tres paquetes no compilan todavía, y está bien.

- [ ] **Paso 5: commitear**

```bash
git add packages/core
git commit -m "El desenlace de un paso es un tipo cerrado

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 6 · El paso devuelve las variantes nuevas

**Archivos:**
- Modificar: `packages/plugin_dart/lib/src/pasos.dart`
- Modificar: `packages/plugin_dart/test/pasos_test.dart`, `pasos_reales_test.dart`
- Modificar: `packages/cli/test/contrato_verificador_test.dart`

**Interfaces:**
- Consume: `Executed`, `Aborted`, `Witness`, `Attempt`, `Omission`, `ScopeObserver`.
- Produce: `PasoDeCascada.run` devuelve `Executed` o `Aborted`, y **lanza `ArgumentError` si no hay ningún sujeto utilizable**. Ya no devuelve nada para el alcance vacío: eso es precondición violada.

- [ ] **Paso 1: las pruebas que fallan**

En `packages/plugin_dart/test/pasos_test.dart`, reemplazá los casos de alcance vacío y de inaplicabilidad por:

```dart
  test('un alcance sin sujetos utilizables es precondición violada', () async {
    // Antes devolvía un testigo con terminación interrumpida y código -1 sobre
    // una herramienta que nunca corrió. La cascada no puede pasarle esto: si
    // llega, es error del arnés, no un desenlace del cambio.
    final paso = PasoDeFormato(
        ejecutor: EjecutorDeclarado(salida()), directorio: raiz.path);
    expect(() => paso.run(const []), throwsArgumentError);
  });

  test('la herramienta ausente devuelve Abortado, no un testigo', () async {
    final o = await formato(salida(
            terminacion: Termination.herramientaAusente,
            codigo: -1,
            error: 'No such file or directory'))
        .run(['lib']);
    expect(o, isA<Aborted>());
    expect((o as Aborted).attempt.termination, Termination.herramientaAusente);
    expect(o.attempt.note, isNotEmpty);
  });

  test('el presupuesto agotado declara los descendientes en la nota', () async {
    final o = await analisis(
            salida(terminacion: Termination.tiempoAgotado, codigo: -1))
        .run(['lib']);
    expect(o, isA<Aborted>());
    expect((o as Aborted).attempt.note, contains('descendientes'));
  });

  test('un código desconocido es Ejecutado no concluyente, con su omisión',
      () async {
    // La herramienta corrió y produjo un resultado: eso es completa por
    // definición. Que no sepamos leerlo es nuestro problema, y va en la
    // omisión — no se falsea la terminación.
    final o = await formato(salida(codigo: 111, estandar: formatoLimpio))
        .run(['lib']);
    expect(o, isA<Executed>());
    final e = o as Executed;
    expect(e.verdict, Verdict.noConcluyente);
    expect(e.witness.omitted.map((x) => x.reason).join(), contains('111'));
  });

  test('lo descartado por el observador queda como omisión CON su sujeto',
      () async {
    // Es lo que salda la obligación de ese par paso-sujeto.
    File('${raiz.path}/LEEME.md').writeAsStringSync('# prosa\n');
    final o = await formato(salida(estandar: formatoLimpio))
        .run(['lib', 'LEEME.md']);
    final e = o as Executed;
    expect(e.witness.invocation, isNot(contains('LEEME.md')));
    expect(e.witness.omitted.where((x) => x.subject == 'LEEME.md'), hasLength(1));
  });
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/plugin_dart
```

Esperado: no compila.

- [ ] **Paso 3: migrar el paso**

En `run`, los cambios son cuatro:

1. Al entrar, después de observar: si `alcance.sanos.isEmpty`, **lanzar**. Borrá las dos ramas que devolvían testigos fabricados —la del alcance vacío y la del no observable— y la que devolvía `NotApplicable`.

```dart
    if (alcance.sanos.isEmpty) {
      throw ArgumentError.value(
          subjects,
          'subjects',
          'No hay ningún sujeto utilizable. Invocar la herramienta sin rutas '
              'la haría mirar el directorio entero, y fabricar un testigo '
              'sería declarar una ejecución que no ocurrió. Quien compone la '
              'corrida decide qué significa un alcance así');
    }
```

2. La rama de terminación incompleta devuelve `Aborted`:

```dart
    if (r.terminacion != Termination.completa) {
      return Aborted(
          attempt: Attempt(
        invocation: invocacion,
        subjects: alcance.sanos,
        termination: r.terminacion,
        exitCode: r.codigo,
        note: [
          'La herramienta no llegó a producir un resultado: ${r.salidaDeError}',
          if (r.terminacion == Termination.tiempoAgotado)
            'Los procesos descendientes no se rastrean: si la herramienta dejó '
                'hijos, pueden seguir vivos.',
        ].join(' '),
        finishedAt: DateTime.now().toUtc(),
      ));
    }
```

3. `conTestigo` deja de recibir terminación y conteo, y devuelve `Executed`. Las omisiones de `alcance.motivos` se construyen **con sujeto**, partiendo el `'sujeto: motivo'` que hoy se arma como texto: el observador ya tiene los dos por separado, así que pasale la observación a la traducción en vez de la lista de cadenas.

4. `cobertura` devuelve `({List<String> cubierto, List<Omission> omitido})`. Lo que el observador descartó lleva su sujeto, porque salda esa obligación; los residuos del paso no lo llevan, porque no se pueden atribuir a ninguno:

```dart
// Del observador: nombra el sujeto, y salda su obligación.
Omission(subject: o.subject, reason: o.reason!)

// Residuo del analizador: no se puede atribuir, así que no salda nada.
Omission(
    reason: 'La herramienta no informa qué archivos leyó: sobre un alcance '
        'vacío devuelve lo mismo que sobre uno limpio.')

// Reconciliación que no cierra: tampoco se puede atribuir, porque el resumen
// es un total y no dice a qué sujeto le faltó.
Omission(
    reason: 'El alcance tiene $archivos archivo(s) y la herramienta informó '
        '$mirados. No cierra, y el resumen es un total: no se certifica ninguno.')
```

- [ ] **Paso 4: migrar la suite de contrato del verificador**

En `packages/cli/test/contrato_verificador_test.dart`, las cláusulas pasan a ser siete. Reemplazá las cinco actuales por:

```dart
      test('cláusula 1 · devuelve Ejecutado o Abortado, nunca otra cosa',
          () async {
        final o = await paso(EjecutorDeclarado(_salida(estandar: limpio)))
            .run(['lib']);
        expect(o, anyOf(isA<Executed>(), isA<Aborted>()));
      });

      test('cláusula 2 · un alcance sin sujetos utilizables lanza', () async {
        final ejecutor = EjecutorDeclarado(_salida());
        expect(() => paso(ejecutor).run(const []), throwsArgumentError);
        expect(ejecutor.invocaciones, isEmpty);
      });

      test('cláusula 3 · una terminación incompleta es Abortado', () async {
        for (final t in [
          Termination.herramientaAusente,
          Termination.tiempoAgotado,
          Termination.interrumpida,
        ]) {
          final o =
              await paso(EjecutorDeclarado(_salida(terminacion: t, codigo: -1)))
                  .run(['lib']);
          expect(o, isA<Aborted>(), reason: 'terminación $t');
          expect((o as Aborted).attempt.termination, t);
        }
      });

      test('cláusula 4 · el testigo nombra la invocación que se hizo',
          () async {
        final ejecutor = EjecutorDeclarado(_salida(estandar: limpio));
        final o = await paso(ejecutor).run(['lib']) as Executed;
        expect(ejecutor.invocaciones, hasLength(1));
        expect(o.witness.invocation, ejecutor.invocaciones.single);
      });

      test('cláusula 5 · un código desconocido no se supone benigno', () async {
        final o = await paso(
                EjecutorDeclarado(_salida(codigo: 111, estandar: limpio)))
            .run(['lib']) as Executed;
        expect(o.verdict, Verdict.noConcluyente);
        expect(o.witness.omitted.map((x) => x.reason).join(), contains('111'));
      });

      test('cláusula 6 · el testigo no nombra sujetos que no recibió',
          () async {
        final o = await paso(EjecutorDeclarado(_salida(estandar: limpio)))
            .run(['lib']) as Executed;
        expect(o.witness.subjects.every((s) => s == 'lib'), isTrue);
      });

      test('cláusula 7 · y SÍ da verde cuando de verdad corrió y no encontró '
          'nada', () async {
        // Sin esto, un paso que devolviera no concluyente siempre pasaría
        // todas las cláusulas de arriba, por la vía de no funcionar.
        final o = await paso(EjecutorDeclarado(_salida(estandar: limpio)))
            .run(['lib']) as Executed;
        expect(o.verdict, Verdict.verde);
        expect(o.witness.subjects, isNotEmpty);
      });
```

- [ ] **Paso 5: correr y commitear**

```
dart test packages/plugin_dart
dart test packages/cli/test/contrato_verificador_test.dart packages/cli/test/contrato_alcance_test.dart
```

```bash
git add packages/plugin_dart packages/cli/test
git commit -m "El paso devuelve ejecutado o abortado, y nada más

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 7 · La cascada clasifica

**Archivos:**
- Modificar: `packages/orchestration/lib/src/cascada.dart`
- Modificar: `packages/orchestration/test/cascada_test.dart`
- Modificar: `packages/orchestration/pubspec.yaml` — `plugin_fake` como dependencia de desarrollo

**Interfaces:**
- Consume: `ScopeObserver`, `ScopeObservation`, todas las variantes de `StepOutcome`.
- Produce: `Cascada(List<Verifier> pasos, {required ScopeObserver observador})`; y `RegisteredStep({required String id, required List<String> expectedScope})`, que la cascada **arma adentro** —hoy el alcance esperado de todos es el utilizable— y expone en el resultado para que el libro de obligaciones lo lea. Cuando llegue la aplicabilidad por paso, el constructor gana un parámetro **opcional** que estrecha ese campo, y eso no rompe a nadie. `Cascada.correr(List<String> sujetos, {void Function(String)? alEmpezar, void Function(String id, StepOutcome)? alTerminar})`.

- [ ] **Paso 1: las pruebas que fallan**

En `packages/orchestration/test/cascada_test.dart`, los casos que definen la clasificación:

```dart
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
    // El impostor dejó de ser representable: el desenlace no lleva id.
    final r = await Cascada([_Paso.verde('A')], observador: _obsDeLib())
        .correr(['lib']);
    expect(r.desenlaces.keys.single, 'A');
  });
```

Agregá el ayudante `_obsDeLib()` que devuelve un `ObservadorDeAlcanceFalso` con `lib` del stack, y cambiá `_Paso` para que devuelva `Executed` en vez de `VerificationOutcome` con id.

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/orchestration
```

- [ ] **Paso 3: migrar la cascada**

Borrá `PasoSaltado`, `DesenlaceDePaso`, `PasoEjecutado`, `PasoSinNadaQueHacer` y `PasoRoto`. El cuerpo de `correr` queda así:

```dart
  Future<ResultadoDeCascada> correr(
    List<String> sujetos, {
    void Function(String id)? alEmpezar,
    void Function(String id, StepOutcome desenlace)? alTerminar,
  }) async {
    final alcance = List<String>.unmodifiable(sujetos);

    // **Una sola foto para toda la corrida.** Dos lecturas pueden diferir, y
    // entonces dos pasos verifican alcances distintos que el reporte declara
    // iguales.
    final observacion = await observador.observe(alcance);
    final utilizables = observacion.usable();
    final ajenos = [for (final o in observacion.observed) if (!o.ofStack) o];

    final desenlaces = <String, StepOutcome>{};

    for (final paso in pasos) {
      alEmpezar?.call(paso.id);
      final StepOutcome desenlace;
      if (utilizables.isEmpty) {
        // **No pude mirar gana sobre no había nada mío.** Para afirmar que no
        // había nada hay que haber podido mirar todo.
        desenlace = observacion.unobserved.isNotEmpty
            ? Unobservable(causes: observacion.unobserved)
            : Skipped(notOfStack: ajenos);
      } else {
        try {
          desenlace = await paso.run(utilizables);
        } on Object catch (e) {
          // Se atrapa cualquier excepción a propósito, y solo acá: un paso que
          // se rompe es un error del arnés, no un veredicto sobre el cambio.
          desenlace = Broken(
              component: paso.id, error: '$e', context: 'alcance: $utilizables');
        }
      }
      desenlaces[paso.id] = desenlace;
      // Fuera del `try`: una excepción del observador de progreso es del
      // arnés, no del verificador que hizo su trabajo.
      alTerminar?.call(paso.id, desenlace);
    }

    return ResultadoDeCascada(
      registrados: registrados,
      alcance: observacion,
      desenlaces: desenlaces,
    );
  }
```

`Cascada` gana el campo `observador` como parámetro obligatorio con nombre, y conserva su validación de ids duplicados y vacíos.

- [ ] **Paso 4: correr y commitear**

```
dart test packages/orchestration
```

```bash
git add packages/orchestration
git commit -m "La cascada clasifica sobre hechos, no sobre conclusiones del paso

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 8 · El resultado deriva, y el libro de obligaciones cierra el falso verde

**Archivos:**
- Modificar: `packages/orchestration/lib/src/cascada.dart` — `ResultadoDeCascada`
- Modificar: `packages/orchestration/test/cascada_test.dart`

**Interfaces:**
- Consume: `ScopeObservation`, `StepOutcome` y sus variantes.
- Produce: `ResultadoDeCascada({required List<String> registrados, required ScopeObservation alcance, required Map<String, StepOutcome> desenlaces})`, con `EstadoDeCorrida get estado`, `List<Obligacion> get obligacionesSinSaldar`, `List<CausaNoConcluyente> get causas`, `List<Diagnostic> get diagnosticos`, `List<String> get ejecutados`. `Obligacion` es `({String paso, String sujeto})`. `CausaNoConcluyente` es un `enum` con `sinVerificadores`, `nadaEjecutado`, `alcanceNoObservable`, `pasoAbortado`, `pasoNoConcluyente`, `obligacionSinSaldar`.

- [ ] **Paso 1: las pruebas que fallan**

```dart
  group('el libro de obligaciones', () {
    test('un paso que cubre un subconjunto SIN explicar el resto no da verde',
        () async {
      // El falso verde reproducido sobre el código anterior: un paso cubría
      // los dos archivos y el otro uno solo, y la corrida salía verde. La
      // unión de los pasos no es la obligación de cada paso.
      final obs = ObservadorDeAlcanceFalso(observados: {
        'a.fuente': ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
        'b.fuente': ObservedSubject(subject: 'b.fuente', ofStack: true, files: 1),
      });
      final r = await Cascada([
        _PasoQueCubre('A', const ['a.fuente', 'b.fuente']),
        _PasoQueCubre('B', const ['a.fuente']),
      ], observador: obs)
          .correr(['a.fuente', 'b.fuente']);

      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.obligacionesSinSaldar,
          [(paso: 'B', sujeto: 'b.fuente')]);
      expect(r.causas, contains(CausaNoConcluyente.obligacionSinSaldar));
    });

    test('una omisión que NOMBRA el sujeto sí salda la obligación', () async {
      final obs = ObservadorDeAlcanceFalso(observados: {
        'a.fuente': ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
        'b.fuente': ObservedSubject(subject: 'b.fuente', ofStack: true, files: 1),
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
        'a.fuente': ObservedSubject(subject: 'a.fuente', ofStack: true, files: 1),
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
      final r =
          await Cascada([_Paso.verde('A')], observador: obs).correr(['LEEME.md']);
      expect(r.obligacionesSinSaldar, isEmpty);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.causas, contains(CausaNoConcluyente.nadaEjecutado));
    });
  });

  group('la precedencia se deriva', () {
    test('un registro vacío no es verde', () async {
      final r = await Cascada(const [], observador: _obsDeLib()).correr(['lib']);
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
      final r = await Cascada([_PasoQueCubre('A', const ['lib'])],
              observador: obs)
          .correr(['lib', 'no/existe']);
      expect(r.estado, EstadoDeCorrida.noConcluyente);
      expect(r.causas, contains(CausaNoConcluyente.alcanceNoObservable));
    });

    test('verde solo cuando ninguna pregunta negativa se contesta que sí',
        () async {
      final r = await Cascada([_PasoQueCubre('A', const ['lib'])],
              observador: _obsDeLib())
          .correr(['lib']);
      expect(r.estado, EstadoDeCorrida.verde);
      expect(r.causas, isEmpty);
    });
  });
```

`_PasoQueCubre(id, cubiertos, {omite})` es un doble que devuelve `Executed` con un testigo que cubre exactamente esos sujetos.

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/orchestration
```

- [ ] **Paso 3: escribir la derivación**

```dart
/// Un par paso-sujeto que el paso tenía que cubrir o explicar.
typedef Obligacion = ({String paso, String sujeto});

/// Por qué una corrida no puede afirmar cobertura. **Es una lista, no un
/// valor**: pueden concurrir, y la acción siguiente sale de la primera.
enum CausaNoConcluyente {
  sinVerificadores,
  nadaEjecutado,
  alcanceNoObservable,
  pasoAbortado,
  pasoNoConcluyente,
  obligacionSinSaldar,
}

class ResultadoDeCascada {
  final List<String> registrados;
  final ScopeObservation alcance;
  final Map<String, StepOutcome> desenlaces;

  ResultadoDeCascada({
    required List<String> registrados,
    required this.alcance,
    required Map<String, StepOutcome> desenlaces,
  })  : registrados = List.unmodifiable(registrados),
        desenlaces = Map.unmodifiable(desenlaces) {
    // **`sinEjecutar` desaparece porque no puede existir.** Antes era una
    // resta que podía dar distinto de cero; ahora todo registrado tiene su
    // desenlace o el resultado no se construye.
    final faltan =
        this.registrados.where((id) => !this.desenlaces.containsKey(id));
    if (faltan.isNotEmpty) {
      throw ArgumentError.value(faltan.toList(), 'desenlaces',
          'Estos pasos están registrados y no tienen desenlace. Un `started` '
          'sin cerrar deja esperando a quien consuma el protocolo');
    }
    final sobran =
        this.desenlaces.keys.where((id) => !this.registrados.contains(id));
    if (sobran.isNotEmpty) {
      throw ArgumentError.value(sobran.toList(), 'desenlaces',
          'Hay desenlaces de pasos que no están registrados');
    }
  }

  /// **El libro.** Para cada paso que ejecutó, cada sujeto utilizable tiene
  /// que estar cubierto por su testigo o nombrado por una de sus omisiones.
  ///
  /// Es por PAR, no por unión: que otro paso haya cubierto el sujeto no salda
  /// la obligación de este. La condición existencial dejaba pasar un paso que
  /// cubría la mitad mientras otro cubría todo.
  List<Obligacion> get obligacionesSinSaldar {
    final esperados = alcance.usable();
    final abiertas = <Obligacion>[];
    desenlaces.forEach((id, d) {
      if (d is! Executed) return;
      final saldados = {
        ...d.witness.subjects,
        for (final o in d.witness.omitted)
          if (o.subject != null) o.subject!,
      };
      for (final s in esperados) {
        if (!saldados.contains(s)) abiertas.add((paso: id, sujeto: s));
      }
    });
    return List.unmodifiable(abiertas);
  }

  List<String> get ejecutados => List.unmodifiable(
      [for (final e in desenlaces.entries) if (e.value is Executed) e.key]);

  List<Diagnostic> get diagnosticos => List.unmodifiable([
        for (final d in desenlaces.values)
          if (d is Executed) ...d.diagnostics,
      ]);

  /// Las causas, en el orden del flujo de decisión. La acción siguiente sale
  /// de la primera, y por eso solo puede nombrar evidencia presente.
  List<CausaNoConcluyente> get causas {
    final c = <CausaNoConcluyente>[];
    if (registrados.isEmpty) c.add(CausaNoConcluyente.sinVerificadores);
    if (ejecutados.isEmpty && registrados.isNotEmpty) {
      c.add(CausaNoConcluyente.nadaEjecutado);
    }
    if (alcance.unobserved.isNotEmpty) {
      c.add(CausaNoConcluyente.alcanceNoObservable);
    }
    if (desenlaces.values.any((d) => d is Aborted)) {
      c.add(CausaNoConcluyente.pasoAbortado);
    }
    if (desenlaces.values
        .any((d) => d is Executed && d.verdict == Verdict.noConcluyente)) {
      c.add(CausaNoConcluyente.pasoNoConcluyente);
    }
    if (obligacionesSinSaldar.isNotEmpty) {
      c.add(CausaNoConcluyente.obligacionSinSaldar);
    }
    return List.unmodifiable(c);
  }

  /// **No hay rama por defecto.** El verde es la hoja que queda cuando todas
  /// las preguntas negativas se contestaron.
  EstadoDeCorrida get estado {
    if (desenlaces.values.any((d) => d is Broken)) {
      return EstadoDeCorrida.errorInterno;
    }
    if (causas.isNotEmpty) return EstadoDeCorrida.noConcluyente;
    if (desenlaces.values
        .any((d) => d is Executed && d.verdict == Verdict.rojo)) {
      return EstadoDeCorrida.rojo;
    }
    return EstadoDeCorrida.verde;
  }
}
```

- [ ] **Paso 4: correr y commitear**

```
dart test packages/orchestration
```

```bash
git add packages/orchestration
git commit -m "El libro de obligaciones es por par paso-sujeto, no por unión

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 8b · El paso no puede contradecir en silencio a la cascada

**Agregada en ejecución**, por un hallazgo de la revisión de las tareas 7 y 8. No estaba en el plan original y su ausencia era un falso verde que se habría ido con la rebanada.

**El problema, medido.** La cascada observa el alcance una vez y le pasa a cada paso solo los sujetos utilizables. Pero el paso **vuelve a observar** esos mismos sujetos por su cuenta, y si su foto discrepa de la de la cascada —porque el árbol cambió entre las dos lecturas— descarta el sujeto y lo declara como omisión **con su sujeto**. Una omisión con sujeto **salda** la obligación de ese par paso-sujeto. Falla abierto: el sujeto queda sin verificar y la corrida puede salir verde.

El caso de divergencia total ya está cerrado: un alcance sin sujetos utilizables lanza desde la tarea 6. Lo que falta es la divergencia **parcial**.

**Archivos:**
- Modificar: `packages/plugin_dart/lib/src/pasos.dart`
- Modificar: `packages/plugin_dart/test/pasos_test.dart`

**Interfaces:**
- Consume: `ScopeObservation`, `Aborted`, `Attempt`, `Termination`.
- Produce: ningún tipo nuevo. Cambia qué devuelve `run` cuando su observación discrepa de lo que le entregaron.

- [ ] **Paso 1: escribir la prueba que falla**

```dart
  test('si la observación del paso discrepa de lo que le entregaron, ABORTA',
      () async {
    // La cascada observa una vez y entrega solo los sujetos utilizables. Si el
    // paso vuelve a mirar y ve otra cosa, el árbol cambió entre las dos
    // lecturas y la evidencia de la corrida dejó de ser coherente.
    //
    // Lo que NO puede hacer es descartar el sujeto y declararlo como omisión
    // con su sujeto: eso SALDA la obligación de ese par paso-sujeto, y el
    // sujeto queda sin verificar con la corrida en verde. Falla abierto.
    final discrepante = ObservadorDeAlcanceFalso(observados: {
      'lib/a.dart': ObservedSubject(
          subject: 'lib/a.dart', ofStack: true, files: 1),
      'lib/b.dart': ObservedSubject(
          subject: 'lib/b.dart',
          ofStack: false,
          files: 0,
          reason: 'el árbol cambió entre las dos lecturas'),
    });
    final ejecutor = EjecutorDeclarado(salida(estandar: formatoLimpio));
    final paso = PasoDeFormato(
        ejecutor: ejecutor, directorio: raiz.path, observador: discrepante);

    final o = await paso.run(['lib/a.dart', 'lib/b.dart']);

    expect(o, isA<Aborted>(),
        reason: 'no se puede concluir sobre un alcance que cambió debajo');
    expect((o as Aborted).attempt.termination, Termination.interrumpida);
    expect(o.attempt.note, contains('lib/b.dart'),
        reason: 'la evidencia tiene que nombrar el sujeto que discrepó');
    expect(ejecutor.invocaciones, isEmpty,
        reason: 'no se invoca la herramienta sobre un alcance incoherente');
  });

  test('y sin discrepancia sigue ejecutando normalmente', () async {
    // El control negativo: sin esto, un paso que abortara SIEMPRE pasaría la
    // prueba de arriba por la vía de no funcionar.
    final coherente = ObservadorDeAlcanceFalso(observados: {
      'lib/a.dart': ObservedSubject(
          subject: 'lib/a.dart', ofStack: true, files: 1),
    });
    final o = await PasoDeFormato(
            ejecutor: EjecutorDeclarado(salida(estandar: formatoLimpio)),
            directorio: raiz.path,
            observador: coherente)
        .run(['lib/a.dart']);
    expect(o, isA<Executed>());
    expect((o as Executed).verdict, Verdict.verde);
  });
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/plugin_dart/test/pasos_test.dart
```

Esperado: el primer caso falla porque hoy devuelve un ejecutado con `lib/b.dart` como omisión con sujeto.

- [ ] **Paso 3: implementar**

En `run`, después de traducir la observación y **antes** de decidir cualquier otra cosa, comprobá que todo sujeto entregado siga siendo utilizable según la propia observación del paso. Si alguno no lo es:

```dart
    // **La cascada ya vetó estos sujetos.** Que la observación del paso vea
    // otra cosa significa que el árbol cambió entre las dos lecturas, y
    // entonces la evidencia de la corrida no es coherente.
    //
    // Descartarlo como omisión con sujeto sería peor que inútil: una omisión
    // con sujeto SALDA la obligación de ese par paso-sujeto, así que el sujeto
    // quedaría sin verificar y la corrida podría salir verde. Falla abierto, y
    // es justo el modo de fallo que esta rebanada existe para cerrar.
    final discrepan = pedidos.where((s) => !alcance.sanos.contains(s)).toList();
    if (discrepan.isNotEmpty) {
      return Aborted(
          attempt: Attempt(
        invocation: '',
        subjects: pedidos,
        termination: Termination.interrumpida,
        exitCode: -1,
        note: 'El alcance cambió entre la observación de la corrida y la de '
            'este paso: ${discrepan.join(", ")} ya no es utilizable. No se '
            'invocó nada: no se puede concluir sobre un alcance incoherente.',
        finishedAt: DateTime.now().toUtc(),
      ));
    }
```

**Cuidado con dos cosas.** `Attempt` exige una invocación no vacía en algunos diseños y una lista de sujetos no vacía siempre: comprobá qué exige el tipo real y ajustá, sin aflojar el tipo. Y este bloque va **después** del que lanza cuando no queda ningún sujeto utilizable, que ya existe y no se toca.

- [ ] **Paso 4: correr, formatear, checks y commit**

```
dart test packages/core packages/orchestration packages/plugin_dart
dart format packages tool
dart format --output=none --set-exit-if-changed packages tool
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart)
```

```bash
git add packages
git commit -m "El paso no puede contradecir en silencio a la cascada

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

**Lo que esta tarea NO hace, y queda declarado.** No elimina la doble lectura del árbol: para eso el paso tendría que recibir la observación de la cascada, y eso cambia la firma del puerto. Lo que hace es que la segunda lectura no pueda **discrepar en silencio**: pasa de fallar abierto a fallar cerrado.

---

## Tarea 9 · El CLI, y el esquema 2

Cierra el árbol: al terminar esta tarea todo vuelve a compilar y a correr.

**Archivos:**
- Modificar: `packages/cli/lib/src/salida.dart`, `verify.dart`, `comando.dart`
- Modificar: `packages/cli/test/apoyo.dart`, `verify_test.dart`, `salida_test.dart`

**Interfaces:**
- Consume: `ResultadoDeCascada`, `CausaNoConcluyente`, `StepOutcome` y sus variantes.
- Produce: `esquemaDeSalida = 2`; `EventEnvelope` y `ResultEnvelope` con `runId` nulable; `String? queHacer(ResultadoDeCascada)` derivado de la primera causa.

- [ ] **Paso 1: las pruebas que fallan**

```dart
    test('cada desenlace tiene su etapa, y son cinco', () async {
      final etapas = <String>{};
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      for (final l in lineas(salida)) {
        final d = l['data'] as Map<String, Object?>?;
        if (d != null && d['stage'] != null) etapas.add(d['stage'] as String);
      }
      expect(etapas, containsAll(['started', 'executed']));
    });

    test('el esquema subió a 2 y lleva runId', () async {
      final (_, salida) = await correr(const ['--json'], [Paso.verde('A')]);
      expect(lineas(salida).every((l) => l['schema'] == 2), isTrue);
      expect(lineas(salida).last.containsKey('runId'), isTrue);
    });

    test('el resultado lleva la causa estructurada y el libro', () async {
      final (c, salida) = await correr(const ['--json'], [Paso.ciego('A')]);
      expect(c, 2);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['inconclusiveBecause'], isNotEmpty);
      expect(data.containsKey('obligations'), isTrue);
    });

    test('la acción siguiente solo nombra evidencia presente en data',
        () async {
      // El canario de la acción imposible: decía «mirá lo que omitió cada
      // testigo con --verbose» sobre una lista vacía.
      final (_, salida) = await correr(const ['--json'], [Paso.ciego('A')]);
      final doc = lineas(salida).last;
      final accion = doc['nextAction']! as String;
      expect(accion, isNot(contains('--verbose')));
      expect(accion, isNot(contains('doctor')));
      expect(accion, isNot(contains('--budget')));
    });

    test('`--json --quiet` deja SOLO el resultado', () async {
      // Es el modo no streaming de la superficie, sin bandera nueva: `--quiet`
      // ya significa callar el progreso.
      final (_, salida) =
          await correr(const ['--json', '--quiet'], [Paso.verde('A')]);
      expect(lineas(salida), hasLength(1));
      expect(lineas(salida).single['type'], 'result');
    });

    test('un start sin terminal queda declarado en el resultado', () async {
      // La garantía de entrega: si el canal se rompe, el consumidor no espera.
      final (c, salida) = await invocarConObservadorRoto();
      expect(c, 70);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['unterminated'], isNotEmpty);
    });
```

- [ ] **Paso 2: los tres ayudantes que estas pruebas usan y que no existen**

En `packages/cli/test/apoyo.dart`:

```dart
/// Un paso que cubre exactamente los sujetos que se le declaran.
class PasoQueCubre implements Verifier {
  @override
  final String id;
  final List<String> cubre;
  final List<Omission> omite;
  PasoQueCubre(this.id, this.cubre, {this.omite = const []});

  @override
  Future<VerificationOutcome> run(List<String> subjects) async => Executed(
        witness: Witness(
          invocation: 'herramienta ${cubre.join(" ")}',
          subjects: cubre,
          omitted: omite,
          exitCode: 0,
          finishedAt: DateTime.utc(2026),
        ),
        diagnostics: const [],
      );
}

/// Corre `verify` con un observador falso que declara del stack los sujetos
/// dados. Sin esto, cada prueba del CLI tendría que tocar el disco.
Future<(int, String)> correrConAlcance(
    List<String> sujetos, List<Verifier> pasos) {
  final obs = ObservadorDeAlcanceFalso(observados: {
    for (final s in sujetos)
      s: ObservedSubject(subject: s, ofStack: true, files: 1),
  });
  return correr(sujetos, pasos,
      construir: (_) => Cascada(pasos, observador: obs));
}

/// Corre `verify` con un observador de progreso que lanza en el primer
/// desenlace. Es el canal roto: el consumidor recibe el `started` y nunca su
/// terminal.
Future<(int, String)> invocarConObservadorRoto() async {
  final obs = ObservadorDeAlcanceFalso(observados: {
    'lib': ObservedSubject(subject: 'lib', ofStack: true, files: 1),
  });
  final out = StringBuffer();
  var primero = true;
  final c = await ejecutar(
    const ['verify', 'lib', '--json'],
    directorio: '.',
    salida: out,
    error: StringBuffer(),
    construirCascada: (_) => Cascada(
        [PasoQueCubre('A', const ['lib']), PasoQueCubre('B', const ['lib'])],
        observador: obs),
    alTerminarDeProgreso: (_, __) {
      if (primero) {
        primero = false;
        throw StateError('canal roto');
      }
    },
  );
  return (c, out.toString());
}
```

`ejecutar` gana el parámetro opcional `alTerminarDeProgreso`, que se compone con el que `verify` ya instala. **Existe solo para poder romper el canal a propósito**: una garantía de entrega que no se puede romper en una prueba es una garantía que nadie comprobó.

- [ ] **Paso 3 al 5: implementar**

En `salida.dart`: `esquemaDeSalida = 2`; los dos envelopes ganan `final String? runId;` y su clave en `toJson`. En `verify.dart`, el `switch` del desenlace pasa a cubrir las cinco variantes, con las etapas `executed`, `aborted`, `skipped`, `unobservable`, `internalError`, y `_queHacer` se deriva de `r.causas.firstOrNull` con un `switch` exhaustivo sobre `CausaNoConcluyente`:

```dart
String? _queHacer(ResultadoDeCascada r) {
  if (r.estado == EstadoDeCorrida.verde) return null;
  if (r.estado == EstadoDeCorrida.errorInterno) {
    final rotos = [
      for (final e in r.desenlaces.entries) if (e.value is Broken) e.key
    ];
    return 'Se rompió un paso del arnés, no la verificación del cambio. '
        'Reportalo con la traza: ${rotos.join(", ")}.';
  }
  final causa = r.causas.isEmpty ? null : r.causas.first;
  return switch (causa) {
    null => 'Hay ${r.diagnosticos.where((d) => d.severity == Severity.bloquea).length} '
        'diagnóstico(s) bloqueante(s). Arreglalos y volvé a correr `verify`.',
    CausaNoConcluyente.sinVerificadores =>
      'No hay ningún verificador registrado, así que no se miró nada. Los '
          'pasos se registran en el composition root: `cli`.',
    CausaNoConcluyente.nadaEjecutado =>
      'Ningún sujeto del alcance es de este stack: '
          '${r.alcance.observed.where((o) => !o.ofStack).map((o) => o.subject).join(", ")}. '
          'No es un fallo, pero tampoco se verificó nada. Revisá el alcance.',
    CausaNoConcluyente.alcanceNoObservable =>
      'No se pudo observar ${r.alcance.unobserved.map((u) => "${u.subject}: ${u.cause}").join("; ")}. '
          'Corregí la ruta o los permisos y volvé a correr.',
    CausaNoConcluyente.pasoAbortado => _accionDeAborto(r),
    CausaNoConcluyente.pasoNoConcluyente => _accionDeNoConcluyente(r),
    CausaNoConcluyente.obligacionSinSaldar => () {
        final o = r.obligacionesSinSaldar.first;
        return '${o.paso} no cubrió ${o.sujeto} y no dijo por qué. Un sujeto '
            'que nadie miró no puede quedar en verde.';
      }(),
  };
}
```

`_accionDeAborto` nombra el paso y la nota de su `Attempt`; `_accionDeNoConcluyente` nombra el paso y el primer motivo de su testigo. **Los dos toman el texto del desenlace**, no de una constante: es lo que hace que la acción no pueda nombrar algo ausente.

- [ ] **Paso 6: correr todo y commitear**

```
dart test packages/core packages/orchestration packages/plugin_dart packages/cli
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart)
```

Esperado: **todo verde por primera vez desde la tarea 5.**

```bash
git add packages tool
git commit -m "El CLI dice cada desenlace como lo que es, y el esquema sube a 2

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 10 · Propiedades y canarios

Las pruebas dirigidas comprueban los casos que se nos ocurrieron. Estas comprueban que **no queda ninguno sin significado**.

**Archivos:**
- Crear: `packages/orchestration/test/propiedades_test.dart`
- Modificar: `packages/cli/test/verify_test.dart` — los canarios que hoy son ataques exitosos

**Interfaces:**
- Consume: todo lo anterior.
- Produce: nada nuevo. Es red, no superficie.

- [ ] **Paso 1: escribir el generador y las cinco propiedades**

Crear `packages/orchestration/test/propiedades_test.dart`:

```dart
/// Lo que las pruebas dirigidas no pueden demostrar: que **todo** estado
/// construible tiene semántica, y que ninguno sin evidencia termina verde.
///
/// El generador es exhaustivo y no aleatorio: el espacio es chico y una
/// corrida reproducible vale más que una muestra.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_fake/plugin_fake.dart';
import 'package:test/test.dart';

const sujetos = ['a.fuente', 'b.fuente'];

/// Todos los desenlaces que un paso puede tener, con su cobertura.
Iterable<(String, StepOutcome)> desenlacesPosibles() sync* {
  final coberturas = <List<String>>[
    const [],
    const ['a.fuente'],
    sujetos,
  ];
  final diagnosticos = <List<Diagnostic>>[
    const [],
    [_diag(Severity.reporta)],
    [_diag(Severity.bloquea)],
  ];
  final omisiones = <List<Omission>>[
    const [],
    [Omission(reason: 'residuo general')],
    [Omission(subject: 'b.fuente', reason: 'no lo leí')],
  ];
  for (final c in coberturas) {
    for (final d in diagnosticos) {
      for (final o in omisiones) {
        if (c.isEmpty && o.isEmpty) continue; // el tipo lo prohíbe
        yield (
          'executed·${c.length}·${d.length}·${o.length}',
          Executed(
            witness: Witness(
              invocation: 'herramienta',
              subjects: c,
              omitted: o,
              exitCode: 0,
              finishedAt: DateTime.utc(2026),
            ),
            diagnostics: d,
          )
        );
      }
    }
  }
  yield (
    'aborted',
    Aborted(
        attempt: Attempt(
      invocation: 'herramienta',
      subjects: sujetos,
      termination: Termination.tiempoAgotado,
      exitCode: -1,
      note: 'se acabó el presupuesto',
      finishedAt: DateTime.utc(2026),
    ))
  );
  yield ('broken', Broken(component: 'X', error: 'se rompió', context: 'lib'));
}

void main() {
  final observador = ObservadorDeAlcanceFalso(observados: {
    for (final s in sujetos)
      s: ObservedSubject(subject: s, ofStack: true, files: 1),
  });

  test('a · todo desenlace construible tiene estado y causa. Función total',
      () async {
    for (final (nombre, d) in desenlacesPosibles()) {
      final r = ResultadoDeCascada(
        registrados: const ['A'],
        alcance: await observador.observe(sujetos),
        desenlaces: {'A': d},
      );
      expect(() => r.estado, returnsNormally, reason: nombre);
      expect(() => r.causas, returnsNormally, reason: nombre);
      expect(EstadoDeCorrida.values, contains(r.estado), reason: nombre);
    }
  });

  test('b · verde implica toda obligación saldada y nada sin concluir',
      () async {
    for (final (nombre, d) in desenlacesPosibles()) {
      final r = ResultadoDeCascada(
        registrados: const ['A'],
        alcance: await observador.observe(sujetos),
        desenlaces: {'A': d},
      );
      if (r.estado != EstadoDeCorrida.verde) continue;
      expect(r.obligacionesSinSaldar, isEmpty, reason: nombre);
      expect(r.causas, isEmpty, reason: nombre);
      expect(d, isA<Executed>(), reason: nombre);
      expect((d as Executed).verdict, Verdict.verde, reason: nombre);
    }
  });

  test('c · la cuenta de diagnósticos es la suma de los ejecutados', () async {
    for (final (nombre, d) in desenlacesPosibles()) {
      final r = ResultadoDeCascada(
        registrados: const ['A'],
        alcance: await observador.observe(sujetos),
        desenlaces: {'A': d},
      );
      final esperados = d is Executed ? d.diagnostics.length : 0;
      expect(r.diagnosticos, hasLength(esperados), reason: nombre);
    }
  });

  test('d · ningún desenlace sin cobertura completa termina verde', () async {
    // La propiedad que cierra el falso verde: cubrir la mitad sin explicar el
    // resto no puede dar verde, sea cual sea el resto de la combinación.
    for (final (nombre, d) in desenlacesPosibles()) {
      if (d is! Executed) continue;
      final saldados = {
        ...d.witness.subjects,
        for (final o in d.witness.omitted)
          if (o.subject != null) o.subject!,
      };
      if (saldados.containsAll(sujetos)) continue;
      final r = ResultadoDeCascada(
        registrados: const ['A'],
        alcance: await observador.observe(sujetos),
        desenlaces: {'A': d},
      );
      expect(r.estado, isNot(EstadoDeCorrida.verde), reason: nombre);
    }
  });

  test('e · un registrado sin desenlace no se puede construir', () async {
    expect(
        () => ResultadoDeCascada(
              registrados: const ['A', 'B'],
              alcance: await observador.observe(sujetos),
              desenlaces: {'A': desenlacesPosibles().first.$2},
            ),
        throwsArgumentError);
  });
}

Diagnostic _diag(Severity s) => Diagnostic(
      file: 'a.fuente',
      severity: s,
      ruleId: 'r',
      message: const QuotedText('m', source: 'test'),
    );
```

Nota sobre la propiedad `e`: `await` no puede ir dentro del `expect`; sacá la observación a una variable antes.

- [ ] **Paso 2: correr y ver que falla, después que pasa**

```
dart test packages/orchestration/test/propiedades_test.dart
```

Si alguna propiedad falla, **no la aflojes**: encontró un estado sin semántica, y ese es el trabajo de la tarea.

- [ ] **Paso 3: convertir en pruebas los seis canarios medidos**

En `packages/cli/test/verify_test.dart`, agregá el grupo que fija que los ataques dejaron de funcionar. Estos seis se reprodujeron sobre el código anterior y salían verdes o daban acciones imposibles:

```dart
  group('los ataques que antes funcionaban', () {
    test('C1 · un verificador no puede declarar que un archivo no es suyo', () {
      // No hay forma de escribir el ataque: `run` devuelve `VerificationOutcome`
      // y `Skipped` no es uno. Si esta prueba deja de compilar porque alguien
      // metió `Skipped` bajo `VerificationOutcome`, el invariante se perdió.
      expect(Skipped(notOfStack: [
        ObservedSubject(
            subject: 'a', ofStack: false, files: 0, reason: 'no es mío')
      ]), isNot(isA<VerificationOutcome>()));
    });

    test('C3 · cubrir la mitad sin explicar el resto no da verde', () async {
      final (c, _) = await correrConAlcance(
          ['a.fuente', 'b.fuente'], [PasoQueCubre('A', const ['a.fuente'])]);
      expect(c, 2);
    });

    test('C6 · un start sin terminal queda declarado', () async {
      final (c, salida) = await invocarConObservadorRoto();
      expect(c, 70);
      final data = lineas(salida).last['data']! as Map<String, Object?>;
      expect(data['unterminated'], isNotEmpty);
    });

    test('C9 · un paso sin evidencia no se puede construir', () {
      expect(
          () => Witness(
                invocation: 'h',
                subjects: const [],
                omitted: const [],
                exitCode: 0,
                finishedAt: DateTime.utc(2026),
              ),
          throwsArgumentError);
    });

    test('C12 · un testigo honesto da verde, sin campos de más', () async {
      // El plugin de terceros que cumplía las cláusulas y nunca obtenía verde,
      // porque le faltaba un conteo que ya no existe.
      final (c, _) = await correrConAlcance(
          ['a.fuente'], [PasoQueCubre('A', const ['a.fuente'])]);
      expect(c, 0);
    });

    test('C5 · la regla del motivo en blanco vale en LOS TRES tipos', () {
      // Antes había dos reglas para el mismo hecho: un tipo rechazaba
      // cualquier blanco y otro solo si TODOS lo eran. `Omission` lanza antes
      // que `Witness`, así que comprobar los dos ahí no probaría nada nuevo:
      // lo que se recorre son los tres lugares donde se escribe un motivo.
      expect(() => Omission(subject: 'a', reason: ' '), throwsArgumentError);
      expect(
          () => ObservedSubject(
              subject: 'a', ofStack: false, files: 0, reason: '  '),
          throwsArgumentError);
      expect(() => UnobservedSubject(subject: 'a', cause: ' '),
          throwsArgumentError);
    });
  });
```

- [ ] **Paso 4: correr todo y commitear**

```
dart test packages
```

```bash
git add packages
git commit -m "Los seis ataques que funcionaban, ahora como pruebas

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Tarea 11 · El arnés propio, y la propagación al corpus

Lo que queda es lo que impide que esto se deshaga en silencio.

**Archivos:**
- Modificar: `arquitectura.json`, `tool/analisis/bin/check.dart`, `tool/checks/capas.py`, `grafo.jsonl`, `README.md`
- Modificar en `../sdlc-agentico/`: el ADR de atestación, el registro de deltas, `docs/03`, `docs/14`, `happy-path.md`, `PSEUDOCODIGO.md`, `docs/08`, el diagrama de componentes, `ESTADO.md`, `INVENTARIO.md`, `README.md`, `CLAUDE.md` y `AGENTS.md`

**Interfaces:**
- Consume: todo.
- Produce: nada ejecutable. Cierra la brecha entre lo construido y lo escrito.

- [ ] **Paso 1: enseñarle al motor de checks las clases selladas**

`tool/analisis/bin/check.dart` compara campos públicos contra claves del JSON. Una jerarquía sellada tiene una base abstracta que no serializa y variantes que sí. La base ya queda exenta por abstracta; lo que hay que agregar es la comprobación de que **cada variante declara su discriminador como campo público**, o el `fromJson` no puede despachar.

Agregá a `arquitectura.json`, en la regla de serialización, una segunda violación canónica: una variante sellada sin su discriminador. Sin eso, el arreglo se puede deshacer sin que nada lo note.

- [ ] **Paso 2: arreglar el meta-check del presupuesto**

`tool/checks/capas.py` cuenta pasos y presupuesto por patrón de texto sobre `verify.dart`. El `switch` nuevo cambia la forma del archivo. Corré el check, mirá qué cuenta, y **comprobá que su caso ciego sigue disparando**: cambiá a mano un paso a `presupuesto * 2` y verificá que el check se pone rojo. Si no, el patrón quedó mirando otra cosa.

- [ ] **Paso 3: regenerar el grafo y correr el arnés entero**

```
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart)
python3 tool/checks/probar_reglas.py
python3 tool/checks/probar_recuperacion.py
dart test packages
```

- [ ] **Paso 4: escribir la sección del README de `shipflow`**

Contá qué se cerró y con qué evidencia. **Corregí la tabla que hoy define el salto como «corrió y no tenía nada suyo»**: ya no corre, y ya no lo decide él.

- [ ] **Paso 5: propagar al corpus**

En `../sdlc-agentico/`, en este orden:

1. El ADR de atestación gana su ampliación fechada: corolario 1 precisado —fuente ilegible es diagnóstico, alcance no observable no lo es—, corolario 4 extendido a la aplicabilidad, la precedencia en las consecuencias, y el invariante ejecutable actualizado con los canarios C1, C3 y C9.
2. Un ADR nuevo con el contenido de la §16 de la propuesta, tomando el número siguiente al último aceptado.
3. El registro de deltas: la enmienda a la delta de cobertura autojuzgada, y cuatro deltas nuevas —variantes cerradas, observador con una sola foto, esquema 2 con causa estructurada, motivos en blanco con una regla—.
4. `docs/03` §4, §5 y §6; `docs/14` con los siete deltas de la §3.3 aplicados y **el estatus de borrador retirado**; `happy-path` fase 7; `PSEUDOCODIGO` INV-2 y el camino de la toolchain ausente; `docs/08` con la matriz; el diagrama de componentes.
5. `ESTADO.md`, `INVENTARIO.md`, `README.md`, y la regla dura de `CLAUDE.md` y `AGENTS.md`, que hoy dice «un paso sin testigo no es verde» y pasa a decir «un paso que no ejecutó con cobertura no es verde, y ningún verificador declara su propia aplicabilidad». **Los dos archivos se editan juntos**: se proyectan del mismo registro.
6. **Mover la propuesta**: cuando el ADR exista, `borradores/PROPUESTA-verificacion-desenlace-cerrado.md` deja de ser una propuesta en revisión. Actualizá la línea del inventario.

- [ ] **Paso 6: los tres checks del corpus**

```
cd ../sdlc-agentico
python3 arnes-propio/checks/estados.py
python3 arnes-propio/checks/coherencia.py
python3 arnes-propio/checks/cifras.py --fix && python3 arnes-propio/checks/cifras.py
```

- [ ] **Paso 7: commitear los dos repositorios**

```bash
git add . && git commit -m "El arnés propio aprende las clases selladas

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

```bash
cd ../sdlc-agentico
git add . && git commit -m "La aplicabilidad sale del verificador, en el corpus

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Lo que este plan NO construye

Declarado, para que su ausencia no se lea como olvido:

- **El corte temprano y la detención.** El código `3` existe en la superficie y nada lo emite. Su criterio no está en el corpus, y esta base es su precondición, no su implementación.
- **La aplicabilidad por paso.** `RegisteredStep` ya lleva el alcance esperado como campo; estrecharlo por paso llega con el paso que lo necesite.
- **El presupuesto de corrida.** Hoy el límite por invocación es lo único que detiene algo, y eso es un disyuntor físico haciendo de política. Queda registrado como la rebanada siguiente.
- **La persistencia de la evidencia.** La superficie dice que `verify` escribe bajo la corrida; `verify` no tiene corrida todavía.
- **La versión del esquema de traza.** Ni la traza ni el testigo la llevan. Sigue declarado y sigue sin construirse.
