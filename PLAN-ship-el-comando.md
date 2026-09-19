# El comando `ship` — plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL REQUERIDA: usá superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para implementar este plan tarea por tarea. Los pasos usan casillas (`- [ ]`) para seguimiento.

**Objetivo:** que `shipflow ship` corra de punta a punta — preflight, candidato, cascada sobre ese candidato, superficie, artefacto, previsualización, compuerta, commit y publicación — y que cada camino termine en un desenlace declarado en vez de en una excepción o en un cuelgue.

**Arquitectura:** la orquestación vive en `cli`, que es la raíz de composición y el único paquete que puede ver a todos los adapters. Las piezas ya existen: el candidato con su almacén aislado, la derivación del entorno sobre él, la cascada sobre raíz arbitraria, la derivación de la superficie, el artefacto, la forja con su empuje y su cuerpo, y —de la rebanada anterior— el desenlace sellado, el documento de la corrida y su persistencia. Esta rebanada las **compone** y agrega lo que ninguna tenía: la entrada, el preflight, el remapeo de rutas, la previsualización y la compuerta.

**Stack:** Dart puro, workspace de pub. Sin dependencias externas nuevas.

**Spec:** `/Users/zeref/Documents/SDLC/sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md` §6, §7, §8 y §13, con las enmiendas `095c993` y `24051eb`. La normativa de las rebanadas anteriores está en `adr/ADR-020`, `ADR-021`, `ADR-022` y `ADR-023` del mismo repositorio.

**Esta es la segunda de tres.** La 4a construyó el desenlace y el documento —ya está en la rama de la que esta parte—. La 4c es `--retry-publication` y la reconciliación, que esta rebanada **no** construye.

## Restricciones globales

- **`core` no tiene dependencias externas ni entrada/salida.** Nada de `dart:io` en `core`.
- **Todo subproceso recibe `environment: entornoSaneado(...)` e `includeParentEnvironment: false` literal.** Lo aplica `subprocesos-con-entorno-saneado`, que identifica el lanzamiento por su elemento resuelto.
- **El nombre del proveedor de la forja vive en `packages/forge` y en ningún otro `lib/` ni `bin/`.** Lo aplica `forja-en-su-adapter`.
- **`lenguaje-en-plugin-dart` mira línea por línea, comentarios incluidos**, y prohíbe el nombre del lenguaje fuera de su plugin y de la raíz de composición. Citar un archivo fuente con su extensión en prosa la dispara: los comentarios de este repositorio nombran los archivos sin extensión.
- **Los tipos sellados serializan con `static fromJson` en la base y `factory` en cada variante**, leyendo el discriminador dentro de la propia fábrica.
- **Nada derivable es además un campo asignable.**
- **`dart analyze --fatal-infos` limpio** y `dart format` sin cambios.
- **Nunca corras `python3 tool/checks/probar_reglas.py` mientras editás.** Lanzalo solo, esperá, y recién después seguí.
- **Orden de comprobación:** `grafo.dart` antes de `capas.py`.
- Los commits terminan con `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

## La secuencia que esta rebanada implementa

```
 1  preflight · entrada, credencial, remoto, rama, base
 2  preparar el CANDIDATO en almacén de objetos AISLADO
 3  materializar por plumbing
 4  correr la cascada SOBRE EL CANDIDATO · remapear rutas
 5  escanear secretos sobre el diff de ESE par de revisiones
 6  derivar superficie · componer artefacto en memoria
 7  PREVIEW
 8  compuerta por estado
 9  crear .shipflow/.gitignore · comprobar que runs/ está ignorado
10  PROMOVER los objetos preparados, sin refiltrar
11  commit-tree                              ← NO mueve la rama
12  persistir `prepared` CON la revisión
13  update-ref condicionado a baseRevision
14  persistir `committed` + proyecciones
15  open(request) idempotente
16  persistir el ShipOutcome final
 ·  LIMPIEZA del workspace, índice y almacén temporales — en TODO camino
```

Los pasos 2, 3, 10, 11 y 13 **ya están construidos** en `vcs`; los pasos 4 y 6 en `orchestration`; el 15 en `forge`. Esta rebanada construye 1, 5, 7, 8, 9, 12, 14, 16 y la limpieza, y el remapeo del 4.

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `packages/cli/lib/src/ship/entrada.dart` **(nuevo)** | Interpretar la invocación: banderas, el DTO del archivo de rebanada, y las cuatro reglas de exclusión |
| `packages/cli/lib/src/ship/preflight.dart` **(nuevo)** | Rama, base, credencial y remoto — todo lo que falla con `4` y cero escrituras |
| `packages/cli/lib/src/ship/preview.dart` **(nuevo)** | Qué se muestra antes de preguntar, y la compuerta por estado |
| `packages/cli/lib/src/ship/ship.dart` **(nuevo)** | La orquestación de los dieciséis pasos y la limpieza |
| `packages/cli/lib/src/ship/gitignore.dart` **(nuevo)** | El `.gitignore` del directorio de corridas, y su comprobación |
| `packages/orchestration/lib/src/remapeo.dart` **(nuevo)** | Rutas del candidato → rutas del usuario |
| `packages/forge/lib/src/cuerpo.dart` | Los cuatro elementos que §13 exige y el cuerpo no lleva |
| `packages/vcs/lib/src/candidato.dart` | El escaneo de secretos pasa al paso 5 |
| `packages/cli/lib/src/comando.dart` | Registro del comando y su ayuda |
| `packages/cli/lib/src/salida.dart` | El payload de `ship` y su `payloadVersion` |

---

### Tarea 1: La entrada, y lo que rechaza

**Archivos:**
- Crear: `packages/cli/lib/src/ship/entrada.dart`
- Test: `packages/cli/test/ship/entrada_test.dart`

**Interfaces:**
- Produce: `class EntradaDeShip` con `intent`, `archivos` (`List<String>`), `branch` (`String?`), `base` (`String?`), `dryRun`, `yes`, `allowIncomplete`; y `EntradaDeShip interpretarShip(List<String> args)`, que lanza `UsoInvalido` —el tipo que `comando` ya usa para el código `5`—.

**Las cuatro reglas, del diseño:**

| Regla | Código |
|---|---|
| `--file` y `--slice` mutuamente excluyentes | `5` |
| `--intent` obligatorio con `--file` | `5` |
| `--intent` **no** se acepta con `--slice` | `5` |
| Cero archivos · archivos repetidos | `5` |

**Y la que no es una bandera:** se rechaza «todos los cambios detectados» como opción por omisión. Barrer el árbol metería en el pull request cambios que nadie planeó, y el artefacto los declararía **cubiertos**, que es pedirle a una persona que no los mire. Un valor por omisión que barre reintroduce **en la entrada** el falso verde que el resto del diseño cierra en la salida.

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/cli/test/ship/entrada_test.dart`:

