# `--retry-publication` y la reconciliación — plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL REQUERIDA: usá superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para ejecutar este plan tarea por tarea. Los pasos usan casillas (`- [ ]`).

**Objetivo:** que una corrida de `ship` que murió después de commitear se pueda terminar sin volver a correr la cascada, y que una que murió antes del compare-and-swap se reconcilie o falle cerrado.

**Arquitectura:** las lecturas nuevas de `git` —el padre de una revisión, su árbol, su mensaje, el `HEAD`, y la comparación del índice acotada a rutas— entran al adapter de `git`, que es el único que habla con la herramienta. Las decisiones —qué estado admite el reintento, si la reconciliación es inequívoca, qué desenlace sale— son funciones **puras** al lado de la comparación de tres casos que ya existe, que no lee el repositorio y por eso se prueba sin montar uno.

**Stack:** Dart puro, monorepo de nueve paquetes, `package:test`. Sin dependencias nuevas.

**Spec:** [`../sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md`](../sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md) **§9**, con las enmiendas `5b1bd84` y `8512585`. **Leé §9 entera antes de empezar**: las enmiendas corrigen cinco desajustes entre lo que decía y lo que el árbol ya tiene.

**Decisiones previas:** `.superpowers/sdd/decisiones-4c.md` — cuatro, tomadas antes de este plan. **Vinculan.**
**Inventario previo:** `.superpowers/sdd/inventario-4c.md` — qué existe y qué falta, con archivo y línea.

## Restricciones globales

Valen para **todas** las tareas. Copiadas del corpus y del árbol.

- **`core` no tiene dependencias externas, ninguna, y no hace entrada/salida.**
- **Quién es la forja lo sabe su propio paquete y ningún otro:** ni su nombre de marca —`GitHub`, esa capitalización— ni su host ni un cliente HTTP, en código bajo `lib/` ni `bin/` de ningún otro paquete. En prosa sí está permitido.
- **Las cadenas `dart`, `flutter`, `pubspec` no aparecen fuera de `plugin_dart/` y del composition root.** Un check escanea **línea por línea, incluidos los comentarios**: no cites un nombre de archivo con su extensión.
- **Las cadenas `claude`, `codex`, `gemini` no aparecen fuera de `agents/` y del composition root.**
- **Todo subproceso se lanza con el entorno saneado.** El adapter de `git` tiene **una sola** excepción declarada y contada; un segundo lanzamiento sin sanear pone el check en rojo.
- **Los constructores de las variantes del tipo sellado del desenlace son privados**, y las fábricas son la única entrada. Nadie ensambla un desenlace eligiendo la combinación que le conviene.
- **Ninguna regla prohibitiva se instala sin su alternativa.** Todo mensaje que diga «no se puede X» dice también «hacé Y».
- **Un paso sin testigo no es verde: es no concluyente**, y precede al rojo.
- **Ningún control decide qué mira en una representación más pobre que su criterio.**
- **Toda afirmación fáctica lleva marca de fuente** en los documentos del corpus: `[P]` primaria o prueba propia, `[S]` secundaria, `[O]` observada, `[I]` interna, `[D]` diseño sin verificación.
- **La suite se corre desde la raíz del repositorio.** Correrla desde dentro de un paquete da seis rojas falsas: un grupo arma la ruta del binario con el directorio actual.
- **No corras `tool/checks/probar_reglas.py` mientras editás.** Trabaja sobre una copia privada y detecta cualquier cambio en el checkout compartido, incluidas marcas de tiempo. Va último, con el árbol limpio y todo commiteado.
- Doc comments y mensajes de error **en español, argumentando el porqué**, no describiendo el qué.
- Commits en español, con el pie `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

## Estructura de archivos

| Archivo | Responsabilidad | Tarea |
|---|---|---|
| `packages/vcs/lib/src/repositorio.dart` | **modificar** · las cuatro lecturas de un objeto commit y el `HEAD` público | T1 |
| `packages/vcs/lib/src/indice.dart` | **crear** · la comparación del índice del usuario contra un árbol, acotada a rutas | T2 |
| `packages/core/lib/src/publicacion.dart` | **modificar** · el borrador gana las rutas de la rebanada | T3 |
| `packages/core/lib/src/documento.dart` | **modificar** · la arista condicionada, y el párrafo de la ventana de versión | T3, T4 |
| `packages/core/lib/src/corrida.dart` | **modificar** · la segunda entrada de la fábrica | T7 |
| `packages/cli/lib/src/ship/entrada.dart` | **modificar** · la bandera y su exclusión mutua | T5 |
| `packages/cli/lib/src/corrida.dart` | **modificar** · el filtro por estado, la rama, y la decisión pura de reconciliación | T6, T8, T9 |
| `packages/cli/lib/src/ship/reintento.dart` | **crear** · la composición del reintento: leer, decidir, publicar, sellar | T10 |
| `packages/cli/lib/src/ship/composicion.dart` | **modificar** · la rama del comando que entra al reintento | T10 |
| `arquitectura.json`, `README.md`, `grafo.jsonl` | **modificar** · el cierre | T11 |

---

## Ayudantes de prueba compartidos

Cinco ayudantes aparecen en las pruebas de varias tareas. **Los escribe la primera
tarea que los usa, en el archivo de prueba donde los usa, y las siguientes los
reusan** — si el archivo cambia, se factorizan al de apoyo compartido que el
paquete ya tiene. Ninguno se duplica.

| Ayudante | Qué devuelve | Primera tarea que lo escribe |
|---|---|---|
| `borradorDePrueba({required List<String> rutas})` | un `PullRequestDraft` válido con las rutas dadas | T3 |
| `documentoEn(EstadoDelDocumento estado)` | un `DocumentoDeCorrida` en ese estado, con `draft.branch == 'feature/x'` y un desenlace que le corresponda | T6 |
| `documentoPreparado()` | `documentoEn(EstadoDelDocumento.prepared)` | T8 |
| `documentoInconsistente()` | `documentoEn(EstadoDelDocumento.localInconsistent)` | T9 |
| `desenlacesRemotosCanonicos` | **las siete** variantes del desenlace de publicación, una de cada una | T7 |

**`desenlacesRemotosCanonicos` no se escribe a mano si ya existe.** El paquete tiene
una suite de serialización con instancias canónicas: buscala y reusá las suyas. Una
lista escrita a mano envejece cuando alguien agrega una variante, y entonces la
prueba que dice cubrir «todas» cubre las de antes — que es exactamente el falso
verde por muestra incompleta que este proyecto ya encontró tres veces.

---

### Tarea 1: Las cuatro lecturas de un objeto commit

**Archivos:**
- Modificar: `packages/vcs/lib/src/repositorio.dart`
- Test: `packages/vcs/test/repositorio_test.dart`

**Interfaces:**
- Consume: `_exigir(List<String>)` — el lanzador saneado privado que ya usa toda la clase.
- Produce: `Future<String> get head`, `Future<String?> padreDe(String revision)`, `Future<String> arbolDe(String revision)`, `Future<String> mensajeDe(String revision)`.

**Por qué esta tarea existe.** `vcs` no sabe leer **nada** de un objeto commit: ni su padre, ni su árbol, ni su mensaje. Ni siquiera el `HEAD`, que tiene tres lecturas privadas y ninguna pública `[P]`. La comparación de tres casos de §9 exige un `HEAD` que hoy su llamador no tiene de dónde sacar, y los pasos 1, 2 y 3 de la reconciliación exigen los otros tres.

**Por qué van acá y no en el CLI.** El encabezado del módulo del candidato lo fija: las costuras contra la herramienta son privadas a propósito, «la única puerta por la que este paquete habla con la herramienta», y abrirlas «convertiría cualquier archivo futuro en un segundo lugar donde se arman invocaciones».

- [ ] **Paso 1: escribir las pruebas que fallan**

En `packages/vcs/test/repositorio_test.dart`, un grupo nuevo:

```dart
  group('leer un objeto commit', () {
    test('el HEAD es el de la rama actual', () async {
      final r = await repoConDosCommits();
      expect(await r.repo.head, r.segundo);
    });

    test('el padre de una revisión es su antecesor', () async {
      final r = await repoConDosCommits();
      expect(await r.repo.padreDe(r.segundo), r.primero);
    });

    test('la PRIMERA revisión no tiene padre, y eso es un HECHO, no un error',
        () async {
      final r = await repoConDosCommits();
      expect(await r.repo.padreDe(r.primero), isNull);
    });

    test('un merge tiene DOS padres, y pedir «el» padre miente', () async {
      final r = await repoConMerge();
      expect(
        () => r.repo.padreDe(r.merge),
        throwsA(isA<GitFallo>()),
        reason: 'devolver el primero haría pasar el paso 1 de la '
            'reconciliación sobre un commit que no es hijo de la base',
      );
    });

    test('el árbol de una revisión es su OID de árbol, no el del commit',
        () async {
      final r = await repoConDosCommits();
      final arbol = await r.repo.arbolDe(r.segundo);
      expect(arbol, isNot(r.segundo));
      expect(arbol, matches(RegExp(r'^[0-9a-f]{40,64}$')));
    });

    test('el mensaje sale ENTERO y sin el salto final que git agrega',
        () async {
      final r = await repoConMensaje('primera línea\n\ncuerpo del mensaje');
      expect(await r.repo.mensajeDe(r.revision), 'primera línea\n\ncuerpo del mensaje');
    });

    test('una revisión que no existe falla, no devuelve vacío', () async {
      final r = await repoConDosCommits();
      expect(
        () => r.repo.arbolDe('0' * 40),
        throwsA(isA<GitFallo>()),
      );
    });
  });
