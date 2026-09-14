# La superficie de verificación · plan de implementación

> **Para quien ejecute esto:** usá `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans`, tarea por tarea. Los pasos llevan casilla (`- [ ]`) para marcarlos. Si el registro de ejecución se lleva aparte —el `git log`, por ejemplo— dejá las casillas sin marcar y decilo en la cabecera: marcarlas al final fabrica un registro que nadie llevó.

**Objetivo.** Que una corrida produzca, derivado y no escrito a mano, **qué quedó demostrado y qué requiere criterio humano** — con la regla de que nada que un control no pueda sostener llega a «cubierto».

**Arquitectura.** Los tipos viven en `core`; la derivación, en `orchestration`. `EstadoDeCorrida` se muda a `core` porque cruza un puerto. El control **declara** qué demuestra y qué no, en el puerto: un registro aparte dejaría afirmar de un control algo que no demuestra. Una fábrica validante en `core` es la única entrada a `AfirmacionCubierta`. Y la derivación toma **tres entradas** —el desenlace del entorno, las alteraciones del candidato, y el resultado de la cascada, que puede faltar— porque los dos primeros son hechos que la cascada no conoce.

**Stack.** Dart 3.11+ con `dart test`; checks propios en Python y Dart bajo `tool/`.

**Diseño que implementa.** `../sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md` §3, §4 y §5, **con la enmienda `53029b9`** del corpus. Leé esas tres secciones antes de la primera tarea: este plan argumenta desde ahí y no repite sus razones.

## Restricciones globales

Valen para toda tarea. Copiadas del diseño y de las reglas instaladas.