```dart
import 'package:cli/cli.dart';
import 'package:test/test.dart';

void main() {
  test('sin archivos no se infiere nada: falla', () {
    // El default que barre el árbol es el falso verde en la ENTRADA.
    expect(
      () => interpretarShip(['--intent', 'x']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('--file y --slice son excluyentes', () {
    expect(
      () => interpretarShip(['--file', 'a.txt', '--slice', 'e.json']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('--file exige --intent, y --slice lo rechaza', () {
    expect(
      () => interpretarShip(['--file', 'a.txt']),
      throwsA(isA<UsoInvalido>()),
    );
    expect(
      () => interpretarShip(['--slice', 'e.json', '--intent', 'x']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  test('un archivo repetido falla, y el mensaje lo nombra', () {
    // Repetir una ruta no es ambiguo: es una rebanada mal declarada, y
    // `apply` exige igualdad LITERAL con los archivos de la rebanada.
    try {
      interpretarShip(['--intent', 'x', '--file', 'a.txt', '--file', 'a.txt']);
      fail('se esperaba UsoInvalido');
    } on UsoInvalido catch (e) {
      expect(e.reason, contains('a.txt'));
      expect(e.queHacer, isNotEmpty);
    }
  });

  test('la forma válida se interpreta entera', () {
    final e = interpretarShip([
      '--intent', 'medir',
      '--file', 'lib/a.txt',
      '--file', 'test/a_test.txt',
      '--base', 'main',
      '--branch', 'feature/x',
      '--yes',
    ]);
    expect(e.intent, 'medir');
    expect(e.archivos, ['lib/a.txt', 'test/a_test.txt']);
    expect(e.base, 'main');
    expect(e.branch, 'feature/x');
    expect(e.yes, isTrue);
    expect(e.dryRun, isFalse);
    expect(e.allowIncomplete, isFalse);
  });

  test('las banderas sin valor no se comen el argumento siguiente', () {
    // `--yes --intent x` no puede interpretar «--intent» como el valor de
    // `--yes`. Es el error clásico de un intérprete escrito a mano.
    final e = interpretarShip([
      '--yes',
      '--intent', 'x',
      '--file', 'a.txt',
    ]);
    expect(e.intent, 'x');
    expect(e.yes, isTrue);
  });

  test('una bandera desconocida falla en vez de ignorarse', () {
    expect(
      () => interpretarShip(['--intent', 'x', '--file', 'a.txt', '--inventada']),
      throwsA(isA<UsoInvalido>()),
    );
  });
}
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/ship/entrada_test.dart
```
Esperado: FALLA al compilar, porque `interpretarShip` no existe.

- [ ] **Paso 3: escribir el intérprete**

Creá `packages/cli/lib/src/ship/entrada.dart`. Mirá antes `interpretarGlobales` en `packages/cli/lib/src/comando.dart`: reusá su `UsoInvalido` y su estilo, que ya tiene el precedente de «una bandera desconocida falla en vez de ignorarse» —lo dice su propio comentario: comprobar con `contains` no es interpretar, y así `--inventada --help` salía con `0`—.

El doc comment del archivo tiene que decir **por qué no hay un valor por omisión que barra el árbol**, con el argumento de arriba.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/ship/entrada.dart packages/cli/test/ship/entrada_test.dart packages/cli/lib/cli.dart
git commit -m "Los archivos se declaran, no se detectan

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 2: El archivo de rebanada, y por qué no es el tipo del dominio

**Archivos:**
- Modificar: `packages/cli/lib/src/ship/entrada.dart`
- Test: `packages/cli/test/ship/entrada_test.dart`

**Interfaces:**
- Produce: `class ArchivoDeRebanada` con `intent`, `files`, `branch`, `base`, y `static ArchivoDeRebanada desdeJson(Map<String, Object?>)`; y la resolución de `--slice` a una `EntradaDeShip`.

**La forma, del diseño:**

```json
{ "intent": "…", "files": ["lib/a.dart", "test/a_test.dart"],
  "branch": "feature/x", "base": "main" }
```

