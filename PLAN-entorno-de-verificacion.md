# El entorno de verificación del candidato · plan de implementación

> **ESTADO: ejecutado el 12–13/09/2026, inline. Las casillas quedan sin marcar a propósito.**
>
> Las once tareas se ejecutaron en orden con `superpowers:executing-plans`, y **el registro es el `git log`**: once commits, uno por tarea, cada uno nombrando lo que encontró. Las sesenta y cinco casillas de abajo dicen «nada hecho» mientras el `README` y el historial dicen que está terminado; **lo cierto es el historial**. Se dejan sin marcar en vez de marcarlas ahora, porque marcarlas al final fabrica un registro de ejecución que nadie llevó paso por paso — es la misma decisión que tomó `PLAN-desenlace-cerrado.md`, y por el mismo motivo.
>
> **Lo que este plan no anticipó está en los commits, no acá.** Nueve hallazgos aparecieron al construir, y tres de ellos corrigen al diseño que el plan implementa; el borrador del corpus y `ADR-020` los registran.

> **Para quien ejecute algo así:** usá `superpowers:subagent-driven-development` (recomendado) o `superpowers:executing-plans`, tarea por tarea.

**Objetivo.** Que la cascada corra **dentro** del candidato materializado, con un entorno derivado del propio candidato y comprobado íntegro antes y después, y que ningún subproceso que este repositorio lance herede el entorno del padre.

**Arquitectura.** Un puerto nuevo en `core`, `VerificationEnvironment`, que `plugin_dart` implementa derivando el entorno con `dart pub get --offline --enforce-lockfile` **una vez por raíz de resolución que la rebanada toca**. Un control de integridad en `vcs`, `PreparedCandidate.alteraciones()`, que le pregunta a `git` qué versionado dejó de coincidir con el árbol fijado. Una función pura en `core`, `entornoSaneado`, que es la única forma admitida de armar el `environment:` de un subproceso, y una regla de `tool/analisis` que lo hace cumplir sobre el árbol sintáctico.

**Stack.** Dart 3.11+ con `dart test`; `git` de verdad en las pruebas de `vcs`; `analyzer` en `tool/analisis`; checks en Python bajo `tool/checks`.

**Diseño que implementa.** `../sdlc-agentico/borradores/PROPUESTA-entorno-de-verificacion.md` (v2 + las cuatro condiciones de la aprobación, commit `26105ac` del corpus). Leelo antes de la primera tarea; este plan argumenta desde ahí y no repite sus razones. Las secciones se citan como §N y los apéndices como A-N.

## Restricciones globales

Valen para toda tarea. Copiadas del diseño y de las reglas ya instaladas.

- **`core` no tiene dependencias ni entrada/salida.** No puede importar `dart:io` ni `package:path`. `entornoSaneado` recibe el mapa del padre como parámetro; nunca lee `Platform.environment`.
- **Las cadenas `dart`, `flutter` y `pubspec` no aparecen fuera de `plugin_dart` y `cli`** (extensiones `.dart .yaml .yml .json .sh .bash .md`, bajo `packages/`). `PUB_CACHE` no contiene ninguna de las tres y puede vivir en `core`.
- **Toda dependencia interna declarada en un pubspec se importa en ese paquete**, en la sección que corresponde a dónde se importa: `cli` gana `vcs` como **dev_dependency**, porque solo su `test/` lo importa.
- **En `core`, los campos de colección se copian a una vista inmodificable; los campos públicos son exactamente las claves de `toJson`/`fromJson`; una clase o serializa o está declarada opaca en `arquitectura.json`.** Cada clase serializable nueva tiene su caso canónico en `packages/core/test/serializacion_test.dart`, sin ningún valor por defecto en ningún campo.
- **Ninguna causa, evidencia o detalle se acepta en blanco.** Los veredictos y estados se derivan, nunca se asignan.
- **La evidencia externa viaja como `QuotedText`**, sin recortar ni normalizar.
- **Un subproceso se lanza con `environment: entornoSaneado(...)` e `includeParentEnvironment: false`.** La única excepción es la captura de identidad de `git` (§8), declarada en `arquitectura.json` y contada por el check.
- **`arquitectura.json` no se edita sin regenerar `tool/checks/arquitectura.huella`** (`python3 tool/checks/capas.py --huella`), y **`grafo.jsonl` se regenera** cuando cambia un import (`cd tool/analisis && dart run bin/grafo.dart --escribir`).
- **Cada tarea termina con la suite del paquete que tocó en verde, `dart analyze --fatal-infos` limpio, `dart format` sin cambios, y un commit** con `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. Nunca `git add -A`: rutas explícitas.
- **No se corre `probar_reglas.py` a la vez que `capas.py`.** El arnés lo detecta y hay que recuperar con `--recuperar`.
- La rama es `entorno-de-verificacion`, desde `develop`; el PR va a `develop`.

## Refinamientos del diseño que este plan fija

Cinco cosas que el código obliga a cerrar antes de escribir, medidas el 12/09/2026. **Las tres primeras se apartan de una frase del diseño y hay que llevarlas al corpus** (tarea 11); van marcadas para que quien apruebe el plan las vea.

1. **`pub` no distingue por código de salida un cache frío de un candidato inválido.** Medido: sin lockfile → `1`; lockfile que no satisface → `65`; cache vacío → `69`; `sdk: inexistente` en el pubspec → **también `69`**. §6 prohíbe deducir la causa de frases de stderr, así que **todo código distinto de cero de `pub` es `CandidatoRechazado(pubRechazoLaResolucion)`** con la salida citada. `DerivacionAbortada` queda para lo que el instrumento no llegó a decir: `herramientaAusente` y `tiempoAgotado`, que ya distingue `EjecutorDeProceso`. **La fila de §14 «cache vacío → `DerivacionAbortada`» pasa a `CandidatoRechazado`**; Q-3 ya dice que la corrida es `noConcluyente` en los dos casos, y la evidencia citada dice cuál fue.
2. **La dependencia `path` que escapa se lee del `pubspec.lock`, no del `package_config.json`.** §7 decía lo segundo. `package_config.json` no distingue una dependencia `path` de una hospedada: las dos tienen `rootUri` fuera del candidato —la hospedada apunta al cache—, y una de `sdk: flutter` apunta al SDK. El lockfile sí: `source: path` y `description.path`. Es el archivo que `--enforce-lockfile` acaba de validar sin reescribir.
3. **La captura de identidad corre con el entorno del padre y es la única excepción a la regla.** §8 lo dice en bash y §9 no lo contempla. `git config --get user.name` tiene que ver `XDG_CONFIG_HOME` y `GIT_CONFIG_GLOBAL`, que la lista blanca no lleva a propósito. La regla gana `excepciones`: exactamente un sitio, en un método nombrado, y el check **cuenta** los lanzamientos sin sanear de ese archivo: más de uno es rojo.
4. **`cambioDeModo` se lee de los modos de `--raw`, y tapa un cambio de contenido simultáneo.** `diff-index --raw` deja el segundo identificador en ceros —no hashea el árbol de trabajo—, así que con modo y contenido cambiados a la vez se reporta `cambioDeModo`. Es una alteración igual y la corrida es `noConcluyente` igual; queda declarado como residuo en el tipo.
5. **Cero raíces es un entorno derivado con cero raíces.** Un archivo del alcance sin ningún `pubspec.yaml` entre él y la raíz del candidato no tiene raíz de resolución. Si ninguno la tiene, no hay nada que derivar y `derivar` devuelve `EntornoDerivado(paquetes: 0, raices: 0)`: el observador de alcance ya va a decir que nada es del stack. No es un rechazo: un candidato sin Dart no es un candidato defectuoso.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `packages/core/lib/src/entorno.dart` | **Nuevo.** `entornoSaneado`, función pura: lista blanca + variables propias |
| `packages/core/lib/src/desenlace.dart` | `ResultadoDeEntorno` sellado: `EntornoDerivado`, `CandidatoRechazado`, `DerivacionAbortada`; `CausaDeRechazo` |
| `packages/core/lib/src/entidades.dart` | `IdentidadDeToolchain`, `AlteracionDelCandidato`, `TipoDeAlteracion` |
| `packages/core/lib/src/puertos.dart` | `VerificationEnvironment`; `PreparedCandidate.alteraciones()` |
| `packages/core/lib/core.dart` | exporta `entorno.dart` |
| `packages/core/test/entorno_test.dart` | **Nuevo.** La lista blanca |
| `packages/core/test/serializacion_test.dart` | Casos canónicos de los tipos nuevos |
| `packages/vcs/lib/src/alteraciones.dart` | **Nuevo `part`.** `leerDiffRaw`: el parser de `diff-index --raw -z`, falla cerrado |
| `packages/vcs/lib/src/candidato.dart` | `alteraciones()`; `chmod` saneado; `commit-tree` con identidad y `useConfigOnly` |
| `packages/vcs/lib/src/repositorio.dart` | Las tres costuras saneadas; `entornoDelPadre` inyectable; `_identidadConfigurada` |
| `packages/vcs/test/candidato_test.dart` | Integridad, filtros, identidad, lista blanca |
| `packages/plugin_dart/lib/src/ejecutor.dart` | `EjecutorDelSistema` saneado, con `entornoDelPadre` |
| `packages/plugin_dart/lib/src/raices.dart` | **Nuevo.** `raicesDeResolucion`, función pura sobre rutas y manifiestos |
| `packages/plugin_dart/lib/src/entorno.dart` | **Nuevo.** `EntornoDart implements VerificationEnvironment` |
| `packages/plugin_dart/lib/plugin_dart.dart` | exporta los dos |
| `packages/plugin_dart/test/raices_test.dart` | **Nuevo.** El fixture con la forma de este repositorio |
| `packages/plugin_dart/test/entorno_test.dart` | **Nuevo.** Derivar, rechazar, abortar |
| `packages/plugin_dart/test/ejecutor_test.dart` | **Nuevo.** Lo que el ejecutable recibe |
| `packages/cli/pubspec.yaml` | `vcs` en `dev_dependencies` |
| `packages/cli/test/entorno_del_candidato_test.dart` | **Nuevo.** La prueba decisiva |
| `tool/analisis/bin/check.dart` | Regla `subprocesos-con-entorno-saneado` |
| `arquitectura.json` | La regla; opacidad de la base sellada; el fake diferido |
| `tool/checks/probar_reglas.py` · `tool/checks/capas.py` | Extras obligatorias; mecanismo de ceguera fijado |
| `tool/checks/arquitectura.huella` · `grafo.jsonl` | Regenerados |
| `README.md` | Fila en la tabla de reglas; sección de la rebanada; fila en la tabla de fakes |
| Corpus (`../sdlc-agentico`) | `ARNES-DEL-PROYECTO.md`, `docs/03`, `docs/06`, `REGISTRO-DELTAS.md`, ADR-020, enmiendas a la propuesta, dos diagramas |

---
### Task 0: La rama

**Files:** ninguno.

- [ ] **Step 1:** `git switch develop && git pull --ff-only && git switch -c entorno-de-verificacion`
- [ ] **Step 2:** Comprobá el punto de partida en verde: `dart pub get && dart test packages/core packages/vcs packages/plugin_dart packages/cli && python3 tool/checks/capas.py`. Todo verde antes de tocar nada.

---

### Task 1: `entornoSaneado` en `core`

**Files:**
- Create: `packages/core/lib/src/entorno.dart`
- Modify: `packages/core/lib/core.dart` (un `export`)
- Test: `packages/core/test/entorno_test.dart`

**Interfaces:**
- Produces: `Map<String, String> entornoSaneado(Map<String, String> delPadre, {Map<String, String> propias = const {}})`. Lista blanca fija `PATH`, `HOME`, `PUB_CACHE`. `propias` se suman tal cual (son las `GIT_*` que el llamador decide en esa invocación). Lanza `ArgumentError` si una clave de `propias` está en la lista blanca: pisar `PATH` desde afuera es exactamente el agujero que se cierra.

- [ ] **Step 1: Escribí la prueba que falla**

```dart
/// §8: lista blanca, no lista negra. Una variable secreta futura no puede
/// filtrarse sola.
library;

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  const padre = {
    'PATH': '/usr/bin',
    'HOME': '/home/u',
    'PUB_CACHE': '/home/u/.pub-cache',
    'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
    'GIT_DIR': '/otro/repo/.git',
    'XDG_CONFIG_HOME': '/home/u/.config',
  };

  test('deja pasar exactamente PATH, HOME y PUB_CACHE', () {
    expect(entornoSaneado(padre), {
      'PATH': '/usr/bin',
      'HOME': '/home/u',
      'PUB_CACHE': '/home/u/.pub-cache',
    });
  });

  test('una variable que no está en la lista no pasa, se llame como se llame', () {
    final s = entornoSaneado(padre);
    expect(s.containsKey('SHIPFLOW_GITHUB_TOKEN'), isFalse);
    expect(s.containsKey('GIT_DIR'), isFalse);
    expect(s.containsKey('XDG_CONFIG_HOME'), isFalse);
  });

  test('PUB_CACHE solo viaja si el padre la tiene', () {
    expect(entornoSaneado({'PATH': '/bin'}), {'PATH': '/bin'});
  });

  test('las propias se suman tal cual', () {
    final s = entornoSaneado(padre, propias: {'GIT_INDEX_FILE': '/tmp/i'});
    expect(s['GIT_INDEX_FILE'], '/tmp/i');
    expect(s['PATH'], '/usr/bin');
  });

  test('una propia no puede pisar la lista blanca', () {
    expect(
      () => entornoSaneado(padre, propias: {'PATH': '/evil'}),
      throwsArgumentError,
    );
  });

  test('el resultado es inmodificable', () {
    expect(() => entornoSaneado(padre)['X'] = 'y', throwsUnsupportedError);
  });
}
```

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/core/test/entorno_test.dart`. Esperado: falla en compilación, `entornoSaneado` no existe.

- [ ] **Step 3: Implementación mínima** — `packages/core/lib/src/entorno.dart`:

```dart
/// El entorno con el que se lanza **todo** subproceso de este repositorio.
///
/// **Lista blanca, no lista negra** (§8 de la propuesta de entorno). Una lista
/// negra promete solo sobre lo que alguien enumeró: cualquier variable secreta
/// futura se filtra sola. Esta función promete lo contrario, y una regla de
/// `tool/analisis` exige que sea la única forma de armar un `environment:`.
///
/// Es pura a propósito: recibe el mapa del padre en vez de leer
/// `Platform.environment`, porque `core` no puede tocar `dart:io` y porque
/// así la prueba le pasa el padre que quiere.
library;

/// Lo único que se hereda. Medido variable por variable (A-8): `dart analyze`
/// necesita solo `PATH`; `dart pub get` necesita encontrar el cache; `git`
/// necesita `HOME`.
const listaBlanca = {'PATH', 'HOME', 'PUB_CACHE'};

/// Arma el entorno saneado: la lista blanca tomada de [delPadre], más
/// [propias] —las variables que ESA invocación necesita y que el llamador
/// decide, como `GIT_INDEX_FILE` o la identidad capturada—.
///
/// Una propia no puede pisar la lista blanca: `PATH` decide qué binario corre,
/// y aceptarlo desde afuera sería reabrir por otra puerta lo que se cerró.
Map<String, String> entornoSaneado(
  Map<String, String> delPadre, {
  Map<String, String> propias = const {},
}) {
  final pisadas = propias.keys.where(listaBlanca.contains).toList()..sort();
  if (pisadas.isNotEmpty) {
    throw ArgumentError.value(
      pisadas,
      'propias',
      'Estas variables son de la lista blanca y se toman del padre, no de '
          'quien llama.',
    );
  }
  return Map.unmodifiable({
    for (final k in listaBlanca)
      if (delPadre.containsKey(k)) k: delPadre[k]!,
    ...propias,
  });
}
```

Y en `packages/core/lib/core.dart`, junto a los otros exports: `export 'src/entorno.dart';`. Agregá a la lista de la cabecera del barril una línea: `/// - **entorno** — [entornoSaneado], la lista blanca con la que se lanza todo subproceso.`

- [ ] **Step 4: Corré y verificá que pasa** — `dart test packages/core/test/entorno_test.dart`. Esperado: 6 pruebas en verde. Después `dart analyze --fatal-infos packages/core && dart format --set-exit-if-changed packages/core`.

- [ ] **Step 5: Commit**