```

**Los ayudantes `repoConDosCommits`, `repoConMerge` y `repoConMensaje` no existen: escribilos** en el mismo archivo, con el estilo de los ayudantes que ya hay ahí. Cada uno devuelve un registro con el repositorio y los OIDs que la prueba necesita, y los construye con `git` de verdad en un temporal.

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/vcs/test/repositorio_test.dart
```
Esperado: FALLA, «The method 'head' isn't defined» y sus tres hermanas.

- [ ] **Paso 3: implementar las cuatro lecturas**

En `packages/vcs/lib/src/repositorio.dart`, junto a `ramaActual`:

```dart
  /// El `HEAD` de la rama actual, resuelto a su OID.
  ///
  /// **Público desde esta rebanada, y no antes.** Tres lugares de este paquete
  /// ya lo leían en privado; la comparación de tres casos de la recuperación
  /// pide el `HEAD` como argumento —a propósito, para no leer el repositorio y
  /// poder probar sus casos sin montar uno— y sin esta lectura su llamador no
  /// tiene de dónde sacarlo.
  Future<String> get head => _exigir(['rev-parse', 'HEAD']);

  /// El padre de [revision], o nulo si no tiene ninguno.
  ///
  /// **Nulo es un HECHO y no un error**: la primera revisión de un repositorio
  /// no tiene padre, y quien reconcilia tiene que poder distinguir «no tiene»
  /// de «no se pudo leer».
  ///
  /// **Con DOS padres lanza, y eso es deliberado.** Devolver el primero haría
  /// pasar el paso 1 de la reconciliación sobre un commit de fusión que no es
  /// hijo de la base en el sentido que ese paso afirma. Ante una forma que la
  /// pregunta no contempla, fallar cerrado.
  Future<String?> padreDe(String revision) async {
    final salida = await _exigir(['rev-list', '--parents', '-n', '1', revision]);
    final campos = salida.split(' ').where((c) => c.isNotEmpty).toList();
    if (campos.length == 1) return null;
    if (campos.length > 2) {
      throw GitFallo(
        'rev-list --parents $revision',
        0,
        'La revisión tiene ${campos.length - 1} padres. «El» padre no existe, '
        'y elegir uno afirmaría una ascendencia que nadie midió. Si esto es '
        'una fusión, la corrida que la produjo no es una que ship pueda '
        'reconciliar: volvé a correr ship desde cero.',
      );
    }
    return campos[1];
  }

  /// El OID del árbol de [revision]. **No es el OID de la revisión.**
  Future<String> arbolDe(String revision) =>
      _exigir(['rev-parse', '$revision^{tree}']);

  /// El mensaje entero de [revision], sin el salto final que `git` agrega.
  ///
  /// **`%B` y no `%s`**: el paso 3 compara el mensaje esperado, y el asunto
  /// solo sería una comparación más pobre que su criterio.
  Future<String> mensajeDe(String revision) async {
    final salida = await _exigirCrudo(['log', '-1', '--format=%B', revision]);
    return salida.endsWith('\n')
        ? salida.substring(0, salida.length - 1)
        : salida;
  }
```

**Comprobá antes de escribir** que `_exigirCrudo` existe y que devuelve la salida sin recortar; si el nombre difiere, usá el que haya y decilo en el reporte. `_exigir` recorta, y recortar el mensaje perdería un salto significativo del cuerpo.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/vcs
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: medir las mutaciones**

Rompé cada mecanismo y anotá qué prueba muere:
1. `padreDe` devuelve `campos[1]` sin comprobar la cantidad → muere la del merge.
2. `arbolDe` usa `revision` en vez de `$revision^{tree}` → muere la del árbol.
3. `mensajeDe` usa `_exigir` en vez de `_exigirCrudo` → muere la del mensaje con cuerpo.

- [ ] **Paso 6: commitear**

```bash
git add packages/vcs/lib/src/repositorio.dart packages/vcs/test/repositorio_test.dart
git commit -m "vcs sabe leer un commit: su padre, su árbol, su mensaje y el HEAD

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 2: La comparación del índice, acotada a rutas

**Archivos:**
- Crear: `packages/vcs/lib/src/indice.dart`
- Modificar: `packages/vcs/lib/vcs.dart` (exportarlo), `packages/vcs/lib/src/repositorio.dart` (el método que lo usa)
- Test: `packages/vcs/test/indice_test.dart`

**Interfaces:**
- Consume: `_exigir`, `_exigirBytes` y el parser `leerDiffRaw` de `packages/vcs/lib/src/alteraciones.dart`.
- Produce: `Future<List<String>> RepositorioGit.rutasQueDifierenDelArbol({required String arbol, required List<String> rutas})` — las rutas, de entre [rutas], en las que el índice del usuario NO coincide con [arbol]. Lista vacía significa **coincide**.

**Por qué acotada a rutas y no entera.** §9 lo dice: comparar el índice entero rechazaría cambios preparados ajenos que la operación de aplicar promete preservar. El reintento no es dueño del índice del usuario: solo puede opinar sobre las rutas de la rebanada.

**Lo que ya existe y hay que reusar, no reescribir.** El trío `read-tree` + `update-index -q --refresh` + `diff-index --raw -z` que `_CandidatoGit.alteraciones` usa es la forma **medida** de preguntar «este índice coincide con este árbol» `[P]`. Pero corre contra el índice **aislado** del candidato, y el candidato ya no existe cuando el reintento corre: su limpieza lo borró. Lo que falta es la versión que corre contra el índice **real** y acepta un conjunto de rutas.

**El `update-index -q --refresh` NO se omite.** Sin él, un archivo con `mtime` cambiado y contenido idéntico aparece como diferente, y el reintento fallaría cerrado sobre un índice que sí coincide. Es la diferencia entre comparar bytes y comparar metadatos.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('un índice que coincide devuelve la lista VACÍA', () async {
    final r = await repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
    final arbol = await r.repo.arbolDe(await r.repo.head);
    expect(
      await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt', 'b.txt']),
      isEmpty,
    );
  });

  test('una ruta preparada con otro contenido sale en la lista', () async {
    final r = await repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
    final arbol = await r.repo.arbolDe(await r.repo.head);
    await r.escribirYPreparar('a.txt', 'CAMBIADO');
    expect(
      await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt', 'b.txt']),
      ['a.txt'],
    );
  });

  test('un cambio preparado FUERA de las rutas NO se reporta: no es nuestro',
      () async {
    final r = await repoConArchivos({'a.txt': 'uno', 'ajeno.txt': 'dos'});
    final arbol = await r.repo.arbolDe(await r.repo.head);
    await r.escribirYPreparar('ajeno.txt', 'CAMBIADO');
    expect(
      await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt']),
      isEmpty,
      reason: 'el reintento no es dueño del índice del usuario: opinar sobre '
          'una ruta ajena rechazaría lo que apply promete preservar',
    );
  });

  test('un mtime tocado con el MISMO contenido no es una diferencia', () async {
    final r = await repoConArchivos({'a.txt': 'uno'});
    final arbol = await r.repo.arbolDe(await r.repo.head);
    await r.tocarSinCambiarContenido('a.txt');
    expect(
      await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt']),
      isEmpty,
      reason: 'sin el refresh previo, git compara metadatos y esto saldría '
          'como diferente sobre un índice que coincide',
    );
  });

  test('una ruta borrada del índice también es una diferencia', () async {
    final r = await repoConArchivos({'a.txt': 'uno', 'b.txt': 'dos'});
    final arbol = await r.repo.arbolDe(await r.repo.head);
    await r.quitarDelIndice('a.txt');
    expect(
      await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: ['a.txt']),
      ['a.txt'],
    );
  });

  test('la lista de rutas VACÍA no significa «todas»', () async {
    final r = await repoConArchivos({'a.txt': 'uno'});
    final arbol = await r.repo.arbolDe(await r.repo.head);
    await r.escribirYPreparar('a.txt', 'CAMBIADO');
    expect(
      await r.repo.rutasQueDifierenDelArbol(arbol: arbol, rutas: const []),
      isEmpty,
      reason: 'sin rutas no hay nada sobre lo que opinar; tratarlo como '
          '«todas» convertiría un alcance vacío en el más ancho posible',
    );
  });
```