**No es un `PullRequestSlice` serializado, y el motivo importa:** eso duplicaría identidad e intención. El identificador de la rebanada es `${runId}/1` y lo asigna la corrida, no el archivo. Hoy hay una sola rebanada por corrida, pero el modelo final admite varias; igualar el identificador al de la corrida fusionaría dos identidades que van a divergir.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el archivo de rebanada NO lleva identificador', () {
    // Si lo llevara, habría dos fuentes de la identidad: la del archivo y la
    // que asigna la corrida. Dos fuentes del mismo hecho divergen siempre.
    expect(
      () => ArchivoDeRebanada.desdeJson({
        'id': 'r-1',
        'intent': 'x',
        'files': ['a.txt'],
      }),
      throwsFormatException,
      reason: 'una clave que el formato no declara no se ignora en silencio',
    );
  });

  test('un archivo de rebanada válido se interpreta entero', () {
    final a = ArchivoDeRebanada.desdeJson({
      'intent': 'medir',
      'files': ['lib/a.txt'],
      'branch': 'feature/x',
      'base': 'main',
    });
    expect(a.intent, 'medir');
    expect(a.files, ['lib/a.txt']);
    expect(a.branch, 'feature/x');
    expect(a.base, 'main');
  });

  test('sin intención o sin archivos, el archivo se rechaza', () {
    expect(
      () => ArchivoDeRebanada.desdeJson({'files': ['a.txt']}),
      throwsFormatException,
    );
    expect(
      () => ArchivoDeRebanada.desdeJson({'intent': 'x', 'files': <String>[]}),
      throwsFormatException,
    );
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/ship/entrada_test.dart
```

- [ ] **Paso 3: escribir el tipo y la resolución**

Escribí `ArchivoDeRebanada` y hacé que `--slice` lo lea y produzca la misma `EntradaDeShip` que `--file`. **Una clave que el formato no declara se rechaza**: ignorarla en silencio deja que alguien crea que configuró algo.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/ship/entrada.dart packages/cli/test/ship/entrada_test.dart
git commit -m "El archivo de rebanada no lleva identidad: la asigna la corrida

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 3: El preflight — lo que falla con `4` y cero escrituras

**Archivos:**
- Crear: `packages/cli/lib/src/ship/preflight.dart`
- Test: `packages/cli/test/ship/preflight_test.dart`

**Interfaces:**
- Consume: `RepositorioGit` de `vcs` —su `ramaActual` devuelve **vacío si `HEAD` está suelto**, y su doc comment dice que eso es un estado y no un error, «que quien la use tiene que poder distinguirlo». Quien la usa es este preflight.
- Consume: `CredentialSource` de `core`.
- Produce: `sealed class ResultadoDePreflight` con `PreflightOk({required String rama, required String base, required Credential credencial})` y `PreflightFallo({required CausaDePreflight causa, required String detalle, required String queHacer})`; y `enum CausaDePreflight { ramaNoCoincide, headSuelto, baseIgualALaRama, baseIndeterminada, credencialAusente }`.

**Las tres reglas de la rama, del diseño:**

| Qué | Comportamiento |
|---|---|
| `--branch` presente | **Aserción**: tiene que coincidir con la rama actual |
| `--branch` ausente | La rama actual, mostrada en la previsualización |
| No coincide · `HEAD` suelto · rama actual **igual a la base** | Preflight, código `4` |

**`ship` nunca cambia de rama.** El usuario crea o cambia antes. Además de simple es necesario: cambiar de rama después de verificar invalidaría el candidato, porque el contenido expuesto a los controles dejaría de ser el que se va a commitear. La enmienda que esto requería ya está en el puerto: `ChangeSink.useBranch` dice que crear o cambiar la rama es de `start`.

**La base no se asume:**

```
--base explícito → configuración de shipflow → rama por defecto que informa la forja
                 → error de preflight si no se puede determinar
```

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
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
      ) as PreflightOk).base,
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
      ) as PreflightOk).base,
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
      ) as PreflightOk).base,
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
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/ship/preflight_test.dart
```

- [ ] **Paso 3: escribir el preflight**

Una función **pura sobre los hechos ya leídos**: recibe la rama actual, la pedida, las tres fuentes de base y la credencial, y devuelve el resultado. No lee el repositorio ni el entorno — quien la llama ya lo hizo. Así los siete casos se prueban sin montar un repositorio por cada uno, que es el mismo criterio que la recuperación de la rebanada anterior.

El doc comment tiene que declarar **qué no comprueba**: el directorio de corridas, a propósito y con el motivo.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/ship/preflight.dart packages/cli/test/ship/preflight_test.dart packages/cli/lib/cli.dart
git commit -m "ship afirma la rama, no la cambia: cambiarla invalidaría el candidato

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 4: El remapeo de rutas, y lo que NO se remapea

**Archivos:**
- Crear: `packages/orchestration/lib/src/remapeo.dart`
- Modificar: `packages/orchestration/lib/orchestration.dart`
- Test: `packages/orchestration/test/remapeo_test.dart`

**Interfaces:**
- Produce: `ResultadoDeCascada remapear(ResultadoDeCascada cascada, {required String raizDelCandidato})`.

**El problema:** la cascada corre sobre la raíz del candidato, así que sus diagnósticos apuntan a un directorio temporal. Sin remapear, el artefacto le muestra al revisor rutas que no existen en su árbol.

**Y el límite, que ya está medido y es normativo:** **remapear el mensaje rompe el contrato de evidencia citada.** `Diagnostic.message` es un `QuotedText` — el texto de la herramienta, sin reescribir. Se remapea `Diagnostic.file` y **nada más**. Si el mensaje de la herramienta menciona la ruta temporal, esa mención **se queda**, y el residuo se declara: es preferible una ruta rara en una cita a una cita adulterada.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el archivo del diagnóstico pasa a ser el del usuario', () {
    final remapeado = remapear(
      cascadaConDiagnosticoEn('/tmp/cand-1/lib/a.txt'),
      raizDelCandidato: '/tmp/cand-1',
    );
    expect(primerDiagnostico(remapeado).file, 'lib/a.txt');
  });

  test('el MENSAJE no se toca, aunque mencione la raíz temporal', () {
    // La evidencia se cita, no se reescribe. Una cita adulterada es peor que
    // una ruta rara: el revisor no puede saber qué dijo la herramienta.
    final sucio = cascadaConMensaje('no se pudo leer /tmp/cand-1/lib/a.txt');
    final remapeado = remapear(sucio, raizDelCandidato: '/tmp/cand-1');
    expect(
      primerDiagnostico(remapeado).message.text,
      contains('/tmp/cand-1/lib/a.txt'),
    );
  });

  test('un archivo que NO está bajo la raíz del candidato se deja igual', () {
    // Puede pasar: una herramienta que reporte sobre su propia instalación.
    // Reescribirlo inventaría una ruta del usuario que no existe.
    final remapeado = remapear(
      cascadaConDiagnosticoEn('/usr/lib/dart/x.txt'),
      raizDelCandidato: '/tmp/cand-1',
    );
    expect(primerDiagnostico(remapeado).file, '/usr/lib/dart/x.txt');
  });

  test('el remapeo no pierde ningún diagnóstico ni cambia su orden', () {
    final antes = cascadaConTresDiagnosticos();
    final despues = remapear(antes, raizDelCandidato: '/tmp/cand-1');
    expect(
      diagnosticosDe(despues).map((d) => d.ruleId).toList(),
      diagnosticosDe(antes).map((d) => d.ruleId).toList(),
    );
  });