```bash
git add packages/core/lib/src/entorno.dart packages/core/lib/core.dart packages/core/test/entorno_test.dart
git commit -m "core: entornoSaneado, la lista blanca con la que se lanza todo subproceso

PATH, HOME y PUB_CACHE del padre, más lo que cada invocación declara. Una
lista negra promete solo sobre lo enumerado; esta promete lo contrario.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Los tipos del entorno en `core`

**Files:**
- Modify: `packages/core/lib/src/desenlace.dart` (al final)
- Modify: `packages/core/lib/src/entidades.dart` (al final)
- Modify: `packages/core/lib/src/puertos.dart` (después de `PreparedCandidate`)
- Modify: `arquitectura.json` (`opacidad-declarada.opacos`, `puertos-sin-implementacion.sin_implementacion`)
- Modify: `packages/core/test/serializacion_test.dart`
- Test: `packages/core/test/entorno_test.dart` (mismo archivo de la tarea 1, grupo nuevo)

**Interfaces:**
- Produces, en `desenlace.dart`:
  ```dart
  sealed class ResultadoDeEntorno { ResultadoDeEntorno(); }
  final class EntornoDerivado extends ResultadoDeEntorno { final int paquetes; final int raices; final IdentidadDeToolchain toolchain; }
  final class CandidatoRechazado extends ResultadoDeEntorno { final CausaDeRechazo causa; final QuotedText evidencia; }
  final class DerivacionAbortada extends ResultadoDeEntorno { final Termination terminacion; final QuotedText evidencia; }
  enum CausaDeRechazo { pubRechazoLaResolucion, dependenciaPathQueEscapa, elArbolVersionaLoQueSeGenera }
  ```
  Cada variante lleva `String get kind` (`'derivado' | 'rechazado' | 'abortada'`), `toJson()` con la clave `kind` además de sus campos, y `fromJson`. La base sellada se declara opaca en `arquitectura.json` **con el mismo texto de motivo que `StepOutcome`** (es la misma situación: jerarquía sellada cuyas variantes serializan).
- Produces, en `entidades.dart`:
  ```dart
  class IdentidadDeToolchain { final QuotedText version; }              // §7: se cita, no se parsea
  enum TipoDeAlteracion { modificada, borrada, cambioDeModo, cambioDeTipo }
  class AlteracionDelCandidato { final String ruta; final TipoDeAlteracion tipo; }
  ```
- Produces, en `puertos.dart`:
  ```dart
  abstract interface class VerificationEnvironment {
    Future<ResultadoDeEntorno> derivar(String candidateRoot, {required List<String> archivos, required Duration presupuesto});
  }
  ```
  **`PreparedCandidate.alteraciones()` NO se agrega acá**: agregarlo rompe la compilación de `vcs` hasta que exista la implementación. Va en la tarea 3, junto con ella.

- [ ] **Step 1: Escribí las pruebas que fallan** — agregá a `packages/core/test/entorno_test.dart` un `group('los tipos del entorno', ...)`:

```dart
  group('los tipos del entorno', () {
    final cita = QuotedText('Unable to satisfy', source: 'pub get');

    test('un rechazo o un aborto no se construyen sin evidencia', () {
      expect(
        () => CandidatoRechazado(
          causa: CausaDeRechazo.pubRechazoLaResolucion,
          evidencia: const QuotedText('', source: 'pub get'),
        ),
        throwsArgumentError,
      );
      expect(
        () => DerivacionAbortada(
          terminacion: Termination.herramientaAusente,
          evidencia: const QuotedText('   ', source: 'x'),
        ),
        throwsArgumentError,
      );
    });

    test('una derivación abortada no puede decir que terminó completa', () {
      // `completa` es «la herramienta corrió y dijo algo»: eso es un rechazo
      // o un entorno derivado, nunca un aborto.
      expect(
        () => DerivacionAbortada(
          terminacion: Termination.completa,
          evidencia: cita,
        ),
        throwsArgumentError,
      );
    });

    test('un entorno derivado no admite cifras negativas ni una toolchain muda', () {
      final tc = IdentidadDeToolchain(
        version: QuotedText('Dart SDK version: 3.12.0', source: 'dart --version'),
      );
      expect(() => EntornoDerivado(paquetes: -1, raices: 1, toolchain: tc), throwsArgumentError);
      expect(() => EntornoDerivado(paquetes: 3, raices: -1, toolchain: tc), throwsArgumentError);
      expect(
        () => IdentidadDeToolchain(version: const QuotedText('', source: 'x')),
        throwsArgumentError,
      );
      // Cero raíces SÍ se admite (refinamiento 5): un candidato sin nada que
      // derivar no es un candidato defectuoso.
      expect(EntornoDerivado(paquetes: 0, raices: 0, toolchain: tc).raices, 0);
    });

    test('una alteración sin ruta no nombra nada', () {
      expect(
        () => AlteracionDelCandidato(ruta: ' ', tipo: TipoDeAlteracion.borrada),
        throwsArgumentError,
      );
    });

    test('ResultadoDeEntorno es cerrado: un switch sin default cubre las tres', () {
      // Si alguien agrega una variante, esto deja de compilar. Es la prueba.
      String nombre(ResultadoDeEntorno r) => switch (r) {
        EntornoDerivado() => 'derivado',
        CandidatoRechazado() => 'rechazado',
        DerivacionAbortada() => 'abortada',
      };
      expect(
        nombre(CandidatoRechazado(causa: CausaDeRechazo.dependenciaPathQueEscapa, evidencia: cita)),
        'rechazado',
      );
    });
  });
```

Nota: en Dart, el `switch` exhaustivo sin `default` sobre un tipo `sealed` es un error de compilación si falta una variante; es lo que hace que la prueba «no admite representar un entorno derivado incompatible» de §14 sea una propiedad del tipo y no una aserción.

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/core/test/entorno_test.dart`. Esperado: no compila.

- [ ] **Step 3: Implementación** — al final de `packages/core/lib/src/desenlace.dart`:

```dart
/// Qué pasó al intentar dejar el candidato en condiciones de ser verificado.
///
/// **Tres desenlaces, y la línea que los separa** (§6): [CandidatoRechazado] es
/// un hecho sobre el candidato; [DerivacionAbortada] es un hecho sobre el
/// instrumento, y no dice nada del candidato. La v1 los mezclaba en un solo
/// enum, que es la confusión que ADR-019 cerró del lado de los pasos.
///
/// Las dos variantes que no son [EntornoDerivado] hacen la corrida
/// `noConcluyente`, nunca roja.
sealed class ResultadoDeEntorno {
  ResultadoDeEntorno();

  String get kind;
  Map<String, Object?> toJson();

  factory ResultadoDeEntorno.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'derivado' => EntornoDerivado.fromJson(json),
        'rechazado' => CandidatoRechazado.fromJson(json),
        'abortada' => DerivacionAbortada.fromJson(json),
        final otro => throw FormatException(
          'ResultadoDeEntorno con kind «$otro», que no es ninguna variante.',
        ),
      };
}

/// El entorno quedó derivado del candidato. Lleva hechos contables, del mismo
/// tipo que «cuántos archivos miró» que el testigo ya lleva.
final class EntornoDerivado extends ResultadoDeEntorno {
  @override
  final String kind = 'derivado';

  /// Entradas de los `package_config.json` resultantes, sumadas.
  final int paquetes;

  /// Cuántas raíces de resolución se derivaron (§10). Cero es legítimo.
  final int raices;

  final IdentidadDeToolchain toolchain;

  EntornoDerivado({
    required this.paquetes,
    required this.raices,
    required this.toolchain,
  }) {
    if (paquetes < 0 || raices < 0) {
      throw ArgumentError(
        'Las cifras del entorno son cuentas: no pueden ser negativas.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'paquetes': paquetes,
    'raices': raices,
    'toolchain': toolchain.toJson(),
  };

  factory EntornoDerivado.fromJson(Map<String, Object?> json) =>
      EntornoDerivado(
        paquetes: json['paquetes']! as int,
        raices: json['raices']! as int,
        toolchain: IdentidadDeToolchain.fromJson(
          json['toolchain']! as Map<String, Object?>,
        ),
      );
}

/// Por qué el candidato no se puede verificar **por lo que es**.
enum CausaDeRechazo {
  /// **`pub` dijo que no, y no inventamos por qué.** Lockfile ausente,
  /// resolución inválida, hash cambiado, SDK incompatible o cache sin el
  /// paquete: `pub` no ofrece un protocolo que los distinga —medido: un SDK
  /// desconocido y un cache frío salen los dos con 69—, y deducirlo de stderr
  /// sería el parser frágil que este proyecto rechaza. La evidencia va citada.
  pubRechazoLaResolucion,

  /// Una dependencia `path` resuelve fuera del candidato (§7). El lockfile
  /// identifica la ruta, no lo que hay adentro.
  dependenciaPathQueEscapa,

  /// El árbol versiona lo que la derivación genera, así que derivar lo
  /// destruiría. Se detecta **antes** de correr nada.
  elArbolVersionaLoQueSeGenera,
}

/// No se puede verificar **por lo que el candidato es**.
final class CandidatoRechazado extends ResultadoDeEntorno {
  @override
  final String kind = 'rechazado';

  final CausaDeRechazo causa;

  /// Lo que la herramienta dijo, tal cual. Nunca en blanco.
  final QuotedText evidencia;

  CandidatoRechazado({required this.causa, required this.evidencia}) {
    if (evidencia.content.trim().isEmpty) {
      throw ArgumentError.value(
        evidencia,
        'evidencia',
        'Un rechazo sin evidencia es una acusación sin prueba.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'causa': causa.name,
    'evidencia': evidencia.toJson(),
  };

  factory CandidatoRechazado.fromJson(Map<String, Object?> json) =>
      CandidatoRechazado(
        causa: CausaDeRechazo.values.byName(json['causa']! as String),
        evidencia: QuotedText.fromJson(
          json['evidencia']! as Map<String, Object?>,
        ),
      );
}

/// No se pudo derivar **por lo que pasó al intentarlo**. No dice nada del
/// candidato: dice que el instrumento no llegó a medir.
final class DerivacionAbortada extends ResultadoDeEntorno {
  @override
  final String kind = 'abortada';

  /// Nunca [Termination.completa]: «corrió y dijo algo» es un rechazo o un
  /// entorno derivado, no un aborto.
  final Termination terminacion;

  final QuotedText evidencia;

  DerivacionAbortada({required this.terminacion, required this.evidencia}) {
    if (terminacion == Termination.completa) {
      throw ArgumentError.value(
        terminacion,
        'terminacion',
        'Una derivación que terminó completa no se abortó: o derivó, o '
            'rechazó al candidato.',
      );
    }
    if (evidencia.content.trim().isEmpty) {
      throw ArgumentError.value(
        evidencia,
        'evidencia',
        'Un aborto sin evidencia no dice qué falló.',
      );
    }
  }

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'terminacion': terminacion.name,
    'evidencia': evidencia.toJson(),
  };

  factory DerivacionAbortada.fromJson(Map<String, Object?> json) =>
      DerivacionAbortada(
        terminacion: Termination.values.byName(json['terminacion']! as String),
        evidencia: QuotedText.fromJson(
          json['evidencia']! as Map<String, Object?>,
        ),
      );
}
```

Al final de `packages/core/lib/src/entidades.dart`:

```dart
/// Con qué toolchain se derivó el entorno (§7).
///
/// **No se parsea la versión. Se cita.** Un número extraído de una frase es un
/// parser más, y lo que hace falta es que el testigo diga con qué se midió.
class IdentidadDeToolchain {
  final QuotedText version;

  IdentidadDeToolchain({required this.version}) {
    if (version.content.trim().isEmpty) {
      throw ArgumentError.value(
        version,
        'version',
        'Una toolchain que no dice qué versión es no identifica nada.',
      );
    }
  }

  Map<String, Object?> toJson() => {'version': version.toJson()};

  factory IdentidadDeToolchain.fromJson(Map<String, Object?> json) =>
      IdentidadDeToolchain(
        version: QuotedText.fromJson(json['version']! as Map<String, Object?>),
      );
}

/// Qué le pasó a una entrada versionada del candidato (§5).
enum TipoDeAlteracion {
  modificada,
  borrada,

  /// El modo cambió. **Residuo declarado:** `diff-index --raw` no hashea el
  /// árbol de trabajo, así que si el contenido cambió A LA VEZ, se reporta esto
  /// y no [modificada]. Es una alteración igual.
  cambioDeModo,

  /// Un archivo regular donde el árbol tiene un enlace, o al revés.
  cambioDeTipo,
}

/// Una entrada versionada del candidato que dejó de coincidir con su árbol.
///
/// **Los archivos nuevos no cuentan**: son lo que el entorno genera, y
/// generarlos es su trabajo.
class AlteracionDelCandidato {
  final String ruta;
  final TipoDeAlteracion tipo;

  AlteracionDelCandidato({required this.ruta, required this.tipo}) {
    if (ruta.trim().isEmpty) {
      throw ArgumentError.value(ruta, 'ruta', 'Una alteración sin ruta no nombra nada.');
    }
  }

  Map<String, Object?> toJson() => {'ruta': ruta, 'tipo': tipo.name};

  factory AlteracionDelCandidato.fromJson(Map<String, Object?> json) =>
      AlteracionDelCandidato(
        ruta: json['ruta']! as String,
        tipo: TipoDeAlteracion.values.byName(json['tipo']! as String),
      );
}
```

En `packages/core/lib/src/puertos.dart`, inmediatamente después de la clase `PreparedCandidate`:

```dart
/// Deja el candidato en condiciones de ser verificado.
///
/// **Lo aporta el plugin del stack**, porque qué hace falta para ejecutar es
/// conocimiento del lenguaje: `core` no puede saberlo y `orchestration` no
/// puede verlo. El entorno se **deriva** del candidato —de lo que el candidato
/// fija—, nunca se presta del árbol de trabajo del usuario (§4).
///
/// **Lleva presupuesto porque abre un subproceso**, y recibe los archivos del
/// alcance porque deriva **una vez por raíz de resolución que la rebanada
/// toca** (§10): un manifiesto que la rebanada no toca no existe para ella.
///
/// No hay `dispose`: lo que se deriva vive dentro de `candidateRoot`, y
/// [PreparedCandidate.dispose] ya borra esa raíz entera.
abstract interface class VerificationEnvironment {
  Future<ResultadoDeEntorno> derivar(
    String candidateRoot, {
    required List<String> archivos,
    required Duration presupuesto,
  });
}
```

- [ ] **Step 4: Declaraciones en `arquitectura.json`** — dos ediciones, con Python para no romper el JSON:

```bash
python3 - <<'EOF'
import json, pathlib
p = pathlib.Path('arquitectura.json'); a = json.loads(p.read_text())
op = a['reglas']['opacidad-declarada']['opacos']
op['ResultadoDeEntorno'] = {"por_que": "Misma situacion que StepOutcome y CommitOutcome: base de una jerarquia sellada cuyas variantes —EntornoDerivado, CandidatoRechazado, DerivacionAbortada— serializan cada una con su kind, y la base solo despacha fromJson. Sin esta declaracion, «no tiene toJson propio» seria indistinguible de un olvido."}
si = a['reglas']['puertos-sin-implementacion']['sin_implementacion']
si['VerificationEnvironment'] = "rebanada del entorno de verificacion · la implementacion real llega en plugin_dart dentro de la MISMA PR (tarea 7 del plan); esta linea existe para que el arbol compile en verde entre las dos tareas, y se borra al implementarlo"
p.write_text(json.dumps(a, indent=2, ensure_ascii=False) + "\n")
EOF
python3 tool/checks/capas.py --huella
```

Revisá con `git diff arquitectura.json` que el diff sea **solo** esas dos claves (el `indent=2` tiene que coincidir con el formato actual; si el diff muestra reindentación masiva, deshacé y editá a mano).

- [ ] **Step 5: Casos canónicos en `serializacion_test.dart`** — agregá, junto a las otras instancias del `main`, y sus entradas en el mapa `canonicas` (buscá `'RutaNoMaterializada': (` para ubicarte):

```dart
  final toolchain = IdentidadDeToolchain(
    version: QuotedText('Dart SDK version: 3.12.0 (stable)', source: 'dart --version'),
  );
  final alteracion = AlteracionDelCandidato(
    ruta: 'tool/x/pubspec.lock',
    tipo: TipoDeAlteracion.borrada,
  );
  final derivado = EntornoDerivado(paquetes: 9, raices: 2, toolchain: toolchain);
  final rechazado = CandidatoRechazado(
    causa: CausaDeRechazo.dependenciaPathQueEscapa,
    evidencia: QuotedText('../fuera', source: 'pubspec.lock'),
  );
  final abortada = DerivacionAbortada(
    terminacion: Termination.tiempoAgotado,
    evidencia: QuotedText('Presupuesto agotado', source: 'dart pub get'),
  );
```

```dart
        'IdentidadDeToolchain': (toolchain.toJson(), IdentidadDeToolchain.fromJson),
        'AlteracionDelCandidato': (alteracion.toJson(), AlteracionDelCandidato.fromJson),
        'EntornoDerivado': (derivado.toJson(), EntornoDerivado.fromJson),
        'CandidatoRechazado': (rechazado.toJson(), CandidatoRechazado.fromJson),
        'DerivacionAbortada': (abortada.toJson(), DerivacionAbortada.fromJson),
```

Ojo: las cadenas de estos literales van en un archivo de `core/test`, donde `dart` y `pubspec` **están prohibidas** por `lenguaje-en-plugin-dart` (alcance `packages/`, extensión `.dart`). Reemplazá en las evidencias: `'Dart SDK version: 3.12.0 (stable)'` → `'SDK version: 3.12.0 (stable)'`, `source: 'dart --version'` → `source: 'toolchain --version'`, `source: 'pubspec.lock'` → `source: 'lockfile'`, `source: 'dart pub get'` → `source: 'resolver'`, y la ruta `'tool/x/pubspec.lock'` → `'tool/x/lockfile'`. Lo mismo vale para `entorno_test.dart` de esta tarea y la anterior: **ninguna de las tres cadenas en `core`**. `capas.py` lo va a decir si te olvidás.

- [ ] **Step 6: Corré todo lo que mira `core`**

```bash
dart test packages/core && dart analyze --fatal-infos packages/core && dart format --set-exit-if-changed packages/core \
  && python3 tool/checks/capas.py && (cd tool/analisis && dart run bin/check.dart)
```

Esperado: `serializacion: ok — 33 clases serializables…, 10 opacas declaradas, 20 puertos sin implementación declarados` (las cifras suben 5, 1 y 1 respecto de hoy: 28, 9, 19).