Escribí los ayudantes `repoConArchivos`, `escribirYPreparar`, `tocarSinCambiarContenido` y `quitarDelIndice` en el mismo archivo, con `git` de verdad.

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/vcs/test/indice_test.dart
```
Esperado: FALLA, «The method 'rutasQueDifierenDelArbol' isn't defined».

- [ ] **Paso 3: implementar**

`packages/vcs/lib/src/indice.dart` lleva la lógica pura de armar la invocación y leer su salida; el método de `RepositorioGit` lanza el proceso, porque **lanzar es de la clase que tiene el lanzador saneado**.

```dart
  /// Las rutas, de entre [rutas], donde el índice del usuario NO coincide con
  /// [arbol]. **Vacía significa que coincide.**
  ///
  /// **Acotada a [rutas] a propósito.** Comparar el índice entero rechazaría
  /// los cambios preparados ajenos que la operación de aplicar promete
  /// preservar: el reintento no es dueño del índice de quien corre, y solo
  /// puede opinar sobre las rutas que la rebanada declaró.
  ///
  /// **Con [rutas] vacía devuelve vacío, y no «todas».** Un alcance vacío es
  /// el más angosto, no el más ancho; la confusión contraria convierte un
  /// control en uno que mira todo el repositorio sin que nadie lo pidiera.
  ///
  /// **El refresco previo no es opcional.** Sin él, un archivo con fecha
  /// tocada y contenido idéntico se informa como diferente, y el reintento
  /// fallaría cerrado sobre un índice que sí coincide.
  Future<List<String>> rutasQueDifierenDelArbol({
    required String arbol,
    required List<String> rutas,
  }) async {
    if (rutas.isEmpty) return const [];
    await _exigir(['update-index', '-q', '--refresh', '--', ...rutas]);
    final crudo = await _exigirBytes([
      'diff-index', '--raw', '-z', '--cached', arbol, '--', ...rutas,
    ]);
    return rutasDeDiffRaw(crudo);
  }
```

En `indice.dart`, `rutasDeDiffRaw` envuelve al parser que ya existe y devuelve solo las rutas, ordenadas. **Reusá `leerDiffRaw` de `alteraciones.dart`; no escribas un segundo parser** — dos parsers del mismo formato divergen.

**Ojo con `update-index --refresh`:** devuelve código distinto de cero cuando hay archivos que necesitaban refresco. Si `_exigir` lo trata como fallo, usá la variante que no exige el código, y **decilo en el reporte con la medición**.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/vcs
dart analyze --fatal-infos
```

- [ ] **Paso 5: medir las mutaciones**

1. Sacar el `--refresh` → muere la del `mtime`.
2. Sacar el `-- ...rutas` del `diff-index` → muere la del cambio ajeno.
3. Devolver «todas» con la lista vacía → muere la última.

- [ ] **Paso 6: commitear**

```bash
git add packages/vcs/lib/src/indice.dart packages/vcs/lib/src/repositorio.dart packages/vcs/lib/vcs.dart packages/vcs/test/indice_test.dart
git commit -m "El índice se compara solo donde la rebanada declaró

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 3: Las rutas de la rebanada, persistidas

**Archivos:**
- Modificar: `packages/core/lib/src/publicacion.dart` (`PullRequestDraft`)
- Modificar: `packages/core/lib/src/documento.dart` (el párrafo de la ventana de versión)
- Modificar: `packages/cli/lib/src/ship/ship.dart` (quien construye el borrador)
- Test: `packages/core/test/publicacion_test.dart`, `packages/core/test/serializacion_test.dart`

**Interfaces:**
- Produce: `PullRequestDraft.rutas` — `List<String>`, no vacía, sin repetidos, ordenada.

**La decisión ya está tomada** (`decisiones-4c.md`, D1) y **no se re-litiga**: las rutas se persisten, no se derivan de un `diff-tree`. Derivarlas al reintentar crea una segunda fuente del mismo hecho, y achica el alcance en silencio — una ruta declarada cuyo contenido no cambió saldría del control del índice.

**La versión del documento NO sube.** Su doc ya argumenta por qué —ninguna rebanada del comando se integró, así que ningún documento con la forma vieja existe en el disco de nadie— y ese argumento sigue en pie. **Lo que sí hay que hacer es precisar ese párrafo:** hoy dice que la ventana se cierra cuando se integre `4a`, y son **tres** rebanadas apiladas que llegan juntas. Reescribilo para que diga que la ventana se cierra cuando llega la pila, y **agregá este cambio de forma a la lista de los que entraron adentro de la ventana, con su fecha**. Una ventana con la lista de lo que pasó por ella es auditable; una sin la lista es una excusa.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el borrador lleva las rutas de la rebanada', () {
    final d = borradorDePrueba(rutas: const ['lib/a.dart', 'lib/b.dart']);
    expect(d.rutas, ['lib/a.dart', 'lib/b.dart']);
  });

  test('un borrador SIN rutas no se construye', () {
    expect(
      () => borradorDePrueba(rutas: const []),
      throwsArgumentError,
      reason: 'una rebanada sin archivos no es una rebanada, y el paso 4 de '
          'la reconciliación no tendría sobre qué opinar',
    );
  });

  test('las rutas repetidas no se construyen', () {
    expect(
      () => borradorDePrueba(rutas: const ['a.txt', 'a.txt']),
      throwsArgumentError,
    );
  });

  test('las rutas viajan en la ida y vuelta', () {
    final d = borradorDePrueba(rutas: const ['lib/b.dart', 'lib/a.dart']);
    expect(PullRequestDraft.fromJson(d.toJson()).rutas, d.rutas);
  });

  test('un JSON sin rutas falla NOMBRANDO la versión', () {
    final json = borradorDePrueba(rutas: const ['a.txt']).toJson()
      ..remove('rutas');
    expect(
      () => PullRequestDraft.fromJson(json),
      throwsA(isA<FormatException>().having(
        (e) => e.message, 'mensaje', contains('formatVersion'))),
      reason: 'quien lo lea tiene que entender «esta es una forma más vieja», '
          'no «este JSON está roto»',
    );
  });
```

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/core
```

- [ ] **Paso 3: implementar**

Agregá el campo, su validación en el constructor y su ida y vuelta. Y **buscá el verificador de serialización** del proyecto: hay una suite que compara `toJson`/`fromJson` **campo por campo** sobre instancias canónicas, y una instancia canónica incompleta ya produjo un falso verde en dos rebanadas distintas. **La instancia canónica del borrador tiene que llevar más de una ruta**, no una: con una sola, un `toJson` que escribiera la primera y perdiera el resto pasaría.

- [ ] **Paso 4: llenar el campo desde el comando**

En `packages/cli/lib/src/ship/ship.dart`, donde se construye el borrador. Las rutas ya están resueltas ahí: son las de la rebanada que el comando interpretó. **No las vuelvas a derivar.**

- [ ] **Paso 5: correr todo**

```
dart test packages
dart analyze --fatal-infos
```

- [ ] **Paso 6: medir la mutación**

`toJson` escribe `rutas.take(1).toList()` → tiene que morir la prueba de ida y vuelta. Si no muere, la instancia canónica tiene una sola ruta y el falso verde está puesto otra vez.

- [ ] **Paso 7: commitear**

```bash
git add packages/core packages/cli/lib/src/ship/ship.dart
git commit -m "Las rutas de la rebanada son un hecho de la corrida, no algo a re-derivar

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 4: La arista condicionada del estado inconsistente