```

Escribí los cuatro ayudantes con los constructores reales de `ResultadoDeCascada`, `StepOutcome` y `Diagnostic`. Mirá `packages/orchestration/test/` para ver cómo los arma la suite existente.

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/orchestration/test/remapeo_test.dart
```

- [ ] **Paso 3: escribir el remapeo**

El doc comment tiene que llevar el límite: **el mensaje no se toca**, con el motivo, y que una ruta que no está bajo la raíz se deja como está.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/orchestration
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/orchestration/lib/src/remapeo.dart packages/orchestration/lib/orchestration.dart packages/orchestration/test/remapeo_test.dart
git commit -m "Las rutas se remapean; la cita de la herramienta no se toca

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 5: El escaneo de secretos pasa al paso 5

**Archivos:**
- Modificar: `packages/vcs/lib/src/candidato.dart`
- Test: `packages/vcs/test/candidato_test.dart`

**El hecho, medido:** hoy el escaneo vive dentro de `createRevision`, que es el paso 11. §8 lo pone en el paso 5, **antes de la previsualización**. Mientras siga donde está, una corrida sin `--yes` se comporta como una previsualización, **nunca llega ahí**, y por lo tanto nunca ve el secreto: la precedencia `secretDetected > confirmationMissing` que el diseño fija es inalcanzable, y quien previsualiza con un secreto adentro recibe `0` y la impresión de que no hay nada que corregir.

**Lo que cambia y lo que no.** El escaneo se expone como una operación propia del candidato, invocable después de materializar y antes de escribir nada. **La llamada de `createRevision` se queda**: es el guardia que cierra la ventana entre lo que se inspecciona y lo que se commitea, y esa ventana no la cubre una comprobación anterior. O sea que el diff se escanea **dos veces**, y eso es deliberado.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el escaneo se puede pedir SIN escribir ningún objeto', () async {
    final candidato = await candidatoConSecreto();
    final espia = ObjetosEscritos.espiar(candidato);
    await expectLater(candidato.exigirSinSecretos(), throwsA(isA<SecretoEnLaRebanada>()));
    expect(espia.hubo, isFalse, reason: 'el paso 5 no escribe');
  });

  test('createRevision SIGUE escaneando: la ventana no la cubre el paso 5', () async {
    // Entre el escaneo del paso 5 y el commit puede cambiar el árbol. Dos
    // escaneos no es redundancia: son dos ventanas distintas.
    final candidato = await candidatoLimpio();
    await candidato.exigirSinSecretos();
    await ensuciarElArbolDelCandidato(candidato);
    await expectLater(candidato.createRevision(), throwsA(isA<SecretoEnLaRebanada>()));
  });
```

Escribí los ayudantes con los que ya usa `candidato_test`; si no hay forma de espiar la escritura de objetos, comprobalo listando el almacén temporal antes y después, y decilo en el reporte.

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/vcs/test/candidato_test.dart
```

- [ ] **Paso 3: exponer el escaneo**

Hacé pública la operación que hoy es privada, con un doc comment que diga **por qué se escanea dos veces**: el paso 5 le permite a la previsualización ver el secreto, y el del commit cierra la ventana.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/vcs
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
cd tool/analisis && dart run bin/check.dart && cd ../..
```

- [ ] **Paso 5: commitear**

```bash
git add packages/vcs/lib/src/candidato.dart packages/vcs/test/candidato_test.dart
git commit -m "Quien previsualiza también tiene que ver el secreto

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 6: El directorio de corridas y su `.gitignore`

**Archivos:**
- Crear: `packages/cli/lib/src/ship/gitignore.dart`
- Test: `packages/cli/test/ship/gitignore_test.dart`

**Interfaces:**
- Produce: `Future<void> asegurarGitignore(String raizDeShipflow)` y `Future<bool> corridasIgnoradas(RepositorioGit repo, String rutaDeUnaCorrida)`.

**Del diseño, con su momento exacto:** el `.gitignore` con `*` se crea **de forma atómica**, **sin sobrescribir uno existente y distinto**, y se comprueba **después de crearlo o validarlo y antes de persistir `prepared`** — **nunca en el preflight**, que impediría el primer uso.