- [ ] **Step 7: Commit**

```bash
git add packages/core arquitectura.json tool/checks/arquitectura.huella
git commit -m "core: los tres desenlaces del entorno, y el puerto que los produce

ResultadoDeEntorno sellado: derivado, rechazado por lo que el candidato es,
abortado por lo que le pasó al instrumento. La línea entre los dos últimos es
la que ADR-019 trazó del lado de los pasos. El puerto queda declarado sin
implementación hasta la tarea que la trae, en esta misma rama.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 3: `alteraciones()` en `vcs`

**Files:**
- Create: `packages/vcs/lib/src/alteraciones.dart` (`part of 'repositorio.dart'`)
- Modify: `packages/vcs/lib/src/repositorio.dart` (una línea `part 'alteraciones.dart';` junto a `part 'candidato.dart';`)
- Modify: `packages/vcs/lib/src/candidato.dart` (`alteraciones()` en `_CandidatoGit`; un `File _indiceDeIntegridad` nuevo en el constructor)
- Modify: `packages/core/lib/src/puertos.dart` (`Future<List<AlteracionDelCandidato>> alteraciones();` en `PreparedCandidate`)
- Test: `packages/vcs/test/candidato_test.dart` (grupo nuevo) y `packages/vcs/test/alteraciones_test.dart` (nuevo, el parser)

**Interfaces:**
- Consumes: `AlteracionDelCandidato`, `TipoDeAlteracion` (tarea 2); `_repo._exigir/_exigirBytes` con `entorno:`; `_entorno` del candidato; `noMaterializadas`.
- Produces: en el puerto, `Future<List<AlteracionDelCandidato>> alteraciones();`. Y el parser público del `part`: `List<AlteracionDelCandidato> leerDiffRaw(List<int> bytes, {required Set<String> declaradas})`.

**Lo medido que esto fija** (A-6, A-10, A-11, A-12): sin `update-index --refresh` el árbol entero sale modificado; sin `-q` el refresco sale 1 cuando hay algo que reportar; `--name-status` pliega el modo en `M`; lo no materializado sale como `D`; el `clean` corre en el refresco.

**Formato de `diff-index --raw -z`**, medido: cada registro es `:<modo viejo> <modo nuevo> <sha viejo> <sha nuevo> <letra>` seguido de **NUL**, la ruta, y **NUL**. El sha nuevo es siempre ceros. Ejemplo, con los NUL como `\0`:

```
:100644 100755 5c1b1494… 0000000… M\0a.txt\0:120000 000000 555dec97… 0000000… D\0abs\0
```

- [ ] **Step 1: Escribí la prueba del parser** — `packages/vcs/test/alteraciones_test.dart`:

```dart
/// El parser de `diff-index --raw -z`, aislado, porque es donde una letra que
/// nadie previó se puede descartar en silencio.
library;

import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

List<int> registro(String meta, String ruta) =>
    [...utf8.encode(meta), 0, ...utf8.encode(ruta), 0];

const ceros = '0000000000000000000000000000000000000000';
const sha = '5c1b14949828006ed75a3e8858957f86a2f7e2eb';

void main() {
  test('M con el mismo modo es modificada', () {
    final r = leerDiffRaw(registro(':100644 100644 $sha $ceros M', 'a.txt'), declaradas: {});
    expect(r.single.ruta, 'a.txt');
    expect(r.single.tipo, TipoDeAlteracion.modificada);
  });

  test('M con otro modo es cambioDeModo', () {
    final r = leerDiffRaw(registro(':100644 100755 $sha $ceros M', 'a.txt'), declaradas: {});
    expect(r.single.tipo, TipoDeAlteracion.cambioDeModo);
  });

  test('D es borrada, T es cambioDeTipo', () {
    final bytes = [
      ...registro(':100644 000000 $sha $ceros D', 'x'),
      ...registro(':120000 100644 $sha $ceros T', 'd/rel'),
    ];
    final r = leerDiffRaw(bytes, declaradas: {});
    expect(r.map((a) => a.tipo), [TipoDeAlteracion.borrada, TipoDeAlteracion.cambioDeTipo]);
  });

  test('una D sobre una ruta declarada no cuenta; una T sobre ella sí', () {
    final bytes = [
      ...registro(':120000 000000 $sha $ceros D', 'abs'),
      ...registro(':120000 100644 $sha $ceros T', 'up'),
    ];
    final r = leerDiffRaw(bytes, declaradas: {'abs', 'up'});
    expect(r.single.ruta, 'up');
    expect(r.single.tipo, TipoDeAlteracion.cambioDeTipo);
  });

  test('una letra que no sea M, D ni T falla cerrado', () {
    expect(
      () => leerDiffRaw(registro(':100644 100644 $sha $ceros R100', 'a'), declaradas: {}),
      throwsA(isA<PromesaIncumplida>()),
    );
    expect(
      () => leerDiffRaw(registro(':100644 100644 $sha $ceros A', 'a'), declaradas: {}),
      throwsA(isA<PromesaIncumplida>()),
    );
  });

  test('un registro sin su ruta falla cerrado', () {
    expect(
      () => leerDiffRaw([...utf8.encode(':100644 100644 $sha $ceros M'), 0], declaradas: {}),
      throwsA(isA<PromesaIncumplida>()),
    );
  });

  test('vacío es ninguna alteración', () {
    expect(leerDiffRaw(const [], declaradas: {}), isEmpty);
  });
}
```

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/vcs/test/alteraciones_test.dart`. Esperado: no compila, `leerDiffRaw` no existe.

- [ ] **Step 3: El parser** — `packages/vcs/lib/src/alteraciones.dart`:

```dart
/// El control de integridad del candidato (§5 de la propuesta de entorno):
/// **se le pide a `git`**, igual que el grafo se le pide a `pub`. Acá vive solo
/// la lectura de lo que `git` contestó; la invocación está en el candidato,
/// que es quien tiene las costuras.
part of 'repositorio.dart';

/// Lee la salida de `diff-index --raw -z`.
///
/// **Falla cerrado ante una letra que no sea `M`, `D` ni `T`.** Con un índice
/// recién leído del árbol no puede haber `A`; una `R` o una `C` solo aparecen
/// con detección de renombres, que no se pide. Si aparece algo así, `git` vio
/// algo que este control no previó, y descartarlo sería leer un hueco como un
/// candidato intacto.
///
/// [declaradas] son las rutas que el candidato **no materializó a propósito**
/// —enlaces absolutos, con `..`, con destino que no es UTF-8, submódulos—.
/// Para `git` están en el árbol y no en el disco, así que salen como `D`
/// (medido, A-10). Una `D` sobre una declarada no es una alteración; **cualquier
/// otra letra sobre ella sí**: alguien escribió algo donde el candidato dejó
/// un hueco a sabiendas.
List<AlteracionDelCandidato> leerDiffRaw(
  List<int> bytes, {
  required Set<String> declaradas,
}) {
  final piezas = _CandidatoGit._partirNul(bytes);
  if (piezas.length.isOdd) {
    throw const PromesaIncumplida(
      'leer la salida de `diff-index --raw -z`',
      'un registro sin su ruta',
    );
  }
  final salida = <AlteracionDelCandidato>[];
  for (var i = 0; i < piezas.length; i += 2) {
    final meta = utf8.decode(piezas[i]).split(' ');
    if (meta.length != 5 || !meta[0].startsWith(':')) {
      throw PromesaIncumplida(
        'leer un registro de `diff-index --raw`',
        '«${utf8.decode(piezas[i])}», que no tiene la forma esperada',
      );
    }
    final modoViejo = meta[0].substring(1);
    final modoNuevo = meta[1];
    final letra = meta[4];
    final ruta = _CandidatoGit._comoRuta(piezas[i + 1]);

    final TipoDeAlteracion tipo;
    switch (letra) {
      case 'D':
        if (declaradas.contains(ruta)) continue;
        tipo = TipoDeAlteracion.borrada;
      case 'T':
        tipo = TipoDeAlteracion.cambioDeTipo;
      case 'M':
        tipo = modoViejo == modoNuevo
            ? TipoDeAlteracion.modificada
            : TipoDeAlteracion.cambioDeModo;
      default:
        throw PromesaIncumplida(
          'clasificar la alteración de «$ruta»',
          'la letra «$letra» de `diff-index`, que este control no previó',
        );
    }
    salida.add(AlteracionDelCandidato(ruta: ruta, tipo: tipo));
  }
  return salida;
}
```

En `repositorio.dart`, debajo de `part 'candidato.dart';`: `part 'alteraciones.dart';`.

- [ ] **Step 4: Corré el parser** — `dart test packages/vcs/test/alteraciones_test.dart`. Esperado: 7 en verde.

- [ ] **Step 5: Las pruebas de integración contra `git`** — nuevo grupo en `candidato_test.dart`, después del grupo `'la preparación no deja efectos'`. Usa los ayudantes `git`, `escribir`, `rebanada`, `conCandidato` que ya están:

```dart
  group('la integridad del candidato se comprueba, no se supone', () {
    test('un candidato intacto no tiene alteraciones', () async {
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });

    test('modificado → modificada; borrado → borrada; +x → cambioDeModo; '
        'regular donde había enlace → cambioDeTipo', () async {
      escribir('a.txt', 'dos\n');
      escribir('b.txt', 'b\n');
      Link('${raiz.path}/enlace').createSync('a.txt');
      git(['add', '-A']);
      git(['commit', '-m', 'con enlace']);
      escribir('a.txt', 'tres\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        File('${c.root}/a.txt').writeAsStringSync('otra cosa\n');
        File('${c.root}/sub/hondo.txt').deleteSync();
        Process.runSync('chmod', ['755', '${c.root}/b.txt']);
        Link('${c.root}/enlace').deleteSync();
        File('${c.root}/enlace').writeAsStringSync('regular\n');
        final a = {for (final x in await c.alteraciones()) x.ruta: x.tipo};
        expect(a, {
          'a.txt': TipoDeAlteracion.modificada,
          'sub/hondo.txt': TipoDeAlteracion.borrada,
          'b.txt': TipoDeAlteracion.cambioDeModo,
          'enlace': TipoDeAlteracion.cambioDeTipo,
        });
        return null;
      });
    });

    test('un archivo generado nuevo NO es una alteración', () async {
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        Directory('${c.root}/.generado').createSync();
        File('${c.root}/.generado/config.json').writeAsStringSync('{}');
        File('${c.root}/nuevo.txt').writeAsStringSync('x');
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });

    test('lo declarado en noMaterializadas no es una alteración, los cuatro a la vez',
        () async {
      // Enlace absoluto, enlace con `..`, destino que no es UTF-8, y submódulo.
      Link('${raiz.path}/abs').createSync('/etc/hosts');
      Link('${raiz.path}/up').createSync('../fuera');
      git(['add', '-A']);
      // El destino no UTF-8 y el gitlink se escriben directo al índice.
      // `Process.start` y no `runSync`: hay que mandarle bytes por stdin.
      final p = await Process.start(
        'git', ['hash-object', '-w', '--stdin'], workingDirectory: raiz.path,
      );
      p.stdin.add([0xff, 0xfe, 0x2f, 0x78]);
      await p.stdin.close();
      final shaMalo = (await utf8.decodeStream(p.stdout)).trim();
      await p.exitCode;
      git(['update-index', '--add', '--cacheinfo', '120000,$shaMalo,raro']);
      git(['update-index', '--add', '--cacheinfo',
        '160000,4b825dc642cb6eb9a060e54bf8d69288fbee4904,sub']);
      git(['commit', '-m', 'lo que no se materializa']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(c.noMaterializadas.map((n) => n.ruta), unorderedEquals(['abs', 'up', 'raro', 'sub']));
        expect(await c.alteraciones(), isEmpty,
            reason: 'sin restar lo declarado, todo candidato con un enlace absoluto sería noConcluyente para siempre');
        return null;
      });
    });
```

```dart
    test('un regular escrito donde el árbol tiene un enlace no materializado SÍ es una alteración',
        () async {
      Link('${raiz.path}/abs').createSync('/etc/hosts');
      git(['add', '-A']);
      git(['commit', '-m', 'abs']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        File('${c.root}/abs').writeAsStringSync('regular\n');
        final a = await c.alteraciones();
        expect(a.single.ruta, 'abs');
        expect(a.single.tipo, TipoDeAlteracion.cambioDeTipo);
        return null;
      });
    });

    test('intacto con clean, smudge y eol=crlf → cero alteraciones', () async {
      git(['config', 'filter.marca.clean', 'sed s/SUCIO/LIMPIO/']);
      git(['config', 'filter.marca.smudge', 'sed s/LIMPIO/SUCIO/']);
      git(['config', 'core.autocrlf', 'true']);
      escribir('.gitattributes', 'conmarca.txt filter=marca\ncrlf.txt text eol=crlf\n');
      escribir('conmarca.txt', 'esto esta SUCIO\n');
      escribir('crlf.txt', 'l1\r\nl2\r\n');
      git(['add', '-A']);
      git(['commit', '-m', 'filtros']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });

    test('un clean NO idempotente hace `modificada` a un candidato intacto: el límite declarado',
        () async {
      // gitattributes(5): «clean→clean should be equivalent to clean». Un
      // repositorio que lo viola ya ve sus archivos perpetuamente modificados
      // en `git status`. Esta prueba FIJA el límite: si algún día da cero, la
      // decisión de §5 hay que revisarla, no el código.
      git(['config', 'filter.suma.clean', r'sed s/$/x/']);
      escribir('.gitattributes', 'suma.txt filter=suma\n');
      escribir('suma.txt', 'base\n');
      git(['add', '-A']);
      git(['commit', '-m', 'no idempotente']);
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        final a = await c.alteraciones();
        expect(a.map((x) => x.ruta), ['suma.txt']);
        expect(a.single.tipo, TipoDeAlteracion.modificada,
            reason: 'si esto deja de ser cierto, git cambió cómo refresca, y §5 hay que releerlo');
        return null;
      });
    });

    test('alteraciones() se puede llamar dos veces y después de crear la revisión', () async {
      escribir('a.txt', 'dos\n');
      await conCandidato(rebanada(['a.txt']), (c) async {
        expect(await c.alteraciones(), isEmpty);
        await c.createRevision();
        expect(await c.alteraciones(), isEmpty);
        return null;
      });
    });
  });
```

- [ ] **Step 6: Corré para verlas fallar** — `dart test packages/vcs/test/candidato_test.dart -N integridad`. Esperado: no compila, `alteraciones` no existe en `PreparedCandidate`.

- [ ] **Step 7: El puerto y la implementación.** En `puertos.dart`, dentro de `PreparedCandidate`, después de `noMaterializadas`:

```dart
  /// Qué entradas versionadas del candidato dejaron de coincidir con su árbol.
  ///
  /// Vacío significa intacto. **Los archivos nuevos no cuentan**: son lo que el
  /// entorno genera, y generarlos es su trabajo. **Lo declarado en
  /// [noMaterializadas] tampoco**, porque el candidato lo dejó afuera a
  /// sabiendas — pero si alguien escribió algo ahí, eso sí cuenta.
  ///
  /// Se comprueba dos veces: después de derivar el entorno, contra que la
  /// derivación haya borrado contenido versionado —está medido que lo hace—, y
  /// después de la cascada, contra que un verificador haya escrito en el
  /// workspace. Una alteración hace la corrida `noConcluyente`, nunca roja.
  Future<List<AlteracionDelCandidato>> alteraciones();
```

En `candidato.dart`, agregá un campo `final File _indiceDeIntegridad;` a `_CandidatoGit`, parámetro `required File indiceDeIntegridad` en el constructor privado, y en `preparar`: `final indiceDeIntegridad = File('${temporal.path}/indice-integridad');` pasado en las dos construcciones (`preparar` y `_fijarYMaterializar`). Es un índice **aparte** del de preparación: `read-tree` lo sobreescribe y no puede pisar el que fijó el contenido. Luego el método:

```dart
  @override
  Future<List<AlteracionDelCandidato>> alteraciones() async {
    if (_dispuesto) {
      throw StateError('El candidato ya se liberó: no hay árbol que comparar.');
    }
    // El índice propio se lee del árbol fijado, se refresca contra el disco y se
    // compara. Los tres comandos, medidos (A-6, A-10, A-12):
    //  - sin `--refresh`, cien diferencias falsas;
    //  - sin `-q`, `--refresh` sale 1 cuando hay algo que reportar y `_exigir`
    //    lo convertiría en GitFallo antes del diff;
    //  - `--raw` y no `--name-status`, que pliega el cambio de modo en `M`.
    final entorno = {
      ..._entorno,
      'GIT_INDEX_FILE': _indiceDeIntegridad.path,
      'GIT_WORK_TREE': root,
    };
    await _repo._exigir(['read-tree', identity.contentRevision], entorno: entorno);
    await _repo._exigir(['update-index', '-q', '--refresh'], entorno: entorno);
    final crudo = await _repo._exigirBytes([
      'diff-index',
      '--raw',
      '-z',
      identity.contentRevision,
    ], entorno: entorno);
    return leerDiffRaw(
      crudo,
      declaradas: {for (final n in noMaterializadas) n.ruta},
    );
  }
```

Ojo con `_promover`: hoy borra `_objetos` y el índice de preparación. Después de promover, `contentRevision` resuelve en el almacén real y `GIT_ALTERNATE_OBJECT_DIRECTORIES` apunta a un directorio borrado; `git` tolera un alternate ausente. La última prueba del grupo lo verifica.