**Archivos:**
- Modificar: `packages/core/lib/src/documento.dart`
- Test: `packages/core/test/documento_test.dart`

**Interfaces:**
- Produce: la transición `localInconsistent → committed` en el mapa, y su condición escrita.

**Por qué.** §9 exige que el reintento, cuando comprueba que el índice **ya** coincide con la revisión, promueva a `committed` y publique. El mapa declara hoy ese estado **terminal**, y hay una prueba que lo fija. **§9 es la autoridad**: la arista entra.

**Lo que NO se hace.** No se abre como una entrada suelta más del mapa sin más. El doc de la transición ya argumenta que devolver un documento nuevo, en vez de mutar, es lo que impide que la comprobación se degrade de invariante a costumbre. Una arista que cualquiera puede tomar sin condición es la misma degradación. **Escribí en el doc del mapa qué la condiciona** —solo por el camino del reintento, solo con el índice verificado contra la revisión— y **quién** la puede tomar. La condición vive en el llamador (T9); lo que vive acá es que esté dicha.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('desde el estado inconsistente se puede promover a commiteado', () {
    final d = documentoDePrueba(EstadoDelDocumento.localInconsistent);
    expect(
      d.avanzarA(EstadoDelDocumento.committed).estado,
      EstadoDelDocumento.committed,
    );
  });

  test('y NADA MÁS: sigue sin ir a ningún otro lado', () {
    final d = documentoDePrueba(EstadoDelDocumento.localInconsistent);
    for (final destino in [
      EstadoDelDocumento.prepared,
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.localInconsistent,
      EstadoDelDocumento.publicationComplete,
      EstadoDelDocumento.publicationIncomplete,
    ]) {
      expect(() => d.avanzarA(destino), throwsStateError, reason: destino.name);
    }
  });

  test('los terminales ahora son DOS, y eso queda fijado', () {
    final terminales = EstadoDelDocumento.values
        .where((e) => DocumentoDeCorrida.destinosDe(e).isEmpty)
        .toSet();
    expect(terminales, {
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.publicationComplete,
    });
  });
```

**La prueba vieja que decía «los TRES estados terminales lo son» queda falsa: corregila, no la borres**, y dejá dicho en su nombre o su razón que el estado inconsistente dejó de serlo y por qué.

Si `destinosDe` no existe, agregalo como lectura pública del mapa —la prueba no puede leer un `const` privado— y documentá que existe **para que la prueba derive los terminales en vez de listarlos**: una lista escrita a mano envejece sin avisar, que es justamente lo que pasó con la anterior.

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/core/test/documento_test.dart
```

- [ ] **Paso 3: implementar**

Agregá `EstadoDelDocumento.committed` al conjunto del estado inconsistente, y escribí en el doc del mapa la condición y su porqué.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/core
```

- [ ] **Paso 5: commitear**

```bash
git add packages/core
git commit -m "El estado inconsistente deja de ser terminal, con su condición dicha

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 5: La entrada `--retry-publication <runId>`

**Archivos:**
- Modificar: `packages/cli/lib/src/ship/entrada.dart`, `packages/cli/lib/src/comando.dart` (la ayuda), `packages/cli/lib/src/ship/composicion.dart` (la ayuda del comando)
- Test: `packages/cli/test/entrada_test.dart`, `packages/cli/test/comando_test.dart`

**Interfaces:**
- Produce: `EntradaDeShip.reintentarPublicacion` — `String?`, el identificador de corrida, nulo cuando no se pidió reintento.

**El estado de hoy, medido `[P]`:** cinco mensajes de acción siguiente ya nombran `--retry-publication`, y la bandera **no existe**: `shipflow ship --retry-publication r-1` sale con `5`, «bandera desconocida». **El CLI le está diciendo a quien corre que use algo que él mismo rechaza.**

**La exclusión mutua.** Un reintento no declara una rebanada: la rebanada está en el documento. Pasar `--file`, `--slice` o `--intent` junto con el reintento es una contradicción, no una preferencia — y este proyecto ya decidió una vez que **dos afirmaciones contradictorias sobre el mismo hecho no se resuelven eligiendo una**, porque eso convierte una contradicción en una preferencia, en silencio. Falla, nombrando las dos.

**Qué banderas SÍ conviven.** `--yes` y `--allow-incomplete` **no** se aceptan con el reintento: la compuerta ya pasó y volver a ofrecerlas sugiere que se puede volver a decidir. `--dry-run` **sí**: un ensayo del reintento es legítimo y no escribe nada.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('la bandera lleva el identificador de la corrida', () {
    final e = interpretarShip(['--retry-publication', 'r-1']);
    expect(e.reintentarPublicacion, 'r-1');
  });

  test('sin valor, falla nombrando la bandera', () {
    expect(
      () => interpretarShip(['--retry-publication']),
      throwsA(isA<UsoInvalido>().having(
        (e) => e.motivo, 'motivo', contains('--retry-publication'))),
    );
  });

  test('un valor que es otra bandera no es un identificador', () {
    expect(
      () => interpretarShip(['--retry-publication', '--yes']),
      throwsA(isA<UsoInvalido>()),
    );
  });

  for (final ajena in ['--file', '--slice', '--intent']) {
    test('$ajena con el reintento es una CONTRADICCIÓN, no una preferencia', () {
      expect(
        () => interpretarShip(['--retry-publication', 'r-1', ajena, 'x']),
        throwsA(isA<UsoInvalido>()
            .having((e) => e.motivo, 'motivo', contains('--retry-publication'))
            .having((e) => e.motivo, 'motivo', contains(ajena))),
        reason: 'la rebanada está en el documento; declararla otra vez afirma '
            'dos cosas sobre el mismo hecho',
      );
    });
  }

  for (final ajena in ['--yes', '--allow-incomplete']) {
    test('$ajena con el reintento se rechaza: la compuerta ya pasó', () {
      expect(
        () => interpretarShip(['--retry-publication', 'r-1', ajena]),
        throwsA(isA<UsoInvalido>()),
      );
    });
  }

  test('--dry-run SÍ convive: un ensayo del reintento no escribe nada', () {
    final e = interpretarShip(['--retry-publication', 'r-1', '--dry-run']);
    expect(e.reintentarPublicacion, 'r-1');
    expect(e.dryRun, isTrue);
  });

  test('sin la bandera, el campo es nulo y ship se interpreta como siempre', () {
    final e = interpretarShip(['--intent', 'x', '--file', 'a.txt']);
    expect(e.reintentarPublicacion, isNull);
  });
```

Y en `comando_test.dart`, anclado a su línea como ya se hace con el resto:

```dart
  test('las dos ayudas nombran el reintento', () async {
    for (final texto in [await ayudaDePrueba(), ayudaDeShip]) {
      expect(texto, contains('--retry-publication'), reason: texto.split('\n').first);
    }
  });
```

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/cli/test/entrada_test.dart
```

- [ ] **Paso 3: implementar**

`interpretarShip` sigue **pura**: no lee disco. Reusá la guardia que ya rechaza un valor que empieza con dos guiones, y la función factorizada que rechaza repetidos. **No copies lógica: las dos existen.**

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/cli
dart analyze --fatal-infos
```

- [ ] **Paso 5: medir la mutación**

Sacar la exclusión mutua de `--file` → tiene que morir su prueba y **ninguna otra**.

- [ ] **Paso 6: commitear**

```bash
git add packages/cli
git commit -m "El CLI deja de recomendar una bandera que él mismo rechaza

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 6: El filtro por estado, y la rama