**Y la comprobación no es que el archivo exista: es que `git` efectivamente ignore la ruta.** Un `.gitignore` puede existir y no aplicar —una regla de negación más arriba, un `core.excludesFile`—, y el fallo sería que el documento de la corrida termine commiteado dentro del pull request.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('se crea con `*` si no hay ninguno', () async {
    await asegurarGitignore(raiz);
    expect(await File('$raiz/.gitignore').readAsString(), contains('*'));
  });

  test('uno existente y DISTINTO no se sobrescribe: falla', () async {
    await File('$raiz/.gitignore').writeAsString('!importante\n');
    await expectLater(asegurarGitignore(raiz), throwsA(isA<Exception>()));
    expect(
      await File('$raiz/.gitignore').readAsString(),
      '!importante\n',
      reason: 'el contenido de alguien más no se pisa',
    );
  });

  test('uno existente e IGUAL no es un error', () async {
    await asegurarGitignore(raiz);
    await expectLater(asegurarGitignore(raiz), completes);
  });

  test('la comprobación pregunta por la RUTA, no por el archivo', () async {
    // Un `.gitignore` puede existir y no aplicar. Lo que importa es si `git`
    // ignora la ruta, y eso lo contesta `git`.
    await asegurarGitignore(raiz);
    expect(await corridasIgnoradas(repo, '$raiz/runs/r-1.json'), isTrue);
  });

  test('si una regla de negación lo desprotege, se detecta', () async {
    await asegurarGitignore(raiz);
    await File('$raiz/.gitignore').writeAsString('*\n!runs/\n');
    expect(await corridasIgnoradas(repo, '$raiz/runs/r-1.json'), isFalse);
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/ship/gitignore_test.dart
```

- [ ] **Paso 3: escribirlo**

La creación es temporal y `rename`, igual que el documento de la corrida —el mismo mecanismo y el mismo límite—. La comprobación se la hace a `git`; mirá qué subcomando contesta si una ruta está ignorada y usá el lanzador saneado de `vcs`, no uno propio.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
cd tool/analisis && dart run bin/check.dart && cd ../..
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/ship/gitignore.dart packages/cli/test/ship/gitignore_test.dart packages/cli/lib/cli.dart
git commit -m "No alcanza con que el .gitignore exista: tiene que ignorar la ruta

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 7: El cuerpo del pull request completa lo que §13 exige

**Archivos:**
- Modificar: `packages/forge/lib/src/cuerpo.dart`
- Test: `packages/forge/test/cuerpo_test.dart`

**El hallazgo que motiva esta tarea:** `cuerpoDeGitHub` recibe la solicitud entera y emite el alcance, la intención, la advertencia, las dos listas y el plan. §13 exige además **la revisión, el `runId`, `payloadVersion`, la acción siguiente y los testigos resumidos en un bloque plegable**. Tres de esos datos estaban disponibles cuando el cuerpo se escribió. El marcador estable lleva la revisión y el `runId`, pero **dentro de un comentario HTML**: invisibles para el revisor humano, que es exactamente para quien §13 dice que el cuerpo tiene que ser autosuficiente.

**Interfaces:**
- Consume: `accionDe(ShipOutcome)` de `cli`… **que `forge` no puede ver** —las flechas van hacia `core`—. Por eso la acción siguiente **entra como parámetro**: `cuerpoDeGitHub(PullRequestRequest solicitud, {String? accionSiguiente})`, y quien la compone es `cli`.
- Produce: `const payloadVersionDeShip = 1` en `core`, junto al desenlace, porque lo comparten el cuerpo y el payload del CLI.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('la revisión y el runId se VEN, no solo en el marcador', () {
    // El marcador va dentro de un comentario HTML: la forja no lo muestra.
    // Un dato que solo está ahí no está para el revisor humano.
    final cuerpo = cuerpoDeGitHub(solicitudDePrueba());
    final visible = sinComentariosHtml(cuerpo);
    expect(visible, contains(revisionDePrueba));
    expect(visible, contains(runIdDePrueba));
  });

  test('la acción siguiente aparece cuando se la da', () {
    final cuerpo = cuerpoDeGitHub(
      solicitudDePrueba(),
      accionSiguiente: 'correr esto otra vez con --yes',
    );
    expect(sinComentariosHtml(cuerpo), contains('correr esto otra vez con --yes'));
  });

  test('sin acción siguiente no se inventa una sección vacía', () {
    final cuerpo = cuerpoDeGitHub(solicitudDePrueba());
    expect(sinComentariosHtml(cuerpo), isNot(contains('## Qué hacer')));
  });

  test('los testigos van en un bloque plegable, y no se truncan', () {
    final cuerpo = cuerpoDeGitHub(solicitudConTestigoLargo());
    expect(cuerpo, contains('<details>'));
    expect(cuerpo, contains(sujetoDelTestigoLargo));
    expect(cuerpo, isNot(contains('…')), reason: 'nunca se truncan en silencio');
  });

  test('el bloque plegable va DESPUÉS de las dos secciones obligatorias', () {
    final cuerpo = cuerpoDeGitHub(solicitudDePrueba());
    expect(
      cuerpo.indexOf('## Qué quedó cubierto'),
      lessThan(cuerpo.indexOf('<details>')),
    );
  });

  test('payloadVersion viaja en el cuerpo', () {
    expect(sinComentariosHtml(cuerpoDeGitHub(solicitudDePrueba())),
        contains('$payloadVersionDeShip'));
  });
```

`sinComentariosHtml` ya existe en esa suite como `renglonesVisibles` o equivalente: reusala en vez de escribir otra.

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/forge/test/cuerpo_test.dart
```

- [ ] **Paso 3: escribir las secciones**

Todo lo que agregues pasa por el render seguro por contexto que el archivo ya tiene —`_textoDeBloque`, `_textoEnLista`, `_identificadorEnCodigo`—: un dato de la corrida no puede cambiar la estructura del cuerpo. **El `<details>` es del adapter**, que es quien aplica la sintaxis; la estructura —que los testigos van agrupados y después de lo obligatorio— es la decisión neutral.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/forge packages/core
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/forge/lib/src/cuerpo.dart packages/forge/test/cuerpo_test.dart packages/core/lib/src/corrida.dart
git commit -m "Lo que solo está en un comentario HTML no está para quien revisa

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 8: La previsualización y la compuerta

**Archivos:**
- Crear: `packages/cli/lib/src/ship/preview.dart`
- Test: `packages/cli/test/ship/preview_test.dart`

**Interfaces:**
- Produce: `String previsualizacion({required EntradaDeShip entrada, required String rama, required String base, required ArtefactoDeRevision artefacto, required List<String> cambiosAjenos})`; y `bool autoriza({required EstadoDeCorrida estado, required bool allowIncomplete})`.

**La compuerta, estado por estado:**

| Estado | Qué puede hacer |
|---|---|
| `verde` | Publica |
| `rojo` | Solo con `--allow-incomplete` |
| `noConcluyente` | Solo con `--allow-incomplete` |
| `errorInterno` | **Nunca publica** |

`--allow-incomplete` autoriza publicar una verificación que **concluyó mal**, no una que no concluyó porque el instrumento se rompió. Y autoriza **una** cosa: no es licencia para saltar secretos ni el árbol exacto.

**Y `--yes` no omite ninguna compuerta** — ni `--allow-incomplete`, ni la de estado, ni el preflight. Autoriza escribir; no autoriza publicar algo que no concluyó.

**Los cambios ajenos van al canal local y solo ahí.** `apply` deja intacto lo que no es de la rebanada, pero esas rutas **no** van al artefacto ni al cuerpo remoto: la superficie se deriva de la cascada, que no los conoce, y publicarle a un revisor remoto rutas que no puede ver no es accionable y filtra nombres de trabajo local.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('la compuerta, estado por estado', () {
    expect(autoriza(estado: EstadoDeCorrida.verde, allowIncomplete: false), isTrue);
    for (final e in [EstadoDeCorrida.rojo, EstadoDeCorrida.noConcluyente]) {
      expect(autoriza(estado: e, allowIncomplete: false), isFalse, reason: e.name);
      expect(autoriza(estado: e, allowIncomplete: true), isTrue, reason: e.name);
    }
    expect(autoriza(estado: EstadoDeCorrida.errorInterno, allowIncomplete: true),
        isFalse,
        reason: '--allow-incomplete no autoriza el arnés roto');
  });

  test('la compuerta cubre TODOS los estados', () {
    // Un estado nuevo tiene que obligar a decidir si publica.
    for (final e in EstadoDeCorrida.values) {
      expect(() => autoriza(estado: e, allowIncomplete: false), returnsNormally);
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
      reason: 'publicarle al revisor remoto rutas que no puede ver filtra '
          'nombres de trabajo local y no es accionable',
    );
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/ship/preview_test.dart
```

- [ ] **Paso 3: escribirlas**

`autoriza` es un `switch` **exhaustivo** sobre `EstadoDeCorrida`, sin comodín: un estado nuevo no compila hasta que alguien decida si publica.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/ship/preview.dart packages/cli/test/ship/preview_test.dart packages/cli/lib/cli.dart
git commit -m "--yes autoriza escribir; no autoriza publicar lo que no concluyó

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 9: La orquestación — los dieciséis pasos, y la limpieza en todo camino

**Archivos:**
- Crear: `packages/cli/lib/src/ship/ship.dart`
- Test: `packages/cli/test/ship/ship_test.dart`

**Interfaces:**
- Produce: `Future<ShipOutcome> correrShip({ … })`, con todos los colaboradores inyectables para poder probar cada camino sin red ni forja.

**La secuencia, con lo que ya existe entre paréntesis:**

```
 1  preflight                                   (tarea 3)
 2  prepareCandidate                            (vcs, ya existe)
 3  materializar                                (vcs, ya existe)
 4  cascada sobre la raíz del candidato         (orchestration, ya existe)
    remapear                                    (tarea 4)
 5  exigirSinSecretos                           (tarea 5)
 6  derivarSuperficie + componer el artefacto   (orchestration, ya existe)
 7  previsualización                            (tarea 8)
 8  autoriza                                    (tarea 8)
 9  asegurarGitignore + corridasIgnoradas       (tarea 6)
10  promover                                    (vcs, ya existe)
11  createRevision                              (vcs, ya existe)
12  escribir `prepared` CON la revisión         (4a, ya existe)
13  applyRevision                               (vcs, ya existe)
14  escribir `committed`                        (4a, ya existe)
15  open(request)                               (forge, ya existe)
16  escribir el ShipOutcome final               (4a, ya existe)
```

**La limpieza corre en TODO camino**, incluidos los de excepción: el workspace, el índice y el almacén temporales. Un camino que salga sin limpiar deja objetos y directorios que nadie va a recoger.

**Y `derivarSuperficie` gana acá su primer llamador productivo**, con el residuo que la rebanada 2 dejó parqueado: hasta hoy se lo llamaba con la lista de alteraciones vacía. Acá se le pasa la real, que sale del candidato.

- [ ] **Paso 1: escribir las pruebas que fallan**

Las pruebas son de camino, y cada una fija un desenlace:

```dart
  test('--dry-run no deja NADA: ni objetos, ni commit, ni PR', () async {
    final mundo = MundoDePrueba();
    final r = await mundo.correr(dryRun: true);
    expect(r, isA<NoIntentado>());
    expect((r as NoIntentado).causa, CausaDeNoIntento.previewOnly);
    expect(mundo.objetosPersistentes, isEmpty);
    expect(mundo.commits, isEmpty);
    expect(mundo.pullRequests, isEmpty);
    expect(mundo.temporalesQueQuedaron, isEmpty);
  });

  test('sin --yes se comporta como una previsualización', () async {
    final mundo = MundoDePrueba();
    final r = await mundo.correr(yes: false);
    expect((r as NoIntentado).causa, CausaDeNoIntento.confirmationMissing);
    expect(mundo.commits, isEmpty);
  });

  test('un secreto se ve SIN --yes, y gana sobre la confirmación', () async {
    // Es la precedencia que el diseño fija y que hasta esta rebanada no se
    // podía alcanzar, porque el escaneo vivía en el camino de escritura.
    final mundo = MundoDePrueba(conSecreto: true);
    final r = await mundo.correr(yes: false);
    expect((r as NoIntentado).causa, CausaDeNoIntento.secretDetected);
    expect(mundo.commits, isEmpty);
  });

  test('rojo sin --allow-incomplete no publica, y con él sí', () async {
    expect(
      ((await MundoDePrueba(estado: EstadoDeCorrida.rojo).correr(yes: true))
              as NoIntentado)
          .causa,
      CausaDeNoIntento.verificationGate,
    );
    expect(
      await MundoDePrueba(estado: EstadoDeCorrida.rojo)
          .correr(yes: true, allowIncomplete: true),
      isA<Publicado>(),
    );
  });

  test('el arnés roto NUNCA publica, ni con --allow-incomplete', () async {
    final mundo = MundoDePrueba(estado: EstadoDeCorrida.errorInterno);
    final r = await mundo.correr(yes: true, allowIncomplete: true);
    expect(r, isA<NoIntentado>());
    expect(mundo.commits, isEmpty);
    expect(mundo.pullRequests, isEmpty);
  });

  test('el CAS rechazado da NoAplicado y la rama no se movió', () async {
    final mundo = MundoDePrueba(headSeMueveAntesDelCas: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoAplicado>());
    expect(mundo.ramaSeMovio, isFalse);
  });

  test('el camino feliz publica y deja el documento en su estado final', () async {
    final mundo = MundoDePrueba();
    final r = await mundo.correr(yes: true);
    expect(r, isA<Publicado>());
    expect(mundo.documento!.estado, EstadoDelDocumento.publicationComplete);
  });

  test('la limpieza corre AUNQUE el camino termine en excepción', () async {
    final mundo = MundoDePrueba(laCascadaExplota: true);
    await expectLater(mundo.correr(yes: true), throwsA(anything));
    expect(mundo.temporalesQueQuedaron, isEmpty);
  });

  test('la rebanada se identifica como `<runId>/1`, no como el runId', () async {
    // Hoy hay UNA rebanada por corrida, pero el modelo final admite varias.
    // Igualar las dos identidades fusiona dos cosas que van a divergir.
    final mundo = MundoDePrueba();
    await mundo.correr(yes: true, runId: 'r-9');
    expect(mundo.rebanadaQueSePidio!.id, 'r-9/1');
  });

  test('el paso 14 escribe las proyecciones, y son LOCALES', () async {
    // El JSON de la revisión es local y está ignorado por git: el revisor
    // remoto no puede abrirlo, y por eso el cuerpo del PR es autosuficiente.
    // Si alguna vez tuviera que estar remoto, se publica por un mecanismo
    // explícito, nunca por una ruta local.
    final mundo = MundoDePrueba();
    await mundo.correr(yes: true);
    expect(mundo.proyeccionesEscritas, isNotEmpty);
    for (final ruta in mundo.proyeccionesEscritas) {
      expect(
        await corridasIgnoradas(mundo.repo, ruta),
        isTrue,
        reason: '$ruta no está ignorada: terminaría commiteada en el PR',
      );
    }
  });

  test('la superficie recibe las alteraciones REALES del candidato', () async {
    // El residuo que la rebanada de la superficie dejó parqueado: hasta hoy
    // se la llamaba con la lista vacía, y vacía significa «comprobado e
    // intacto», no «no se comprobó».
    final mundo = MundoDePrueba(candidatoAlterado: true);
    final r = await mundo.correr(yes: true);
    expect(r, isA<NoIntentado>());
    expect(mundo.superficieRecibio, isNotEmpty);
  });
```

**`MundoDePrueba` es el ayudante grande de esta tarea**, y de él depende que las diez pruebas midan algo. Escribilo en el mismo archivo. Tiene que doblar a **todos** los colaboradores de la firma y **registrar hechos, no llamadas**: qué objetos persistentes quedaron, qué commits se crearon, qué pull requests se abrieron, qué temporales sobrevivieron, qué documento quedó escrito, qué rebanada se pidió, qué alteraciones recibió la superficie y qué proyecciones se escribieron. Sus interruptores son los que las pruebas usan: `conSecreto`, `estado`, `headSeMueveAntesDelCas`, `laCascadaExplota` y `candidatoAlterado`.

**Reusá los dobles que ya existen en `plugin_fake`** —`SalidaDePrFalsa`, `FuenteDeCredencialFalsa` y los demás— en vez de escribir otros: un doble nuevo al lado de uno que ya existe es una segunda definición del mismo contrato, y divergen.

Para lo de `vcs` no hay dobles: usá un repositorio de verdad en un directorio temporal, como ya hacen `packages/vcs/test/candidato_test` y `packages/cli/test/entorno_del_candidato_test`. Es más lento y es lo correcto: lo que estas pruebas fijan es que el commit **no ocurre** en ciertos caminos, y eso contra un doble no prueba nada.

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/ship/ship_test.dart
```

- [ ] **Paso 3: escribir la orquestación**

El esqueleto, con la limpieza en `finally`:

```dart
Future<ShipOutcome> correrShip({
  required EntradaDeShip entrada,
  required String runId,
  required RepositorioGit repo,
  required VerificationEnvironment ambiente,
  required Cascada Function(String raiz) construirCascada,
  required Map<String, Verifier> controles,
  required CredentialSource credenciales,
  required PullRequestSink forja,
  required RegistroDeCorridas registro,
  required String ramaActual,
  String? baseConfigurada,
  String? baseDeLaForja,

  /// Cómo se pregunta la confirmación. **Inyectable para poder probar los dos
  /// caminos** sin una terminal: sin terminal no se pregunta y se sale como
  /// una previsualización, que es lo que el contrato del CLI ya dice.
  required Future<bool> Function(String previsualizacion)? confirmar,
}) async {
  final pre = preflight(/* … */);
  if (pre is PreflightFallo) return /* … */;

  PreparedCandidate? candidato;
  try {
    candidato = await repo.prepareCandidate(rebanada);
    final entorno = await ambiente.derivar(candidato.root, /* … */);
    final cascada = /* correr sobre candidato.root */;
    final remapeada = remapear(cascada, raizDelCandidato: candidato.root);
    await candidato.exigirSinSecretos();          // paso 5
    final superficie = derivarSuperficie(
      entorno: entorno,
      alteraciones: await candidato.alteraciones(/* … */),
      cascada: remapeada,
      controles: controles,
    );
    // … artefacto, previsualización, compuerta, gitignore, promoción,
    //    commit-tree, prepared, CAS, committed, publicación, desenlace
  } finally {
    // **En TODO camino.** Un camino que salga sin limpiar deja objetos y
    // directorios que nadie va a recoger.
    await candidato?.dispose();
  }
}
```

Cada desenlace sale de `ShipOutcome.derivar`: **no construyas variantes a mano**, que para eso los constructores son privados.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
cd tool/analisis && dart run bin/check.dart && cd ../..
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/ship/ship.dart packages/cli/test/ship/ship_test.dart packages/cli/lib/cli.dart
git commit -m "Los dieciséis pasos, y la limpieza en todo camino

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 10: El comando y su payload

**Archivos:**
- Modificar: `packages/cli/lib/src/comando.dart`, `packages/cli/lib/src/salida.dart`
- Test: `packages/cli/test/comando_test.dart`

**El payload de `ship`, del diseño.** El envelope **no sube de versión** —ADR-019 lo fija en `2`, y subirlo haría que `verify` emitiera `3` contra un ADR aceptado—: `ship` versiona **su propio payload**.

```json
{
  "schema": 2,
  "exitCode": 6,
  "verdict": "ok",
  "data": {
    "payloadVersion": 1,
    "deliveryStatus": "incomplete",
    "push": "succeeded", "pullRequest": "unknown", "retryable": true,
    "revision": "abc123", "branch": "feature/x", "base": "main", "runId": "…",
    "candidate": {"contentRevision": "…", "baseRevision": "…"}
  },
  "nextAction": "shipflow ship --retry-publication <runId>. No se creará otro commit ni un segundo PR."
}
```

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el envelope NO sube de versión', () {
    expect(payloadDeShip(desenlaceDePrueba())['schema'], isNull,
        reason: 'el schema es del envelope, no del payload');
    expect(esquemaDeSalida, 2);
  });

  test('el payload lleva su propia versión', () {
    expect(payloadDeShip(desenlaceDePrueba())['payloadVersion'],
        payloadVersionDeShip);
  });

  test('una entrega incompleta sale 6 y dice cómo reintentar', () {
    final d = ShipOutcome.publicacionIncompletaParaLaPrueba(
      remoto: PushUnknown(causa: CausaDePublicacion.red),
      verificacion: EstadoPublicable.verde,
    );
    expect(Codigo.deShip(d), 6);
    expect(accionDe(d), contains('--retry-publication'));
  });

  test('shipflow ship sin argumentos sale 5, no 70', () async {
    expect(await ejecutarDePrueba(['ship']), Codigo.errorDeUso);
  });

  test('la ayuda nombra a ship y sus banderas', () async {
    final texto = await ayudaDePrueba();
    for (final b in ['ship', '--intent', '--file', '--slice', '--yes',
                     '--dry-run', '--allow-incomplete']) {
      expect(texto, contains(b), reason: b);
    }
  });

  test('la ayuda nombra los códigos nuevos', () async {
    final texto = await ayudaDePrueba();
    for (final c in ['3', '4', '6']) {
      expect(texto, contains(c), reason: c);
    }
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/comando_test.dart
```

- [ ] **Paso 3: registrar el comando y escribir el payload**

Registrá `ship` en el despachador, agregalo a la ayuda con sus banderas y los códigos nuevos, y escribí `payloadDeShip`. **Las causas secundarias no se pierden**: cuando la precedencia descarta una, viaja en `data`.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/comando.dart packages/cli/lib/src/salida.dart packages/cli/test/comando_test.dart
git commit -m "El envelope no sube: ship versiona su propio payload

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 10b: La forja compuesta, y el payload completo

**Esta tarea se agregó durante la ejecución, y el plan no la tenía.** La tarea 10
descubrió que `ship` corre punta a punta hasta el paso 14 y que el 15 —la
publicación— no tiene con qué: la configuración del adapter de la forja exige
dueño, repositorio, base de API y URL del remoto, y ninguno es derivable hoy.

**La decisión de arquitectura que ejecuta.** El residuo declarado de la regla
`forja-en-su-adapter` anticipaba este choque y dejaba dos salidas —renombrar los
símbolos del paquete de la forja, o darle a la regla una excepción acotada a la
raíz de composición—, diciendo que la elección era de esta rebanada. Se eligió
una tercera: **una fábrica de nombre neutro dentro del paquete de la forja**, que
recibe la URL del remoto y arma su propia configuración. La `alternativa` de la
propia regla ya la contenía —«el resto del árbol recibe un puerto, nunca el
proveedor»—: lo que faltaba no era una excepción, era el constructor. Así la
marca no cruza el límite ni una vez y el día que haya un segundo proveedor la
selección ya vive donde tiene que vivir.

Sus siete pasos están en
`.superpowers/sdd/PLAN-ship-el-comando/task-10b-brief.md`: la lectura del remoto
en `vcs`, la fábrica neutra y su parseo de URL, la composición, los cuatro campos
del payload releídos del documento persistido, la salida por código de
configuración cuando no hay repositorio, y el registro de la decisión en el
manifiesto.

---

### Tarea 11: El cierre — declaraciones, grafo y arnés entero

**Archivos:**
- Modificar: `arquitectura.json`, `README.md`, `grafo.jsonl`

- [ ] **Paso 1: los puertos que salen de la lista**

`ChangeSink` y `VerificationEnvironment` salieron de `sin_implementacion` en rebanadas anteriores **sin consumidor**, y eso quedó escrito. Esta rebanada les da el primero. Revisá esas entradas y actualizá lo que haya quedado vencido: la convención del mapa es decir **con cuántas implementaciones salió** cada puerto y qué le falta.

- [ ] **Paso 2: enlazar el plan desde el README**

`grafo.dart` trata un archivo que ningún punto de entrada alcanza como huérfano. Agregá el párrafo que enlaza este plan, con el estilo de los anteriores. **Hacelo temprano si podés**: el rojo del grafo arrastra a `capas.py`, y un rojo que tapa a otro ya costó ocho tareas en la rebanada anterior.

- [ ] **Paso 3: documentar la rebanada y sus residuos**

Los que tienen que quedar escritos:

- **La detección de secretos corre dos veces, y es deliberado**: el paso 5 para que la previsualización la vea, y el del commit para cerrar la ventana entre lo que se inspecciona y lo que se commitea.
- **El remapeo toca `Diagnostic.file` y no el mensaje**: si el texto de la herramienta menciona la ruta temporal, esa mención se queda. Una cita adulterada es peor que una ruta rara.
- **`--retry-publication` no existe todavía**: es la rebanada siguiente. Lo que sí existe es el documento que la hace posible.
- **La comprobación del `.gitignore` le pregunta a `git` si la ruta está ignorada**, no si el archivo existe.
- **Lo que esta rebanada NO hace**, en su propia sección.

- [ ] **Paso 4: regenerar el grafo y correr todo**

```
cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart && cd ../..
python3 tool/checks/capas.py
```

- [ ] **Paso 5: el arnés entero, solo**

```
ARNES_ORIGEN=$(pwd) python3 tool/checks/probar_reglas.py
python3 tool/checks/probar_recuperacion.py
```
**Sin tocar nada mientras corre.**

- [ ] **Paso 6: commitear**

```bash
git add arquitectura.json README.md grafo.jsonl
git commit -m "El comando ship, declarado: lo que hace, lo que no, y lo que deja abierto

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```