- [ ] **Step 8: Corré todo `vcs`** — `dart test packages/vcs && dart analyze --fatal-infos packages/vcs packages/core && dart format --set-exit-if-changed packages/vcs packages/core`. Esperado: verde, con las 8 pruebas nuevas.

- [ ] **Step 9: El sabotaje del estado intermedio n.º 2** (§14): vaciá el cuerpo de `alteraciones()` para que devuelva `const []`, corré el grupo, comprobá que **se ponen rojas** las pruebas de «modificado → modificada» y del `clean` no idempotente. Restaurá el cuerpo a mano —no con `git checkout`, que borraría el trabajo sin commitear— y verificá verde otra vez. (La prueba de que el saboteo pone rojo no se automatiza acá: `probar_reglas.py` sabotea reglas, no pruebas.)

- [ ] **Step 10: Commit**

```bash
git add packages/core/lib/src/puertos.dart packages/vcs/lib/src/repositorio.dart packages/vcs/lib/src/alteraciones.dart packages/vcs/lib/src/candidato.dart packages/vcs/test/alteraciones_test.dart packages/vcs/test/candidato_test.dart
git commit -m "vcs: la integridad del candidato se comprueba, no se supone

read-tree + update-index -q --refresh + diff-index --raw -z sobre un índice
propio. Lo declarado en noMaterializadas sale como D y se resta; una letra
que no sea M, D ni T falla cerrado. Con filtros idempotentes y eol=crlf da
cero; con un clean no idempotente da modificada sobre un candidato intacto,
y la prueba fija ese límite en vez de taparlo.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 4: `vcs` lanza `git` con el entorno saneado, y la identidad se captura

**Files:**
- Modify: `packages/vcs/lib/src/repositorio.dart` (constructor; `_git`, `_exigirBytes`, `_exigirConEntrada`; `_identidadConfigurada` nuevo; el comentario de `_git` que dice que el entorno «se suma»)
- Modify: `packages/vcs/lib/src/candidato.dart` (`chmod`; `commit-tree`)
- Test: `packages/vcs/test/candidato_test.dart` (grupo nuevo)

**Interfaces:**
- Consumes: `entornoSaneado` (tarea 1).
- Produces: `RepositorioGit({..., Map<String, String>? entornoDelPadre})` — `null` significa `Platform.environment`; las pruebas le pasan el padre que quieren. `Future<Map<String, String>> _identidadComoEntorno()` (privado, memoizado): `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` cuando `git config --get` las devuelve; vacío si no.

**Lo medido que esto fija** (A-7, A-8): con `PATH+HOME` y la identidad solo en XDG, `git` **fabrica** un autor; `git config --get` con el entorno del padre la recupera; `user.useConfigOnly=true` hace que sin identidad falle con «Author identity unknown» en vez de inventar.

- [ ] **Step 1: Escribí las pruebas que fallan** — nuevo grupo en `candidato_test.dart`. Necesita un `git` falso que registre su entorno y delegue en el real:

```dart
  group('git corre con el entorno saneado', () {
    late File registro;
    late File gitFalso;

    setUp(() {
      registro = File('${raiz.path}/entorno-visto.txt');
      gitFalso = File('${raiz.path}/git-falso.sh')
        ..writeAsStringSync('#!/bin/sh\nenv >> "${registro.path}"\nexec git "\$@"\n');
      Process.runSync('chmod', ['755', gitFalso.path]);
    });

    RepositorioGit conPadre(Map<String, String> padre) => RepositorioGit(
      directorio: raiz.path,
      politica: const _TodoEsFuente(),
      programa: gitFalso.path,
      entornoDelPadre: padre,
    );

    test('el token del padre no llega a git, ni un GIT_DIR hostil', () async {
      final r = conPadre({
        'PATH': Platform.environment['PATH']!,
        'HOME': Platform.environment['HOME']!,
        'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
        'GIT_DIR': '/otro/repositorio/.git',
      });
      escribir('a.txt', 'dos\n');
      final c = await r.prepareCandidate(rebanada(['a.txt']));
      await c.dispose();
      final visto = registro.readAsStringSync();
      expect(visto, isNotEmpty, reason: 'el git falso tiene que haber corrido');
      expect(visto, isNot(contains('secreto-de-prueba')));
      expect(visto, isNot(contains('GIT_DIR=')),
          reason: 'un GIT_DIR del shell del usuario corrompería nuestras operaciones');
      expect(visto, contains('GIT_INDEX_FILE='),
          reason: 'las propias de la invocación sí viajan');
    });

    test('chmod también corre saneado', () async {
      escribir('ejecutable.sh', '#!/bin/sh\n');
      Process.runSync('chmod', ['755', '${raiz.path}/ejecutable.sh']);
      git(['add', '-A']);
      git(['commit', '-m', 'con ejecutable']);
      final chmodFalso = File('${raiz.path}/chmod-falso.sh')
        ..writeAsStringSync('#!/bin/sh\nenv >> "${registro.path}"\nexec chmod "\$@"\n');
      Process.runSync('chmod', ['755', chmodFalso.path]);
      final r = RepositorioGit(
        directorio: raiz.path,
        politica: const _TodoEsFuente(),
        programaChmod: chmodFalso.path,
        entornoDelPadre: {
          'PATH': Platform.environment['PATH']!,
          'HOME': Platform.environment['HOME']!,
          'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
        },
      );
      escribir('ejecutable.sh', '#!/bin/sh\necho x\n');
      final c = await r.prepareCandidate(rebanada(['ejecutable.sh']));
      await c.dispose();
      expect(registro.readAsStringSync(), isNot(contains('secreto-de-prueba')));
    });
  });

  group('la identidad del autor es la configurada, o no hay commit', () {
    late Directory hogar;

    setUp(() {
      // Sin identidad local: la que se prueba es la global, que es la que el
      // saneamiento puede perder.
      git(['config', '--unset', 'user.email']);
      git(['config', '--unset', 'user.name']);
      hogar = Directory.systemTemp.createTempSync('hogar_');
    });
    tearDown(() => hogar.deleteSync(recursive: true));

    Map<String, String> padre([Map<String, String> extra = const {}]) => {
      'PATH': Platform.environment['PATH']!,
      'HOME': hogar.path,
      ...extra,
    };

    Future<String> autorDe(RepositorioGit r) async {
      escribir('a.txt', 'dos\n');
      final c = await r.prepareCandidate(rebanada(['a.txt']));
      try {
        final rev = await c.createRevision();
        return git(['log', '-1', '--format=%an <%ae>', rev]);
      } finally {
        await c.dispose();
      }
    }

    RepositorioGit con(Map<String, String> p) =>
        RepositorioGit(directorio: raiz.path, politica: const _TodoEsFuente(), entornoDelPadre: p);

    test('con ~/.gitconfig', () async {
      File('${hogar.path}/.gitconfig')
          .writeAsStringSync('[user]\n\tname = Del Hogar\n\temail = hogar@ejemplo.test\n');
      expect(await autorDe(con(padre())), 'Del Hogar <hogar@ejemplo.test>');
    });

    test('con la identidad SOLO en XDG, que la lista blanca no lleva', () async {
      final xdg = Directory('${hogar.path}/config/git')..createSync(recursive: true);
      File('${xdg.path}/config')
          .writeAsStringSync('[user]\n\tname = Solo XDG\n\temail = xdg@ejemplo.test\n');
      expect(
        await autorDe(con(padre({'XDG_CONFIG_HOME': '${hogar.path}/config'}))),
        'Solo XDG <xdg@ejemplo.test>',
        reason: 'A-7: con PATH+HOME solos git fabricaba «zeref@…local». La captura lo evita.',
      );
    });

    test('sin ninguna identidad, git se niega en vez de inventar una', () async {
      await expectLater(
        autorDe(con(padre())),
        throwsA(isA<GitFallo>().having((e) => e.salida, 'salida', contains('identity'))),
      );
    });
  });
```

Nota sobre `%an <%ae>`: `git log` de la revisión creada. `createRevision` no mueve la rama, pero el objeto se promovió al almacén real, así que `git log -1 <sha>` lo lee.

- [ ] **Step 2: Corré para verlas fallar** — `dart test packages/vcs/test/candidato_test.dart -N "entorno saneado" -N identidad`. Esperado: no compila (`entornoDelPadre` no existe).

- [ ] **Step 3: Implementación en `repositorio.dart`.** Campo y constructor:

```dart
  /// El entorno del proceso padre. **`null` es `Platform.environment`**; las
  /// pruebas le pasan el que quieren, que es la única forma de probar qué
  /// llega y qué no sin depender del shell de quien corre la suite.
  final Map<String, String>? _entornoDelPadre;

  const RepositorioGit({
    required this.directorio,
    required this.politica,
    this.programa = 'git',
    this.programaChmod = 'chmod',
    this.detector = const DetectorDeSecretos(),
    Map<String, String>? entornoDelPadre,
  }) : _entornoDelPadre = entornoDelPadre;

  Map<String, String> get _padre => _entornoDelPadre ?? Platform.environment;
```

En `_git`, `_exigirBytes` y `_exigirConEntrada`, la llamada pasa a:

```dart
        environment: entornoSaneado(_padre, propias: entorno),
        includeParentEnvironment: false,
```

Y el comentario de `_git` que dice «[entorno] se **suma** al del proceso, no lo reemplaza» pasa a decir:

```dart
  /// [entorno] son las variables **propias de esta invocación** —`GIT_INDEX_FILE`,
  /// `GIT_OBJECT_DIRECTORY`, la identidad—. Se suman a la lista blanca de
  /// `entornoSaneado` y a nada más: el entorno del padre **no se hereda**. Se
  /// heredaba, y un `GIT_DIR` o un `GIT_INDEX_FILE` en el shell del usuario
  /// corrompía nuestras operaciones sin que nada lo notara.