**Archivos:**
- Modificar: `packages/cli/lib/src/corrida.dart`
- Test: `packages/cli/test/corrida_test.dart`

**Interfaces:**
- Consume: `DocumentoDeCorrida`, `EstadoDelDocumento`, `decidirRecuperacion`.
- Produce: `sealed class PuertaDelReintento` con las variantes `Reconciliar`, `PublicarDirecto` y `NoSeReintenta(CausaDeNoReintento)`; `PuertaDelReintento puertaDelReintento({required DocumentoDeCorrida documento, required String ramaActual})`.

**Por qué esta tarea llega temprano.** La comparación de tres casos declara en su doc que **no filtra por estado**, que eso es una precondición, y que asegurarla es de esta rebanada. Medido `[P]`: **en cinco de los seis estados su respuesta es inútil o falsa, y en cuatro de ellos obedecerla termina en un error de estado** que sale por la red de último recurso como «se rompió el arnés» sobre una corrida donde no se rompió nada. El filtro no es un adorno: es lo único que separa esa función de un error en producción.

**El hueco que su doc NO declara, y que esta tarea cierra:** la comparación **no mira la rama**. La operación que aplica la revisión sí la compara antes que nada `[P]`. Quien esté parado en otra rama cuyo `HEAD` coincida con la base recibe hoy «reintentá el compare-and-swap», y reintentarlo movería **otra** rama.

**La tabla, de §9 enmendada.** Los seis estados:

| Estado | Qué hace el reintento |
|---|---|
| `prepared` | **Reconciliar** los cinco pasos (T8) |
| `committed` | **Publicar directo**: no hay nada que reconciliar |
| `publicationIncomplete` | **Publicar directo**: es el caso que §9 declara reintentable |
| `publicationComplete` | **No se reintenta**: ya está publicado. Código de éxito, y decir dónde |
| `notApplied` | **No se reintenta**: §9 lo dice por su nombre, no hay entrega que recuperar. La acción siguiente es volver a correr `ship` |
| `localInconsistent` | **Reconciliar**, pero por el otro camino: comprobar el índice (T9) |

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('los SEIS estados tienen respuesta, y ninguna es un error de estado', () {
    for (final estado in EstadoDelDocumento.values) {
      expect(
        () => puertaDelReintento(
          documento: documentoEn(estado),
          ramaActual: 'feature/x',
        ),
        returnsNormally,
        reason: estado.name,
      );
    }
  });

  test('desde commiteado se publica directo', () {
    expect(
      puertaDelReintento(documento: documentoEn(EstadoDelDocumento.committed),
          ramaActual: 'feature/x'),
      isA<PublicarDirecto>(),
    );
  });

  test('desde una publicación incompleta también', () {
    expect(
      puertaDelReintento(
          documento: documentoEn(EstadoDelDocumento.publicationIncomplete),
          ramaActual: 'feature/x'),
      isA<PublicarDirecto>(),
    );
  });

  test('desde preparado se reconcilia', () {
    expect(
      puertaDelReintento(documento: documentoEn(EstadoDelDocumento.prepared),
          ramaActual: 'feature/x'),
      isA<Reconciliar>(),
    );
  });

  test('una publicación completa NO se reintenta, y lo dice', () {
    final p = puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.publicationComplete),
        ramaActual: 'feature/x');
    expect(p, isA<NoSeReintenta>());
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.yaPublicado);
  });

  test('un CAS rechazado NO se reintenta: no hay entrega que recuperar', () {
    final p = puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.notApplied),
        ramaActual: 'feature/x');
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.nadaQueEntregar);
  });

  test('parado en OTRA rama no se reintenta, aunque el HEAD coincida', () {
    final p = puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.committed),
        ramaActual: 'otra-rama');
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.ramaDistinta);
    expect(p.detalle, allOf(contains('feature/x'), contains('otra-rama')),
        reason: 'un mensaje que no nombra las dos ramas no dice qué hacer');
  });

  test('la rama se comprueba ANTES que el estado', () {
    final p = puertaDelReintento(
        documento: documentoEn(EstadoDelDocumento.publicationComplete),
        ramaActual: 'otra-rama');
    expect((p as NoSeReintenta).causa, CausaDeNoReintento.ramaDistinta,
        reason: 'estar en otra rama vuelve irrelevante cualquier cosa que el '
            'estado diga: lo que se leyó no es del repositorio que se mira');
  });
```

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/cli/test/corrida_test.dart
```

- [ ] **Paso 3: implementar**

El `switch` sobre `EstadoDelDocumento` es **exhaustivo y sin comodín**: un estado nuevo no compila hasta que alguien decida qué hace el reintento con él. Ese es el mismo criterio que la rebanada anterior instaló para la compuerta por estado, después de encontrar que un `!=` dejaba compilar un estado nuevo y reventaba después del pull request.

Y actualizá el doc de la comparación de tres casos: su párrafo dice que el llamador «todavía no existe». Ya existe. **Nombralo y decí que el filtro está puesto**, para que el próximo que lo lea no vuelva a preguntárselo.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/cli
dart analyze --fatal-infos
```

- [ ] **Paso 5: medir las mutaciones**

1. Mover la comprobación de la rama después del `switch` → muere la última.
2. Devolver `PublicarDirecto` para el estado ya publicado → muere la suya.
3. Agregar un comodín al `switch` → **no** rompe ninguna prueba, y ese es el punto: lo que fuerza la decisión es el compilador. Decilo en el reporte.

- [ ] **Paso 6: commitear**

```bash
git add packages/cli
git commit -m "La precondición que la comparación de tres casos delegaba, puesta

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 7: El desenlace de un reintento

**Archivos:**
- Modificar: `packages/core/lib/src/corrida.dart`
- Test: `packages/core/test/corrida_test.dart`

**Interfaces:**
- Produce: `static ShipOutcome ShipOutcome.derivarReintento({required EstadoPublicable verificacion, required PublicationOutcome remoto})`.

**La decisión ya está tomada** (`decisiones-4c.md`, D3) y **no se re-litiga.**

**El problema, medido `[P]`.** La fábrica que existe vuelve a evaluar la compuerta por estado, y la bandera de incompleto **no está persistida**. Un reintento sobre una corrida que se autorizó incompleta y ya commiteó, sin volver a pasar la bandera, deriva «no intentado» — y el sellado revienta con un chequeo de nulo, porque ese desenlace no afirma ningún estado del documento. Compila igual y falla en tiempo de ejecución.

**Por qué una segunda entrada y no un parámetro más.** La compuerta ya pasó, y **que haya pasado es lo que `committed` significa**. La única forma de que la fábrica actual conteste bien sería alimentarla con hechos fabricados —«se confirmó», «autoriza incompleto»—, que es **exactamente** el defecto que la rebanada anterior cerró: los constructores privados impiden elegir la variante, así que se terminaba eligiendo el hecho. Una corrida que ya commiteó tiene un conjunto de hechos distinto, y la precedencia de la otra fábrica no aplica a ninguno.

**No hace falta ningún campo nuevo** para el estado de verificación: viaja en el documento, adentro del artefacto del borrador, en la superficie `[P]`.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('un reintento que publica da Publicado, sin pasar por ninguna compuerta',
      () {
    final d = ShipOutcome.derivarReintento(
      verificacion: EstadoPublicable.rojo,
      remoto: PullRequestOpen(url: 'https://forja/pr/1', numero: 1),
    );
    expect(d, isA<Publicado>());
    expect((d as Publicado).verificacion, EstadoPublicable.rojo,
        reason: 'la corrida era roja y se autorizó en su momento; volver a '
            'evaluarlo sería decidir de nuevo algo ya decidido y registrado');
  });

  test('un reintento cuya publicación no es utilizable da entrega incompleta',
      () {
    final d = ShipOutcome.derivarReintento(
      verificacion: EstadoPublicable.verde,
      remoto: PushUnknown(causa: CausaDePublicacion.red),
    );
    expect(d, isA<PublicacionIncompleta>());
  });

  test('de esta fábrica NO pueden salir las otras tres variantes', () {
    for (final remoto in desenlacesRemotosCanonicos) {
      final d = ShipOutcome.derivarReintento(
          verificacion: EstadoPublicable.verde, remoto: remoto);
      expect(d, anyOf(isA<Publicado>(), isA<PublicacionIncompleta>()),
          reason: '$remoto');
    }
  });

  test('la fábrica del reintento no acepta un estado no publicable', () {
    // EstadoPublicable no tiene errorInterno: la garantía es del TIPO y esta
    // prueba fija que sigue siéndolo, no que alguien la compruebe.
    expect(EstadoPublicable.values.map((e) => e.name),
        isNot(contains('errorInterno')));
  });