- **`core` no tiene dependencias ni entrada/salida**, y **no puede ver `orchestration`**: por eso la derivación no vive ahí.
- **Las cadenas `dart`, `flutter` y `pubspec` no aparecen fuera de `plugin_dart` y `cli`**, ni siquiera en prosa de un comentario. Se cobra en `core`, en `vcs` y en `orchestration`.
- **En `core`, los campos de colección se copian a una vista inmodificable; los campos públicos son exactamente las claves de `toJson` y las que lee `fromJson`; una clase o serializa o está declarada opaca.** Cada clase serializable nueva tiene su caso canónico en `packages/core/test/serializacion_test.dart`, **sin ningún valor por defecto en ningún campo**.
- **Ningún motivo, detalle ni declaración se acepta en blanco.** Los veredictos y estados se **derivan**: no hay campo donde escribirlos.
- **Una `fromJson` lee sus claves donde las usa**, no en un ayudante: el verificador deriva las claves de los índices que hace la propia función. Y la base de una jerarquía sellada despacha con un **método estático**, no con una factory — una factory es un constructor, y el verificador la lee como «esta clase serializa».
- **`arquitectura.json` no se edita sin regenerar `tool/checks/arquitectura.huella`** (`python3 tool/checks/capas.py --huella`), y **`grafo.jsonl` se regenera** cuando cambia un import (`cd tool/analisis && dart run bin/grafo.dart --escribir`).
- **Cada tarea termina con las suites de los paquetes que tocó en verde, `dart analyze --fatal-infos` limpio, `dart format` sin cambios, y un commit** con `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. Nunca `git add -A`: rutas explícitas.
- **Nada corre en paralelo con `probar_reglas.py`.** Ni `capas.py`, ni `dart test`, ni una edición del árbol: el arnés compara una huella del checkout compartido —con lo generado incluido— y cualquiera de las tres la mueve. Se aprendió tropezando dos veces en la rebanada anterior.
- La rama es `superficie-de-verificacion`, desde `develop`; el PR va a `develop`.

## Lo que este plan fija, y el diseño no decide

1. **`SuperficieDeVerificacion` no lleva el candidato ni el `runId`.** §4 la define con tres campos y nada más; quien quiera atar la superficie a un contenido usa `ArtefactoDeRevision`, que sí lo lleva. Mantenerla sin identidad es lo que permite derivarla de una corrida que **no llegó a tener candidato** —el entorno falló— sin inventar un valor.
2. **`estado` se deriva dentro de la superficie, no se copia del resultado de la cascada.** Si se copiara, una corrida con el entorno caído tendría que fabricar uno; y una corrida con alteraciones publicaría el de la cascada, que es justo el falso verde que la enmienda cierra.
3. **El orden de la derivación es: entorno, integridad, cascada.** Los dos primeros pueden vaciar `cubierto` entero, así que decidirlos después sería armar una lista para tirarla.
4. **`Afirmacion` va en `regla.dart`, no en `entidades.dart`.** Es del mismo género que `Rule` y sus evasiones —una declaración con su límite obligatorio— y el archivo ya tiene esa forma.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `packages/core/lib/src/desenlace.dart` | `EstadoDeCorrida` (mudado desde `orchestration`) |
| `packages/core/lib/src/regla.dart` | `Afirmacion`: qué demuestra un control y qué no |
| `packages/core/lib/src/superficie.dart` | **Nuevo.** `MotivoDeCriterio`, `EntradaDeCriterio`, `AfirmacionCubierta` con su fábrica, `SuperficieDeVerificacion`, `ArtefactoDeRevision` |
| `packages/core/lib/src/puertos.dart` | `Verifier` gana `Afirmacion get afirmacion` |
| `packages/core/lib/core.dart` | exporta `superficie.dart` |
| `packages/core/test/superficie_test.dart` | **Nuevo.** Los invariantes de los tipos y de la fábrica |
| `packages/core/test/serializacion_test.dart` | Casos canónicos de los cinco tipos nuevos |
| `packages/orchestration/lib/src/cascada.dart` | `EstadoDeCorrida` sale; se reexporta desde `core` |
| `packages/orchestration/lib/src/superficie.dart` | **Nuevo.** `derivarSuperficie`, la función de tres entradas |
| `packages/orchestration/lib/orchestration.dart` | exporta lo nuevo y reexporta `EstadoDeCorrida` |
| `packages/orchestration/test/superficie_test.dart` | **Nuevo.** La derivación, motivo por motivo |
| `packages/plugin_dart/lib/src/pasos.dart` | Los dos pasos declaran su afirmación |
| `packages/cli/test/apoyo.dart` · las suites de `orchestration` | Los seis dobles declaran la suya |
| `arquitectura.json` · `tool/checks/*` · `README.md` · `grafo.jsonl` | Registro, sabotajes y prosa |
| Corpus (`../sdlc-agentico`) | ADR-021, deltas, `docs/03`, `docs/07` |

---
### Task 0: La rama, y el punto de partida verde

**Files:** ninguno.

- [ ] **Step 1:** `git switch develop && git pull --ff-only && git switch -c superficie-de-verificacion`
- [ ] **Step 2:** `dart pub get && dart test packages/core packages/orchestration packages/vcs packages/plugin_dart packages/cli && python3 tool/checks/capas.py`. Todo verde antes de tocar nada; si algo falla, es de `develop` y no de esta rebanada.

---

### Task 1: `EstadoDeCorrida` se muda a `core`

**Files:**
- Modify: `packages/core/lib/src/desenlace.dart` (al final)
- Modify: `packages/orchestration/lib/src/cascada.dart` (sale el enum, entra un `export`)
- Modify: `packages/orchestration/lib/orchestration.dart`
- Test: `packages/core/test/superficie_test.dart` (nuevo, un caso)

**Interfaces:**
- Produces: `enum EstadoDeCorrida { verde, rojo, noConcluyente, errorInterno }` en `core`, reexportado por `orchestration` para que **ningún consumidor cambie sus imports**.

**Por qué se muda.** El artefacto lo necesita y viaja por un puerto de `core`; dejarlo en `orchestration` produce `core → orchestration`, que `deps-hacia-core` caza. Radio medido: 49 referencias en 8 archivos, ninguna en `core`.

- [ ] **Step 1: Escribí la prueba que falla** — `packages/core/test/superficie_test.dart`:

```dart
/// Los tipos de la superficie de verificación, y sus invariantes.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('EstadoDeCorrida vive en core', () {
    // Se muda porque cruza un puerto: el artefacto de revisión lo lleva, y un
    // puerto de `core` no puede nombrar un tipo de `orchestration`.
    expect(EstadoDeCorrida.values, hasLength(4));
    expect(EstadoDeCorrida.verde.name, 'verde');
    expect(EstadoDeCorrida.values, contains(EstadoDeCorrida.errorInterno));
  });
}
```

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/core/test/superficie_test.dart`. Esperado: no compila, `EstadoDeCorrida` no existe en `core`.

- [ ] **Step 3: Mové el enum.** Cortá de `packages/orchestration/lib/src/cascada.dart` el bloque completo —el doc y el `enum EstadoDeCorrida { … }`— y pegalo al final de `packages/core/lib/src/desenlace.dart`, **sin cambiar una palabra del doc**: su párrafo sobre los estados que faltan sigue siendo cierto y sigue siendo de quien compone la corrida.

En `cascada.dart`, donde estaba, dejá el reexport con su motivo:

```dart
/// **`EstadoDeCorrida` se mudó a `core`** y se reexporta desde acá.
///
/// Cruzó un puerto: el artefacto de revisión lo lleva, y un puerto de `core`
/// no puede nombrar un tipo de este paquete —`deps-hacia-core` lo caza—. Se
/// reexporta para que ningún consumidor cambie sus imports: se midieron 49
/// referencias en 8 archivos, y ninguna tuvo que tocarse.
export 'package:core/core.dart' show EstadoDeCorrida;
```

- [ ] **Step 4: Verificá que nadie más cambió** — `dart analyze --fatal-infos` tiene que salir limpio **sin haber tocado ningún import**. Si alguno se queja, el reexport está mal puesto: arreglalo ahí, no en el consumidor.

- [ ] **Step 5: Corré todo lo que lo usa**

```bash
dart test packages/core packages/orchestration packages/cli && python3 tool/checks/capas.py
```

Esperado: verde. `capas.py` comprueba que `core` no ganó dependencias.

- [ ] **Step 6: Commit**

```bash
git add packages/core/lib/src/desenlace.dart packages/core/test/superficie_test.dart packages/orchestration/lib/src/cascada.dart packages/orchestration/lib/orchestration.dart
git commit -m "core: EstadoDeCorrida se muda, porque cruza un puerto

Lo necesita el artefacto de revisión, que viaja por un puerto de core;
dejarlo en orchestration produciría core → orchestration. Se reexporta desde
donde estaba: 49 referencias en 8 archivos, ninguna tuvo que cambiar.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: El control declara qué demuestra, y qué no

**Files:**
- Modify: `packages/core/lib/src/regla.dart` (al final)
- Modify: `packages/core/lib/src/puertos.dart` (`Verifier`)
- Modify: `packages/plugin_dart/lib/src/pasos.dart` (los dos pasos)
- Modify: `packages/cli/test/apoyo.dart`, `packages/orchestration/test/cascada_test.dart`, `packages/plugin_dart/test/pasos_test.dart` (los seis dobles)
- Test: `packages/core/test/superficie_test.dart`

**Interfaces:**
- Produces: `class Afirmacion { final String id; final String demuestra; final String noDemuestra; }` — los tres requeridos, ninguno en blanco. Y `Afirmacion get afirmacion;` en `Verifier`.

**Por qué en el puerto y no en un registro.** §3 dice «la declara el control» y no dice dónde. Un registro aparte pone la afirmación lejos del control que la sostiene, y deja construible un registro que afirme de un control algo que ese control no demuestra. Es la misma razón por la que las evasiones viven en la `Rule` y no en una tabla.

**`noDemuestra` obligatorio es INV-11 aplicado**: una `Rule` prohibitiva no se construye sin su alternativa; una afirmación sin límite falla igual.

- [ ] **Step 1: Escribí las pruebas que fallan** — agregá a `packages/core/test/superficie_test.dart`:

```dart
  group('una afirmación declara su límite', () {
    test('los tres campos son obligatorios y ninguno va en blanco', () {
      expect(
        () => Afirmacion(id: ' ', demuestra: 'x', noDemuestra: 'y'),
        throwsArgumentError,
      );
      expect(
        () => Afirmacion(id: 'a', demuestra: '  ', noDemuestra: 'y'),
        throwsArgumentError,
      );
      expect(
        () => Afirmacion(id: 'a', demuestra: 'x', noDemuestra: ''),
        throwsArgumentError,
        reason:
            'una afirmación sin límite es una prohibición sin alternativa: '
            'le dice al revisor que se saltee algo sin decirle qué queda sin '
            'mirar',
      );
    });

    test('una afirmación completa se construye', () {
      final a = Afirmacion(
        id: 'formato.conforme',
        demuestra: 'coincide con la salida del formateador',
        noDemuestra: 'comportamiento, lógica ni criterios',
      );
      expect(a.id, 'formato.conforme');
    });
  });
```

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/core/test/superficie_test.dart`. Esperado: no compila.

- [ ] **Step 3: `Afirmacion`**, al final de `packages/core/lib/src/regla.dart`:

```dart
/// Lo que un control demuestra cuando ejecuta limpio, **y lo que no**.
///
/// La declara el control, en su puerto. Un registro aparte la pondría lejos
/// del control que la sostiene, y dejaría construible un registro que afirme
/// de un control algo que ese control no demuestra.
///
/// **[noDemuestra] es obligatorio, y es el mismo invariante que [Rule] aplica
/// a las prohibiciones.** Lo que entra en «cubierto» habilita a un revisor a
/// **no mirar**: una afirmación sin límite le dice que se saltee algo sin
/// decirle qué queda sin verificar, que es el peor fallo que ADR-016 nombra.
class Afirmacion {
  /// Identifica la afirmación, no al control: un control podría declarar más
  /// de una el día que tenga evidencia por sujeto.
  final String id;

  final String demuestra;
  final String noDemuestra;

  Afirmacion({
    required this.id,
    required this.demuestra,
    required this.noDemuestra,
  }) {
    if (id.trim().isEmpty ||
        demuestra.trim().isEmpty ||
        noDemuestra.trim().isEmpty) {
      throw ArgumentError(
        'Una afirmación necesita id, qué demuestra y qué NO demuestra, y '
        'ninguno de los tres puede ir en blanco: lo que entra en «cubierto» '
        'habilita a un revisor a no mirar.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'demuestra': demuestra,
    'noDemuestra': noDemuestra,
  };

  factory Afirmacion.fromJson(Map<String, Object?> json) => Afirmacion(
    id: json['id']! as String,
    demuestra: json['demuestra']! as String,
    noDemuestra: json['noDemuestra']! as String,
  );
}
```

- [ ] **Step 4: El puerto.** En `packages/core/lib/src/puertos.dart`, dentro de `Verifier`, junto a `String get id`:

```dart
  /// Qué demuestra este control cuando ejecuta limpio, y **qué no**.
  ///
  /// Va acá y no en un registro aparte porque el límite lo sostiene quien
  /// ejecuta. Lo consume la fábrica de `AfirmacionCubierta`, que **no acepta
  /// una afirmación que no sea la de este control**.
  Afirmacion get afirmacion;
```

- [ ] **Step 5: Los dos pasos reales**, en `packages/plugin_dart/lib/src/pasos.dart`. En `PasoDeFormato`, junto a su `id`:

```dart
  @override
  Afirmacion get afirmacion => Afirmacion(
    id: 'formato.conforme',
    demuestra: 'que el archivo coincide con la salida del formateador',
    noDemuestra: 'comportamiento, lógica ni criterios de aceptación',
  );
```

Y en `PasoDeAnalisis`:

```dart
  @override
  Afirmacion get afirmacion => Afirmacion(
    id: 'analisis.sinBloqueantes',
    demuestra: 'que el analizador no reportó diagnósticos bloqueantes',
    // **Lo segundo está medido, no supuesto.** La salida del analizador trae
    // solo diagnósticos y versión: no lista los archivos que leyó, así que un
    // sujeto limpio es indistinguible de uno que no se analizó.
    noDemuestra:
        'que haya leído todos los archivos del alcance, ni comportamiento',
  );
```

- [ ] **Step 6: Los seis dobles.** `Paso` y `PasoQueCubre` en `packages/cli/test/apoyo.dart`; `_Paso`, `_Espia` y `_PasoQueCubre` en `packages/orchestration/test/cascada_test.dart`; `_ProgramaInestable` hereda de `PasoDeCascada` y no necesita nada si la base no la declara — comprobalo con `dart analyze` y agregale la suya si se queja. A cada doble:

```dart
  @override
  Afirmacion get afirmacion => Afirmacion(
    id: 'doble.corrio',
    demuestra: 'que este doble ejecutó',
    noDemuestra: 'absolutamente nada más: es un doble',
  );
```

- [ ] **Step 7: Corré todo** — `dart test packages/core packages/orchestration packages/plugin_dart packages/cli && dart analyze --fatal-infos && dart format --set-exit-if-changed packages tool`.

- [ ] **Step 8: Commit**

```bash
git add packages/core packages/plugin_dart packages/orchestration/test packages/cli/test
git commit -m "core: el control declara qué demuestra, y qué NO

En el puerto, no en un registro aparte: un registro deja construible una
tabla que afirme de un control algo que ese control no demuestra, igual que
las evasiones viven en la Rule y no en una tabla.

noDemuestra es obligatorio por el mismo invariante que una prohibición sin
alternativa: lo que entra en «cubierto» habilita a un revisor a NO MIRAR, y
una afirmación sin límite le dice que se saltee algo sin decirle qué queda
sin verificar.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: Los tipos de la superficie, y la fábrica que los valida

**Files:**
- Create: `packages/core/lib/src/superficie.dart`
- Modify: `packages/core/lib/core.dart`
- Test: `packages/core/test/superficie_test.dart`

**Interfaces:**
- Consumes: `Afirmacion` (tarea 2), `EstadoDeCorrida` (tarea 1), `Witness`, `Executed`, `Verdict`, `CandidateIdentity`.
- Produces:
  ```dart
  enum MotivoDeCriterio { hallazgo, declaradoNoMirado, nadieDioCuenta, ajenoAlStack,
      noSePudoMirar, intentoIncompleto, instrumentoFallo, residuoGeneral,
      entornoNoDerivado, candidatoAlterado }
  class EntradaDeCriterio { final String? controlId; final String? sujeto;
      final MotivoDeCriterio motivo; final String detalle; }
  class AfirmacionCubierta { final String controlId; final String sujeto;
      final Afirmacion afirmacion; final Witness testigo;
      static AfirmacionCubierta? desde({required Verifier control,
          required StepOutcome desenlace, required String sujeto}); }
  ```
  La fábrica `desde` es **la única entrada**: el constructor es privado.

**Las cuatro comprobaciones de la fábrica**, de §4: el control es el que se declara; la afirmación es la que **ese** control declara; el testigo proviene de **su** desenlace; y el desenlace **no es rojo**.

- [ ] **Step 1: Escribí las pruebas que fallan** — agregá a `packages/core/test/superficie_test.dart`:

```dart
  group('la fábrica de afirmaciones cubiertas', () {
    final afirmacion = Afirmacion(
      id: 'ctrl.limpio',
      demuestra: 'que la herramienta no encontró nada',
      noDemuestra: 'comportamiento',
    );

    Executed limpio(List<String> sujetos) => Executed(
      witness: Witness(
        invocation: 'herramienta --sobre ${sujetos.join(" ")}',
        subjects: sujetos,
        exitCode: 0,
        finishedAt: DateTime.utc(2026),
        omitted: const [],
      ),
      diagnostics: const [],
    );

    test('un desenlace limpio produce la afirmación del control', () {
      final c = _ControlDeclarado('ctrl', afirmacion);
      final a = AfirmacionCubierta.desde(
        control: c,
        desenlace: limpio(['lib']),
        sujeto: 'lib',
      );
      expect(a, isNotNull);
      expect(a!.controlId, 'ctrl');
      expect(a.afirmacion.id, 'ctrl.limpio');
      expect(a.testigo.subjects, contains('lib'));
    });

    test('un desenlace ROJO no produce ninguna', () {
      // Es la regla central de §3, y no es prudencia: está medido que el
      // veredicto es global al paso y que los diagnósticos no tienen relación
      // validada con los sujetos del testigo. No se sabe cuál sujeto lo
      // originó, así que ninguno se puede declarar cubierto.
      final rojo = Executed(
        witness: limpio(['lib']).witness,
        diagnostics: [
          Diagnostic(
            file: 'lib/a.fuente',
            severity: Severity.bloquea,
            ruleId: 'r',
            message: const QuotedText('algo', source: 'herramienta'),
          ),
        ],
      );
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', afirmacion),
          desenlace: rojo,
          sujeto: 'lib',
        ),
        isNull,
      );
    });

    test('un sujeto que el testigo no cubre no produce ninguna', () {
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', afirmacion),
          desenlace: limpio(['lib']),
          sujeto: 'test',
        ),
        isNull,
      );
    });

    test('un desenlace que no es Executed no produce ninguna', () {
      expect(
        AfirmacionCubierta.desde(
          control: _ControlDeclarado('ctrl', afirmacion),
          desenlace: Aborted(
            attempt: Attempt(
              invocation: 'herramienta',
              subjects: const ['lib'],
              termination: Termination.tiempoAgotado,
              exitCode: -1,
              note: 'no llegó',
              finishedAt: DateTime.utc(2026),
            ),
          ),
          sujeto: 'lib',
        ),
        isNull,
      );
    });

    test('no hay otra puerta: el constructor no es público', () {
      // Si alguien agrega un constructor público, esta prueba no se pone roja
      // sola —no hay forma de comprobarlo desde afuera— así que lo que la
      // sostiene es la regla de arquitectura de la tarea 7.
      expect(AfirmacionCubierta.desde, isNotNull);
    });
  });

  group('una entrada de criterio', () {
    test('el detalle nunca va en blanco', () {
      expect(
        () => EntradaDeCriterio(
          motivo: MotivoDeCriterio.residuoGeneral,
          detalle: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('el motivo es un enum cerrado de DIEZ', () {
      // Ocho de §3, más los dos que la enmienda agregó con la rebanada del
      // entorno: hechos que la cascada no conoce y que igual vuelven no
      // concluyente la corrida.
      expect(MotivoDeCriterio.values, hasLength(10));
      expect(MotivoDeCriterio.values, contains(MotivoDeCriterio.entornoNoDerivado));
      expect(MotivoDeCriterio.values, contains(MotivoDeCriterio.candidatoAlterado));
    });
  });
```

Y arriba del `main`, el doble que las pruebas usan:

```dart
/// Un control que solo declara: no ejecuta. La fábrica no lo invoca — recibe
/// el desenlace ya producido— así que `run` no hace falta para probarla.
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
```

- [ ] **Step 2: Corré para verlas fallar** — `dart test packages/core/test/superficie_test.dart`. Esperado: no compila.

- [ ] **Step 3: Los tipos** — `packages/core/lib/src/superficie.dart`:

```dart
/// La superficie de verificación: **qué quedó demostrado y qué requiere
/// criterio humano**.
///
/// «Cubierto» habilita a un revisor a **saltar**, así que todo lo que entra ahí
/// tiene que ser algo que se pueda no mirar sin perder información. Una
/// traducción mala le dice al revisor que se saltee lo que nadie verificó: es
/// el peor fallo que ADR-016 nombra, y por eso las reglas de acá son
/// restrictivas por construcción y no por criterio de quien compone.
library;

import 'desenlace.dart';
import 'entidades.dart';
import 'puertos.dart';
import 'regla.dart';
import 'valores.dart';

/// Por qué algo no se puede dar por cubierto. **Enum cerrado de diez.**
///
/// Ocho salen de la derivación original; las dos últimas entraron con la
/// rebanada del entorno de verificación, que produjo hechos que la cascada no
/// conoce y que igual vuelven la corrida no concluyente.
enum MotivoDeCriterio {
  /// El control encontró algo. **Todos sus sujetos**, no solo el del
  /// diagnóstico: el veredicto es global al paso, y está medido que los
  /// diagnósticos no tienen relación validada con los sujetos del testigo.
  hallazgo,

  /// El control declaró que no miró ese sujeto.
  declaradoNoMirado,

  /// Nadie dio cuenta del sujeto: el libro de obligaciones lo dejó abierto.
  nadieDioCuenta,

  /// El sujeto no es de este stack.
  ajenoAlStack,

  /// No se pudo establecer qué era.
  noSePudoMirar,

  /// El control empezó y no llegó a terminar.
  intentoIncompleto,

  /// El arnés se rompió.
  instrumentoFallo,

  /// El control declaró un residuo que no ata a ningún sujeto.
  residuoGeneral,

  /// **El entorno no se pudo derivar, así que la cascada nunca corrió.** No
  /// hay nada que la corrida pueda afirmar, y no hay un resultado de cascada
  /// del cual derivarlo.
  entornoNoDerivado,

  /// **El candidato dejó de ser el árbol que dice representar.** Una
  /// alteración no dice cuál de los dos árboles vio cada control, así que
  /// ningún sujeto se puede dar por cubierto — el mismo argumento que el
  /// control rojo.
  candidatoAlterado,
}

/// Algo que un revisor humano tiene que mirar, y por qué.
class EntradaDeCriterio {
  /// Qué control la originó, si la originó alguno. Nulo cuando el hecho no es
  /// de ningún control —el entorno, una alteración, un sujeto que nadie tomó—.
  final String? controlId;

  /// Sobre qué sujeto. Nulo cuando el hecho no es de ningún sujeto.
  final String? sujeto;

  final MotivoDeCriterio motivo;

  /// Qué pasó, en concreto. **Nunca en blanco**: el motivo dice la categoría,
  /// y esto dice el caso. Sin él, una entrada le pide a alguien que mire algo
  /// sin decirle qué.
  final String detalle;

  EntradaDeCriterio({
    this.controlId,
    this.sujeto,
    required this.motivo,
    required this.detalle,
  }) {
    if (detalle.trim().isEmpty) {
      throw ArgumentError.value(
        detalle,
        'detalle',
        'Una entrada de criterio sin detalle le pide a alguien que mire algo '
            'sin decirle qué.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'controlId': controlId,
    'sujeto': sujeto,
    'motivo': motivo.name,
    'detalle': detalle,
  };

  factory EntradaDeCriterio.fromJson(Map<String, Object?> json) =>
      EntradaDeCriterio(
        controlId: json['controlId'] as String?,
        sujeto: json['sujeto'] as String?,
        motivo: MotivoDeCriterio.values.byName(json['motivo']! as String),
        detalle: json['detalle']! as String,
      );
}

/// Un sujeto que un control demostró, con el testigo que lo sostiene.
///
/// **No se ensambla a mano.** Un constructor público dejaría armar una
/// afirmación cubierta con cualquier afirmación y cualquier testigo; la única
/// entrada es [desde], que comprueba las cuatro cosas que la vuelven cierta.
class AfirmacionCubierta {
  final String controlId;
  final String sujeto;
  final Afirmacion afirmacion;
  final Witness testigo;

  AfirmacionCubierta._({
    required this.controlId,
    required this.sujeto,
    required this.afirmacion,
    required this.testigo,
  });

  /// La única entrada. Devuelve nulo cuando **no** se puede afirmar, que es lo
  /// más frecuente:
  ///
  /// - el desenlace no ejecutó —no hay testigo del que leer cobertura—;
  /// - el desenlace es **rojo**: el veredicto es global al paso y los
  ///   diagnósticos no tienen relación validada con los sujetos, así que no se
  ///   sabe cuál lo originó;
  /// - el testigo **no cubre** ese sujeto.
  ///
  /// La afirmación y el id salen del control, no de quien llama: así no hay
  /// forma de atribuirle a un control algo que no declara.
  static AfirmacionCubierta? desde({
    required Verifier control,
    required StepOutcome desenlace,
    required String sujeto,
  }) {
    if (desenlace is! Executed) return null;
    if (desenlace.verdict != Verdict.verde) return null;
    if (!desenlace.witness.subjects.contains(sujeto)) return null;
    return AfirmacionCubierta._(
      controlId: control.id,
      sujeto: sujeto,
      afirmacion: control.afirmacion,
      testigo: desenlace.witness,
    );
  }

  Map<String, Object?> toJson() => {
    'controlId': controlId,
    'sujeto': sujeto,
    'afirmacion': afirmacion.toJson(),
    'testigo': testigo.toJson(),
  };

  /// **Reconstruye lo que ya fue validado**, y por eso no vuelve a validar: el
  /// documento viene de una corrida donde la fábrica sí corrió. Volver a
  /// comprobar acá exigiría el control, que un documento no lleva.
  factory AfirmacionCubierta.fromJson(Map<String, Object?> json) =>
      AfirmacionCubierta._(
        controlId: json['controlId']! as String,
        sujeto: json['sujeto']! as String,
        afirmacion: Afirmacion.fromJson(
          json['afirmacion']! as Map<String, Object?>,
        ),
        testigo: Witness.fromJson(json['testigo']! as Map<String, Object?>),
      );
}
```

- [ ] **Step 4: Exportá y corré** — en `packages/core/lib/core.dart`, `export 'src/superficie.dart';` y una línea en la lista del doc. Después `dart test packages/core/test/superficie_test.dart`.

- [ ] **Step 5: Commit**

```bash
git add packages/core/lib/src/superficie.dart packages/core/lib/core.dart packages/core/test/superficie_test.dart
git commit -m "core: los tipos de la superficie, y la fábrica que los valida

Una afirmación cubierta no se ensambla a mano: la única entrada comprueba que
el desenlace ejecutó, que no es rojo y que su testigo cubre ese sujeto, y toma
la afirmación DEL CONTROL, no de quien llama.

Un desenlace rojo no produce ninguna, y no es prudencia: está medido que el
veredicto es global al paso y que los diagnósticos no tienen relación validada
con los sujetos, así que no se sabe cuál lo originó.

MotivoDeCriterio queda en diez: los ocho de la derivación original más los dos
que la enmienda agregó con la rebanada del entorno.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: `SuperficieDeVerificacion` y su derivación de tres entradas

**Files:**
- Modify: `packages/core/lib/src/superficie.dart` (el tipo)
- Create: `packages/orchestration/lib/src/superficie.dart` (la derivación)
- Modify: `packages/orchestration/lib/orchestration.dart`
- Test: `packages/orchestration/test/superficie_test.dart` (nuevo)

**Interfaces:**
- Consumes: los tipos de la tarea 3; `ResultadoDeCascada`, `Obligacion`; `ResultadoDeEntorno`, `EntornoDerivado`, `AlteracionDelCandidato`.
- Produces:
  ```dart
  // en core
  class SuperficieDeVerificacion {
    final List<AfirmacionCubierta> cubierto;
    final List<EntradaDeCriterio> requiereCriterio;
    final EstadoDeCorrida estado;
  }
  // en orchestration
  SuperficieDeVerificacion derivarSuperficie({
    required ResultadoDeEntorno entorno,
    required List<AlteracionDelCandidato> alteraciones,
    required ResultadoDeCascada? cascada,
    required Map<String, Verifier> controles,
  });
  ```
  `controles` mapea id de paso → el control, porque `ResultadoDeCascada` guarda desenlaces por id y no los controles: la fábrica necesita el objeto para leerle la afirmación.

**El orden, y por qué:** entorno, integridad, cascada. Los dos primeros pueden vaciar `cubierto` entero, así que decidirlos después sería armar una lista para tirarla.

- [ ] **Step 1: Escribí las pruebas que fallan** — `packages/orchestration/test/superficie_test.dart`:

```dart
/// La derivación de la superficie, motivo por motivo.
///
/// **Tres entradas, no una.** El desenlace del entorno y las alteraciones del
/// candidato son hechos que la cascada no conoce, y los dos pueden vaciar
/// «cubierto» entero. Derivar solo de la cascada publicaba afirmaciones sobre
/// un árbol que había dejado de ser el que se fijó.
library;

import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:test/test.dart';

final _afirmacion = Afirmacion(
  id: 'ctrl.limpio',
  demuestra: 'que la herramienta no encontró nada',
  noDemuestra: 'comportamiento',
);

class _Control implements Verifier {
  @override
  final String id;
  @override
  Afirmacion get afirmacion => _afirmacion;
  _Control(this.id);
  @override
  Future<VerificationOutcome> run(VerificationScope alcance) =>
      throw UnsupportedError('doble');
}

Witness _testigo(List<String> sujetos, {List<Omission> omite = const []}) =>
    Witness(
      invocation: 'herramienta --sobre ${sujetos.join(" ")}',
      subjects: sujetos,
      exitCode: 0,
      finishedAt: DateTime.utc(2026),
      omitted: omite,
    );

ScopeObservation _observacion(List<String> sujetos) => ScopeObservation(
  requested: sujetos,
  observed: [
    for (final s in sujetos) ObservedSubject(subject: s, ofStack: true, files: 1),
  ],
  unobserved: const [],
  observedAt: DateTime.utc(2026),
);

ResultadoDeCascada _cascada(Map<String, StepOutcome> desenlaces, List<String> sujetos) =>
    ResultadoDeCascada(
      registrados: [
        for (final id in desenlaces.keys)
          RegisteredStep(id: id, expectedScope: sujetos),
      ],
      alcance: _observacion(sujetos),
      desenlaces: desenlaces,
    );

final _entornoOk = EntornoDerivado(
  paquetes: 3,
  raices: 1,
  toolchain: IdentidadDeToolchain(
    version: QuotedText('SDK 3.12.0', source: 'toolchain'),
  ),
);

void main() {
  test('un control limpio cubre sus sujetos', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada({
        'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
      }, ['lib']),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto.single.sujeto, 'lib');
    expect(s.cubierto.single.afirmacion.id, 'ctrl.limpio');
    expect(s.requiereCriterio, isEmpty);
    expect(s.estado, EstadoDeCorrida.verde);
  });

  test('un control ROJO no cubre ninguno de sus sujetos', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada({
        'ctrl': Executed(
          witness: _testigo(['lib', 'bin']),
          diagnostics: [
            Diagnostic(
              file: 'lib/a.fuente',
              severity: Severity.bloquea,
              ruleId: 'r',
              message: const QuotedText('algo', source: 'herramienta'),
            ),
          ],
        ),
      }, ['lib', 'bin']),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto, isEmpty);
    expect(
      s.requiereCriterio.map((e) => e.motivo).toSet(),
      {MotivoDeCriterio.hallazgo},
    );
    expect(s.requiereCriterio.map((e) => e.sujeto), containsAll(['lib', 'bin']));
    expect(s.estado, EstadoDeCorrida.rojo);
  });

  test('EL ENTORNO NO DERIVADO: sin cascada, y nada cubierto', () {
    // La cascada nunca corrió, así que no hay resultado del cual derivar. El
    // hecho se nombra en vez de faltar.
    final s = derivarSuperficie(
      entorno: CandidatoRechazado(
        causa: CausaDeRechazo.pubRechazoLaResolucion,
        evidencia: const QuotedText('sin archivo de bloqueo', source: 'resolver'),
      ),
      alteraciones: const [],
      cascada: null,
      controles: const {},
    );
    expect(s.cubierto, isEmpty);
    expect(s.requiereCriterio.single.motivo, MotivoDeCriterio.entornoNoDerivado);
    expect(s.requiereCriterio.single.detalle, contains('sin archivo de bloqueo'));
    expect(s.estado, EstadoDeCorrida.noConcluyente);
  });

  test('UN CANDIDATO ALTERADO vacía «cubierto», aunque la cascada dé verde', () {
    // El falso verde que la enmienda cierra: la cascada no se entera de que el
    // árbol cambió, y publicar «cubierto» le diría al revisor que se saltee lo
    // que se verificó sobre otro árbol.
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: [
        AlteracionDelCandidato(
          ruta: 'lib/nuevo.fuente',
          tipo: TipoDeAlteracion.agregada,
        ),
      ],
      cascada: _cascada({
        'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
      }, ['lib']),
      controles: {'ctrl': _Control('ctrl')},
    );
    expect(s.cubierto, isEmpty, reason: 'la cascada dio verde y no alcanza');
    expect(
      s.requiereCriterio.map((e) => e.motivo),
      contains(MotivoDeCriterio.candidatoAlterado),
    );
    expect(s.estado, EstadoDeCorrida.noConcluyente);
  });

  test('una omisión CON sujeto es declaradoNoMirado; sin sujeto, residuo', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada({
        'ctrl': Executed(
          witness: _testigo(
            ['lib'],
            omite: [
              Omission(subject: 'bin', reason: 'no lo miró'),
              Omission(reason: 'no rastrea descendientes'),
            ],
          ),
          diagnostics: const [],
        ),
      }, ['lib', 'bin']),
      controles: {'ctrl': _Control('ctrl')},
    );
    final motivos = {for (final e in s.requiereCriterio) e.motivo};
    expect(motivos, contains(MotivoDeCriterio.declaradoNoMirado));
    expect(motivos, contains(MotivoDeCriterio.residuoGeneral));
    expect(s.cubierto.single.sujeto, 'lib');
  });

  test('una obligación sin saldar es nadieDioCuenta', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada({
        'ctrl': Executed(witness: _testigo(['lib']), diagnostics: const []),
      }, ['lib', 'bin']),
      controles: {'ctrl': _Control('ctrl')},
    );
    final abierta = s.requiereCriterio.firstWhere(
      (e) => e.motivo == MotivoDeCriterio.nadieDioCuenta,
    );
    expect(abierta.sujeto, 'bin');
    expect(abierta.controlId, 'ctrl');
  });

  test('un paso abortado es intentoIncompleto, y uno roto instrumentoFallo', () {
    final s = derivarSuperficie(
      entorno: _entornoOk,
      alteraciones: const [],
      cascada: _cascada({
        'a': Aborted(
          attempt: Attempt(
            invocation: 'herramienta',
            subjects: const ['lib'],
            termination: Termination.tiempoAgotado,
            exitCode: -1,
            note: 'no llegó',
            finishedAt: DateTime.utc(2026),
          ),
        ),
        'b': Broken(
          component: 'ctrl',
          error: 'reventó',
          context: 'al correr',
        ),
      }, ['lib']),
      controles: {'a': _Control('a'), 'b': _Control('b')},
    );
    final motivos = {for (final e in s.requiereCriterio) e.motivo};
    expect(motivos, contains(MotivoDeCriterio.intentoIncompleto));
    expect(motivos, contains(MotivoDeCriterio.instrumentoFallo));
    expect(s.estado, EstadoDeCorrida.errorInterno);
  });

  test('toda entrada de criterio trae detalle, en todos los caminos', () {
    // Una entrada sin detalle no se construye; esta prueba comprueba que
    // NINGÚN camino de la derivación lo deja en blanco, que es distinto.
    for (final s in [
      derivarSuperficie(
        entorno: DerivacionAbortada(
          terminacion: Termination.herramientaAusente,
          causa: CausaDeAborto.laHerramientaNoRespondio,
          evidencia: const QuotedText('no estaba', source: 'x'),
        ),
        alteraciones: const [],
        cascada: null,
        controles: const {},
      ),
      derivarSuperficie(
        entorno: _entornoOk,
        alteraciones: [
          AlteracionDelCandidato(ruta: 'a', tipo: TipoDeAlteracion.borrada),
        ],
        cascada: null,
        controles: const {},
      ),
    ]) {
      expect(s.requiereCriterio, isNotEmpty);
      for (final e in s.requiereCriterio) {
        expect(e.detalle.trim(), isNotEmpty);
      }
    }
  });
}
```

- [ ] **Step 2: Corré para verlas fallar** — `dart test packages/orchestration/test/superficie_test.dart`. Esperado: no compila.

- [ ] **Step 3: El tipo**, al final de `packages/core/lib/src/superficie.dart`:

```dart
/// Lo que se deriva de una corrida entera: qué quedó demostrado y qué requiere
/// criterio humano.
///
/// **No lleva el candidato ni el identificador de la corrida.** Quien quiera
/// atar la superficie a un contenido usa [ArtefactoDeRevision]; mantenerla sin
/// identidad es lo que permite derivarla de una corrida que no llegó a tener
/// candidato — porque el entorno no se pudo derivar — sin inventar un valor.
class SuperficieDeVerificacion {
  final List<AfirmacionCubierta> cubierto;
  final List<EntradaDeCriterio> requiereCriterio;

  /// **Se deriva de la corrida entera, no se copia de la cascada.** Copiarlo
  /// obligaría a fabricar uno cuando la cascada no corrió, y publicaría el de
  /// la cascada cuando el candidato se alteró — que es el falso verde que esta
  /// superficie existe para cerrar.
  final EstadoDeCorrida estado;

  SuperficieDeVerificacion({
    required List<AfirmacionCubierta> cubierto,
    required List<EntradaDeCriterio> requiereCriterio,
    required this.estado,
  }) : cubierto = List.unmodifiable(cubierto),
       requiereCriterio = List.unmodifiable(requiereCriterio) {
    if (estado != EstadoDeCorrida.verde && cubierto.isNotEmpty) {
      // No es una comprobación de más: es el invariante del tipo. Una corrida
      // que no salió verde no puede autorizar a saltear nada.
      if (requiereCriterio.isEmpty) {
        throw ArgumentError(
          'Una corrida que no salió verde tiene que decir qué requiere '
              'criterio: si no, afirma cobertura sin nombrar lo que falta.',
        );
      }
    }
  }

  Map<String, Object?> toJson() => {
    'cubierto': [for (final c in cubierto) c.toJson()],
    'requiereCriterio': [for (final e in requiereCriterio) e.toJson()],
    'estado': estado.name,
  };

  factory SuperficieDeVerificacion.fromJson(Map<String, Object?> json) =>
      SuperficieDeVerificacion(
        cubierto: [
          for (final c in json['cubierto']! as List<Object?>)
            AfirmacionCubierta.fromJson(Map<String, Object?>.from(c! as Map)),
        ],
        requiereCriterio: [
          for (final e in json['requiereCriterio']! as List<Object?>)
            EntradaDeCriterio.fromJson(Map<String, Object?>.from(e! as Map)),
        ],
        estado: EstadoDeCorrida.values.byName(json['estado']! as String),
      );
}
```

- [ ] **Step 4: La derivación** — `packages/orchestration/lib/src/superficie.dart`:

```dart
/// De dónde sale la superficie de verificación.
///
/// **Vive acá y no en `core` por una sola razón:** recibe `ResultadoDeCascada`,
/// que es de este paquete, y `core` no puede verlo. Los otros tres tipos de
/// entrada sí son de `core` y viajan sin problema.
library;

import 'package:core/core.dart';

import 'cascada.dart';

/// Deriva la superficie de los **tres** hechos de una corrida.
///
/// La primera versión del diseño derivaba solo de [cascada], y la rebanada del
/// entorno de verificación la falsificó: el desenlace del entorno y las
/// alteraciones del candidato son hechos que la cascada no conoce, y los dos
/// vuelven la corrida no concluyente.
///
/// **El orden importa.** Entorno, integridad, cascada: los dos primeros pueden
/// vaciar `cubierto` entero, así que decidirlos después sería armar una lista
/// para tirarla.
///
/// [cascada] es nulo cuando **no llegó a correr**, que es lo que pasa cuando el
/// entorno no se derivó. [controles] mapea id de paso al control, porque el
/// resultado guarda desenlaces por id y la fábrica necesita el objeto para
/// leerle su afirmación.
SuperficieDeVerificacion derivarSuperficie({
  required ResultadoDeEntorno entorno,
  required List<AlteracionDelCandidato> alteraciones,
  required ResultadoDeCascada? cascada,
  required Map<String, Verifier> controles,
}) {
  final criterio = <EntradaDeCriterio>[];

  // 1 · El entorno. Si no se derivó, no hay nada más que mirar: la cascada no
  //     corrió, y lo que haya en disco no se verificó contra nada.
  if (entorno is! EntornoDerivado) {
    final evidencia = switch (entorno) {
      CandidatoRechazado(:final causa, :final evidencia) =>
        '${causa.name}: ${evidencia.content}',
      DerivacionAbortada(:final causa, :final evidencia) =>
        '${causa.name}: ${evidencia.content}',
      EntornoDerivado() => '',
    };
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.entornoNoDerivado,
          detalle:
              'El entorno de verificación no se pudo derivar, así que ningún '
              'control llegó a correr. $evidencia',
        ),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  // 2 · La integridad. Una alteración no dice cuál de los dos árboles vio cada
  //     control, así que ninguno se puede dar por cubierto.
  if (alteraciones.isNotEmpty) {
    for (final a in alteraciones) {
      criterio.add(
        EntradaDeCriterio(
          sujeto: a.ruta,
          motivo: MotivoDeCriterio.candidatoAlterado,
          detalle:
              'El candidato dejó de coincidir con el árbol que dice '
              'representar: ${a.ruta} está ${a.tipo.name}.',
        ),
      );
    }
    if (cascada != null) {
      for (final registro in cascada.registrados) {
        for (final sujeto in registro.expectedScope) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: sujeto,
              motivo: MotivoDeCriterio.candidatoAlterado,
              detalle:
                  'No se sabe cuál árbol miró este control, así que lo que '
                  'haya afirmado no se puede sostener.',
            ),
          );
        }
      }
    }
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: criterio,
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  // 3 · La cascada. Sin entorno no llega acá; con entorno y sin cascada, la
  //     corrida no verificó nada y eso es un hecho, no un vacío.
  if (cascada == null) {
    return SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.nadieDioCuenta,
          detalle:
              'El entorno se derivó y ningún control corrió, así que nadie '
              'dio cuenta de nada.',
        ),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
  }

  final cubierto = <AfirmacionCubierta>[];
  for (final registro in cascada.registrados) {
    final desenlace = cascada.desenlaces[registro.id]!;
    final control = controles[registro.id];
    switch (desenlace) {
      case Executed(:final witness, :final verdict):
        if (verdict == Verdict.rojo) {
          for (final sujeto in witness.subjects) {
            criterio.add(
              EntradaDeCriterio(
                controlId: registro.id,
                sujeto: sujeto,
                motivo: MotivoDeCriterio.hallazgo,
                detalle:
                    'El control encontró algo. El veredicto es global al '
                    'paso y los diagnósticos no se atribuyen a un sujeto, '
                    'así que ninguno de los suyos queda cubierto.',
              ),
            );
          }
        } else if (verdict == Verdict.verde && control != null) {
          for (final sujeto in witness.subjects) {
            final a = AfirmacionCubierta.desde(
              control: control,
              desenlace: desenlace,
              sujeto: sujeto,
            );
            if (a != null) cubierto.add(a);
          }
        }
        for (final o in witness.omitted) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: o.subject,
              motivo: o.subject == null
                  ? MotivoDeCriterio.residuoGeneral
                  : MotivoDeCriterio.declaradoNoMirado,
              detalle: o.reason,
            ),
          );
        }
      case Aborted(:final attempt):
        criterio.add(
          EntradaDeCriterio(
            controlId: registro.id,
            motivo: MotivoDeCriterio.intentoIncompleto,
            detalle: attempt.note,
          ),
        );
      case Skipped(:final notOfStack):
        for (final s in notOfStack) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: s.subject,
              motivo: MotivoDeCriterio.ajenoAlStack,
              detalle: s.reason ?? 'no es de este stack',
            ),
          );
        }
      case Unobservable(:final causes):
        for (final c in causes) {
          criterio.add(
            EntradaDeCriterio(
              controlId: registro.id,
              sujeto: c.subject,
              motivo: MotivoDeCriterio.noSePudoMirar,
              detalle: c.cause,
            ),
          );
        }
      case Broken(:final component, :final error, :final context):
        criterio.add(
          EntradaDeCriterio(
            controlId: registro.id,
            motivo: MotivoDeCriterio.instrumentoFallo,
            detalle: '$component: $error ($context)',
          ),
        );
    }
  }

  for (final o in cascada.obligacionesSinSaldar) {
    criterio.add(
      EntradaDeCriterio(
        controlId: o.paso,
        sujeto: o.sujeto,
        motivo: MotivoDeCriterio.nadieDioCuenta,
        detalle:
            'El alcance esperado de este control incluía este sujeto y su '
            'testigo no lo cubrió ni lo nombró como omisión.',
      ),
    );
  }

  return SuperficieDeVerificacion(
    cubierto: cubierto,
    requiereCriterio: criterio,
    estado: cascada.estado,
  );
}
```

Los nombres de campo del `switch` están **verificados contra el código**, no supuestos: `Skipped.notOfStack` es `List<ObservedSubject>` y `ObservedSubject.reason` es `String?`; `Unobservable.causes` es `List<UnobservedSubject>` y `UnobservedSubject.cause` es `String` no nulable. Por eso el patrón de `Skipped` lleva el `??` y el de `Unobservable` no.

- [ ] **Step 5: Exportá y corré** — en `packages/orchestration/lib/orchestration.dart`, `export 'src/superficie.dart';`. Después `dart test packages/orchestration packages/core`.

- [ ] **Step 6: Comprobá que las pruebas cazan el defecto.** Cambiá `estado: EstadoDeCorrida.noConcluyente` por `cascada.estado` en la rama de las alteraciones y corré: la prueba del candidato alterado tiene que ponerse roja. Restaurá a mano.

- [ ] **Step 7: Commit**

```bash
git add packages/core/lib/src/superficie.dart packages/orchestration/lib/src/superficie.dart packages/orchestration/lib/orchestration.dart packages/orchestration/test/superficie_test.dart
git commit -m "orchestration: la superficie se deriva de TRES hechos, no solo de la cascada

El desenlace del entorno y las alteraciones del candidato son hechos que la
cascada no conoce, y los dos vuelven la corrida no concluyente. Sin ellos, una
cascada verde sobre un árbol alterado publicaba «cubierto»: le decía al revisor
que se saltee lo que se verificó sobre otro árbol.

El orden es entorno, integridad, cascada, porque los dos primeros pueden vaciar
«cubierto» entero. Y el estado se deriva acá en vez de copiarse de la cascada:
copiarlo obligaría a fabricar uno cuando la cascada no corrió.

Vive en orchestration porque recibe ResultadoDeCascada, que core no puede ver.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: `ArtefactoDeRevision`

**Files:**
- Modify: `packages/core/lib/src/superficie.dart`
- Test: `packages/core/test/superficie_test.dart`

**Interfaces:**
- Consumes: `SuperficieDeVerificacion` (tarea 4), `CandidateIdentity`.
- Produces:
  ```dart
  class ArtefactoDeRevision {
    final SuperficieDeVerificacion superficie;
    final CandidateIdentity candidato;
    final String intent;
    final String? plan;
    final String? sinPlanPorque;      // presente si y solo si plan es null
    final String alcanceDeLoAfirmado; // requerido, nunca en blanco
    static const alcanceSoloPR = '…';  // el texto de §4
  }
  ```

**La revisión no está acá, y es a propósito:** el artefacto existe **antes** de que el commit exista. La separación entre borrador y solicitud es de §10, y es de la rebanada siguiente.

- [ ] **Step 1: Escribí las pruebas que fallan** — agregá a `packages/core/test/superficie_test.dart`:

```dart
  group('el artefacto de revisión', () {
    final superficie = SuperficieDeVerificacion(
      cubierto: const [],
      requiereCriterio: [
        EntradaDeCriterio(
          motivo: MotivoDeCriterio.residuoGeneral,
          detalle: 'algo quedó afuera',
        ),
      ],
      estado: EstadoDeCorrida.noConcluyente,
    );
    final candidato = CandidateIdentity(
      contentRevision: 'arbol',
      baseRevision: 'base',
    );

    ArtefactoDeRevision armar({
      String? plan,
      String? sinPlanPorque,
      String alcance = 'lo que se afirmó',
      String intent = 'por qué existe',
    }) => ArtefactoDeRevision(
      superficie: superficie,
      candidato: candidato,
      intent: intent,
      plan: plan,
      sinPlanPorque: sinPlanPorque,
      alcanceDeLoAfirmado: alcance,
    );

    test('la ausencia de plan se DECLARA, no se inventa', () {
      // Sin plan y sin motivo, el artefacto afirmaría por omisión que no hacía
      // falta ninguno. Y con los dos, diría dos cosas incompatibles.
      expect(() => armar(), throwsArgumentError);
      expect(
        () => armar(plan: 'el plan', sinPlanPorque: 'no hay'),
        throwsArgumentError,
      );
      expect(armar(sinPlanPorque: 'el modo solo-PR no tiene tareas').plan, isNull);
      expect(armar(plan: 'el plan').sinPlanPorque, isNull);
    });

    test('el alcance de lo afirmado y la intención nunca van en blanco', () {
      expect(() => armar(plan: 'p', alcance: '  '), throwsArgumentError);
      expect(() => armar(plan: 'p', intent: ''), throwsArgumentError);
    });

    test('el texto de alcance para el modo solo-PR nombra su límite medido', () {
      // La segunda frase no es adorno: es el límite de la materialización, y
      // sin ella el revisor lee «el objeto commiteado es el que se verificó»
      // como si valiera sin condiciones.
      expect(ArtefactoDeRevision.alcanceSoloPR, contains('revisión humana'));
      expect(ArtefactoDeRevision.alcanceSoloPR, contains('filtros'));
    });

    test('no lleva la revisión: el artefacto existe ANTES del commit', () {
      final a = armar(plan: 'p');
      expect(a.toJson().containsKey('revision'), isFalse);
      expect(a.candidato.contentRevision, 'arbol');
    });
  });
```

- [ ] **Step 2: Corré para verlas fallar** — `dart test packages/core/test/superficie_test.dart`.

- [ ] **Step 3: El tipo**, al final de `packages/core/lib/src/superficie.dart`:

```dart
/// Lo que se le publica a un revisor humano.
///
/// **La revisión no está acá, y es a propósito:** este artefacto existe antes
/// de que el commit exista. Lo que lleva revisión es la solicitud, y vive del
/// lado de la forja.
class ArtefactoDeRevision {
  final SuperficieDeVerificacion superficie;

  /// Qué contenido se expuso a los controles.
  final CandidateIdentity candidato;

  /// Por qué existe esta rebanada.
  final String intent;

  /// El plan, si lo hay.
  final String? plan;

  /// Por qué no hay plan. **Presente si y solo si [plan] es nulo.**
  ///
  /// Sin esto, un artefacto sin plan afirmaría por omisión que no hacía falta
  /// ninguno. **Y no se inventan tareas**: un listado fabricado sería una
  /// superficie que se lee como capacidad, que es el diagnóstico que este
  /// repositorio ya se hace a sí mismo con los puertos sin implementación.
  final String? sinPlanPorque;

  /// Qué alcance tiene lo que se afirma. **Requerido**: sin él, «cubierto» se
  /// lee como una afirmación sobre el cambio entero.
  final String alcanceDeLoAfirmado;

  /// El texto para el modo sin elementos de trabajo.
  ///
  /// **La segunda frase no es adorno**: es el límite medido de cómo se
  /// materializa el candidato. Con normalización o filtros de contenido, el
  /// objeto que se commitea puede diferir del archivo tal como se ve en el
  /// editor, y un revisor que no lo sepa lee de más.
  static const alcanceSoloPR =
      'No existen criterios de aceptación ni cobertura funcional. Se '
      'verificaron propiedades de herramienta; el comportamiento y el '
      'propósito de todos los cambios requieren revisión humana. El objeto '
      'commiteado es exactamente el que se expuso a los controles; con '
      'normalización o filtros de contenido, ese objeto puede diferir del '
      'archivo tal como se ve en el editor.';

  ArtefactoDeRevision({
    required this.superficie,
    required this.candidato,
    required this.intent,
    required this.plan,
    required this.sinPlanPorque,
    required this.alcanceDeLoAfirmado,
  }) {
    if ((plan == null) != (sinPlanPorque != null)) {
      throw ArgumentError(
        'O hay plan, o hay un motivo por el que no lo hay: sin ninguno de los '
            'dos el artefacto afirma por omisión que no hacía falta, y con los '
            'dos dice dos cosas incompatibles.',
      );
    }
    if (intent.trim().isEmpty || alcanceDeLoAfirmado.trim().isEmpty) {
      throw ArgumentError(
        'La intención y el alcance de lo afirmado son lo que un revisor lee '
            'primero: ninguno puede ir en blanco.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'superficie': superficie.toJson(),
    'candidato': candidato.toJson(),
    'intent': intent,
    'plan': plan,
    'sinPlanPorque': sinPlanPorque,
    'alcanceDeLoAfirmado': alcanceDeLoAfirmado,
  };

  factory ArtefactoDeRevision.fromJson(Map<String, Object?> json) =>
      ArtefactoDeRevision(
        superficie: SuperficieDeVerificacion.fromJson(
          json['superficie']! as Map<String, Object?>,
        ),
        candidato: CandidateIdentity.fromJson(
          json['candidato']! as Map<String, Object?>,
        ),
        intent: json['intent']! as String,
        plan: json['plan'] as String?,
        sinPlanPorque: json['sinPlanPorque'] as String?,
        alcanceDeLoAfirmado: json['alcanceDeLoAfirmado']! as String,
      );
}
```

- [ ] **Step 4: Corré** — `dart test packages/core`. Esperado: verde.

- [ ] **Step 5: Commit**

```bash
git add packages/core/lib/src/superficie.dart packages/core/test/superficie_test.dart
git commit -m "core: el artefacto de revisión, con la ausencia de plan declarada

O hay plan, o hay un motivo por el que no lo hay: sin ninguno de los dos el
artefacto afirma por omisión que no hacía falta. Y no se inventan tareas — un
listado fabricado sería una superficie que se lee como capacidad.

No lleva la revisión, a propósito: el artefacto existe antes de que el commit
exista.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Serialización, registro y arnés

**Files:**
- Modify: `packages/core/test/serializacion_test.dart`
- Modify: `arquitectura.json` + `tool/checks/arquitectura.huella`
- Modify: `tool/checks/probar_reglas.py` (una extra)
- Modify: `README.md`
- Regenerar: `grafo.jsonl`

- [ ] **Step 1: Los cinco casos canónicos.** En `packages/core/test/serializacion_test.dart`, junto a las otras instancias, y sus entradas en el mapa `canonicas`. **Ningún campo con valor por defecto**: es lo que vuelve derivada la aserción de que nada se aplasta.

```dart
  final afirmacion = Afirmacion(
    id: 'formato.conforme',
    demuestra: 'que coincide con la salida del formateador',
    noDemuestra: 'comportamiento ni criterios',
  );

  final entradaDeCriterio = EntradaDeCriterio(
    controlId: 'FormatCheck',
    sujeto: 'lib/algo.fuente',
    motivo: MotivoDeCriterio.declaradoNoMirado,
    detalle: 'la herramienta no informó este archivo',
  );

  final afirmacionCubierta = AfirmacionCubierta.fromJson({
    'controlId': 'FormatCheck',
    'sujeto': 'lib',
    'afirmacion': afirmacion.toJson(),
    'testigo': testigo.toJson(),
  });

  final superficie = SuperficieDeVerificacion(
    cubierto: [afirmacionCubierta],
    requiereCriterio: [entradaDeCriterio],
    estado: EstadoDeCorrida.noConcluyente,
  );

  final artefacto = ArtefactoDeRevision(
    superficie: superficie,
    candidato: candidato,
    intent: 'por qué existe esta rebanada',
    plan: 'el plan declarado',
    sinPlanPorque: null,
    alcanceDeLoAfirmado: 'propiedades de herramienta, nada de comportamiento',
  );
```

```dart
        'Afirmacion': (afirmacion.toJson(), Afirmacion.fromJson),
        'EntradaDeCriterio': (
          entradaDeCriterio.toJson(),
          EntradaDeCriterio.fromJson,
        ),
        'AfirmacionCubierta': (
          afirmacionCubierta.toJson(),
          AfirmacionCubierta.fromJson,
        ),
        'SuperficieDeVerificacion': (
          superficie.toJson(),
          SuperficieDeVerificacion.fromJson,
        ),
        'ArtefactoDeRevision': (artefacto.toJson(), ArtefactoDeRevision.fromJson),
```

**`ArtefactoDeRevision` tiene `sinPlanPorque` nulo**, y la prueba exige que ningún campo del JSON sea un valor por defecto —y `null` lo es—. Es un choque real entre dos invariantes: el del tipo dice «uno de los dos, nunca los dos», y el de la prueba dice «ningún campo aplastado». **Resolvelo declarando la instancia canónica con `plan: null` y `sinPlanPorque: 'el modo solo-PR no tiene tareas'`**, y agregando `'plan'` a la lista de rutas exentas de esa prueba con su motivo escrito al lado — mirá cómo la prueba trata hoy otros campos nulables antes de inventar un mecanismo.

- [ ] **Step 2: Corré** — `dart test packages/core && (cd tool/analisis && dart run bin/check.dart)`. El verificador tiene que contar 5 clases serializables más.

- [ ] **Step 3: El residuo de la fábrica, declarado y no fingido.**

  `AfirmacionCubierta` se protege con un constructor privado, y **nada impide que alguien agregue uno público**. Una prueba desde afuera no puede detectarlo —Dart no tiene reflexión sin la biblioteca que `core` tiene prohibida— y ninguna de las reglas existentes cubre el caso: `opacidad-declarada` gobierna qué serializa, no qué construye.

  **Queda como residuo declarado**, en dos lugares: el doc de la clase —ya escrito en la tarea 3— y una línea en la sección del README de la tarea 4. **No inventes un check para esto**: un control que no puede mirar lo que dice mirar es exactamente lo que este repositorio llama un guardia que no puede ponerse rojo, y hay una regla que exige declarar cómo se deja ciego a cada uno.

- [ ] **Step 4: El grafo y el README.**

```bash
cd tool/analisis && dart run bin/grafo.dart --escribir && dart run bin/grafo.dart && cd ../..
```

En `README.md`, una sección `## La superficie de verificación` antes de `## El falso rojo simétrico`, con estas subsecciones —tres a seis oraciones cada una, en el registro del README—: `### Cubierto habilita a saltar, así que se restringe por construcción`; `### Un control rojo no cubre ninguno de sus sujetos, y está medido`; `### Y un candidato alterado tampoco`; `### El control declara su afirmación, y su límite`; `### Tres entradas, no una`; `### Lo que esta rebanada NO hace` (no hay `ship`, no hay forja, no hay composición: el artefacto es un tipo sin productor, **y eso va declarado**).

- [ ] **Step 5: El arnés completo, sin nada corriendo en paralelo**

```bash
python3 tool/checks/capas.py \
  && (cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart) \
  && python3 tool/checks/probar_reglas.py && python3 tool/checks/probar_recuperacion.py \
  && dart test packages/core packages/orchestration packages/vcs packages/cli packages/plugin_dart \
  && dart analyze --fatal-infos && dart format --set-exit-if-changed packages tool
```

Si `probar_reglas.py` dice que la cuenta de sabotajes no cuadra, la cifra que manda es la que imprime el arnés: actualizá el README con ella.

- [ ] **Step 6: Commit y PR**

```bash
git add packages/core/test/serializacion_test.dart README.md grafo.jsonl
git commit -m "La superficie, serializada y declarada

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push -u origin superficie-de-verificacion
gh pr create --base develop --title "La superficie de verificación: qué quedó demostrado, y qué requiere criterio" --body-file - <<'CUERPO'
Implementa §3–§5 de la propuesta de `ship`, con la enmienda del corpus que la rebanada del entorno obligó.

- **`core`** · `EstadoDeCorrida` se muda —cruza un puerto—; `Afirmacion` con su límite obligatorio; `MotivoDeCriterio` de diez; `AfirmacionCubierta` con fábrica validante y constructor privado; `SuperficieDeVerificacion`; `ArtefactoDeRevision`.
- **`orchestration`** · `derivarSuperficie`, de tres entradas.
- **`Verifier`** · declara su afirmación.

**Lo que la enmienda cerró:** derivar solo de la cascada publicaba «cubierto» sobre un árbol alterado — el peor fallo que ADR-016 nombra.

**Sin productor:** el artefacto es un tipo y nadie lo compone todavía. Declarado.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
CUERPO
```

---

### Task 7: El corpus

**Repo:** `/Users/zeref/Documents/SDLC/sdlc-agentico`, rama `superficie-de-verificacion-corpus` — **ya existe, con la enmienda `53029b9` adentro**. PR a `production` después del merge del código.

- [ ] **Step 1:** `adr/ADR-021-superficie-de-verificacion.md`, con la estructura de `ADR-020` —leelo entero antes— incluidos sus invariantes ejecutables. Los que esta rebanada instala: una afirmación sin límite no se construye; un desenlace rojo no produce ninguna cubierta; una alteración vacía «cubierto»; el artefacto sin plan y sin motivo no se construye.
- [ ] **Step 2:** deltas en `REGISTRO-DELTAS.md`, numerados desde el último que exista (`grep -o 'D-[0-9]*' REGISTRO-DELTAS.md | sort -V | tail -1`).
- [ ] **Step 3:** `docs/03` §5 —los tipos nuevos y el puerto que cambió— y `docs/07`, que es donde vive la revisión y la observabilidad.
- [ ] **Step 4:** los cuatro checks del corpus, `cifras.py --fix` incluido, y el PR.

---

## Autorrevisión del plan contra el diseño

**Cobertura de §3.** La unidad es la afirmación → tarea 2. «Un control rojo no produce ninguna cubierta» → tareas 3 y 4, con prueba en las dos. La tabla de derivación, nueve filas más las dos de la enmienda → tarea 4, una prueba por motivo salvo `ajenoAlStack` y `noSePudoMirar`, que van juntas en la prueba de abortado/roto — **agregar una prueba propia para cada una si el `switch` no las cubre**.

**Cobertura de §4.** `EstadoDeCorrida` se muda → tarea 1. Los cinco tipos → tareas 3, 4 y 5. «Las afirmaciones no se ensamblan a mano» → tarea 3. «La declaración de alcance, requerida» y «la ausencia de plan se declara» → tarea 5.

**Cobertura de §5.** Quién deriva y quién compone → tarea 4; la composición es de la rebanada 4 y va declarada en el README (tarea 6).

**Consistencia de nombres.** `Afirmacion{id,demuestra,noDemuestra}` (2) es lo que usan 3, 4 y 6. `AfirmacionCubierta.desde({control, desenlace, sujeto})` (3) es lo que llama 4. `derivarSuperficie({entorno, alteraciones, cascada, controles})` (4) es lo que prueban 4 y 6. `SuperficieDeVerificacion{cubierto, requiereCriterio, estado}` (4) es lo que compone 5.

**Lo que este plan deja fuera a sabiendas:** la composición del artefacto, `ship`, la forja, la credencial, los códigos de salida y el protocolo. Son las rebanadas 3 y 4.

**Un riesgo que el ejecutor va a encontrar:** el `switch` de la tarea 4 asume los nombres de campo de `Skipped` y `Unobservable`. El paso 4 de esa tarea lo dice, pero conviene repetirlo acá: **comprobalos en el código antes de escribir el patrón**, no después de que el analizador se queje.