```

La captura de identidad, como método de `RepositorioGit` (memoizado en un campo `Future<Map<String, String>>? _identidad;` — la clase deja de ser `const`-construible si el campo es mutable: usá un `static final Expando<Future<Map<String, String>>> _identidades = Expando();` para memoizar por instancia sin perder el constructor `const`):

```dart
  /// La identidad de `git`, **capturada con el entorno del padre**, antes de
  /// sanear (§8). Es LA excepción a `subprocesos-con-entorno-saneado`, y está
  /// declarada en `arquitectura.json`: `git config` tiene que ver
  /// `XDG_CONFIG_HOME` y `GIT_CONFIG_GLOBAL`, y enumerar por dónde `git` puede
  /// leer su configuración es la misma carrera que una lista negra.
  ///
  /// Devuelve vacío si no hay identidad: entonces `commit-tree` corre con
  /// `user.useConfigOnly=true` y se niega, en vez de fabricar un autor con el
  /// usuario del sistema y el hostname.
  Future<Map<String, String>> _identidadComoEntorno() =>
      _identidades[this] ??= _capturarIdentidad();

  static final Expando<Future<Map<String, String>>> _identidades = Expando();

  Future<Map<String, String>> _capturarIdentidad() async {
    Future<String> leer(String clave) async {
      final r = await Process.run(
        programa,
        ['config', '--get', clave],
        workingDirectory: directorio,
        environment: _padre, // la excepción declarada: ver arriba
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      return r.exitCode == 0 ? (r.stdout as String).trim() : '';
    }

    final nombre = await leer('user.name');
    final correo = await leer('user.email');
    if (nombre.isEmpty || correo.isEmpty) return const {};
    return {
      'GIT_AUTHOR_NAME': nombre,
      'GIT_AUTHOR_EMAIL': correo,
      'GIT_COMMITTER_NAME': nombre,
      'GIT_COMMITTER_EMAIL': correo,
    };
  }
```

Ojo: `git config --get` con la identidad **local** desconfigurada y `HOME` apuntando a un directorio vacío devuelve exit 1 y nada; por eso `''` y no un `GitFallo`.

- [ ] **Step 4: Implementación en `candidato.dart`.** El `chmod`:

```dart
        final r = await Process.run(
          _repo.programaChmod,
          ['755', destino.path],
          environment: entornoSaneado(_repo._padre),
          includeParentEnvironment: false,
        );
```

Y el `commit-tree` en `createRevision`:

```dart
    return _revision = await _repo._exigir([
      '-c',
      'user.useConfigOnly=true',
      'commit-tree',
      identity.contentRevision,
      '-p',
      identity.baseRevision,
      '-m',
      _slice.intent,
    ], entorno: await _repo._identidadComoEntorno());
```

`--literal-pathspecs` va antes de `-c` porque `_git` lo antepone; las dos son opciones globales y el orden entre ellas no importa.

- [ ] **Step 5: Corré `vcs` entero** — `dart test packages/vcs`. Esperado: todo verde, incluidas las suites viejas: la identidad local del `setUp` (`p@p`/`prueba`) sigue valiendo para ellas porque `git config --get` la lee del `.git/config` del repositorio.

Si `chmod` u otra prueba vieja falla por `PATH`: `entornoDelPadre` `null` usa `Platform.environment`, que tiene `PATH`. Si falla `hash-object` en `_promover`: es `_exigirConEntrada`, que ahora también sanea; revisá que le pases `entorno:` vacío y no `null`.

- [ ] **Step 6: Formato, análisis, commit**

```bash
dart analyze --fatal-infos packages/vcs && dart format --set-exit-if-changed packages/vcs
git add packages/vcs/lib/src/repositorio.dart packages/vcs/lib/src/candidato.dart packages/vcs/test/candidato_test.dart
git commit -m "vcs: git corre con el entorno saneado, y la identidad se captura antes

Lista blanca más las propias de cada invocación; el padre no se hereda, así
que un GIT_DIR del shell del usuario ya no llega. La identidad se lee UNA vez
con el entorno del padre —la única excepción, declarada— y viaja como
GIT_AUTHOR_*/GIT_COMMITTER_* al commit-tree, que además lleva
user.useConfigOnly: sin identidad, git se niega en vez de inventar un autor.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 5: El ejecutor de `plugin_dart` lanza con el entorno saneado

**Files:**
- Modify: `packages/plugin_dart/lib/src/ejecutor.dart` (`EjecutorDelSistema`)
- Test: `packages/plugin_dart/test/ejecutor_test.dart` (nuevo)

**Interfaces:**
- Consumes: `entornoSaneado`.
- Produces: `const EjecutorDelSistema({Map<String, String>? entornoDelPadre})`. La firma de `correr` **no cambia**: `PUB_CACHE` viaja por la lista blanca, y ningún paso necesita una variable propia.

- [ ] **Step 1: Escribí la prueba que falla** — `packages/plugin_dart/test/ejecutor_test.dart`:

```dart
/// Lo que el ejecutable recibe de verdad, medido con un script que lo imprime.
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
    imprimeEntorno = File('${raiz.path}/entorno.sh')..writeAsStringSync('#!/bin/sh\nenv\n');
    Process.runSync('chmod', ['755', imprimeEntorno.path]);
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  test('el ejecutable recibe PATH, HOME y PUB_CACHE, y no el token', () async {
    final ejecutor = EjecutorDelSistema(
      entornoDelPadre: {
        'PATH': '/usr/bin:/bin',
        'HOME': '/home/u',
        'PUB_CACHE': '/home/u/.pub-cache',
        'SHIPFLOW_GITHUB_TOKEN': 'secreto-de-prueba',
      },
    );
    final r = await ejecutor.correr(
      imprimeEntorno.path,
      const [],
      directorio: raiz.path,
      presupuesto: const Duration(seconds: 10),
    );
    expect(r.terminacion, Termination.completa);
    final lineas = r.salidaEstandar.trim().split('\n')..sort();
    expect(lineas, [
      'HOME=/home/u',
      'PATH=/usr/bin:/bin',
      'PUB_CACHE=/home/u/.pub-cache',
    ]);
  });

  test('sin PUB_CACHE en el padre, el hijo tampoco la tiene', () async {
    final r = await EjecutorDelSistema(entornoDelPadre: {'PATH': '/usr/bin:/bin'}).correr(
      imprimeEntorno.path,
      const [],
      directorio: raiz.path,
      presupuesto: const Duration(seconds: 10),
    );
    expect(r.salidaEstandar.trim(), 'PATH=/usr/bin:/bin');
  });

  test('sin entornoDelPadre se usa el del proceso, saneado', () async {
    final r = await const EjecutorDelSistema().correr(
      imprimeEntorno.path,
      const [],
      directorio: raiz.path,
      presupuesto: const Duration(seconds: 10),
    );
    final claves = r.salidaEstandar.trim().split('\n').map((l) => l.split('=').first).toSet();
    expect(claves.difference({'PATH', 'HOME', 'PUB_CACHE'}), isEmpty);
    expect(claves, contains('PATH'));
  });
}
```

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/plugin_dart/test/ejecutor_test.dart`. Esperado: no compila.

- [ ] **Step 3: Implementación.** En `EjecutorDelSistema`:

```dart
class EjecutorDelSistema implements EjecutorDeProceso {
  /// El entorno del padre. **`null` es `Platform.environment`**; las pruebas
  /// pasan el que quieren.
  final Map<String, String>? _entornoDelPadre;

  const EjecutorDelSistema({Map<String, String>? entornoDelPadre})
    : _entornoDelPadre = entornoDelPadre;

  Map<String, String> get _padre => _entornoDelPadre ?? Platform.environment;
```

y en `correr`:

```dart
      proceso = await Process.start(
        ejecutable,
        argumentos,
        workingDirectory: directorio,
        environment: entornoSaneado(_padre),
        includeParentEnvironment: false,
      );
```

Agregá al doc de la clase un párrafo: «**El hijo recibe la lista blanca y nada más** (§8). `PATH` decide qué binario corre; `HOME` y `PUB_CACHE`, dónde está el cache. Está medido que `dart analyze` corre con `PATH` solo: `package_config.json` lleva rutas absolutas al cache.»

- [ ] **Step 4: Corré `plugin_dart` entero** — `dart test packages/plugin_dart && dart analyze --fatal-infos packages/plugin_dart && dart format --set-exit-if-changed packages/plugin_dart`. Las pruebas reales (`pasos_reales_test.dart`) siguen verdes: `dart` está en `PATH`.

- [ ] **Step 5: Commit**

```bash
git add packages/plugin_dart/lib/src/ejecutor.dart packages/plugin_dart/test/ejecutor_test.dart
git commit -m "plugin_dart: la toolchain corre con la lista blanca y nada más

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Las raíces de resolución, como función pura

**Files:**
- Create: `packages/plugin_dart/lib/src/raices.dart`
- Modify: `packages/plugin_dart/lib/plugin_dart.dart` (`export 'src/raices.dart';`)
- Test: `packages/plugin_dart/test/raices_test.dart` (nuevo)

**Interfaces:**
- Produces: `List<String> raicesDeResolucion(String candidateRoot, List<String> archivos)` — rutas **relativas** a `candidateRoot`, `'.'` para la raíz, ordenadas y sin repetir. Sin correr `pub`, sin tocar nada. Un archivo sin ningún `pubspec.yaml` entre él y la raíz **no aporta raíz** (refinamiento 5). Un `pubspec.yaml` que no parsea se trata como raíz propia: la evidencia del defecto la va a dar `pub` cuando la tarea 7 intente derivarla.

**La regla** (§10): archivo → su `pubspec.yaml` más cercano hacia arriba → si declara `resolution: workspace`, la raíz es el ancestro más cercano cuyo `workspace:` lo lista; si no, el paquete mismo. Si declara `resolution: workspace` y ningún ancestro lo lista, el paquete mismo (y `pub` dirá por qué no).

- [ ] **Step 1: El fixture con la forma exacta de este repositorio y las pruebas** — `packages/plugin_dart/test/raices_test.dart`:

```dart
/// §10 sobre un fixture **con la forma exacta de este repositorio**: raíz de
/// workspace con miembros, `tool/analisis` no miembro con lockfile propio, y
/// `fixtures/app-minima/{dominio,app}` con `app` sobre `sdk: flutter`. Un
/// fixture de un solo manifiesto jamás habría encontrado el defecto que la
/// aprobación encontró: la v2 excluía a `shipflow` de verificarse a sí mismo.
library;

import 'dart:io';

import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

void main() {
  late Directory raiz;

  void escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  /// La forma de `shipflow`, con los mismos nombres.
  void comoShipflow() {
    escribir('pubspec.yaml',
        'name: shipflow\nenvironment:\n  sdk: ^3.11.0\nworkspace:\n  - packages/core\n  - packages/vcs\n');
    escribir('pubspec.lock', '# Generated by pub\npackages: {}\nsdks:\n  dart: ">=3.11.0 <4.0.0"\n');
    escribir('packages/core/pubspec.yaml', 'name: core\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\n');
    escribir('packages/core/lib/valores.dart', 'class A {}\n');
    escribir('packages/vcs/pubspec.yaml',
        'name: vcs\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\ndependencies:\n  core:\n    path: ../core\n');
    escribir('packages/vcs/lib/repo.dart', 'class R {}\n');
    escribir('tool/analisis/pubspec.yaml', 'name: analisis\nenvironment:\n  sdk: ^3.11.0\n');
    escribir('tool/analisis/pubspec.lock', '# Generated by pub\npackages: {}\nsdks:\n  dart: ">=3.11.0 <4.0.0"\n');
    escribir('tool/analisis/bin/check.dart', 'void main() {}\n');
    escribir('fixtures/app-minima/dominio/pubspec.yaml', 'name: dominio\nenvironment:\n  sdk: ^3.11.0\n');
    escribir('fixtures/app-minima/dominio/lib/dominio.dart', 'class D {}\n');
    escribir('fixtures/app-minima/app/pubspec.yaml',
        'name: app\nenvironment:\n  sdk: ^3.11.0\n  flutter: ">=3.18.0"\ndependencies:\n  flutter:\n    sdk: flutter\n  dominio:\n    path: ../dominio\n');
    escribir('fixtures/app-minima/app/lib/main.dart', 'void main() {}\n');
    escribir('README.md', '# x\n');
    escribir('.github/workflows/checks.yml', 'name: checks\n');
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('raices_');
    comoShipflow();
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  List<String> raices(List<String> archivos) => raicesDeResolucion(raiz.path, archivos);

  test('una rebanada que solo toca packages/ deriva UNA raíz: el workspace', () {
    expect(raices(['packages/core/lib/valores.dart']), ['.']);
    expect(raices(['packages/core/lib/valores.dart', 'packages/vcs/lib/repo.dart']), ['.']);
  });

  test('packages/ y tool/analisis derivan DOS raíces', () {
    expect(
      raices(['packages/core/lib/valores.dart', 'tool/analisis/bin/check.dart']),
      ['.', 'tool/analisis'],
    );
  });

  test('el fixture Flutter solo aparece cuando la rebanada lo toca', () {
    expect(raices(['fixtures/app-minima/app/lib/main.dart']), ['fixtures/app-minima/app']);
    expect(raices(['packages/core/lib/valores.dart']), isNot(contains('fixtures/app-minima/app')));
  });

  test('un archivo de la raíz que no es de ningún paquete cae en el workspace', () {
    expect(raices(['README.md', '.github/workflows/checks.yml']), ['.']);
  });

  test('un miembro que declara resolution: workspace pero nadie lista es raíz propia', () {
    escribir('packages/suelto/pubspec.yaml', 'name: suelto\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\n');
    escribir('packages/suelto/lib/s.dart', '');
    expect(raices(['packages/suelto/lib/s.dart']), ['packages/suelto']);
  });

  test('sin ningún manifiesto hacia arriba no hay raíz', () {
    final vacio = Directory.systemTemp.createTempSync('sin_manifiesto_');
    try {
      File('${vacio.path}/a.txt').writeAsStringSync('x');
      expect(raicesDeResolucion(vacio.path, ['a.txt']), isEmpty);
    } finally {
      vacio.deleteSync(recursive: true);
    }
  });

  test('un manifiesto que no parsea es raíz propia: pub dirá por qué', () {
    escribir('tool/roto/pubspec.yaml', 'name: [\n');
    escribir('tool/roto/bin/x.dart', '');
    expect(raices(['tool/roto/bin/x.dart']), ['tool/roto']);
  });

  test('un archivo fuera del candidato no se acepta', () {
    expect(() => raices(['../afuera.dart']), throwsArgumentError);
    expect(() => raices(['/etc/hosts']), throwsArgumentError);
  });
}
```

- [ ] **Step 2: Corré para verla fallar** — `dart test packages/plugin_dart/test/raices_test.dart`. Esperado: no compila.

- [ ] **Step 3: Implementación** — `packages/plugin_dart/lib/src/raices.dart`:

```dart
/// Qué raíces de resolución toca una rebanada (§10 de la propuesta de entorno).
///
/// **Función pura sobre rutas y manifiestos.** No corre `pub`: así la prueba
/// puede fijar la forma exacta de este repositorio sin depender de dónde vive
/// `dart` en la máquina que la corre — que es lo que hizo que «derivar todas
/// las raíces» funcionara acá y fuera a fallar en el runner.
library;

import 'dart:io';

import 'package:path/path.dart' as rutas;
import 'package:yaml/yaml.dart';

/// Las raíces, relativas a [candidateRoot] (`'.'` para la raíz), ordenadas y
/// sin repetir. Un archivo sin manifiesto hacia arriba **no aporta raíz**.
List<String> raicesDeResolucion(String candidateRoot, List<String> archivos) {
  final raiz = rutas.canonicalize(candidateRoot);
  final salida = <String>{};
  for (final archivo in archivos) {
    final absoluto = rutas.canonicalize(rutas.join(raiz, archivo));
    if (!rutas.isWithin(raiz, absoluto)) {
      throw ArgumentError.value(
        archivo,
        'archivos',
        'Está fuera del candidato. La rebanada solo puede tocar lo que el '
            'candidato contiene.',
      );
    }
    final paquete = _manifiestoMasCercano(rutas.dirname(absoluto), raiz);
    if (paquete == null) continue;
    salida.add(_relativa(_raizDe(paquete, raiz), raiz));
  }
  return salida.toList()..sort();
}

/// El directorio del `pubspec.yaml` más cercano, subiendo hasta [raiz]
/// inclusive; `null` si no hay ninguno.
String? _manifiestoMasCercano(String desde, String raiz) {
  var dir = desde;
  while (true) {
    if (File(rutas.join(dir, 'pubspec.yaml')).existsSync()) return dir;
    if (rutas.equals(dir, raiz)) return null;
    dir = rutas.dirname(dir);
  }
}

/// La raíz de resolución de un paquete: el workspace que lo lista si declara
/// `resolution: workspace`; él mismo si no, o si nadie lo lista, o si su
/// manifiesto no se puede leer — en esos dos últimos casos `pub` va a decir
/// por qué, con su propia evidencia, al intentar derivar.
String _raizDe(String paquete, String raiz) {
  if (!_declaraResolucionWorkspace(paquete)) return paquete;
  var dir = paquete;
  while (!rutas.equals(dir, raiz)) {
    dir = rutas.dirname(dir);
    final miembros = _miembrosDe(dir);
    if (miembros == null) continue;
    final relativo = rutas.relative(paquete, from: dir);
    if (miembros.any((m) => rutas.equals(rutas.join(dir, m), rutas.join(dir, relativo)))) {
      return dir;
    }
  }
  return paquete;
}

Map<Object?, Object?>? _leer(String dir) {
  try {
    final doc = loadYaml(File(rutas.join(dir, 'pubspec.yaml')).readAsStringSync());
    return doc is Map ? doc : null;
  } on Object {
    return null; // ilegible: raíz propia, y pub dará la evidencia
  }
}

bool _declaraResolucionWorkspace(String paquete) =>
    _leer(paquete)?['resolution'] == 'workspace';

/// La lista `workspace:` de un manifiesto, o `null` si no la tiene.
List<String>? _miembrosDe(String dir) {
  final ws = _leer(dir)?['workspace'];
  if (ws is! List) return null;
  return [for (final m in ws) if (m is String) m];
}

String _relativa(String absoluto, String raiz) {
  final r = rutas.relative(absoluto, from: raiz);
  return r == '.' ? '.' : r.replaceAll(r'\', '/');
}
```

Y en el barril `plugin_dart.dart`: `export 'src/raices.dart';`.

- [ ] **Step 4: Corré** — `dart test packages/plugin_dart/test/raices_test.dart`. Esperado: 8 en verde. Después el paquete entero, análisis y formato.

- [ ] **Step 5: Regenerá el grafo** (import nuevo de `path` y `yaml` desde un archivo nuevo): `cd tool/analisis && dart pub get && dart run bin/grafo.dart --escribir && dart run bin/grafo.dart && cd ../..`.

- [ ] **Step 6: Commit**

```bash
git add packages/plugin_dart/lib/src/raices.dart packages/plugin_dart/lib/plugin_dart.dart packages/plugin_dart/test/raices_test.dart grafo.jsonl
git commit -m "plugin_dart: las raíces de resolución que la rebanada toca, sin correr pub

Fixture con la forma exacta de shipflow: packages/ solo da una raíz; con
tool/analisis, dos; el fixture Flutter solo cuando se lo toca. La v2 excluía
a este repositorio de verificarse a sí mismo, y un fixture de un manifiesto
no lo habría visto.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

(Si `grafo.jsonl` tiene proyecciones que también cambian —mirá `git status`—, agregalas al `add`.)

---
### Task 7: `EntornoDart`, la implementación del puerto

**Files:**
- Create: `packages/plugin_dart/lib/src/entorno.dart`
- Modify: `packages/plugin_dart/lib/plugin_dart.dart` (`export 'src/entorno.dart';`)
- Modify: `arquitectura.json` (quitar `VerificationEnvironment` de `sin_implementacion`; agregar al `_` de esa lista la frase de con qué salió) + `tool/checks/arquitectura.huella`
- Test: `packages/plugin_dart/test/entorno_test.dart` (nuevo)

**Interfaces:**
- Consumes: `raicesDeResolucion` (tarea 6); `EjecutorDeProceso`/`EjecutorDelSistema`/`EjecutorDeclarado`; los tipos de la tarea 2.
- Produces: `class EntornoDart implements VerificationEnvironment { const EntornoDart({EjecutorDeProceso ejecutor = const EjecutorDelSistema()}); }`.

**Orden de `derivar`, y por qué:**
1. `raicesDeResolucion`. Cero raíces → `EntornoDerivado(paquetes: 0, raices: 0)` **después** de atestiguar la toolchain igual (el testigo dice con qué se midió aunque no haya nada que derivar).
2. Para cada raíz, `.dart_tool/` presente en el árbol fijado → `CandidatoRechazado(elArbolVersionaLoQueSeGenera)` **antes de correr nada**.
3. `dart --version` → `IdentidadDeToolchain`. Terminación no completa → `DerivacionAbortada`.
4. Por raíz, `dart pub get --offline --enforce-lockfile` en el directorio de la raíz. Terminación no completa → `DerivacionAbortada`; código ≠ 0 → `CandidatoRechazado(pubRechazoLaResolucion)` con stdout+stderr citados (refinamiento 1).
5. Por raíz, el `pubspec.lock`: toda entrada `source: path` cuya ruta canonicalizada quede fuera del candidato → `CandidatoRechazado(dependenciaPathQueEscapa)` (refinamiento 2).
6. Por raíz, contar `packages` de `.dart_tool/package_config.json`. Suma → `paquetes`.

El `presupuesto` es **por subproceso**, no por derivación entera: es lo que `EjecutorDeProceso` sabe hacer, y va dicho en el doc del método.

- [ ] **Step 1: Escribí las pruebas que fallan** — `packages/plugin_dart/test/entorno_test.dart`. Precondición declarada: `dart` en `PATH` y `meta` en el cache local (lo está en cualquier máquina que haya corrido `dart pub get` en este repositorio: `test` lo trae).

```dart
/// `EntornoDart` contra `pub` de verdad, sobre fixtures que resuelven sin red.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';

const presupuesto = Duration(minutes: 2);

void main() {
  late Directory raiz;

  void escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  /// Resuelve UNA vez con el cache real para dejar el lockfile —lo que un
  /// candidato trae— y borra lo generado —lo que un candidato NO trae—.
  void fijarLockfile(String dir) {
    final r = Process.runSync('dart', ['pub', 'get', '--offline'], workingDirectory: rutas.join(raiz.path, dir));
    if (r.exitCode != 0) throw StateError('no pude fijar el lockfile de $dir: ${r.stderr}');
    Directory(rutas.join(raiz.path, dir, '.dart_tool')).deleteSync(recursive: true);
  }

  /// Un paquete sin dependencias externas: resuelve con el cache vacío (A-9).
  void paqueteSolo(String dir, {String extra = ''}) {
    escribir('$dir/pubspec.yaml', 'name: ${rutas.basename(dir)}\nenvironment:\n  sdk: ^3.11.0\n$extra');
    escribir('$dir/lib/a.dart', 'void a() {}\n');
  }

  Future<ResultadoDeEntorno> derivar(List<String> archivos, {EjecutorDeProceso? ejecutor}) =>
      EntornoDart(ejecutor: ejecutor ?? const EjecutorDelSistema())
          .derivar(raiz.path, archivos: archivos, presupuesto: presupuesto);

  setUp(() => raiz = Directory.systemTemp.createTempSync('entorno_'));
  tearDown(() => raiz.deleteSync(recursive: true));

  group('deriva', () {
    test('un paquete con lockfile → derivado, y el lockfile queda byte a byte igual', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      final antes = File('${raiz.path}/pubspec.lock').readAsBytesSync();
      final r = await derivar(['lib/a.dart']);
      expect(r, isA<EntornoDerivado>());
      final d = r as EntornoDerivado;
      expect(d.raices, 1);
      expect(d.paquetes, greaterThanOrEqualTo(1));
      expect(d.toolchain.version.content, contains('version'));
      expect(File('${raiz.path}/.dart_tool/package_config.json').existsSync(), isTrue);
      expect(File('${raiz.path}/pubspec.lock').readAsBytesSync(), antes);
    });

    test('con el cache VACÍO, un paquete sin dependencias igual deriva', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      final cache = Directory.systemTemp.createTempSync('cache_vacio_');
      try {
        final r = await derivar(['lib/a.dart'], ejecutor: EjecutorDelSistema(entornoDelPadre: {
          'PATH': Platform.environment['PATH']!,
          'HOME': Platform.environment['HOME']!,
          'PUB_CACHE': cache.path,
        }));
        expect(r, isA<EntornoDerivado>());
      } finally {
        cache.deleteSync(recursive: true);
      }
    });

    test('una restricción nueva que el lockfile ya satisface → derivado', () async {
      paqueteSolo('.', extra: 'dependencies:\n  meta: ^1.0.0\n');
      fijarLockfile('.');
      escribir('pubspec.yaml', 'name: raiz\nenvironment:\n  sdk: ^3.11.0\ndependencies:\n  meta: ">=1.0.0"\n');
      expect(await derivar(['lib/a.dart']), isA<EntornoDerivado>());
    });

    test('la forma de shipflow: un miembro → una raíz; miembro + tool → dos; el fixture no se toca', () async {
      escribir('pubspec.yaml', 'name: ws\nenvironment:\n  sdk: ^3.11.0\nworkspace:\n  - packages/a\n  - packages/b\n');
      paqueteSolo('packages/a', extra: 'resolution: workspace\n');
      paqueteSolo('packages/b', extra: 'resolution: workspace\ndependencies:\n  a:\n    path: ../a\n');
      paqueteSolo('tool/analisis');
      paqueteSolo('fixtures/app');
      escribir('fixtures/app/pubspec.yaml', 'name: app\nenvironment:\n  sdk: ^3.11.0\n  flutter: ">=3.18.0"\ndependencies:\n  flutter:\n    sdk: flutter\n');
      fijarLockfile('.');
      fijarLockfile('tool/analisis');

      final una = await derivar(['packages/a/lib/a.dart']) as EntornoDerivado;
      expect(una.raices, 1);
      expect(Directory('${raiz.path}/tool/analisis/.dart_tool').existsSync(), isFalse);
      expect(Directory('${raiz.path}/fixtures/app/.dart_tool').existsSync(), isFalse,
          reason: 'un manifiesto que la rebanada no toca no se deriva ni se rechaza');

      final dos = await derivar(['packages/a/lib/a.dart', 'tool/analisis/lib/a.dart']) as EntornoDerivado;
      expect(dos.raices, 2);
      expect(Directory('${raiz.path}/tool/analisis/.dart_tool').existsSync(), isTrue);
    });

    test('sin ningún manifiesto: cero raíces, derivado igual', () async {
      escribir('a.txt', 'x');
      final r = await derivar(['a.txt']) as EntornoDerivado;
      expect(r.raices, 0);
      expect(r.paquetes, 0);
    });
  });

  group('rechaza al candidato', () {
    test('un lockfile que no satisface el manifiesto, y el lockfile no se toca', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      final antes = File('${raiz.path}/pubspec.lock').readAsBytesSync();
      escribir('pubspec.yaml', 'name: raiz\nenvironment:\n  sdk: ^3.11.0\ndependencies:\n  meta: ^1.0.0\n');
      final r = await derivar(['lib/a.dart']);
      expect(r, isA<CandidatoRechazado>());
      expect((r as CandidatoRechazado).causa, CausaDeRechazo.pubRechazoLaResolucion);
      expect(r.evidencia.content, contains('pubspec.lock'));
      expect(File('${raiz.path}/pubspec.lock').readAsBytesSync(), antes);
    });

    test('Q-4: una raíz tocada sin lockfile', () async {
      paqueteSolo('.');
      final r = await derivar(['lib/a.dart']) as CandidatoRechazado;
      expect(r.causa, CausaDeRechazo.pubRechazoLaResolucion);
      expect(r.evidencia.content, contains('pubspec.lock'));
    });

    test('cache vacío con una dependencia hospedada: pub dijo que no, y se cita', () async {
      // Refinamiento 1: pub sale con 69 tanto acá como con un SDK desconocido,
      // así que no se adivina la causa. Es un rechazo con la evidencia literal.
      paqueteSolo('.', extra: 'dependencies:\n  meta: ^1.0.0\n');
      fijarLockfile('.');
      final cache = Directory.systemTemp.createTempSync('cache_vacio_');
      try {
        final r = await derivar(['lib/a.dart'], ejecutor: EjecutorDelSistema(entornoDelPadre: {
          'PATH': Platform.environment['PATH']!,
          'HOME': Platform.environment['HOME']!,
          'PUB_CACHE': cache.path,
        })) as CandidatoRechazado;
        expect(r.causa, CausaDeRechazo.pubRechazoLaResolucion);
        expect(r.evidencia.content, contains('offline'));
      } finally {
        cache.deleteSync(recursive: true);
      }
    });

    test('.dart_tool versionado → rechazado ANTES de correr nada', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      escribir('.dart_tool/package_config.json', '{}');
      final ejecutor = EjecutorDeclarado(const ResultadoDeProceso(
        terminacion: Termination.completa, codigo: 0, salidaEstandar: '', salidaDeError: ''));
      final r = await derivar(['lib/a.dart'], ejecutor: ejecutor) as CandidatoRechazado;
      expect(r.causa, CausaDeRechazo.elArbolVersionaLoQueSeGenera);
      expect(ejecutor.invocaciones, isEmpty);
    });

    test('una dependencia path que escapa del candidato', () async {
      final fuera = Directory.systemTemp.createTempSync('fuera_');
      try {
        File('${fuera.path}/pubspec.yaml').writeAsStringSync('name: fuera\nenvironment:\n  sdk: ^3.11.0\n');
        paqueteSolo('.', extra: 'dependencies:\n  fuera:\n    path: ${fuera.path}\n');
        fijarLockfile('.');
        final r = await derivar(['lib/a.dart']) as CandidatoRechazado;
        expect(r.causa, CausaDeRechazo.dependenciaPathQueEscapa);
        expect(r.evidencia.content, contains('fuera'));
      } finally {
        fuera.deleteSync(recursive: true);
      }
    });

    test('una dependencia path que queda adentro no escapa', () async {
      paqueteSolo('adentro');
      paqueteSolo('.', extra: 'dependencies:\n  adentro:\n    path: adentro\n');
      fijarLockfile('.');
      expect(await derivar(['lib/a.dart']), isA<EntornoDerivado>());
    });
  });

  group('aborta la derivación', () {
    ResultadoDeProceso incompleto(Termination t) => ResultadoDeProceso(
        terminacion: t, codigo: -1, salidaEstandar: '', salidaDeError: 'no se pudo');

    test('toolchain ausente → herramientaAusente, nunca un verde', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      final r = await derivar(['lib/a.dart'],
          ejecutor: EjecutorDeclarado(incompleto(Termination.herramientaAusente))) as DerivacionAbortada;
      expect(r.terminacion, Termination.herramientaAusente);
      expect(r.evidencia.content, contains('no se pudo'));
    });

    test('presupuesto agotado → tiempoAgotado', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      final r = await derivar(['lib/a.dart'],
          ejecutor: EjecutorDeclarado(incompleto(Termination.tiempoAgotado))) as DerivacionAbortada;
      expect(r.terminacion, Termination.tiempoAgotado);
    });

    test('con el ejecutable ausente de verdad, el ejecutor real dice herramientaAusente', () async {
      paqueteSolo('.');
      fijarLockfile('.');
      final r = await EntornoDart(ejecutor: const EjecutorDelSistema(), programa: '/no/existe/dart')
          .derivar(raiz.path, archivos: ['lib/a.dart'], presupuesto: presupuesto) as DerivacionAbortada;
      expect(r.terminacion, Termination.herramientaAusente);
    });
  });
}
```

`EntornoDart` gana entonces un segundo parámetro, `programa` (default `'dart'`), como `RepositorioGit.programa`: es lo que permite probar la ausencia sin desinstalar nada. Actualizá la firma en **Interfaces** de arriba: `const EntornoDart({EjecutorDeProceso ejecutor = const EjecutorDelSistema(), String programa = 'dart'})`.

- [ ] **Step 2: Corré para verlas fallar** — `dart test packages/plugin_dart/test/entorno_test.dart`. Esperado: no compila.

- [ ] **Step 3: Implementación** — `packages/plugin_dart/lib/src/entorno.dart`:

```dart
/// La primera implementación de `VerificationEnvironment` (propuesta de
/// entorno, §4–§7 y §10): el entorno se **deriva** del candidato, nunca se
/// presta del árbol del usuario.
library;