```

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/core/test/corrida_test.dart
```

- [ ] **Paso 3: implementar**

```dart
  /// El desenlace de una corrida **cuyas compuertas son historia**.
  ///
  /// **Por qué existe, y por qué no es un parámetro más de [derivar].** Una
  /// corrida que llegó a commitear ya pasó el secreto, la compuerta por estado
  /// y la confirmación: que hayan pasado es lo que su estado SIGNIFICA.
  /// Volverlas a evaluar es volver a decidir algo ya decidido y ya registrado,
  /// y la única forma de que [derivar] conteste bien sobre un reintento sería
  /// pasarle hechos fabricados —«se confirmó», «autoriza incompleto»— que
  /// nadie midió en esa corrida. Los constructores privados impiden elegir la
  /// variante; alimentarla con hechos falsos es elegirla igual, un nivel más
  /// arriba.
  ///
  /// **De acá salen dos variantes y no cinco**, porque los hechos que producen
  /// las otras tres ya no pueden ocurrir: la compuerta no se vuelve a correr,
  /// el compare-and-swap ya corrió, y el índice se comprueba antes de llegar
  /// acá.
  static ShipOutcome derivarReintento({
    required EstadoPublicable verificacion,
    required PublicationOutcome remoto,
  }) => switch (remoto) {
        PublicacionUtilizable() =>
            Publicado._(pr: remoto, verificacion: verificacion),
        PublicacionNoUtilizable() =>
            PublicacionIncompleta._(remoto: remoto, verificacion: verificacion),
      };
```

**Actualizá el doc de la clase sellada**: hoy dice que la fábrica es «la única entrada real». Ahora son dos, y el doc tiene que decir **cuál para qué** y por qué no son la misma. Un doc que dice «la única» cuando hay dos es la clase de motivo falso que la rebanada anterior pagó caro.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/core
```

- [ ] **Paso 5: medir la mutación**

Hacer que `derivarReintento` llame a `derivar` con `seConfirmo: true, autorizaIncompleto: true, soloPreview: false, huboSecreto: false` → **tiene que morir la primera prueba**, la de la corrida roja. Si no muere, la prueba no está midiendo la compuerta.

- [ ] **Paso 6: commitear**

```bash
git add packages/core
git commit -m "Una corrida que ya commiteó tiene otros hechos: su propia fábrica

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 8: La reconciliación desde `prepared`, los cinco pasos

**Archivos:**
- Modificar: `packages/cli/lib/src/corrida.dart`
- Test: `packages/cli/test/corrida_test.dart`

**Interfaces:**
- Consume: `RepositorioGit.head`, `padreDe`, `arbolDe`, `mensajeDe`, `rutasQueDifierenDelArbol` (T1, T2); `decidirRecuperacion`, `puertaDelReintento` (T6).
- Produce: `class HechosDeLaRevision` — los cuatro hechos ya leídos: `String? padre`, `String arbol`, `String mensaje`, `List<String> rutasQueDifieren`. Y `sealed class Reconciliacion` con `Inequivoca(QueHacerAlRecuperar)` y `Ambigua(CausaDeAmbiguedad, String detalle)`; `Reconciliacion reconciliar({required DocumentoDeCorrida documento, required String headActual, required HechosDeLaRevision hechos})`.

**La decisión ya está tomada** (`decisiones-4c.md`, D2): las lecturas viven en el adapter de `git`, **la decisión es pura**. No le agregues lecturas a esta función. El motivo es una propiedad que no quiero gastar: la comparación de tres casos declara que no lee el repositorio y que por eso sus casos se prueban sin montar uno; la reconciliación tiene **cinco** pasos y más combinaciones, así que la propiedad vale más acá, no menos.

**Los cinco pasos, de §9.** En este orden:

1. el padre de la revisión candidata es la revisión base;
2. el árbol de la revisión es **exactamente** el contenido del candidato — igualdad de identificadores, no comparación de diferencias;
3. el mensaje coincide con el esperado;
4. el índice coincide, **solo en las rutas de la rebanada**;
5. promover **solo si es inequívoco**; ante cualquier ambigüedad, **fallar cerrado**.

**Qué significa fallar cerrado acá.** No promover, no publicar, salir con la acción precisa. Un reintento que adivina publica sobre un commit que nadie verificó que sea el suyo.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  HechosDeLaRevision hechosSanos(DocumentoDeCorrida d) => HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      );

  test('con los cinco pasos en orden, la reconciliación es inequívoca', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: hechosSanos(d),
    );
    expect(r, isA<Inequivoca>());
    expect((r as Inequivoca).queHacer, QueHacerAlRecuperar.promoverACommitted);
  });

  test('si el padre NO es la base, falla cerrado', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: 'otro' * 10,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.padreDistinto);
  });

  test('si el ÁRBOL difiere, falla cerrado aunque el padre coincida', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: 'a' * 40,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.contenidoDistinto);
  });

  test('si el MENSAJE difiere, falla cerrado', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: 'otra intención',
        rutasQueDifieren: const [],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.mensajeDistinto);
  });

  test('si el índice difiere EN LAS RUTAS, falla cerrado y las nombra', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: d.draft.artefacto.candidato.contentRevision,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const ['lib/a.dart'],
      ),
    );
    expect((r as Ambigua).causa, CausaDeAmbiguedad.indiceDistinto);
    expect(r.detalle, contains('lib/a.dart'),
        reason: 'una acción que no nombra el archivo no dice qué hacer');
  });

  test('con el HEAD en la base, los cinco pasos NO deciden: se reintenta el CAS',
      () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.draft.artefacto.candidato.baseRevision,
      hechos: hechosSanos(d),
      );
    expect((r as Inequivoca).queHacer, QueHacerAlRecuperar.reintentarElCas);
  });

  test('con un HEAD ajeno, alguien más avanzó y los cinco pasos son ociosos',
      () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: 'f' * 40,
      hechos: hechosSanos(d),
    );
    expect((r as Inequivoca).queHacer, QueHacerAlRecuperar.alguienMasAvanzo);
  });

  test('la ambigüedad GANA sobre los tres casos: no se promueve lo dudoso', () {
    final d = documentoPreparado();
    final r = reconciliar(
      documento: d,
      headActual: d.revision,
      hechos: HechosDeLaRevision(
        padre: d.draft.artefacto.candidato.baseRevision,
        arbol: 'a' * 40,
        mensaje: d.draft.artefacto.intent,
        rutasQueDifieren: const [],
      ),
    );
    expect(r, isA<Ambigua>(),
        reason: 'el HEAD coincide con la revisión, así que la comparación de '
            'tres casos diría «promover»; promoverlo publicaría sobre un '
            'commit que nadie verificó que sea el nuestro');
  });
```

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/cli/test/corrida_test.dart
```

- [ ] **Paso 3: implementar**

Los cinco pasos **solo se evalúan cuando la comparación de tres casos dice promover**: si el `HEAD` está en la base o en otra cosa, no hay ninguna revisión nuestra en la rama sobre la que opinar. Y cuando dice promover, **la ambigüedad gana**.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/cli
```

- [ ] **Paso 5: medir las mutaciones**

1. Evaluar los cinco pasos **antes** que los tres casos → muere la del `HEAD` en la base.
2. Dejar que los tres casos ganen sobre la ambigüedad → muere la última.
3. Comparar el árbol con `contains` en vez de igualdad → muere la del árbol.

- [ ] **Paso 6: commitear**

```bash
git add packages/cli
git commit -m "Los cinco pasos de §9, y la ambigüedad gana sobre los tres casos

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 9: La comprobación del índice desde el estado inconsistente

**Archivos:**
- Modificar: `packages/cli/lib/src/corrida.dart`
- Test: `packages/cli/test/corrida_test.dart`

**Interfaces:**
- Consume: `RepositorioGit.rutasQueDifierenDelArbol` (T2), la arista condicionada (T4).
- Produce: `sealed class IndiceDelReintento` con `IndiceCoincide` e `IndiceNoCoincide(List<String> rutas)`; `IndiceDelReintento comprobarIndice({required DocumentoDeCorrida documento, required List<String> rutasQueDifieren})`.

**Qué dice §9.** El reintento, desde el estado inconsistente, **comprueba que el índice YA coincide con la revisión**: si coincide promueve a `committed` y publica; si no, **falla cerrado, con la acción precisa**.

**Lo que el reintento NO hace**, y §9 lo dice por su nombre: **no vuelve a ejecutar la operación de aplicar**. Rodea el problema en vez de resolverlo — así no necesita distinguir «ya aplicada» de «plan mal declarado», que es lo que la guardia correspondiente no puede hacer sin marcar el commit.

**De dónde sale el desenlace que se lee** (`decisiones-4c.md`, D4): del documento sellado, **no de atrapar una excepción**. Medido `[P]`: el comando commitea por la operación del candidato, que ante ese fallo **devuelve** el desenlace en vez de lanzar; la función de `vcs` que sí lanza no tiene ningún llamador de producción. **No construyas nada sobre ella.**

**La acción siguiente tiene que nombrar la reparación concreta**, no decir «arreglá el índice». Es la regla dura: ninguna regla prohibitiva sin su alternativa.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el índice que coincide deja promover', () {
    final d = documentoInconsistente();
    expect(
      comprobarIndice(documento: d, rutasQueDifieren: const []),
      isA<IndiceCoincide>(),
    );
  });

  test('el índice que no coincide falla cerrado y NOMBRA las rutas', () {
    final d = documentoInconsistente();
    final r = comprobarIndice(
        documento: d, rutasQueDifieren: const ['lib/a.dart', 'lib/b.dart']);
    expect(r, isA<IndiceNoCoincide>());
    expect((r as IndiceNoCoincide).rutas, ['lib/a.dart', 'lib/b.dart']);
  });

  test('la promoción desde el estado inconsistente es legal', () {
    final d = documentoInconsistente();
    expect(
      d.avanzarA(EstadoDelDocumento.committed).estado,
      EstadoDelDocumento.committed,
      reason: 'sin la arista de la tarea 4 esto lanza, y el camino de §9 no '
          'sería construible',
    );
  });

  test('sobre un documento que NO está en ese estado, no se comprueba nada', () {
    expect(
      () => comprobarIndice(
          documento: documentoEn(EstadoDelDocumento.committed),
          rutasQueDifieren: const []),
      throwsStateError,
      reason: 'esta comprobación es la puerta de UN estado; usarla en otro '
          'promovería por una arista que ese estado no tiene',
    );
  });
```

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/cli/test/corrida_test.dart
```

- [ ] **Paso 3: implementar**

Y escribí el texto de la acción siguiente para el caso que falla: tiene que nombrar **las rutas** y **el comando concreto** que sincroniza el índice con la revisión. El candidato es `git reset <revision> -- <rutas>`, que reescribe el índice en esas rutas sin tocar el árbol de trabajo. **Corrélo y comprobá que deja el índice coincidiendo** antes de escribirlo en el mensaje: un consejo que no repara es peor que no darlo, porque quien lo siga va a creer que ya está.

- [ ] **Paso 4: correr y comprobar que pasan**

```
dart test packages/cli
```

- [ ] **Paso 5: medir la mutación**

Tratar la lista no vacía como coincidencia → muere la segunda y la promoción se haría sobre un índice sucio.

- [ ] **Paso 6: commitear**

```bash
git add packages/cli
git commit -m "El índice se comprueba antes de promover, y si no coincide se dice cómo

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 10: La publicación del reintento

**Archivos:**
- Crear: `packages/cli/lib/src/ship/reintento.dart`
- Modificar: `packages/cli/lib/src/ship/composicion.dart`, `packages/cli/lib/cli.dart`
- Test: `packages/cli/test/reintento_test.dart`, `packages/cli/test/comando_test.dart`

**Interfaces:**
- Consume: todo lo anterior, más `RegistroDeCorridas.leer`, `PullRequestSink.open`, `ShipOutcome.derivarReintento`, y los caminos de salida que ya existen.
- Produce: `Future<ShipOutcome> correrReintento({...})`, y la rama del comando que la invoca.

**Qué hace, en orden.** Leer el documento; si no existe, salir con configuración y decir dónde se buscó. Leer la rama y el `HEAD`. Pasar por la puerta (T6). Según lo que diga: reconciliar (T8), comprobar el índice (T9), o publicar directo. Reconstruir la solicitud del pull request **desde el documento**, publicar, derivar el desenlace con la fábrica del reintento (T7), sellar el documento y devolverlo.

**Lo que NO vuelve a correr:** la cascada, la detección de secretos, la compuerta, la confirmación. El documento lleva el borrador completo justamente para eso.

**El tercer argumento de la solicitud NO es un dato del documento: es una medición.** El constructor de la solicitud exige el árbol de la revisión y valida su relación con ella. Pasarle el contenido del candidato satisface el constructor comparando el valor **contra sí mismo** y vacía la guarda `[P]`. **El árbol se lee del repositorio** (T1), y **que coincida con el del candidato es justamente el paso 2 de la reconciliación**, no una suposición.

**La idempotencia entre procesos es lo que hace seguro todo esto, y no está verificada.** La búsqueda por marcador estable está escrita, y §17 pide su prueba, pero **no se midió que esa prueba exista entre procesos distintos** `[P]`. Esta tarea la escribe: un reintento sobre una corrida cuyo pull request ya se abrió **no abre un segundo**. Si el mecanismo no alcanza, **decilo y paralo** — un segundo pull request es el fallo más caro que esta rebanada puede producir.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('un identificador que no existe sale con configuración y dice dónde buscó',
      () async {
    final m = await MundoDeReintento.nuevo();
    final r = await m.correr('r-inexistente');
    expect(m.codigo(r), Codigo.errorDeConfiguracion);
    expect(m.mensaje, contains('runs'));
  });

  test('desde commiteado publica y sella, SIN correr la cascada', () async {
    final m = await MundoDeReintento.conDocumentoEn(EstadoDelDocumento.committed);
    final d = await m.correr(m.runId);
    expect(d, isA<Publicado>());
    expect(m.forja.recibidas, hasLength(1));
    expect(m.cascadasCorridas, 0,
        reason: 'el documento lleva el borrador completo justamente para que '
            'la recuperación no vuelva a verificar nada');
    expect((await m.documento()).estado, EstadoDelDocumento.publicationComplete);
  });

  test('el árbol de la solicitud se MIDE, no se copia del documento', () async {
    final m = await MundoDeReintento.conDocumentoEn(EstadoDelDocumento.committed);
    await m.correr(m.runId);
    expect(m.forja.recibidas.single.arbolDeLaRevision, m.arbolLeidoDelRepo,
        reason: 'copiar el contenido del candidato satisface el constructor '
            'comparando el valor contra sí mismo y vacía su guarda');
  });

  test('una corrida ROJA autorizada en su momento se publica igual', () async {
    final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.committed, verificacion: EstadoDeCorrida.rojo);
    final d = await m.correr(m.runId);
    expect(d, isA<Publicado>());
    expect((d as Publicado).verificacion, EstadoPublicable.rojo,
        reason: 'la compuerta pasó cuando la corrida corrió; volver a '
            'evaluarla acá derivaría NoIntentado y el sellado reventaría');
  });

  test('desde una publicación incompleta reintenta y completa', () async {
    final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.publicationIncomplete);
    final d = await m.correr(m.runId);
    expect(d, isA<Publicado>());
  });

  test('UN SEGUNDO reintento NO abre un segundo pull request', () async {
    final m = await MundoDeReintento.conDocumentoEn(EstadoDelDocumento.committed);
    await m.correr(m.runId);
    final segundo = await m.correr(m.runId);
    expect(m.forja.pullRequestsAbiertos, 1,
        reason: 'es el fallo más caro que esta rebanada puede producir');
    expect(segundo, isA<Publicado>());
  });

  test('una corrida ya publicada NO se reintenta, y sale con éxito diciendo dónde',
      () async {
    final m = await MundoDeReintento.conDocumentoEn(
        EstadoDelDocumento.publicationComplete);
    final r = await m.correr(m.runId);
    expect(m.codigo(r), Codigo.exito);
    expect(m.mensaje, contains('http'));
    expect(m.forja.recibidas, isEmpty);
  });

  test('un CAS rechazado NO se reintenta, y manda a correr ship de nuevo',
      () async {
    final m = await MundoDeReintento.conDocumentoEn(EstadoDelDocumento.notApplied);
    await m.correr(m.runId);
    expect(m.accion, contains('ship'));
    expect(m.forja.recibidas, isEmpty);
  });

  test('--dry-run con reintento NO deja NADA: ni publicación ni sellado',
      () async {
    final m = await MundoDeReintento.conDocumentoEn(EstadoDelDocumento.committed);
    final antes = await m.documento();
    await m.correr(m.runId, dryRun: true);
    expect(m.forja.recibidas, isEmpty);
    expect((await m.documento()).estado, antes.estado);
  });

  test('desde preparado con reconciliación ambigua NO publica', () async {
    final m = await MundoDeReintento.conDocumentoEn(EstadoDelDocumento.prepared,
        mensajeDelCommit: 'otra cosa');
    await m.correr(m.runId);
    expect(m.forja.recibidas, isEmpty);
    expect(m.accion, isNotEmpty);
  });
```