import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;
import 'package:yaml/yaml.dart';

import 'ejecutor.dart';
import 'raices.dart';

class EntornoDart implements VerificationEnvironment {
  final EjecutorDeProceso ejecutor;

  /// Con qué se invoca la toolchain. Inyectable para poder probar su
  /// ausencia sin desinstalar nada, igual que `RepositorioGit.programa`.
  final String programa;

  const EntornoDart({
    this.ejecutor = const EjecutorDelSistema(),
    this.programa = 'dart',
  });

  static const _resolver = ['pub', 'get', '--offline', '--enforce-lockfile'];

  /// [presupuesto] es **por subproceso**: la atestación y cada `pub get`
  /// reciben el mismo, porque es lo que el ejecutor sabe cortar.
  @override
  Future<ResultadoDeEntorno> derivar(
    String candidateRoot, {
    required List<String> archivos,
    required Duration presupuesto,
  }) async {
    final raiz = rutas.canonicalize(candidateRoot);
    final raices = raicesDeResolucion(raiz, archivos);

    // §6: el árbol versiona lo que la derivación genera. Se detecta ANTES de
    // correr nada: derivar lo destruiría.
    for (final r in raices) {
      final generado = Directory(rutas.join(raiz, r, '.dart_tool'));
      if (generado.existsSync()) {
        return CandidatoRechazado(
          causa: CausaDeRechazo.elArbolVersionaLoQueSeGenera,
          evidencia: QuotedText(
            '${_relativa(generado.path, raiz)} está en el árbol fijado.',
            source: 'candidato',
          ),
        );
      }
    }

    // §7: la toolchain se atestigua, no se parsea.
    final version = await ejecutor.correr(programa, const ['--version'],
        directorio: raiz, presupuesto: presupuesto);
    if (version.terminacion != Termination.completa) {
      return _abortada(version, '$programa --version');
    }
    final toolchain = IdentidadDeToolchain(
      version: QuotedText(
        _texto(version),
        source: '$programa --version',
      ),
    );

    var paquetes = 0;
    for (final r in raices) {
      final dir = rutas.join(raiz, r);
      final invocacion = '$programa ${_resolver.join(' ')} en $r';
      final pub = await ejecutor.correr(programa, _resolver,
          directorio: dir, presupuesto: presupuesto);
      if (pub.terminacion != Termination.completa) return _abortada(pub, invocacion);
      if (pub.codigo != 0) {
        // Refinamiento 1: pub dijo que no, y no inventamos por qué.
        return CandidatoRechazado(
          causa: CausaDeRechazo.pubRechazoLaResolucion,
          evidencia: QuotedText(_texto(pub), source: invocacion),
        );
      }
      final escapa = _dependenciaPathQueEscapa(dir, raiz);
      if (escapa != null) {
        return CandidatoRechazado(
          causa: CausaDeRechazo.dependenciaPathQueEscapa,
          evidencia: QuotedText(escapa, source: '$r/pubspec.lock'),
        );
      }
      paquetes += _paquetesDe(dir);
    }

    return EntornoDerivado(paquetes: paquetes, raices: raices.length, toolchain: toolchain);
  }

  DerivacionAbortada _abortada(ResultadoDeProceso r, String invocacion) =>
      DerivacionAbortada(
        terminacion: r.terminacion,
        evidencia: QuotedText(_texto(r), source: invocacion),
      );

  /// stdout y stderr, los dos: `dart --version` escribe en los dos según la
  /// versión, y `pub` explica en stderr. Nunca en blanco: los tipos lo
  /// rechazan, y un proceso mudo también es un hecho que hay que citar.
  static String _texto(ResultadoDeProceso r) {
    final t = '${r.salidaEstandar}${r.salidaDeError}'.trim();
    return t.isEmpty ? '(sin salida; código ${r.codigo})' : t;
  }

  /// Refinamiento 2: se lee del lockfile que `pub` acaba de validar, porque
  /// `package_config.json` no distingue una dependencia `path` de una
  /// hospedada ni de una del SDK.
  static String? _dependenciaPathQueEscapa(String dir, String raiz) {
    final lock = File(rutas.join(dir, 'pubspec.lock'));
    final doc = loadYaml(lock.readAsStringSync());
    final paquetes = doc is Map ? doc['packages'] : null;
    if (paquetes is! Map) return null;
    for (final e in paquetes.entries) {
      final p = e.value;
      if (p is! Map || p['source'] != 'path') continue;
      final desc = p['description'];
      if (desc is! Map || desc['path'] is! String) continue;
      final ruta = desc['path'] as String;
      final absoluta = rutas.canonicalize(
        rutas.isAbsolute(ruta) ? ruta : rutas.join(dir, ruta),
      );
      if (!rutas.isWithin(raiz, absoluta) && !rutas.equals(raiz, absoluta)) {
        return '${e.key}: $ruta resuelve fuera del candidato.';
      }
    }
    return null;
  }

  static int _paquetesDe(String dir) {
    final f = File(rutas.join(dir, '.dart_tool', 'package_config.json'));
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    return (json['packages'] as List).length;
  }