`MundoDeReintento` **extiende** los adapters reales y registra **hechos** —qué recibió la forja, qué quedó en el documento, cuántas cascadas corrieron— en vez de contar llamadas. **La forja es un doble**, pero la búsqueda idempotente que la prueba del segundo reintento ejercita tiene que ser la del adapter real: si el doble la simula, la prueba mide el doble. **Decí en el reporte cómo lo resolviste.**

- [ ] **Paso 2: correr y comprobar que fallan**

```
dart test packages/cli/test/reintento_test.dart
```

- [ ] **Paso 3: implementar, y cablear lo que las otras tareas produjeron**

Esta es la única tarea que junta todo, así que el cableado va explícito:

- `hechos` para la reconciliación (T8) se arma con las cuatro lecturas de T1:
  `padre: await repo.padreDe(documento.revision)`,
  `arbol: await repo.arbolDe(documento.revision)`,
  `mensaje: await repo.mensajeDe(documento.revision)`, y
  `rutasQueDifieren: await repo.rutasQueDifierenDelArbol(arbol: documento.draft.artefacto.candidato.contentRevision, rutas: documento.draft.rutas)` — T2 con las rutas que T3 persistió.
- `headActual` sale de `await repo.head` (T1). La comparación de tres casos lo pide
  como argumento a propósito: no lee el repositorio.
- `ramaActual` sale de `await repo.ramaActual`, que ya existía.
- El árbol del tercer argumento de la solicitud es **el mismo `await repo.arbolDe(...)`**
  que alimenta el paso 2, no una segunda lectura: dos lecturas del mismo hecho pueden
  discrepar entre sí y entonces la guarda del constructor validaría contra una y el
  paso 2 contra la otra.

Y en el comando, la rama que entra al reintento cuando la bandera está puesta. **La previsualización y la confirmación no aplican**: no hay nada que autorizar que no se haya autorizado ya.

- [ ] **Paso 4: el payload y los códigos**

Los cinco mensajes de acción siguiente que ya nombran la bandera pasan a ser ciertos. Comprobá que cada uno mande al camino que efectivamente existe ahora, y **corregí el que no** — un consejo que nombra un camino que no lleva a ninguna parte es peor que no darlo.

- [ ] **Paso 5: correr todo**

```
dart test packages
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart && cd ../..
python3 tool/checks/capas.py
```

- [ ] **Paso 6: medir las mutaciones**

1. Copiar el contenido del candidato como árbol de la solicitud → muere la tercera.
2. Usar la fábrica vieja del desenlace → muere la de la corrida roja.
3. Sacar el corte de `--dry-run` → muere la suya.
4. Sacar la búsqueda idempotente del adapter → muere la del segundo reintento.

- [ ] **Paso 7: commitear**

```bash
git add packages/cli
git commit -m "El reintento publica desde el documento, sin volver a verificar nada

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 11: El cierre — declaraciones, grafo y arnés entero

**Archivos:**
- Modificar: `arquitectura.json`, `README.md`, `grafo.jsonl`

- [ ] **Paso 1: enlazar el plan desde el README, TEMPRANO**

El generador del grafo trata un archivo que ningún punto de entrada alcanza como huérfano, y ese rojo arrastra al control de capas. **Hacelo apenas empieces la tarea**, no al final: un rojo que tapa a otro ya costó ocho tareas en una rebanada anterior, y en la siguiente el control llegó a reportar algo **falso** por la misma causa.

- [ ] **Paso 2: los puertos y las funciones que salen de sus listas**

Revisá `sin_implementacion` y cualquier entrada que esta rebanada haya vuelto vencida. La convención del mapa es decir **con cuántas implementaciones salió** cada puerto y qué le falta.

Y buscá, midiendo: el README declara **dos veces** que la comparación de tres casos «sigue sin productor» `[P]`. Ya lo tiene. Ponelo al día.

- [ ] **Paso 3: documentar la rebanada y sus residuos**

Los que tienen que quedar escritos:

- **El reintento no vuelve a correr la cascada, ni la compuerta, ni la detección de secretos.** El documento lleva el borrador completo para eso, y la fábrica del desenlace del reintento existe para no tener que mentirle a la otra.
- **El reintento no vuelve a ejecutar la operación de aplicar**, y por eso no necesita distinguir «ya aplicada» de «plan mal declarado».
- **La función de `vcs` que aplica sigue sin ningún llamador de producción**, medido. §9 dice por su nombre que el reintento no la ejecuta, así que el residuo que la rebanada anterior dejó abierto —«superficie de 4c o camino obsoleto»— **se resuelve del lado obsoleto**. Su retiro no es de esta rebanada: lo que corresponde acá es dejar medido que sigue sin llamador, para que la próxima no vuelva a preguntárselo.
- **La ventana de la versión del documento**, con la lista de los cambios de forma que entraron adentro y la fecha en que se cierra.
- **Un remoto por un canal que la publicación no acepta se rechaza antes de escribir**, y el reintento hereda eso.
- **Lo que esta rebanada NO hace**, en su propia sección: el modelo de corridas completo, la recuperación general, abortar, una segunda forja.

- [ ] **Paso 4: regenerar el grafo y correr los cuatro**

```
cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart && cd ../..
python3 tool/checks/capas.py
```

- [ ] **Paso 5: el arnés entero, solo, con el árbol limpio**

```
ARNES_ORIGEN=$(pwd) python3 tool/checks/probar_reglas.py
python3 tool/checks/probar_recuperacion.py
```

**Sin tocar nada mientras corre**, y con todo commiteado: trabaja sobre una copia privada y detecta cualquier cambio en el checkout, incluidas marcas de tiempo.

**Si da rojo, medilo contra el commit base en un worktree antes de atribuirlo.** En la rebanada anterior el primer rojo era un **canario que se había vuelto legítimo**: el árbol creció hasta que lo que declaraba como violación pasó a ser código correcto, y el rojo lo daba otra cosa. «Preexistente, no es mío» es la afirmación que no la verifica quien la hace.

- [ ] **Paso 6: commitear**

```bash
git add arquitectura.json README.md grafo.jsonl
git commit -m "El reintento, declarado: lo que recupera, lo que no vuelve a correr y lo que deja abierto

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Lo que esta rebanada NO construye

De §14, más lo que la ejecución fue decidiendo: `analyze`, `plan`, `implement`, `review`; el modelo de corridas completo, `resume` general, `abort`; una segunda forja; un almacén de credenciales real; el corte temprano y el presupuesto de corrida. Y el retiro de la función de `vcs` que aplica: se deja medida y declarada, no se toca.