  static String _relativa(String absoluto, String raiz) =>
      rutas.relative(absoluto, from: raiz).replaceAll(r'\', '/');
}
```

En el barril: `export 'src/entorno.dart';`.

- [ ] **Step 4: Sacá el puerto de la lista de huecos.** Con Python, como en la tarea 2: borrá la clave `VerificationEnvironment` de `sin_implementacion`, y **agregá al final del texto `_` de esa lista** esta frase: «VerificationEnvironment salió en la rebanada del entorno con UNA implementacion real en plugin_dart y NINGUNA falsa, y eso va escrito: no hay etapa que lo consuma —la composicion vive en una prueba de cli—, asi que una suite de contrato con una sola implementacion correria la misma logica dos veces. El fake llega con la etapa que lo consuma.» Después `python3 tool/checks/capas.py --huella`.

- [ ] **Step 5: Corré todo** — `dart test packages/plugin_dart && dart analyze --fatal-infos packages/plugin_dart && dart format --set-exit-if-changed packages/plugin_dart && (cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart --escribir && dart run bin/grafo.dart) && python3 tool/checks/capas.py`. Esperado: `check.dart` vuelve a decir `19 puertos sin implementación declarados`.

- [ ] **Step 6: El sabotaje del estado intermedio n.º 1** (§14): sacá `'--enforce-lockfile'` de `_resolver`, corré `entorno_test.dart`, comprobá que «un lockfile que no satisface» **se pone roja** (pub lo reescribiría y derivaría). Restaurá a mano y verificá verde.

- [ ] **Step 7: Commit**

```bash
git add packages/plugin_dart/lib/src/entorno.dart packages/plugin_dart/lib/plugin_dart.dart packages/plugin_dart/test/entorno_test.dart arquitectura.json tool/checks/arquitectura.huella grafo.jsonl
git commit -m "plugin_dart: el entorno se deriva del candidato, una vez por raíz que la rebanada toca

pub get --offline --enforce-lockfile: el lockfile del candidato manda y no
se reescribe. Todo «no» de pub es un rechazo con su salida citada —69 no
distingue un cache frío de un SDK desconocido—; abortar queda para lo que
el instrumento no llegó a decir. La toolchain se cita, no se parsea.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 8: La regla `subprocesos-con-entorno-saneado`

**Files:**
- Modify: `tool/analisis/bin/check.dart` (mapa `esperadas`; sección nueva `4 · subprocesos`; visitor `_Subprocesos`)
- Modify: `arquitectura.json` (la regla entera) + `tool/checks/arquitectura.huella`
- Modify: `tool/checks/probar_reglas.py` (`EXTRAS_OBLIGATORIAS`)
- Modify: `tool/checks/capas.py` (`CIEGO_FIJO`)
- Modify: `README.md` (una fila en la tabla de reglas, línea ~87; el resto del README va en la tarea 10)

**Interfaces:**
- Consumes: los cinco sitios ya saneados (tareas 4, 5) y la excepción `_capturarIdentidad` (tarea 4).
- Produces: la regla, con `tipo: "entorno_saneado"`, `aplicada_por: "tool/analisis"`, canónica, **cuatro** `violaciones_extra`, `caso_ciego: archivo_ilegible`, y `excepciones: [{archivo, metodo, por_que}]`.

**Qué comprueba** (§9: semántica, no forma): en todo `.dart` bajo `packages/*/lib` y `packages/*/bin`, cada `Process.run`, `Process.runSync` y `Process.start` tiene `environment:` **cuya expresión es una llamada a `entornoSaneado`**, e `includeParentEnvironment: false` **literal**. `environment: Platform.environment` cumple la forma de la v1 y no sanea nada; acá es rojo. Un sitio que no cumpla solo se admite si su archivo está en `excepciones` y el sitio está **dentro del método declarado**; en ese archivo se admite **exactamente uno**: si hay dos, o si el declarado ya no existe, rojo. Los `test/` quedan fuera: las pruebas lanzan `git` y `chmod` a mano y eso es correcto.

- [ ] **Step 1: La regla en `arquitectura.json`** — con Python, agregá esta entrada a `reglas` y regenerá la huella. El contenido de los canarios va como cadena con `\n`; acá se muestra desplegado por legibilidad:

```json
"subprocesos-con-entorno-saneado": {
  "enunciado": "Todo subproceso que este repositorio lanza recibe `environment: entornoSaneado(...)` e `includeParentEnvironment: false`. El entorno del padre no se hereda.",
  "origen": "Propuesta de entorno de verificacion §8 y §9, aprobada el 12/09/2026. Medido: con el entorno heredado, el token de la forja llega a todo hijo (A-8), y un GIT_DIR del shell del usuario corrompe las operaciones de vcs.",
  "tipo": "entorno_saneado",
  "aplicada_por": "tool/analisis",
  "alternativa": "Pasale `environment: entornoSaneado(padre, propias: {...})` e `includeParentEnvironment: false`. Lo que esa invocacion necesite de mas va en `propias`, nunca heredado.",
  "por_que": [
    "Una lista negra promete solo sobre lo que alguien enumero: cualquier variable",
    "secreta futura se filtra sola. La lista blanca promete lo contrario, y esta",
    "regla exige que sea la UNICA forma de armar un entorno.",
    "",
    "Comprueba SEMANTICA, no forma: `environment: Platform.environment` con",
    "`includeParentEnvironment: false` cumple al pie lo que la v1 pedia y no sanea",
    "nada. Aca lo que se exige es la llamada a `entornoSaneado`, sobre el arbol",
    "sintactico, en los tres lanzadores: run, runSync y start."
  ],
  "alcance": {
    "raiz": "packages",
    "que_mira": "Archivos .dart bajo lib/ y bin/ de cada paquete. Los test/ no: las pruebas lanzan git y chmod a mano, y esa es su forma de medir.",
    "residuo_declarado": "Mira `Process.run|runSync|start` por nombre simple. Un alias (`final p = Process; p.run(...)`) o una funcion que envuelva `Process.start` y reciba el entorno de afuera no se ven. Lo segundo es exactamente lo que hacen las costuras de vcs y plugin_dart, y por eso la regla se aplica ADENTRO de ellas, donde esta el `Process.` literal."
  },
  "excepciones": [
    {
      "archivo": "packages/vcs/lib/src/repositorio.dart",
      "metodo": "_capturarIdentidad",
      "por_que": "La identidad de git se captura UNA vez con el entorno del padre, antes de sanear (§8). `git config --get` tiene que ver XDG_CONFIG_HOME y GIT_CONFIG_GLOBAL, y enumerar por donde git puede leer su configuracion es la misma carrera que una lista negra. Es un `git config` de solo lectura: no ejecuta ganchos ni filtros. El check admite exactamente UN sitio sin sanear en este archivo, dentro de este metodo."
    }
  ],
  "violacion_canonica": {
    "donde": "packages/vcs/lib/src/_canario_proceso.dart",
    "contenido": "import 'dart:io';\n\nFuture<void> canario() async {\n  await Process.run(\n    'x',\n    const [],\n    environment: Platform.environment,\n    includeParentEnvironment: false,\n  );\n}\n",
    "debe_mencionar": "entornoSaneado"
  },
  "violaciones_extra": [
    {
      "nombre": "sin environment, hereda todo",
      "archivos": {"packages/vcs/lib/src/_canario_proceso.dart": "import 'dart:io';\n\nFuture<void> canario() async {\n  await Process.run('x', const []);\n}\n"},
      "debe_mencionar": "entornoSaneado"
    },
    {
      "nombre": "entornoSaneado sin includeParentEnvironment: false",
      "archivos": {"packages/vcs/lib/src/_canario_proceso.dart": "import 'dart:io';\n\nimport 'package:core/core.dart';\n\nFuture<void> canario() async {\n  await Process.run('x', const [], environment: entornoSaneado(Platform.environment));\n}\n"},
      "debe_mencionar": "includeParentEnvironment"
    },
    {
      "nombre": "start y runSync tambien cuentan",
      "archivos": {"packages/vcs/lib/src/_canario_proceso.dart": "import 'dart:io';\n\nvoid canario() {\n  Process.runSync('x', const [], environment: Platform.environment, includeParentEnvironment: false);\n  Process.start('x', const [], environment: Platform.environment, includeParentEnvironment: false);\n}\n"},
      "debe_mencionar": "entornoSaneado"
    },
    {
      "nombre": "una segunda excepcion en el archivo exceptuado",
      "por_que": "La excepcion admite UN sitio. Si el archivo gana otro `Process.run` sin sanear, la declaracion lo taparia; el check cuenta.",
      "archivos": {"packages/vcs/lib/src/_canario_proceso.dart": "part of 'repositorio.dart';\n\nFuture<void> canarioDeExcepcion(RepositorioGit r) async {\n  await Process.run('git', const ['config', '--get', 'user.name'], environment: r._padre, includeParentEnvironment: false);\n}\n"},
      "debe_mencionar": "excepcion"
    }
  ],
  "caso_ciego": {
    "_": "Simetrico de la violacion canonica: aquella prueba que el check detecta un EXCESO; este, que detecta una OMISION.",
    "que": "Un archivo de packages/ que no parsea.",
    "como": "archivo_ilegible",
    "por_que_ciega": "Los lanzamientos se buscan en el arbol sintactico. De un arbol parcial no sale ninguno, y un archivo que no se pudo leer no tiene subprocesos que revisar — que se lee igual que no tenerlos.",
    "debe_mencionar": "no parsea"
  }
}
```

Sobre la cuarta extra: el canario es un `part of 'repositorio.dart'`, así que **no** está en el archivo exceptuado; para que el check lo vea como «segunda excepción» hay que contar por **biblioteca**, no por archivo: un `part` pertenece a la biblioteca de su `part of`. Eso hace la regla más fuerte y es lo que el visitor implementa abajo: la clave de la excepción es el archivo de la biblioteca, y los `part` se atribuyen a ella. Si al ejecutar resulta demasiado costoso resolver `part of`, reemplazá esa extra por: mismo canario como archivo suelto con **dos** `Process.run` sin sanear y `excepciones` apuntando a él vía `arq_con` (mirá cómo `declarar_sin_implementacion` muta el JSON en `probar_reglas.py`) — pero primero intentá la versión por biblioteca.

- [ ] **Step 2: Registrala en los tres arneses.** En `check.dart`, mapa `esperadas`: `'subprocesos-con-entorno-saneado': 'entorno_saneado',`. En `capas.py`, `CIEGO_FIJO`: `"subprocesos-con-entorno-saneado": "archivo_ilegible",`. En `probar_reglas.py`, `EXTRAS_OBLIGATORIAS`:

```python
    "subprocesos-con-entorno-saneado": {
        "sin environment, hereda todo",
        "entornoSaneado sin includeParentEnvironment: false",
        "start y runSync tambien cuentan",
        "una segunda excepcion en el archivo exceptuado",
    },
```

En `README.md`, tabla de reglas, después de la fila de `dependencias-declaradas-se-usan`:

```
| `subprocesos-con-entorno-saneado` | Que un subproceso herede el entorno del padre —el token, un `GIT_DIR` ajeno— en vez de recibir la lista blanca | `tool/analisis` |
```

- [ ] **Step 3: Corré la canónica a mano para ver el check en verde-falso** — creá `packages/vcs/lib/src/_canario_proceso.dart` con el contenido de la canónica, corré `cd tool/analisis && dart run bin/check.dart`. Esperado hoy: **verde** (la regla no existe todavía). Es la línea de base. Borrá el canario.

- [ ] **Step 4: El visitor en `check.dart`.** Después de `_Retornos`, antes de `main`:

```dart
/// Un lanzamiento de proceso, y si cumple la regla.
class _Lanzamiento {
  final String archivo; // relativo a la raíz
  final String biblioteca; // el archivo, o el de su `part of`
  final int offset;
  final String metodo; // el método o función que lo contiene, o ''
  final String? problema; // null si cumple
  const _Lanzamiento(this.archivo, this.biblioteca, this.offset, this.metodo, this.problema);
}

/// Recorre un archivo buscando `Process.run|runSync|start`.
class _Subprocesos extends RecursiveAstVisitor<void> {
  final String archivo;
  final String biblioteca;
  final List<_Lanzamiento> vistos = [];
  final List<String> _pila = [];

  _Subprocesos(this.archivo, this.biblioteca);

  static const _lanzadores = {'run', 'runSync', 'start'};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _pila.add(node.name.lexeme);
    super.visitMethodDeclaration(node);
    _pila.removeLast();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _pila.add(node.name.lexeme);
    super.visitFunctionDeclaration(node);
    _pila.removeLast();
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target?.toSource() != 'Process' ||
        !_lanzadores.contains(node.methodName.name)) {
      return;
    }
    final nombrados = {
      for (final a in node.argumentList.arguments)
        if (a is NamedExpression) a.name.label.name: a.expression,
    };
    final entorno = nombrados['environment'];
    final hereda = nombrados['includeParentEnvironment'];
    String? problema;
    if (entorno is! MethodInvocation ||
        entorno.methodName.name != 'entornoSaneado') {
      problema =
          '`environment:` no es una llamada a `entornoSaneado`'
          '${entorno == null ? " (no está: hereda todo)" : ""}. '
          'Pasar `Platform.environment` cumple la forma y no sanea nada.';
    } else if (hereda is! BooleanLiteral || hereda.value) {
      problema =
          'falta `includeParentEnvironment: false` literal: sin él, el '
          'entorno saneado se SUMA al del padre.';
    }
    vistos.add(_Lanzamiento(
      archivo,
      biblioteca,
      node.offset,
      _pila.isEmpty ? '' : _pila.last,
      problema,
    ));
  }
}

/// A qué biblioteca pertenece un archivo: él mismo, o el de su `part of`.
String _bibliotecaDe(CompilationUnit unidad, String rel) {
  for (final d in unidad.directives) {
    if (d is PartOfDirective && d.uri != null) {
      final uri = d.uri!.stringValue ?? '';
      final dir = rel.substring(0, rel.lastIndexOf('/'));
      return '$dir/$uri';
    }
  }
  return rel;
}
```

Y la sección, en `main`, antes de `// --- salida`:

```dart
  // --- 4 · subprocesos con entorno saneado -------------------------------
  //
  // §9 de la propuesta de entorno: se comprueba SEMÁNTICA, no forma. Lo que se
  // exige es la llamada a `entornoSaneado`, no que el parámetro exista.
  final reglaEntorno =
      reglas['subprocesos-con-entorno-saneado'] as Map<String, Object?>?;
  final excepciones = <String, String>{
    // biblioteca → método admitido
    for (final e in (reglaEntorno?['excepciones'] as List<Object?>? ?? const []))
      (e as Map<String, Object?>)['archivo']! as String: e['metodo']! as String,
  };
  final lanzamientos = <_Lanzamiento>[];
  for (final f in fuentes(dirPaquetes)) {
    final rel = f.path.substring(raiz.path.length + 1);
    // Producción es un conjunto cerrado: lib/ y bin/. Los test/ lanzan git y
    // chmod a mano, y esa es su forma de medir.
    if (!RegExp(r'^packages/[^/]+/(lib|bin)/').hasMatch(rel)) continue;
    final r = parseFile(
      path: f.path,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    // Un archivo que no parsea ya fue reportado por `clasesDe`; de un árbol
    // parcial no se deriva nada.
    if (r.errors.isNotEmpty) continue;
    final v = _Subprocesos(rel, _bibliotecaDe(r.unit, rel));
    r.unit.accept(v);
    lanzamientos.addAll(v.vistos);
  }
  final sinSanear = lanzamientos.where((l) => l.problema != null).toList();
  final porBiblioteca = <String, List<_Lanzamiento>>{};
  for (final l in sinSanear) {
    (porBiblioteca[l.biblioteca] ??= []).add(l);
  }
  for (final e in porBiblioteca.entries) {
    final metodo = excepciones[e.key];
    if (metodo == null) {
      for (final l in e.value) {
        fallos.add(
          '${l.archivo}:${l.offset}: lanza un proceso y ${l.problema} '
          'Usá `environment: entornoSaneado(...)` e '
          '`includeParentEnvironment: false`.',
        );
      }
      continue;
    }
    // La excepción admite EXACTAMENTE uno, dentro del método declarado.
    final fuera = e.value.where((l) => l.metodo != metodo).toList();
    for (final l in fuera) {
      fallos.add(
        '${l.archivo}:${l.offset}: la excepcion de «${e.key}» admite un solo '
        'lanzamiento sin sanear, en `$metodo`; este está en '
        '`${l.metodo.isEmpty ? "nivel superior" : l.metodo}`. ${l.problema}',
      );
    }
    final adentro = e.value.where((l) => l.metodo == metodo).length;
    if (adentro > 1) {
      fallos.add(
        '${e.key}: `$metodo` tiene $adentro lanzamientos sin sanear y la '
        'excepcion admite uno. Una excepción que crece en silencio es una '
        'lista negra.',
      );
    }
  }
  for (final e in excepciones.entries) {
    if (!(porBiblioteca[e.key]?.any((l) => l.metodo == e.value) ?? false)) {
      fallos.add(
        'arquitectura.json: «subprocesos-con-entorno-saneado» exceptúa '
        '`${e.value}` en ${e.key}, y ahí no hay ningún lanzamiento sin '
        'sanear. La declaración quedó vieja y taparía al próximo.',
      );
    }
  }
```

Y en la línea final de salida, agregá la cifra: `', ${lanzamientos.length} lanzamientos de proceso, ${sinSanear.length} exceptuado(s).'`. Esperado con el árbol de las tareas 4 y 5: **6 lanzamientos** (tres costuras de `repositorio.dart`, `chmod` en `candidato.dart`, `Process.start` en `ejecutor.dart`, y `_capturarIdentidad`), **1 exceptuado**.

- [ ] **Step 5: Ahora sí, en rojo y en verde** — creá el canario de la canónica otra vez, corré `check.dart`: esperado **rojo** mencionando `entornoSaneado`. Borralo: verde. Y el arnés completo, que aplica canónica, cuatro extras, dos neutralizaciones y el caso ciego:

```bash
python3 tool/checks/capas.py --huella && python3 tool/checks/capas.py && python3 tool/checks/probar_reglas.py
```

Esperado: `probar_reglas: ok — 127 sabotajes detectados sobre 13 reglas, de los cuales 13 son casos CIEGOS…`. Si la cifra difiere, la que manda es la que imprime el arnés; anotala para la tarea 10.

- [ ] **Step 6: Commit**

```bash
dart format --set-exit-if-changed tool
git add tool/analisis/bin/check.dart arquitectura.json tool/checks/arquitectura.huella tool/checks/probar_reglas.py tool/checks/capas.py README.md
git commit -m "tool/analisis: la regla que exige entornoSaneado en todo lanzamiento

Semántica, no forma: environment: Platform.environment cumple lo que la v1
pedía y no sanea nada. Cubre run, runSync y start sobre el árbol
sintáctico; una excepción declarada —la captura de identidad— y contada:
un segundo sitio en esa biblioteca es rojo. Cuatro extras y caso ciego.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---
### Task 9: La prueba decisiva, en `cli`

**Files:**
- Modify: `packages/cli/pubspec.yaml` (`vcs` en `dev_dependencies`)
- Create: `packages/cli/test/entorno_del_candidato_test.dart`
- Regenerar: `grafo.jsonl`

**Interfaces:**
- Consumes: `RepositorioGit`, `PreparedCandidate.alteraciones()` (tareas 3, 4); `EntornoDart` (7); `cascadaPorDefecto` de `cli`; `EstadoDeCorrida`.
- Produces: nada de producción. **La composición vive en la prueba** (§12): preparar → derivar → integridad → cascada → integridad. Es lo que la rebanada 2 va a levantar a un coordinador; acá está escrita una vez para que la regla «una alteración hace la corrida `noConcluyente`, nunca roja» tenga dónde probarse.

- [ ] **Step 1: La dependencia.** En `packages/cli/pubspec.yaml`, bajo `dev_dependencies`, después de `plugin_fake`: `  vcs:\n    path: ../vcs`. Corré `dart pub get`. `deps-hacia-core.permitidas` ya permite `cli → vcs`; la regla `dependencias-declaradas-se-usan` va a exigir que algo de `test/` lo importe: esta prueba.

- [ ] **Step 2: La prueba** — `packages/cli/test/entorno_del_candidato_test.dart`:

```dart
/// **La prueba decisiva** (§14): un error inyectado SOLO en el candidato produce
/// un diagnóstico que apunta al candidato, el repositorio real no cambia, y el
/// candidato sigue íntegro después de la cascada.
///
/// `cli` es el único paquete que ve `vcs` y `plugin_dart` a la vez, y por eso
/// la composición vive acá, en una prueba: todavía no hay coordinador de
/// producción (§12), y eso está declarado en `arquitectura.json`.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

class _TodoEsFuente implements ArtifactPolicy {
  const _TodoEsFuente();
  @override
  bool isGenerated(String path) => false;
  @override
  bool isEditable(String path) => path.trim().isNotEmpty;
}

const presupuesto = Duration(minutes: 3);

/// La composición que la rebanada 2 va a volver productiva. Devuelve el estado
/// y deja en [medidas] cuánto tardó cada control (Q-1, Q-2 de §13).
Future<EstadoDeCorrida> verificarCandidato(
  PreparedCandidate c, {
  required List<String> archivos,
  required List<String> sujetos,
  required Map<String, Duration> medidas,
  void Function()? entreCascadaYControl,
}) async {
  final reloj = Stopwatch()..start();
  final entorno = await const EntornoDart().derivar(c.root, archivos: archivos, presupuesto: presupuesto);
  medidas['derivar'] = reloj.elapsed;
  if (entorno is! EntornoDerivado) return EstadoDeCorrida.noConcluyente;

  reloj.reset();
  if ((await c.alteraciones()).isNotEmpty) return EstadoDeCorrida.noConcluyente;
  medidas['integridad'] = reloj.elapsed;

  final resultado = await cascadaPorDefecto(directorio: c.root, presupuesto: presupuesto).correr(sujetos);
  entreCascadaYControl?.call();
  // Una alteración DESPUÉS de la cascada hace la corrida noConcluyente, nunca
  // roja: no se puede afirmar nada sobre un árbol que dejó de ser el fijado.
  if ((await c.alteraciones()).isNotEmpty) return EstadoDeCorrida.noConcluyente;
  return resultado.estado;
}

void main() {
  late Directory raiz;
  late RepositorioGit repo;

  String git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: raiz.path);
    if (r.exitCode != 0) throw StateError('git ${args.join(" ")} → ${r.stderr}');
    return (r.stdout as String).trim();
  }

  void escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('decisiva_');
    // La forma de shipflow, mínima: raíz de workspace con un miembro, y un
    // manifiesto no miembro que la rebanada no toca.
    escribir('pubspec.yaml', 'name: ws\nenvironment:\n  sdk: ^3.11.0\nworkspace:\n  - packages/a\n');
    escribir('packages/a/pubspec.yaml', 'name: a\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\n');
    escribir('packages/a/lib/a.dart', 'int sano() => 1;\n');
    escribir('tool/x/pubspec.yaml', 'name: x\nenvironment:\n  sdk: ^3.11.0\n');
    escribir('tool/x/lib/x.dart', '');
    // El lockfile se fija UNA vez con pub y se versiona; lo generado, no.
    final r = Process.runSync('dart', ['pub', 'get', '--offline'], workingDirectory: raiz.path);
    if (r.exitCode != 0) throw StateError('no pude fijar el lockfile: ${r.stderr}');
    Directory('${raiz.path}/.dart_tool').deleteSync(recursive: true);
    Directory('${raiz.path}/packages/a/.dart_tool').deleteSync(recursive: true);
    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
    repo = RepositorioGit(directorio: raiz.path, politica: const _TodoEsFuente());
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  test('el error inyectado en el candidato se ve en el candidato y el repositorio real no cambia',
      () async {
    escribir('packages/a/lib/a.dart', "int sano() => 1;\nint roto = 'no soy un int';\n");
    final antes = git(['status', '--porcelain']);
    final rebanada = PullRequestSlice(id: 'r1', intent: 'romper a propósito', files: ['packages/a/lib/a.dart']);
    final c = await repo.prepareCandidate(rebanada);
    final medidas = <String, Duration>{};
    try {
      final entorno = await const EntornoDart()
          .derivar(c.root, archivos: rebanada.files, presupuesto: presupuesto) as EntornoDerivado;
      expect(entorno.raices, 1, reason: 'tool/x no se toca: no existe para esta rebanada');
      expect(Directory('${c.root}/tool/x/.dart_tool').existsSync(), isFalse);
      expect(await c.alteraciones(), isEmpty);

      final resultado = await cascadaPorDefecto(directorio: c.root, presupuesto: presupuesto)
          .correr(['packages/a/lib']);
      expect(resultado.estado, EstadoDeCorrida.rojo);
      final diagnosticos = [
        for (final d in resultado.desenlaces.values)
          if (d is Executed) ...d.diagnostics,
      ];
      expect(diagnosticos, isNotEmpty);
      for (final d in diagnosticos) {
        expect(d.file, startsWith(c.root), reason: 'el diagnóstico apunta al candidato, no al árbol del usuario');
      }
      expect(await c.alteraciones(), isEmpty, reason: 'la cascada no escribió en el candidato');
      expect(git(['status', '--porcelain']), antes, reason: 'el repositorio real sigue exactamente igual');
      expect(Directory('${raiz.path}/.dart_tool').existsSync(), isFalse,
          reason: 'la derivación escribió en el candidato, no en el árbol del usuario');
    } finally {
      await c.dispose();
    }
  });

  test('Q-1 y Q-2: la integridad y la derivación caben en el presupuesto, y se registran', () async {
    escribir('packages/a/lib/a.dart', 'int sano() => 2;\n');
    final c = await repo.prepareCandidate(
        PullRequestSlice(id: 'r2', intent: 'medir', files: ['packages/a/lib/a.dart']));
    final medidas = <String, Duration>{};
    try {
      final estado = await verificarCandidato(c,
          archivos: ['packages/a/lib/a.dart'], sujetos: ['packages/a/lib'], medidas: medidas);
      expect(estado, EstadoDeCorrida.verde);
      expect(medidas['derivar'], lessThan(presupuesto));
      expect(medidas['integridad'], lessThan(presupuesto));
      // Se imprime: es medición registrada con techo sobre ESTE árbol, no
      // evidencia sobre un monorepo. El techo es la aserción; la cifra, el dato.
      printOnFailure('derivar: ${medidas['derivar']} · integridad: ${medidas['integridad']}');
      print('Q-1 integridad=${medidas['integridad']!.inMilliseconds}ms · Q-2 derivar=${medidas['derivar']!.inMilliseconds}ms');
    } finally {
      await c.dispose();
    }
  });

  test('una alteración después de la cascada → noConcluyente, aunque la cascada haya dado rojo',
      () async {
    escribir('packages/a/lib/a.dart', "int sano() => 1;\nint roto = 'no soy un int';\n");
    final c = await repo.prepareCandidate(
        PullRequestSlice(id: 'r3', intent: 'alterar', files: ['packages/a/lib/a.dart']));
    try {
      final estado = await verificarCandidato(
        c,
        archivos: ['packages/a/lib/a.dart'],
        sujetos: ['packages/a/lib'],
        medidas: {},
        entreCascadaYControl: () =>
            File('${c.root}/packages/a/pubspec.yaml').writeAsStringSync('name: otro\n'),
      );
      expect(estado, EstadoDeCorrida.noConcluyente);
      expect(estado, isNot(EstadoDeCorrida.rojo));
    } finally {
      await c.dispose();
    }
  });
}
```

Si `medidas` queda sin usar en la primera prueba, borrala de ahí: el analizador con `--fatal-infos` lo va a cobrar.

- [ ] **Step 3: Corré** — `dart test packages/cli/test/entorno_del_candidato_test.dart`. Esperado: 3 en verde, con la línea `Q-1 … · Q-2 …` impresa. Si `dart analyze` dentro del candidato no encuentra el `package_config.json`: el workspace se derivó en `c.root` (raíz `.`), y `analyze` sobre `packages/a/lib` lo busca hacia arriba; comprobá que `packages/a/pubspec.yaml` se materializó con `resolution: workspace`.

- [ ] **Step 4: El grafo y los checks** — `cd tool/analisis && dart run bin/grafo.dart --escribir && dart run bin/grafo.dart && cd ../.. && python3 tool/checks/capas.py && dart test packages/cli && dart analyze --fatal-infos && dart format --set-exit-if-changed packages tool`.

- [ ] **Step 5: Commit**

```bash
git add packages/cli/pubspec.yaml packages/cli/test/entorno_del_candidato_test.dart grafo.jsonl pubspec.lock
git commit -m "cli: la prueba decisiva — el error se ve en el candidato y el repositorio no cambia

Preparar, derivar, integridad, cascada, integridad. Un error inyectado solo
en el candidato da rojo apuntando al candidato; el árbol del usuario queda
intacto; una alteración después de la cascada hace la corrida noConcluyente
aunque la cascada haya dado rojo. Q-1 y Q-2 quedan como medición con techo.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

(`pubspec.lock` solo si `dart pub get` lo cambió por la dependencia nueva; mirá `git status`.)

---

### Task 10: README, el arnés entero, y el PR

**Files:**
- Modify: `README.md`
- Verificar: todo.

- [ ] **Step 1: El README.** Tres ediciones:
  1. En la tabla «Puerto | Real | Fake» (buscá `| \`ChangeSink\` | \`git\` de verdad`), agregá: `| \`VerificationEnvironment\` | \`pub get --offline --enforce-lockfile\` sobre el candidato, una raíz por vez | **no hay**, y está declarado |`. Y debajo del párrafo que empieza «`ChangeSink` salió igual», un párrafo: «`VerificationEnvironment` salió con **una real y ningún fake**, por el mismo motivo y en el mismo registro: no hay etapa que lo consuma —la composición vive en una prueba de `cli`—, y una suite de contrato con una sola implementación corre la misma lógica dos veces.»
  2. La línea `**El arnés aplica 119 sabotajes.**` → la cifra que imprimió `probar_reglas.py` en la tarea 8.
  3. Una sección nueva `## El entorno de verificación se deriva del candidato`, antes de `## El falso rojo simétrico`, con estas subsecciones —cada una tres a seis oraciones, en el registro del README: qué se midió, qué se decidió, qué control lo sostiene—: `### Por qué derivar y no prestar` (§4, A-1/A-2); `### Pub borra lo que el candidato versiona, y por eso la integridad se comprueba` (§5, A-5/A-6; `-q`, `--raw`, lo no materializado, el límite del `clean` no idempotente); `### Tres desenlaces, y la línea que los separa` (§6 y refinamiento 1: el 69 de `pub`); `### Una raíz por cada resolución que la rebanada toca` (§10: `shipflow` se verifica a sí mismo, el fixture con su forma); `### La lista blanca, y la identidad capturada` (§8, A-7/A-8, la excepción declarada y contada); `### Lo que esta rebanada NO hace` (§12: sin coordinador, sin fake, sin `ship`; Windows rechazado §11).

- [ ] **Step 2: El arnés entero, en el orden de CI, y sin solaparlos:**

```bash
dart pub get && python3 tool/checks/capas.py \
  && (cd tool/analisis && dart pub get && dart run bin/check.dart && dart run bin/grafo.dart) \
  && python3 tool/checks/probar_reglas.py && python3 tool/checks/probar_recuperacion.py \
  && dart test packages/core && dart test packages/orchestration && dart test packages/vcs \
  && dart test packages/cli && dart test packages/plugin_dart \
  && dart analyze --fatal-infos && dart format --set-exit-if-changed packages tool
```

`capas.py` verifica el README contra las reglas y contra los pasos de CI; `check.dart` verifica las cifras de la cascada que el README afirma. Si algo de la sección nueva rompe `_readme_*`, el mensaje dice qué.

- [ ] **Step 3: Commit y PR**

```bash
git add README.md
git commit -m "README: el entorno de verificación, control por control

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
git push -u origin entorno-de-verificacion
gh pr create --base develop --title "El entorno de verificación se deriva del candidato, y ningún subproceso hereda el del padre" --body-file - <<'EOF'
Implementa la propuesta de entorno de verificación (corpus, `borradores/PROPUESTA-entorno-de-verificacion.md`, v2 + las cuatro condiciones de la aprobación).

- `core`: `entornoSaneado` (lista blanca), `ResultadoDeEntorno` sellado, `VerificationEnvironment`, `PreparedCandidate.alteraciones()`.
- `vcs`: integridad por `read-tree` + `update-index -q --refresh` + `diff-index --raw -z`; lo no materializado se resta; `git` corre saneado; identidad capturada y `useConfigOnly`.
- `plugin_dart`: `EntornoDart`, una raíz por resolución que la rebanada toca; `raicesDeResolucion` pura, con el fixture de la forma exacta de este repositorio.
- `tool/analisis`: regla `subprocesos-con-entorno-saneado`, semántica sobre el AST, con una excepción declarada y contada.
- `cli`: la prueba decisiva.

**Se aparta del diseño en tres puntos, medidos** (plan, «Refinamientos»): todo «no» de `pub` es rechazo —69 no distingue cache frío de SDK desconocido—; la dependencia `path` que escapa se lee del lockfile; la captura de identidad es la única excepción a la regla. Van al corpus en el PR hermano.

Sin coordinador productivo y sin fake: declarado en `arquitectura.json` y en el README.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

Después: `gh pr checks --watch`. Las tres patas (`capas` ×2, `formato`, `fixture`) en verde antes de pedir review.

---

### Task 11: El corpus

**Repo:** `/Users/zeref/Documents/SDLC/sdlc-agentico`, rama nueva `entorno-de-verificacion-corpus` desde `production`. PR a `production`, **después** de que el PR de código esté mergeado (el check `estados.py` cruza las reglas contra `../shipflow/`, y `anonimato.py --repo ../shipflow` mira su árbol).

**Files:**
- Modify: `arnes-propio/ARNES-DEL-PROYECTO.md` — fila para `subprocesos-con-entorno-saneado`, con la forma exacta de la fila de `dependencias-declaradas-se-usan` (línea 98): `| código | \`subprocesos-con-entorno-saneado\` — … | **instalado · bloquea el merge** |`. `estados.py` falla sin ella.
- Modify: `borradores/PROPUESTA-entorno-de-verificacion.md` — los tres refinamientos, como enmiendas marcadas `[P/E]` con un `A-13 · Los códigos de salida de pub` (`1` sin lockfile, `65` lockfile que no satisface, `69` cache vacío **y** `69` SDK desconocido); §6 y la fila de §14 «cache vacío» pasan a `CandidatoRechazado`; §7 dice «del lockfile» y por qué; §9 gana el párrafo de la excepción única y contada. Cabecera: «**Implementada** en shipflow, PR #N».
- Modify: `docs/03-dominio-y-puertos.md` §5 — el puerto `VerificationEnvironment` y `PreparedCandidate.alteraciones()`, en el registro de las otras entradas de la sección (leé dos antes de escribir la tuya).
- Modify: `docs/06-seguridad.md` §2 y §3 — el saneamiento como lista blanca, la identidad capturada, y la excepción declarada; una fila en el mapeo ASI de §1 si hay una categoría que lo cubra (leé la tabla).
- Modify: `REGISTRO-DELTAS.md` — un delta por decisión nueva, con el número siguiente al último que exista (`grep -o 'D-[0-9]*' REGISTRO-DELTAS.md | sort -V | tail -1`) y el formato de sus vecinos; y la fila de «Estado de propagación» para `docs/03` y `docs/06`.
- Create: `adr/ADR-020-entorno-derivado-del-candidato.md` — con la estructura exacta de `ADR-019-desenlace-de-paso-sellado.md` (leelo entero antes), incluido su **invariante ejecutable**: «todo lanzamiento de proceso bajo `packages/*/{lib,bin}` pasa por `entornoSaneado`, salvo el único exceptuado y contado; lo verifica `tool/analisis/bin/check.dart` en cada corrida».
- Create: dos diagramas **como documentación, no como compuerta** (condición de la aprobación): (1) secuencia de `verificarCandidato` con sus ramas de fallo —`CandidatoRechazado`, `DerivacionAbortada`, alteración antes, alteración después—; (2) flujo de datos y fronteras de confianza —árbol del usuario, candidato, cache de pub, entorno del padre, lista blanca, identidad capturada—. Si el skill `archify` está disponible, usalo y dejá `diagramas/shipflow-entorno-*.{html,archify.json}` como los seis que ya hay en `diagramas/`; si no, Mermaid dentro del ADR. Los seis `diagramas/shipflow-*` que hoy están sin trackear **no son de esta rebanada**: no los agregues ni los borres.

- [ ] **Step 1:** Rama, y las ediciones de arriba.
- [ ] **Step 2:** Los cuatro checks: `python3 arnes-propio/checks/coherencia.py && python3 arnes-propio/checks/cifras.py --fix && python3 arnes-propio/checks/cifras.py && python3 arnes-propio/checks/estados.py && python3 arnes-propio/checks/anonimato.py`. Verde los cuatro (y `cifras.py` puede reescribir `INVENTARIO.md`: se commitea).
- [ ] **Step 3:** Commit con rutas explícitas (`git add adr/ADR-020-… docs/03-… docs/06-… REGISTRO-DELTAS.md INVENTARIO.md arnes-propio/ARNES-DEL-PROYECTO.md borradores/PROPUESTA-entorno-de-verificacion.md diagramas/shipflow-entorno-*`), push, `gh pr create --base production` con el mismo cierre `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## Autorrevisión del plan contra el diseño

**Cobertura de §14, fila por fila.** `core` (3 filas) → tareas 1 y 2. `vcs` (11 filas: intacto, tipos, generado nuevo, no materializadas ×2, filtros ×2, letra desconocida, git falso, identidad ×3, `GIT_DIR`) → tareas 3 y 4. `plugin_dart` (12 filas: lockfile que no satisface, restricción que satisface, `.dart_tool` versionado, fixture con la forma de shipflow ×3, manifiesto no tocado, Q-4, `path` que escapa, cache vacío —con el refinamiento 1—, toolchain ausente, presupuesto, lista blanca del ejecutable) → tareas 5, 6 y 7. `cli` (3 filas) → tarea 9. `arquitectura.json` → tarea 8. Los tres sabotajes del estado intermedio → tarea 7 paso 6, tarea 3 paso 9, tarea 8 (la canónica). Las cinco premisas nuevas de la tabla de §14 (refresh sale 1, `--name-status` pliega, no materializado sale `D`, el `clean` corre) → tarea 3.

**§15, archivo por archivo.** Todos tienen tarea, salvo `docs/14` (la propuesta lo listaba por la superficie de `ship`, que esta rebanada no toca: no hay nada que enmendar ahí todavía) y `packages/vcs/lib/src/secretos.dart`, que no cambia.

**Consistencia de nombres entre tareas.** `entornoSaneado(delPadre, {propias})` (1) es lo que usan 4 y 5 y lo que exige 8. `alteraciones()` (3) es lo que llama 9. `raicesDeResolucion(candidateRoot, archivos)` (6) es lo que llama 7. `EntornoDart({ejecutor, programa})` (7) es lo que llama 9. `EjecutorDelSistema({entornoDelPadre})` (5) es lo que usa 7 en sus pruebas. `_capturarIdentidad` (4) es el `metodo` de la excepción (8). `TipoDeAlteracion` con cuatro variantes (2) es lo que produce `leerDiffRaw` (3).

**Lo que este plan deja fuera a sabiendas:** el coordinador productivo, el fake de `VerificationEnvironment`, `ship`, la superficie de verificación, la forja, el presupuesto por corrida, y Windows. Son las rebanadas 2 a 4.
