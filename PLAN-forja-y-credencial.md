# Forja y credencial — plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL REQUERIDA: usá
> `superpowers:subagent-driven-development` (recomendada) o
> `superpowers:executing-plans` para ejecutar este plan tarea por tarea. Los
> pasos usan casillas (`- [ ]`).

**Objetivo:** construir la salida del PR —`packages/forge/`, el adapter real de
GitHub— y el aislamiento de la credencial que esa salida vuelve necesario.

**Arquitectura:** la credencial entra al proceso por una variable de entorno y
sale del entorno del proceso **en un solo sitio**: `EntornoDelProceso` la
convierte en `Credential` y entrega hacia abajo un mapa que ya no la tiene. El
desenlace de la publicación es una jerarquía sellada con `retryable`,
`deliveryStatus` y `nextAction` **derivados** de la variante. El adapter de
GitHub lanza su propio `git push` con la cadena de ganchos y la de credential
helpers vaciadas, y habla con la API por `dart:io` sin dependencias externas.

**Stack:** Dart 3.11+, workspace de pub, `package:test`. Sin dependencias
externas nuevas.

**Especificación:**
`/Users/zeref/Documents/SDLC/sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md`
§10 y §11, con la enmienda `365cfc1`. Leé esas dos secciones enteras antes de
empezar: el plan argumenta desde ahí.

## Restricciones globales

- **`core` no tiene dependencias externas ni entrada/salida.** Lo aplican
  `nucleo-sin-externas` y `nucleo-sin-entrada-salida`. Todo lo que toque el
  mundo vive en otro paquete.
- **Ningún paquete nuevo ve más que `core`.** Solo `cli` ve a los plugins y a
  `forge`. Lo aplica `deps-hacia-core` con su mapa `permitidas`.
- **Todo lanzamiento de subproceso** lleva `environment: entornoSaneado(...)` e
  `includeParentEnvironment: false` **literal**. Lo aplica
  `subprocesos-con-entorno-saneado` por elemento resuelto. Hay **una** excepción
  declarada en `arquitectura.json` y el arnés cuenta: un segundo lanzamiento sin
  sanear en esa biblioteca es rojo.
- **Los tipos sellados serializan con `static fromJson`, nunca `factory`.** Un
  `factory` es un `ConstructorDeclaration` y el verificador lo lee como «esta
  clase serializa», que en una base sellada opaca es rojo. Copiá la forma de
  `StepOutcome` y de `ResultadoDeEntorno`.
- **Cada variante lee `json['kind']` dentro de su propia fábrica**, no en un
  ayudante: el verificador deriva las claves de los índices que hace la propia
  `fromJson`, y una lectura delegada le queda invisible.
- **Ningún control decide qué mira en una representación más pobre que su
  criterio.** Si el filtro caro no se puede pagar, achicá el universo **por
  ruta**, nunca por coincidencia de texto. Está en `CLAUDE.md`.
- **Nunca corras `dart test` ni edites archivos mientras corre
  `probar_reglas.py`.** El arnés trabaja sobre una copia privada y detecta
  cualquier cambio en el checkout compartido, incluidas las marcas de tiempo de
  `.dart_tool`. Pasó dos veces.
- **`dart analyze --fatal-infos` tiene que quedar limpio.**
- **Nomenclatura:** los tipos del dominio se nombran en español, como el resto
  del árbol. Los puertos conservan su nombre en inglés porque ya existen.
- Los commits terminan con
  `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
  Los cuerpos de PR terminan con
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `packages/core/lib/src/entorno.dart` | **Modificar.** Gana `clavesDeCredencial` y `EntornoDelProceso`: el único sitio donde la credencial sale del mapa |
| `packages/core/lib/src/puertos.dart` | **Modificar.** `CredentialSource` segregado de `CredentialStore`; `PullRequestSink` recibe `PullRequestRequest` y devuelve `PublicationOutcome` |
| `packages/core/lib/src/publicacion.dart` | **Crear.** `CausaDePublicacion`, `PublicationOutcome` y su jerarquía, `AccionSiguiente`, `EstadoDeEntrega`, `PullRequestDraft`, `PullRequestRequest` |
| `packages/cli/lib/src/credenciales.dart` | **Crear.** `FuenteDeEntorno`, el `CredentialSource` que lee del entorno capturado |
| `packages/forge/` | **Crear.** Paquete del adapter: push aislado, cliente de GitHub, búsqueda idempotente, render de su sintaxis |
| `packages/plugin_fake/lib/src/publicacion.dart` | **Crear.** `SalidaDePrFalsa` y `FuenteDeCredencialFalsa` |
| `tool/analisis/bin/check.dart` | **Modificar.** La regla `forja-en-su-adapter` |
| `arquitectura.json` | **Modificar.** Registro de puertos, `permitidas` con `forge`, la excepción condicionada, la regla nueva y sus sabotajes |
| `tool/checks/capas.py` | **Modificar.** El paso obligatorio de las pruebas de `forge` |
| `.github/workflows/checks.yml` | **Modificar.** Ese paso |

**Ruling registrado:** la tabla §18 de la propuesta pone `PublicationOutcome` en
`desenlace.dart` y el borrador/solicitud en `entidades.dart`. Van los cuatro a
un archivo nuevo, `publicacion.dart`. La tabla ya es orientativa —`EstadoDeCorrida`
terminó en `desenlace.dart` y no en `valores.dart`— y lo que cambia junto vive
junto: la solicitud y su desenlace son una sola responsabilidad. Si esto
resultara equivocado, el costo es mover declaraciones entre archivos de `core` y
reexportar; ningún consumidor los nombra todavía.

---

### Tarea 1: `EntornoDelProceso` — el único sitio donde sale la credencial

**Archivos:**
- Modificar: `packages/core/lib/src/entorno.dart`
- Test: `packages/core/test/entorno_test.dart`

**Interfaces:**
- Consume: `Credential` de `packages/core/lib/src/credencial.dart`.
- Produce: `const clavesDeCredencial = {'SHIPFLOW_GITHUB_TOKEN'}`;
  `class EntornoDelProceso` con `EntornoDelProceso(Map<String, String> crudo)`,
  `Map<String, String> get paraHijos` y `Credential? credencial(String clave)`.

**Por qué existe esta tarea.** §11 pedía «exclusión explícita de
`SHIPFLOW_GITHUB_TOKEN`» en cada lanzador. Eso es una lista negra repetida, y
este repositorio ya decidió contra las listas negras. La enmienda `365cfc1` lo
reemplaza por un punto único de remoción: **el mapa que se inyecta hacia abajo
no puede contener la credencial, por construcción.** `paraHijos` es un derivado,
no un campo, por la misma razón por la que `incompleto` no puede ser campo.

- [ ] **Paso 1: escribir las pruebas que fallan**

En `packages/core/test/entorno_test.dart`, agregá al final:

```dart
  group('EntornoDelProceso', () {
    test('lo que va a los hijos no lleva la credencial', () {
      final e = EntornoDelProceso(const {
        'PATH': '/bin',
        'HOME': '/casa',
        'SHIPFLOW_GITHUB_TOKEN': 'ghp_secreto',
      });
      expect(e.paraHijos.containsKey('SHIPFLOW_GITHUB_TOKEN'), isFalse);
      expect(e.paraHijos['PATH'], '/bin');
      expect(e.paraHijos['HOME'], '/casa');
    });

    test('lo que va a los hijos es inmodificable', () {
      final e = EntornoDelProceso(const {'PATH': '/bin'});
      expect(() => e.paraHijos['X'] = 'y', throwsUnsupportedError);
    });

    test('la credencial sale como Credential, nunca como cadena', () {
      final e = EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': 'ghp_x'});
      final c = e.credencial('SHIPFLOW_GITHUB_TOKEN');
      expect(c, isNotNull);
      expect(c.toString(), '***');
      expect(c!.use((secreto) => secreto), 'ghp_x');
    });

    test('ausente y vacía son la misma respuesta: no hay credencial', () {
      expect(EntornoDelProceso(const {}).credencial('SHIPFLOW_GITHUB_TOKEN'),
          isNull);
      expect(
          EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': ''})
              .credencial('SHIPFLOW_GITHUB_TOKEN'),
          isNull);
    });

    test('pedir una clave que no está declarada como credencial no compila '
        'un secreto: falla', () {
      final e = EntornoDelProceso(const {'PATH': '/bin'});
      expect(() => e.credencial('PATH'), throwsArgumentError);
    });

    test('el mapa crudo que se le pasó no se puede leer entero desde afuera',
        () {
      // La clase no expone el crudo. Esta prueba existe para que agregar un
      // getter que lo devuelva rompa algo: sin ella, exponerlo es invisible.
      final e = EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': 'ghp_x'});
      expect(e.paraHijos.values.contains('ghp_x'), isFalse);
    });
  });
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/core/test/entorno_test.dart
```

Esperado: FALLA con `Undefined name 'EntornoDelProceso'`.

- [ ] **Paso 3: implementar**

Al final de `packages/core/lib/src/entorno.dart`:

```dart
/// Las variables que llevan un secreto. **Declaradas, no adivinadas**: la
/// lista blanca de [entornoSaneado] ya protege a todo lanzador saneado, así
/// que esta enumeración solo gobierna el único sitio que NO sanea —la
/// excepción declarada de `vcs`— y la fuente que las lee.
const clavesDeCredencial = {'SHIPFLOW_GITHUB_TOKEN'};

/// El entorno del proceso, capturado una vez en la raíz de composición.
///
/// **Existe para que la credencial salga del mapa en UN solo sitio.** La
/// alternativa —excluirla en cada lanzamiento— es la lista negra otra vez:
/// promete solo sobre lo que alguien se acordó de enumerar, en cada llamada.
///
/// Lo que se inyecta hacia abajo es [paraHijos], y es un **derivado**: con un
/// campo asignable se construye un entorno «para hijos» que todavía lleva el
/// token, igual que con dos campos independientes se construye un artefacto no
/// concluyente marcado como completo.
///
/// **No expone el mapa crudo.** Un getter que lo devolviera volvería inútil
/// todo lo anterior, porque el llamador de al lado lo usaría por comodidad.
class EntornoDelProceso {
  final Map<String, String> _crudo;

  EntornoDelProceso(Map<String, String> crudo)
    : _crudo = Map.unmodifiable(Map<String, String>.of(crudo));

  /// El entorno con el que se lanza cualquier hijo. **Nunca lleva credencial.**
  Map<String, String> get paraHijos => Map.unmodifiable({
    for (final e in _crudo.entries)
      if (!clavesDeCredencial.contains(e.key)) e.key: e.value,
  });

  /// La credencial de [clave], opaca. Nula si no está o está vacía: las dos
  /// cosas significan lo mismo —no hay con qué autenticarse— y distinguirlas
  /// obligaría a cada llamador a tratar dos casos que tienen una sola salida.
  ///
  /// Pedir una clave que no está en [clavesDeCredencial] **falla**: si
  /// devolviera el valor, este método sería un lector del entorno crudo con
  /// otro nombre.
  Credential? credencial(String clave) {
    if (!clavesDeCredencial.contains(clave)) {
      throw ArgumentError.value(
        clave,
        'clave',
        'No está declarada en `clavesDeCredencial`. Este método no es un '
            'lector del entorno: solo entrega lo que el repositorio declaró '
            'secreto.',
      );
    }
    final valor = _crudo[clave];
    if (valor == null || valor.isEmpty) return null;
    return Credential(valor, label: clave);
  }
}
```

Y en la cabecera del archivo, importá la credencial:

```dart
import 'credencial.dart';
```

- [ ] **Paso 4: correr y ver que pasa**

```
dart test packages/core/test/entorno_test.dart
dart analyze --fatal-infos packages/core
```

Esperado: todas PASAN, analyze limpio.

- [ ] **Paso 5: commitear**

```bash
git add packages/core/lib/src/entorno.dart packages/core/test/entorno_test.dart
git commit -m "La credencial sale del entorno en un solo sitio"
```

---

### Tarea 2: `CredentialSource` segregado, y su única implementación

**Archivos:**
- Modificar: `packages/core/lib/src/puertos.dart:518-524`
- Crear: `packages/cli/lib/src/credenciales.dart`
- Modificar: `packages/cli/lib/cli.dart` (export)
- Modificar: `arquitectura.json` (registro `sin_implementacion`)
- Test: `packages/cli/test/credenciales_test.dart`

**Interfaces:**
- Consume: `EntornoDelProceso` y `clavesDeCredencial` de la tarea 1.
- Produce: `abstract interface class CredentialSource { Future<Credential?> read(String key); }`;
  `abstract interface class CredentialStore implements CredentialSource { Future<void> write(String key, Credential value); Future<void> delete(String key); }`;
  `class FuenteDeEntorno implements CredentialSource` con
  `const FuenteDeEntorno(EntornoDelProceso entorno)`.

**Por qué se parte el puerto.** Una implementación que lee y lanza en `write` y
`delete` no es sustituible por el puerto completo. Y el verificador recolecta los
supertipos y los sigue hasta arriba: si la clase dijera `implements
CredentialStore`, vería una implementación viva y **rechazaría que el puerto siga
declarado sin implementación**. Las dos cosas no pueden valer a la vez. Partido,
`CredentialStore` sigue siendo abstracto —y por lo tanto un puerto, no una
implementación—, así que sigue sin implementación mientras nadie escriba
almacenamiento real.

**Se descarta la cadena de resolución** que preguntaría por el CLI de la forja:
mete conocimiento de un proveedor concreto en el mecanismo genérico. Si alguien
quiere esa comodidad, es **otra** `CredentialSource`.

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/cli/test/credenciales_test.dart`:

```dart
import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('lee la credencial declarada del entorno capturado', () async {
    final fuente = FuenteDeEntorno(
      EntornoDelProceso(const {'SHIPFLOW_GITHUB_TOKEN': 'ghp_x'}),
    );
    final c = await fuente.read('SHIPFLOW_GITHUB_TOKEN');
    expect(c, isNotNull);
    expect(c!.use((secreto) => secreto), 'ghp_x');
    expect(c.label, 'SHIPFLOW_GITHUB_TOKEN');
  });

  test('sin la variable no hay credencial, y eso no es un error', () async {
    final fuente = FuenteDeEntorno(EntornoDelProceso(const {}));
    expect(await fuente.read('SHIPFLOW_GITHUB_TOKEN'), isNull);
  });

  test('una clave que el repositorio no declaró secreta no se sirve', () {
    final fuente = FuenteDeEntorno(EntornoDelProceso(const {'PATH': '/bin'}));
    expect(() => fuente.read('PATH'), throwsArgumentError);
  });

  test('es un CredentialSource y NO un CredentialStore', () {
    final fuente = FuenteDeEntorno(EntornoDelProceso(const {}));
    expect(fuente, isA<CredentialSource>());
    expect(fuente, isNot(isA<CredentialStore>()));
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/cli/test/credenciales_test.dart
```

Esperado: FALLA con `Undefined name 'FuenteDeEntorno'`.

- [ ] **Paso 3: partir el puerto**

En `packages/core/lib/src/puertos.dart`, reemplazá el bloque de
`CredentialStore` por:

```dart
/// **Entrega** credenciales. Devuelve [Credential], nunca cadenas: el tipo es
/// lo que impide que el secreto termine en una traza (INV-5).
///
/// **Partido de [CredentialStore] a propósito.** Quien solo lee no puede ser
/// sustituible por el puerto entero sin lanzar en `write` y `delete`, y un
/// método cuya única implementación es lanzar es una capacidad declarada que no
/// existe — el diagnóstico que este repositorio ya se hace con los puertos sin
/// implementación. Partido, `ship` depende de lo que necesita y el
/// almacenamiento sigue sin existir hasta que alguien lo escriba.
abstract interface class CredentialSource {
  Future<Credential?> read(String key);
}

/// Guarda y entrega. **Sigue sin implementación**: llega con `init`, que es la
/// primera etapa que necesita escribir una credencial.
abstract interface class CredentialStore implements CredentialSource {
  Future<void> write(String key, Credential value);
  Future<void> delete(String key);
}
```

- [ ] **Paso 4: implementar la fuente**

Creá `packages/cli/lib/src/credenciales.dart`:

```dart
import 'package:core/core.dart';

/// El `CredentialSource` de este arnés: lee del entorno capturado en la raíz.
///
/// **Es delgado a propósito.** Toda la decisión —qué variables son secretas,
/// cómo se convierte una en [Credential], y que el mapa que baja a los hijos ya
/// no la tenga— vive en [EntornoDelProceso], que es puro y se prueba sin tocar
/// el mundo. Acá solo queda el puerto.
class FuenteDeEntorno implements CredentialSource {
  final EntornoDelProceso _entorno;

  const FuenteDeEntorno(this._entorno);

  @override
  Future<Credential?> read(String key) async => _entorno.credencial(key);
}
```

Agregá a `packages/cli/lib/cli.dart`:

```dart
export 'src/credenciales.dart';
```

- [ ] **Paso 5: actualizar el registro de puertos**

En `arquitectura.json`, dentro de
`reglas["puertos-sin-implementacion"]["sin_implementacion"]`: **sacá**
`CredentialStore` de donde está hoy y volvé a agregarlo con el texto de abajo, y
**no agregues** `CredentialSource` — tiene implementación viva.

```json
"CredentialStore": "fase de `init` · el puerto se partió en la rebanada de la forja: `CredentialSource`, que solo lee, salió de esta lista con UNA implementación real —`FuenteDeEntorno` en cli— y la falsa de plugin_fake. `CredentialStore` agrega escritura y borrado, y sigue sin implementación porque no hay almacenamiento real: una clase que leyera y lanzara en `write`/`delete` sería una capacidad declarada que no existe"
```

- [ ] **Paso 6: correr y ver que pasa**

```
dart test packages/cli/test/credenciales_test.dart
cd tool/analisis && dart run bin/check.dart && cd ../..
dart analyze --fatal-infos
```

Esperado: pruebas PASAN; `check.dart` dice `puertos: ok`; analyze limpio.

- [ ] **Paso 7: commitear**

```bash
git add packages/core/lib/src/puertos.dart packages/cli/lib/src/credenciales.dart \
        packages/cli/lib/cli.dart packages/cli/test/credenciales_test.dart arquitectura.json
git commit -m "Quien solo lee una credencial no tiene por qué poder borrarla"
```

---

### Tarea 3: las costuras reciben un entorno que ya no puede llevar la credencial

**Archivos:**
- Modificar: `packages/vcs/lib/src/repositorio.dart:113-128`
- Modificar: `packages/plugin_dart/lib/src/ejecutor.dart:70-78`
- Modificar: `arquitectura.json` (el `por_que` de la excepción declarada)
- Test: `packages/vcs/test/repositorio_test.dart`,
  `packages/plugin_dart/test/ejecutor_test.dart`

**Interfaces:**
- Consume: `EntornoDelProceso` de la tarea 1.
- Produce: `RepositorioGit({..., EntornoDelProceso? entornoDelPadre})` y
  `EjecutorDelSistema({EntornoDelProceso? entornoDelPadre})`. En los dos, el
  getter privado `_padre` devuelve `Map<String, String>` y sale de
  `paraHijos`.

**Qué se está arreglando.** Hay **una** excepción declarada a
`subprocesos-con-entorno-saneado`: `_identidadComoEntorno` le pasa a `git config
--get` el entorno del padre entero, porque enumerar por dónde `git` lee su
configuración es la misma carrera que una lista negra. Su justificación dice que
ese comando no corre ganchos, no corre filtros y no escribe nada. **Nunca dijo
qué puede VER el hijo**, y no hacía falta: no había nada secreto en el entorno.
La tarea 2 puso `SHIPFLOW_GITHUB_TOKEN` ahí.

Cambiar el tipo de la costura —de `Map<String, String>?` a
`EntornoDelProceso?`— es lo que vuelve el invariante inevitable: **no hay forma
de pasarle a `vcs` un mapa crudo con el token**, ni desde la raíz ni desde una
prueba distraída. Y el respaldo cuando nadie inyecta deja de ser
`Platform.environment` a secas.

- [ ] **Paso 1: escribir la prueba que falla, en `vcs`**

Agregá a `packages/vcs/test/repositorio_test.dart`:

```dart
  test('el lanzamiento sin sanear tampoco ve la credencial', () async {
    // `git config --get` es el único lanzamiento exceptuado de `entornoSaneado`
    // y recibe el entorno del padre ENTERO. Esta prueba fija que ese «entero»
    // ya no puede incluir un secreto.
    final repo = RepositorioGit(
      directorio: temporal.path,
      // La política que ya usan las pruebas de `vcs`; mirá
      // `packages/vcs/test/candidato_test.dart` y reusá la que aplique.
      politica: const _TodoEsFuente(),
      programa: espia.path,
      entornoDelPadre: EntornoDelProceso(const {
        'PATH': '/bin',
        'SHIPFLOW_GITHUB_TOKEN': 'ghp_no_debe_llegar',
      }),
    );
    await repo.identidadCapturadaParaLaPrueba();
    final visto = await File('${temporal.path}/entorno-visto.txt').readAsString();
    expect(visto, contains('PATH='));
    expect(visto, isNot(contains('ghp_no_debe_llegar')));
    expect(visto, isNot(contains('SHIPFLOW_GITHUB_TOKEN')));
  });
```

El `espia` es un script que vuelca su entorno. Creálo en el `setUp` del grupo:

```dart
  late Directory temporal;
  late File espia;

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('vcs-entorno-');
    espia = File('${temporal.path}/espia.sh');
    await espia.writeAsString(
      '#!/bin/sh\nenv > "${temporal.path}/entorno-visto.txt"\nexit 0\n',
    );
    await Process.run('chmod', ['+x', espia.path]);
  });

  tearDown(() async => temporal.delete(recursive: true));
```

Si `identidadCapturadaParaLaPrueba` no existe, exponé `_identidadComoEntorno`
con un nombre público de prueba mínimo:

```dart
  /// Solo para la suite: la captura de identidad es privada y esta es la única
  /// forma de comprobar QUÉ entorno recibe el único lanzamiento exceptuado.
  @visibleForTesting
  Future<Map<String, String>> identidadCapturadaParaLaPrueba() =>
      _identidadComoEntorno();
```

y agregá `import 'package:meta/meta.dart';` — `meta` ya está en el workspace
porque lo arrastra `lints`; si `dart pub get` se queja, sacá la anotación y
dejá el método público con el nombre de prueba, que es lo que importa.

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/vcs/test/repositorio_test.dart -n 'credencial'
```

Esperado: FALLA. Hoy el tipo del parámetro es `Map<String, String>?`, así que ni
compila; y si se le pasa el mapa crudo, el volcado contiene el token.

- [ ] **Paso 3: cambiar la costura de `vcs`**

En `packages/vcs/lib/src/repositorio.dart`:

```dart
  /// El entorno del proceso padre. **Nulo significa el del proceso**; las
  /// pruebas le pasan el que quieren, que es la única forma de comprobar qué
  /// llega a `git` y qué no sin depender del shell de quien corre la suite.
  ///
  /// **Es [EntornoDelProceso] y no un mapa, y el tipo es el control.** El
  /// único lanzamiento exceptuado de `entornoSaneado` recibe este entorno
  /// ENTERO; con un mapa, «entero» podía traer la credencial y nada lo
  /// impedía. Con este tipo, lo que sale de acá ya pasó por `paraHijos`.
  final EntornoDelProceso? _entornoDelPadre;

  const RepositorioGit({
    required this.directorio,
    required this.politica,
    this.programa = 'git',
    this.programaChmod = 'chmod',
    this.detector = const DetectorDeSecretos(),
    EntornoDelProceso? entornoDelPadre,
  }) : _entornoDelPadre = entornoDelPadre;

  Map<String, String> get _padre =>
      (_entornoDelPadre ?? EntornoDelProceso(Platform.environment)).paraHijos;
```

`const RepositorioGit` sigue siendo válido: `EntornoDelProceso?` como campo no
lo impide; lo que no se puede es construir un `EntornoDelProceso` constante, y
nadie lo hace.

- [ ] **Paso 4: la misma costura en `plugin_dart`**

En `packages/plugin_dart/lib/src/ejecutor.dart`:

```dart
  final EntornoDelProceso? _entornoDelPadre;

  const EjecutorDelSistema({EntornoDelProceso? entornoDelPadre})
    : _entornoDelPadre = entornoDelPadre;

  Map<String, String> get _padre =>
      (_entornoDelPadre ?? EntornoDelProceso(Platform.environment)).paraHijos;
```

Y agregá a `packages/plugin_dart/test/ejecutor_test.dart`:

```dart
  test('el hijo no ve la credencial ni cuando el padre la tiene', () async {
    final ejecutor = EjecutorDelSistema(
      entornoDelPadre: EntornoDelProceso(const {
        'PATH': '/usr/bin:/bin',
        'SHIPFLOW_GITHUB_TOKEN': 'ghp_no_debe_llegar',
      }),
    );
    final r = await ejecutor.correr(
      'sh',
      ['-c', 'env'],
      directorio: Directory.systemTemp.path,
      presupuesto: const Duration(seconds: 10),
    );
    expect(r.salidaEstandar, isNot(contains('ghp_no_debe_llegar')));
  });
```

Ajustá el nombre del método y el del campo de salida a los que ya tenga
`EjecutorDeProceso` en `packages/core/lib/src/puertos.dart`; no inventes una
firma nueva.

- [ ] **Paso 5: arreglar los llamadores de las pruebas existentes**

Buscá quién le pasa hoy un mapa a esas dos costuras y envolvelo:

```
grep -rn "entornoDelPadre:" packages/ | grep -v "EntornoDelProceso"
```

Cada resultado pasa de `entornoDelPadre: {...}` a
`entornoDelPadre: EntornoDelProceso(const {...})`.

- [ ] **Paso 6: condicionar la excepción declarada**

En `arquitectura.json`, en
`reglas["subprocesos-con-entorno-saneado"]["excepciones"][0]["por_que"]`,
agregá al final:

```
 CONDICIONADA desde la rebanada de la forja: el tipo de la costura es `EntornoDelProceso`, y lo que entrega hacia abajo ya pasó por `paraHijos`, que quita `clavesDeCredencial`. Antes de esa rebanada la justificacion argumentaba que `git config --get` no corre ganchos ni escribe nada, y nunca argumento QUE VE el hijo; no hacia falta, porque no habia nada secreto en el entorno. La rebanada de la forja lo puso ahi. Que el entero que recibe este lanzamiento ya no pueda traer la credencial no se resuelve en cada llamada —eso seria la lista negra otra vez— sino en el tipo.
```

- [ ] **Paso 7: correr y ver que pasa**

```
dart test packages/vcs packages/plugin_dart packages/core packages/cli
dart analyze --fatal-infos
```

Esperado: todo verde.

- [ ] **Paso 8: commitear**

```bash
git add packages/vcs packages/plugin_dart arquitectura.json
git commit -m "El único lanzamiento exceptuado tampoco puede ver el token"
```

---

### Tarea 4: `PublicationOutcome` — una sola jerarquía, partida donde importa

**Archivos:**
- Crear: `packages/core/lib/src/publicacion.dart`
- Modificar: `packages/core/lib/core.dart` (export y el índice del encabezado)
- Test: `packages/core/test/publicacion_test.dart`
- Modificar: `packages/core/test/serializacion_test.dart`

**Interfaces:**
- Produce: `enum CausaDePublicacion { red, autenticacion, permisos, rechazoDeLaForja, desconocida }`;
  `enum EstadoDeEntrega { completa, incompletaReintentable, incompletaNoReintentable }`;
  `enum AccionSiguiente { ninguna, reintentarPublicacion, corregirPermisos, entregaNuevaExplicita }`;
  `sealed class PublicationOutcome` con `String get kind`,
  `Map<String, Object?> toJson()`, `static PublicationOutcome fromJson(...)`,
  y los derivados `bool get retryable`, `EstadoDeEntrega get deliveryStatus`,
  `AccionSiguiente get nextAction`;
  `sealed class PublicacionUtilizable extends PublicationOutcome { final String url; }`
  con `PullRequestOpen` y `PullRequestMerged`;
  `sealed class PublicacionNoUtilizable extends PublicationOutcome` con
  `PushFailed`, `PushUnknown`, `PullRequestFailed`, `PullRequestUnknown`
  —las cuatro con `final CausaDePublicacion causa` y `String get safeReason`— y
  `PullRequestClosed { final String url; }`.

**Por qué sellado y no dos enums.** El producto cartesiano admitía `push:
failed, pullRequest: succeeded`, y `succeeded` no distinguía abierto de cerrado
ni de fusionado. **`unknown` es imprescindible**, y tiene precedente exacto: es
la distinción entre `Skipped` y `Unobservable`. Sin él, una respuesta perdida se
reporta como `failed`, y un reintento crea un segundo PR.

**`safeReason` nunca copia la excepción externa**, que puede traer la credencial
adentro. Sale de la causa cerrada y de nada más.

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/core/test/publicacion_test.dart`:

```dart
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test('lo utilizable no cabe donde va lo incompleto', () {
    expect(PullRequestOpen(url: 'u'), isA<PublicacionUtilizable>());
    expect(PullRequestMerged(url: 'u'), isA<PublicacionUtilizable>());
    expect(
      PullRequestClosed(url: 'u'),
      isNot(isA<PublicacionUtilizable>()),
      reason: 'cerrado es terminal y NO completo',
    );
  });

  test('la acción siguiente se deriva de la variante y su causa', () {
    expect(PushFailed(causa: CausaDePublicacion.red).nextAction,
        AccionSiguiente.reintentarPublicacion);
    expect(PushUnknown(causa: CausaDePublicacion.desconocida).nextAction,
        AccionSiguiente.reintentarPublicacion);
    expect(PushFailed(causa: CausaDePublicacion.permisos).nextAction,
        AccionSiguiente.corregirPermisos,
        reason: 'reintentar no ayuda');
    expect(PullRequestFailed(causa: CausaDePublicacion.red).nextAction,
        AccionSiguiente.reintentarPublicacion);
    expect(PullRequestUnknown(causa: CausaDePublicacion.red).nextAction,
        AccionSiguiente.reintentarPublicacion);
    expect(PullRequestClosed(url: 'u').nextAction,
        AccionSiguiente.entregaNuevaExplicita);
    expect(PullRequestOpen(url: 'u').nextAction, AccionSiguiente.ninguna);
    expect(PullRequestMerged(url: 'u').nextAction, AccionSiguiente.ninguna);
  });

  test('permisos no es reintentable y el cerrado tampoco', () {
    expect(PushFailed(causa: CausaDePublicacion.permisos).retryable, isFalse);
    expect(PullRequestClosed(url: 'u').retryable, isFalse);
    expect(PushFailed(causa: CausaDePublicacion.red).retryable, isTrue);
    expect(PushUnknown(causa: CausaDePublicacion.red).retryable, isTrue);
  });

  test('solo lo utilizable es entrega completa', () {
    expect(PullRequestOpen(url: 'u').deliveryStatus, EstadoDeEntrega.completa);
    expect(PullRequestMerged(url: 'u').deliveryStatus, EstadoDeEntrega.completa);
    expect(PullRequestClosed(url: 'u').deliveryStatus,
        EstadoDeEntrega.incompletaNoReintentable);
    expect(PushFailed(causa: CausaDePublicacion.red).deliveryStatus,
        EstadoDeEntrega.incompletaReintentable);
    expect(PushFailed(causa: CausaDePublicacion.permisos).deliveryStatus,
        EstadoDeEntrega.incompletaNoReintentable);
  });

  test('la razón segura sale de la causa, no de un texto externo', () {
    for (final c in CausaDePublicacion.values) {
      final razon = PushFailed(causa: c).safeReason;
      expect(razon, isNotEmpty);
      expect(razon.contains('ghp_'), isFalse);
    }
  });

  test('una URL en blanco no identifica ningún PR', () {
    expect(() => PullRequestOpen(url: '  '), throwsArgumentError);
    expect(() => PullRequestClosed(url: ''), throwsArgumentError);
  });

  test('un kind que no nombra ninguna variante lanza', () {
    expect(() => PublicationOutcome.fromJson(const {'kind': 'inventado'}),
        throwsFormatException);
  });

  test('cada fromJson rechaza un discriminador ajeno', () {
    expect(
      () => PullRequestOpen.fromJson(const {'kind': 'merged', 'url': 'u'}),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/core/test/publicacion_test.dart
```

Esperado: FALLA, `Undefined name 'PullRequestOpen'`.

- [ ] **Paso 3: implementar**

Creá `packages/core/lib/src/publicacion.dart`. Copiá **exactamente** la forma de
`ResultadoDeEntorno` en `desenlace.dart`: base sellada con `String get kind`,
`toJson()` abstracto, `_exigirKind` estático, y `static fromJson` que despacha —
**nunca `factory`**, porque un constructor `fromJson` en una base sellada es lo
que el verificador lee como «esta clase serializa».

```dart
/// El desenlace de la publicación: el efecto remoto de una corrida.
library;

/// Por qué no se pudo publicar. **Cerrada**, y de acá sale `safeReason`: la
/// excepción externa NO se copia nunca, porque puede traer la credencial
/// adentro.
enum CausaDePublicacion { red, autenticacion, permisos, rechazoDeLaForja, desconocida }

/// Qué tan entregada quedó la corrida. **Derivado**, nunca asignable.
enum EstadoDeEntrega { completa, incompletaReintentable, incompletaNoReintentable }

/// Qué hace quien recibe el desenlace. **Derivado** de la variante y su causa.
enum AccionSiguiente {
  ninguna,
  reintentarPublicacion,
  corregirPermisos,
  entregaNuevaExplicita,
}

/// **Una sola jerarquía**, partida donde importa: lo utilizable no puede caber
/// donde va lo incompleto.
///
/// Dos enums independientes admitían el producto cartesiano —`push: failed,
/// pullRequest: succeeded`— y `succeeded` no distinguía abierto de cerrado ni
/// de fusionado.
sealed class PublicationOutcome {
  PublicationOutcome();

  String get kind;

  Map<String, Object?> toJson();

  bool get retryable;

  EstadoDeEntrega get deliveryStatus;

  AccionSiguiente get nextAction;

  static void _exigirKind(Object? kind, String propio) {
    if (kind != propio) {
      throw ArgumentError.value(
        kind,
        'kind',
        'fromJson de «$propio» recibió un discriminador que no es el suyo',
      );
    }
  }

  static PublicationOutcome fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'prAbierto' => PullRequestOpen.fromJson(json),
        'prFusionado' => PullRequestMerged.fromJson(json),
        'prCerrado' => PullRequestClosed.fromJson(json),
        'pushFallo' => PushFailed.fromJson(json),
        'pushDesconocido' => PushUnknown.fromJson(json),
        'prFallo' => PullRequestFailed.fromJson(json),
        'prDesconocido' => PullRequestUnknown.fromJson(json),
        final otro => throw FormatException(
          'PublicationOutcome con kind «$otro», que no es ninguna variante.',
        ),
      };
}
```

Seguí con las dos ramas. La utilizable exige URL con contenido —una URL en
blanco no identifica ningún PR, y el estado terminal `publicationComplete` se
lee de acá—:

```dart
/// Hay un PR que sirve.
sealed class PublicacionUtilizable extends PublicationOutcome {
  final String url;

  PublicacionUtilizable({required this.url}) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(url, 'url', 'Una URL en blanco no identifica '
          'ningún pull request, y esta variante afirma que hay uno.');
    }
  }

  @override
  bool get retryable => false;

  @override
  EstadoDeEntrega get deliveryStatus => EstadoDeEntrega.completa;

  @override
  AccionSiguiente get nextAction => AccionSiguiente.ninguna;
}

final class PullRequestOpen extends PublicacionUtilizable {
  @override
  final String kind = 'prAbierto';

  PullRequestOpen({required super.url});

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'url': url};

  factory PullRequestOpen.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prAbierto');
    return PullRequestOpen(url: json['url']! as String);
  }
}
```

`PullRequestMerged` es idéntica con `kind = 'prFusionado'`. **Escribila entera;
no la derives de la anterior.**

La rama no utilizable:

```dart
/// No hay PR utilizable confirmado.
sealed class PublicacionNoUtilizable extends PublicationOutcome {
  PublicacionNoUtilizable();

  @override
  EstadoDeEntrega get deliveryStatus => retryable
      ? EstadoDeEntrega.incompletaReintentable
      : EstadoDeEntrega.incompletaNoReintentable;
}

/// Las cuatro que fallaron o no se supieron. **`unknown` no es un lujo**: es
/// la distinción entre `Skipped` y `Unobservable`. Sin él, una respuesta
/// perdida se reporta como `failed` y un reintento crea un segundo PR.
sealed class PublicacionConCausa extends PublicacionNoUtilizable {
  final CausaDePublicacion causa;

  PublicacionConCausa({required this.causa});

  /// **Nunca copia la excepción externa.** Sale de la causa cerrada, que es
  /// lo único que se puede publicar sin arriesgar el secreto.
  String get safeReason => switch (causa) {
    CausaDePublicacion.red => 'la red falló',
    CausaDePublicacion.autenticacion => 'la credencial no fue aceptada',
    CausaDePublicacion.permisos => 'la credencial no alcanza para esta '
        'operación',
    CausaDePublicacion.rechazoDeLaForja => 'la forja rechazó la operación',
    CausaDePublicacion.desconocida => 'no se pudo determinar la causa',
  };

  @override
  bool get retryable => causa != CausaDePublicacion.permisos;

  @override
  AccionSiguiente get nextAction => causa == CausaDePublicacion.permisos
      ? AccionSiguiente.corregirPermisos
      : AccionSiguiente.reintentarPublicacion;
}
```

Y las cinco variantes concretas. `PushFailed`, `PushUnknown`,
`PullRequestFailed` y `PullRequestUnknown` extienden `PublicacionConCausa` con
sus `kind` respectivos —`pushFallo`, `pushDesconocido`, `prFallo`,
`prDesconocido`—, `toJson` con `{'kind': kind, 'causa': causa.name}` y una
`factory fromJson` que empieza con `PublicationOutcome._exigirKind(json['kind'],
'<el suyo>')` y resuelve la causa con
`CausaDePublicacion.values.byName(json['causa']! as String)`. **Escribí las
cuatro completas.**

`PullRequestClosed` es la quinta y no tiene causa:

```dart
/// El PR existió y está cerrado. **Terminal pero NO completo**: no se
/// reintenta, se entrega de nuevo y explícitamente.
final class PullRequestClosed extends PublicacionNoUtilizable {
  @override
  final String kind = 'prCerrado';

  final String url;

  PullRequestClosed({required this.url}) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(url, 'url', 'Una URL en blanco no identifica '
          'ningún pull request, y esta variante afirma que hubo uno.');
    }
  }

  @override
  bool get retryable => false;

  @override
  AccionSiguiente get nextAction => AccionSiguiente.entregaNuevaExplicita;

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'url': url};

  factory PullRequestClosed.fromJson(Map<String, Object?> json) {
    PublicationOutcome._exigirKind(json['kind'], 'prCerrado');
    return PullRequestClosed(url: json['url']! as String);
  }
}
```

- [ ] **Paso 4: exportar y registrar en la suite de serialización**

En `packages/core/lib/core.dart` agregá `export 'src/publicacion.dart';` y una
entrada al índice del encabezado. En
`packages/core/test/serializacion_test.dart`, agregá las siete variantes al mapa
de ida y vuelta, con la misma forma que ya usan las demás.

- [ ] **Paso 5: correr y ver que pasa**

```
dart test packages/core
cd tool/analisis && dart run bin/check.dart && cd ../..
dart analyze --fatal-infos
```

Esperado: pruebas PASAN; `check.dart` dice `serializacion: ok` con la cuenta de
clases subida en siete; analyze limpio.

- [ ] **Paso 6: commitear**

```bash
git add packages/core/lib/src/publicacion.dart packages/core/lib/core.dart \
        packages/core/test/publicacion_test.dart packages/core/test/serializacion_test.dart
git commit -m "Una respuesta perdida no es un fallo, y confundirlas crea dos PRs"
```

---

### Tarea 5: el borrador y la solicitud, sin un solo hecho repetido

**Archivos:**
- Modificar: `packages/core/lib/src/publicacion.dart`
- Test: `packages/core/test/publicacion_test.dart`

**Interfaces:**
- Consume: `ArtefactoDeRevision`, `SuperficieDeVerificacion`, `EstadoDeCorrida`
  y `CandidateIdentity`, todos ya en `core`.
- Produce:
  `class PullRequestDraft { final String runId; final String branch; final String base; final ArtefactoDeRevision artefacto; String get intent; }`
  y
  `class PullRequestRequest { final PullRequestDraft draft; final String revision; bool get incompleto; String get titulo; }`
  con constructor
  `PullRequestRequest({required PullRequestDraft draft, required String revision, required String arbolDeLaRevision})`.

**Qué se está arreglando, y es la enmienda `365cfc1`.** La v3 llevaba `slice` en
el borrador, cuyo `intent` ya vive en `artefacto.intent`: dos cadenas
independientes para una cosa, y la que el adapter elija decide qué lee el
revisor. Y llevaba `revision` suelta al lado de `artefacto.candidato.contentRevision`:
una nombra **a dónde apunta el PR** y la otra **qué vieron los controles**. Si
discrepan, el cuerpo afirma verificación sobre contenido que el PR no contiene —
el falso verde peor, porque el revisor no tiene desde dónde notarlo.

No son iguales —una es commit y la otra es árbol—, así que no se puede derivar
una de la otra. **La relación se exige en el constructor**, que es lo que queda
cuando la derivación no está disponible.

Y tampoco lleva `title`: la v3 lo llevaba renderizado tres líneas después de
prohibir el `body` renderizado por el mismo motivo. Un título es texto con la
misma propiedad.

- [ ] **Paso 1: escribir las pruebas que fallan**

Agregá a `packages/core/test/publicacion_test.dart`:

```dart
  group('el borrador y la solicitud', () {
    ArtefactoDeRevision artefacto({
      required EstadoDeCorrida estado,
      String arbol = 'arbol-1',
    }) => ArtefactoDeRevision(
      superficie: SuperficieDeVerificacion(
        cubierto: const [],
        requiereCriterio: const [],
        estado: estado,
      ),
      candidato: CandidateIdentity(
        contentRevision: arbol,
        baseRevision: 'base-1',
      ),
      intent: 'sostener el arnés',
      plan: null,
      sinPlanPorque: 'no hay elementos de trabajo',
      alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
    );

    PullRequestDraft borrador(EstadoDeCorrida estado) => PullRequestDraft(
      runId: 'corrida-1',
      branch: 'rama',
      base: 'develop',
      artefacto: artefacto(estado: estado),
    );

    test('la intención no se repite: sale del artefacto', () {
      expect(borrador(EstadoDeCorrida.verde).intent, 'sostener el arnés');
    });

    test('el commit tiene que llevar el árbol que vieron los controles', () {
      expect(
        () => PullRequestRequest(
          draft: borrador(EstadoDeCorrida.verde),
          revision: 'commit-1',
          arbolDeLaRevision: 'OTRO-arbol',
        ),
        throwsArgumentError,
        reason: 'si no, el cuerpo afirma sobre contenido que el PR no tiene',
      );
    });

    test('con el árbol correcto, construye', () {
      final s = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: 'commit-1',
        arbolDeLaRevision: 'arbol-1',
      );
      expect(s.revision, 'commit-1');
      expect(s.incompleto, isFalse);
    });

    test('incompleto se deriva del estado, y no hay dónde escribirlo', () {
      for (final estado in EstadoDeCorrida.values) {
        final s = PullRequestRequest(
          draft: borrador(estado),
          revision: 'commit-1',
          arbolDeLaRevision: 'arbol-1',
        );
        expect(s.incompleto, estado != EstadoDeCorrida.verde);
      }
    });

    test('el título se deriva, y cuando está incompleto lo dice', () {
      final verde = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.verde),
        revision: 'c',
        arbolDeLaRevision: 'arbol-1',
      );
      expect(verde.titulo, 'sostener el arnés');

      final rojo = PullRequestRequest(
        draft: borrador(EstadoDeCorrida.noConcluyente),
        revision: 'c',
        arbolDeLaRevision: 'arbol-1',
      );
      expect(rojo.titulo, startsWith(PullRequestRequest.prefijoIncompleto));
      expect(rojo.titulo, contains('sostener el arnés'));
    });
  });
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/core/test/publicacion_test.dart -n 'borrador'
```

Esperado: FALLA, `Undefined name 'PullRequestDraft'`.

- [ ] **Paso 3: implementar**

Al final de `packages/core/lib/src/publicacion.dart`:

```dart
/// Antes del commit. **No tiene revisión porque todavía no existe.**
class PullRequestDraft {
  final String runId;
  final String branch;
  final String base;
  final ArtefactoDeRevision artefacto;

  PullRequestDraft({
    required this.runId,
    required this.branch,
    required this.base,
    required this.artefacto,
  });

  /// **Derivado.** El artefacto ya lleva la intención de la rebanada; llevarla
  /// también acá serían dos cadenas independientes para una cosa, y la que el
  /// adapter eligiera decidiría qué lee el revisor.
  String get intent => artefacto.intent;
}

/// Después del commit.
class PullRequestRequest {
  /// Lo que antecede al título cuando la superficie no está verde. **Es una
  /// constante y no un literal suelto**: el adapter la necesita para truncar
  /// sin comerse la advertencia.
  static const prefijoIncompleto = '[verificación incompleta] ';

  final PullRequestDraft draft;

  /// El commit al que la rama va a apuntar.
  final String revision;

  /// **El árbol del commit tiene que ser el contenido que vieron los
  /// controles.** No se puede derivar uno del otro —uno es commit y el otro es
  /// árbol—, así que la relación se exige acá, que es lo que queda cuando la
  /// derivación no está disponible. Si discreparan, el cuerpo afirmaría
  /// verificación sobre contenido que el PR no contiene, y el revisor no
  /// tendría desde dónde notarlo.
  PullRequestRequest({
    required this.draft,
    required this.revision,
    required String arbolDeLaRevision,
  }) {
    final esperado = draft.artefacto.candidato.contentRevision;
    if (arbolDeLaRevision != esperado) {
      throw ArgumentError.value(
        arbolDeLaRevision,
        'arbolDeLaRevision',
        'El commit «$revision» lleva un árbol que no es el que se expuso a los '
            'controles («$esperado»). Publicar así afirmaría verificación sobre '
            'contenido que el pull request no contiene.',
      );
    }
  }

  /// **Derivado, no asignable.** Con dos campos independientes se construye
  /// `artefacto: noConcluyente, incompleto: false`, y el adapter omite la
  /// advertencia obligatoria.
  bool get incompleto =>
      draft.artefacto.superficie.estado != EstadoDeCorrida.verde;

  /// **También derivado.** Un título es texto con la misma propiedad que el
  /// cuerpo: «✅ verificado» en un título es una afirmación sobre la corrida, y
  /// quien la escriba no es quien la puede sostener. El adapter lo trunca al
  /// límite de su proveedor; la advertencia va adelante para que el truncado
  /// no se la coma.
  String get titulo =>
      incompleto ? '$prefijoIncompleto${draft.intent}' : draft.intent;
}
```

- [ ] **Paso 4: correr y ver que pasa**

```
dart test packages/core
dart analyze --fatal-infos
```

Esperado: verde.

- [ ] **Paso 5: commitear**

```bash
git add packages/core/lib/src/publicacion.dart packages/core/test/publicacion_test.dart
git commit -m "El PR no puede apuntar a un árbol distinto del que se verificó"
```

---

### Tarea 6: `PullRequestSink` recibe la solicitud y devuelve el desenlace

**Archivos:**
- Modificar: `packages/core/lib/src/puertos.dart:487-502`
- Test: ninguno propio — el puerto es una interfaz; lo ejerce la tarea 12.

**Interfaces:**
- Consume: `PullRequestRequest` y `PublicationOutcome` de las tareas 4 y 5.
- Produce: `abstract interface class PullRequestSink { Future<PublicationOutcome> open(PullRequestRequest request); }`.

**Por qué cambia.** Hoy devuelve `Future<String>`: una URL o una excepción. Eso
no puede representar «el push salió y el PR no», que es exactamente el estado
que ADR-014 exige poder terminar. Y no tiene dónde decir `unknown`.

`open` es **idempotente**: llamarla de nuevo con la misma solicitud no crea un
segundo PR. La clave de la búsqueda —repositorio/remoto, rama origen, rama base,
la revisión esperada, el marcador estable y el estado del PR— la implementa el
adapter en la tarea 9. Rama y base no alcanzan: una rama reutilizada recuperaría
un PR ajeno.

- [ ] **Paso 1: reemplazar la declaración**

```dart
/// Por donde sale un Pull Request a la forja.
///
/// **Separado de [ChangeSink] a propósito.** Uno es local y funciona sin red;
/// el otro es remoto, necesita credencial y depende de un proveedor. Fallan
/// por razones distintas, se prueban distinto, y ADR-014 exige que se pueda
/// terminar con el primero hecho y el segundo no.
///
/// **Quién es la forja no se sabe acá.** GitHub, GitLab o lo que sea vive en
/// su propio adapter, igual que el stack vive en su plugin. El
/// repositorio/remoto pertenece a la configuración inyectada de ese adapter,
/// no a la solicitud.
///
/// **Devuelve el desenlace; no lanza por un fallo remoto.** Con un `String` y
/// una excepción no había forma de representar «el push salió y el PR no», ni
/// de distinguir una respuesta perdida de un rechazo — y confundirlas hace que
/// el reintento cree un segundo PR.
abstract interface class PullRequestSink {
  /// Abre el PR y devuelve dónde quedó. **Idempotente**: repetirla con la
  /// misma solicitud no crea un segundo pull request.
  Future<PublicationOutcome> open(PullRequestRequest request);
}
```

- [ ] **Paso 2: comprobar que nadie lo rompió**

```
grep -rn "PullRequestSink" packages/ tool/ | grep -v "^packages/core/lib/src/puertos.dart"
```

Esperado: solo `packages/vcs/lib/vcs.dart` en prosa y `arquitectura.json`. Si
aparece un llamador, adaptalo; no debería haberlo.

- [ ] **Paso 3: correr y commitear**

```
dart analyze --fatal-infos
cd tool/analisis && dart run bin/check.dart && cd ../..
```

```bash
git add packages/core/lib/src/puertos.dart
git commit -m "La salida del PR ya puede decir que no sabe"
```

---

### Tarea 7: `packages/forge/`, el paquete del adapter

**Archivos:**
- Crear: `packages/forge/pubspec.yaml`, `packages/forge/lib/forge.dart`,
  `packages/forge/analysis_options.yaml`
- Modificar: `pubspec.yaml` (raíz, lista `workspace:`)
- Modificar: `arquitectura.json` (mapa `permitidas`)
- Modificar: `tool/checks/capas.py` (`PASOS_OBLIGATORIOS`)
- Modificar: `.github/workflows/checks.yml`
- Modificar: `README.md` (la cuenta de pasos obligatorios)

**Interfaces:**
- Produce: el paquete `forge`, que depende **solo** de `core`.

**Por qué su propio paquete.** El adapter del proveedor no vive en `vcs`: `vcs`
es local y funciona sin red. Y `forge` no puede ver a `vcs` —`deps-hacia-core`
solo deja flechas hacia `core`, y únicamente `cli` ve a los plugins—, así que
**`forge` lanza su propio `git push`**, con el saneamiento que le corresponde a
todo lanzador de este repositorio.

- [ ] **Paso 1: crear el paquete**

`packages/forge/pubspec.yaml`:

```yaml
name: forge
description: >-
  El adapter de la forja: por donde sale el pull request. Quién es la forja
  vive acá y en ningún otro paquete.
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.11.0

resolution: workspace

dependencies:
  core:
    path: ../core
```

`packages/forge/lib/forge.dart`:

```dart
/// `forge` — por donde sale el pull request, y el único paquete que sabe quién
/// es la forja.
///
/// **Lanza su propio `git push`.** No puede usar `vcs`: las flechas entre
/// paquetes apuntan a `core` y solo `cli` ve a los adapters. Eso no es una
/// molestia del mapa — `vcs` es local y funciona sin red, `forge` es remoto y
/// necesita credencial, y confundirlos es lo que ADR-014 prohíbe.
library;
```

Copiá `analysis_options.yaml` de `packages/core/` sin cambios.

- [ ] **Paso 2: sumarlo al workspace y al mapa de dependencias**

En `pubspec.yaml` de la raíz, agregá `  - packages/forge` a la lista
`workspace:`, después de `packages/plugin_fake`.

En `arquitectura.json`, en `reglas["deps-hacia-core"]["permitidas"]`: agregá
`"forge": ["core"]` y sumá `"forge"` a la lista de `"cli"`.

- [ ] **Paso 3: sumarlo a los pasos obligatorios**

En `tool/checks/capas.py`, dentro de `PASOS_OBLIGATORIOS`, después de
`"las pruebas del plugin de stack"`:

```python
    "las pruebas de la forja": ("dart test packages/forge", None),
```

En `.github/workflows/checks.yml`, después del paso `pruebas del plugin de
stack`:

```yaml
      # El adapter de la forja contra un servidor local: que el push no le
      # entregue la credencial a los ganchos ni al credential helper del
      # usuario, y que `open` repetido no cree un segundo PR.
      - name: pruebas de la forja
        run: dart test packages/forge
```

En `README.md`, buscá `los N pasos obligatorios` y subí el número en uno.
`capas.py` verifica que coincida, así que si te olvidás se pone rojo.

- [ ] **Paso 4: resolver y comprobar**

```
dart pub get
python3 tool/checks/capas.py
dart analyze --fatal-infos
```

Esperado: `capas: ok` con `forge` entre los miembros; analyze limpio. Todavía no
hay pruebas de `forge`, así que `dart test packages/forge` va a decir que no
encontró archivos: normal hasta la tarea 8.

- [ ] **Paso 5: commitear**

```bash
git add packages/forge pubspec.yaml pubspec.lock arquitectura.json \
        tool/checks/capas.py .github/workflows/checks.yml README.md
git commit -m "La forja tiene su paquete, y solo ve a core"
```

---

### Tarea 8: el push, aislado del código del usuario

**Archivos:**
- Crear: `packages/forge/lib/src/empuje.dart`
- Modificar: `packages/forge/lib/forge.dart` (export)
- Test: `packages/forge/test/empuje_test.dart`

**Interfaces:**
- Consume: `entornoSaneado`, `Credential`, `CausaDePublicacion`,
  `PublicacionNoUtilizable`, `PushFailed`, `PushUnknown` de `core`.
- Produce:
  `sealed class ResultadoDeEmpuje` con `final class Empujado` y
  `final class NoEmpujado { final PublicacionNoUtilizable desenlace; }`;
  `class EmpujeAislado` con
  `EmpujeAislado({required String directorio, required Map<String, String> entornoDelPadre, String programa = 'git'})`
  y
  `Future<ResultadoDeEmpuje> empujar({required String urlDelRemoto, required Credential credencial, required String revision, required String rama})`.

**El hallazgo que esta tarea implementa.** Medido con un gancho y un
`credential.helper` propios:

| Canal | Qué ve el código del usuario |
|---|---|
| El token en el entorno de `git push` | el gancho `pre-push` lo recibe **verbatim** |
| `-c core.hooksPath=<vacío>` | frena el gancho — el mismo mecanismo que el commit |
| …pero el `credential.helper` del usuario | **corre igual**, dos veces, y ve el entorno entero |
| `-c http.extraHeader=<token>` | llega a ese helper **por entorno**, como `GIT_CONFIG_PARAMETERS` |
| `-c credential.helper=` y la credencial en la URL | el helper **no corre**; el token no entra al entorno |

La cuarta fila es la que se lee mal: el padre del helper es `git-remote-http`,
cuyo `argv` no lleva el `-c`, así que por `ps` el canal parece argv. No lo es.
`git` reinyecta sus `-c` a los hijos por entorno, de modo que **argv y entorno
son el mismo canal con otro nombre**.

- [ ] **Paso 1: escribir la prueba que falla**

Creá `packages/forge/test/empuje_test.dart`. La prueba levanta un servidor que
responde `401` y **registra el encabezado `Authorization`**; pone un `HOME`
temporal con un `credential.helper` que deja un archivo si corre; y un
`pre-push` que deja otro.

```dart
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporal;
  late HttpServer servidor;
  final autorizaciones = <String?>[];

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('forge-empuje-');
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((pedido) async {
      autorizaciones.add(pedido.headers.value('authorization'));
      pedido.response.statusCode = HttpStatus.unauthorized;
      pedido.response.headers.set('WWW-Authenticate', 'Basic realm="x"');
      await pedido.response.close();
    });

    // Un HOME con un credential helper que deja rastro si corre.
    final casa = Directory('${temporal.path}/casa')..createSync();
    File('${casa.path}/.gitconfig').writeAsStringSync('''
[user]
\tname = t
\temail = t@t
[credential]
\thelper = "!f() { echo corrio > ${temporal.path}/helper-corrio; echo username=x; echo password=y; }; f"
''');

    // Un repositorio con un commit y un pre-push que deja rastro si corre.
    final trabajo = Directory('${temporal.path}/trabajo')..createSync();
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args,
          workingDirectory: trabajo.path,
          environment: {'PATH': Platform.environment['PATH']!, 'HOME': casa.path},
          includeParentEnvironment: false);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    await git(['init', '-q']);
    File('${trabajo.path}/a.txt').writeAsStringSync('a');
    await git(['add', 'a.txt']);
    await git(['commit', '-qm', 'a']);
    File('${trabajo.path}/.git/hooks/pre-push').writeAsStringSync(
        '#!/bin/sh\necho corrio > ${temporal.path}/gancho-corrio\n');
    await Process.run('chmod', ['+x', '${trabajo.path}/.git/hooks/pre-push']);
  });

  tearDown(() async {
    await servidor.close(force: true);
    await temporal.delete(recursive: true);
    autorizaciones.clear();
  });

  test('la credencial llega al remoto y no al código del usuario', () async {
    final casa = '${temporal.path}/casa';
    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: {'PATH': Platform.environment['PATH']!, 'HOME': casa},
    );

    final r = await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
      credencial: const Credential('ghp_secreto', label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );

    // El remoto vio la credencial: llegó por el canal que elegimos.
    expect(autorizaciones.whereType<String>(), isNotEmpty);

    // Y nadie más la vio.
    expect(File('${temporal.path}/helper-corrio').existsSync(), isFalse,
        reason: 'el credential.helper del usuario no debe correr');
    expect(File('${temporal.path}/gancho-corrio').existsSync(), isFalse,
        reason: 'el pre-push del usuario no debe correr');

    // El servidor no es una forja: el push no puede terminar bien, y eso se
    // reporta como desenlace, no como excepción.
    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace, isA<PushFailed>());
    expect((r.desenlace as PushFailed).causa, CausaDePublicacion.autenticacion);
    expect((r.desenlace as PushFailed).safeReason, isNot(contains('ghp_')));
  });

  test('un remoto que no existe es red, y es reintentable', () async {
    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: {
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      },
    );
    final r = await empuje.empujar(
      // Puerto cerrado a propósito.
      urlDelRemoto: 'http://127.0.0.1:1/x.git',
      credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );
    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace.retryable, isTrue);
  });
}
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/forge/test/empuje_test.dart
```

Esperado: FALLA, `Undefined name 'EmpujeAislado'`.

- [ ] **Paso 3: implementar**

Creá `packages/forge/lib/src/empuje.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';

/// El desenlace del empuje. **Sellado y no un nulo**: «nulo quiere decir que
/// salió bien» es una convención que hay que recordar en cada llamada.
sealed class ResultadoDeEmpuje {
  const ResultadoDeEmpuje();
}

final class Empujado extends ResultadoDeEmpuje {
  const Empujado();
}

final class NoEmpujado extends ResultadoDeEmpuje {
  final PublicacionNoUtilizable desenlace;
  const NoEmpujado(this.desenlace);
}

/// Empuja una revisión a una rama del remoto **sin entregarle la credencial a
/// ningún programa del usuario**.
///
/// Dos `-c`, y los dos son el mismo mecanismo que el `core.hooksPath` con el
/// que `vcs` commitea:
///
/// - `core.hooksPath` a un directorio vacío frena TODOS los ganchos. Medido:
///   con el token en el entorno de `git`, un `pre-push` lo recibe verbatim.
/// - `credential.helper` vacío **resetea la cadena entera** del usuario.
///   `core.hooksPath` no la gobierna: medido, el helper corre igual —dos
///   veces— y ve el entorno completo.
///
/// Y la credencial viaja en la URL de destino, de un solo uso, **nunca en el
/// entorno**. El canal que parecía más seguro no lo era: `-c
/// http.extraHeader=<token>` le llega a ese helper por entorno, como
/// `GIT_CONFIG_PARAMETERS`. Por `ps` parece argv porque el padre del helper es
/// `git-remote-http`; elegirlo por eso sería decidir sobre una representación
/// más pobre que el criterio.
///
/// **Residuo declarado:** `/proc/<pid>/cmdline` en Linux deja ver el argv de
/// nuestro propio `git`. Es limitación de ambiente, no un fallo que causemos
/// nosotros — a diferencia de entregarle el token a un programa que el usuario
/// eligió y nosotros ejecutamos.
class EmpujeAislado {
  final String directorio;

  /// El entorno del padre **ya despojado**: viene de
  /// `EntornoDelProceso.paraHijos`.
  final Map<String, String> entornoDelPadre;

  final String programa;

  const EmpujeAislado({
    required this.directorio,
    required this.entornoDelPadre,
    this.programa = 'git',
  });

  Future<ResultadoDeEmpuje> empujar({
    required String urlDelRemoto,
    required Credential credencial,
    required String revision,
    required String rama,
  }) async {
    final sinGanchos = await Directory.systemTemp.createTemp('forge-ganchos-');
    try {
      final destino = credencial.use(
        (secreto) => _conCredencial(urlDelRemoto, secreto),
      );
      final r = await Process.run(
        programa,
        [
          '-c', 'core.hooksPath=${sinGanchos.path}',
          '-c', 'credential.helper=',
          'push',
          destino,
          '$revision:refs/heads/$rama',
        ],
        workingDirectory: directorio,
        environment: entornoSaneado(entornoDelPadre),
        includeParentEnvironment: false,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (r.exitCode == 0) return const Empujado();
      return NoEmpujado(
        PushFailed(causa: _causaDe(r.stderr as String)),
      );
    } on ProcessException {
      // No se pudo ni lanzar `git`. No sabemos si algo salió.
      return NoEmpujado(
        PushUnknown(causa: CausaDePublicacion.desconocida),
      );
    } finally {
      await sinGanchos.delete(recursive: true);
    }
  }

  /// Mete la credencial en el `userinfo` de la URL. **No se registra en
  /// ningún lado**: es un destino de un solo uso, no un remoto configurado.
  static String _conCredencial(String url, String secreto) {
    final u = Uri.parse(url);
    return u
        .replace(
          userInfo: 'x-access-token:${Uri.encodeComponent(secreto)}',
        )
        .toString();
  }

  /// Clasifica **sin copiar nada**: lo que sale de acá es una causa cerrada, y
  /// `safeReason` se deriva de ella. El texto de `git` no se propaga.
  ///
  /// **Residuo declarado:** la clasificación mira el texto de nuestro propio
  /// hijo, que es un universo acotado por construcción. Un mensaje que no
  /// reconozca cae en `desconocida`, que es reintentable: el precio de errar
  /// es un reintento de más, nunca una publicación que se lea como completa.
  static CausaDePublicacion _causaDe(String stderr) {
    final t = stderr.toLowerCase();
    if (t.contains('authentication failed') ||
        t.contains('invalid username or password')) {
      return CausaDePublicacion.autenticacion;
    }
    if (t.contains('permission denied') ||
        t.contains('denied to') ||
        t.contains('403')) {
      return CausaDePublicacion.permisos;
    }
    if (t.contains('could not resolve host') ||
        t.contains('failed to connect') ||
        t.contains('connection refused') ||
        t.contains('operation timed out')) {
      return CausaDePublicacion.red;
    }
    if (t.contains('rejected') || t.contains('non-fast-forward')) {
      return CausaDePublicacion.rechazoDeLaForja;
    }
    return CausaDePublicacion.desconocida;
  }
}
```

Agregá `export 'src/empuje.dart';` a `packages/forge/lib/forge.dart`.

- [ ] **Paso 4: correr y ver que pasa**

```
dart test packages/forge
cd tool/analisis && dart run bin/check.dart && cd ../..
dart analyze --fatal-infos
```

Esperado: pruebas PASAN; `check.dart` acepta el lanzamiento porque
`environment:` es una llamada a `entornoSaneado` de `core`; analyze limpio.

- [ ] **Paso 5: commitear**

```bash
git add packages/forge
git commit -m "El push no le entrega el token al código del usuario"
```

---

### Tarea 9: el cliente de GitHub y la búsqueda idempotente

**Archivos:**
- Crear: `packages/forge/lib/src/github.dart`
- Modificar: `packages/forge/lib/forge.dart` (export)
- Test: `packages/forge/test/github_test.dart`

**Interfaces:**
- Consume: `EmpujeAislado`, `Credential`, `PullRequestRequest`,
  `PublicationOutcome` y sus variantes.
- Produce:
  `class ConfiguracionDeGitHub { final String duenio; final String repositorio; final Uri baseDeLaApi; final String urlDelRemoto; }`
  y `class SalidaDePrDeGitHub implements PullRequestSink` con
  `SalidaDePrDeGitHub({required ConfiguracionDeGitHub configuracion, required CredentialSource credenciales, required EmpujeAislado empuje, HttpClient Function()? clienteHttp})`.

**La búsqueda idempotente.** Rama y base no alcanzan: una rama reutilizada
recuperaría un PR ajeno. La clave es **repositorio/remoto, rama origen, rama
base, la revisión esperada, el marcador estable, y el estado del PR**. El
marcador estable es una línea al final del cuerpo:

```
<!-- shipflow:pr formatVersion=1 runId=<runId> revision=<revision> -->
```

Va en el cuerpo y no en el título porque el título se trunca. Lleva
`formatVersion` —del marcador, no de ningún JSONL— para poder cambiarlo sin
romper la búsqueda de los que ya existen.

**Sin dependencias externas:** `dart:io` trae `HttpClient`. Agregar un paquete
HTTP metería una dependencia nueva en un repositorio que resuelve con
`--offline --enforce-lockfile`, y no compra nada que haga falta acá.

**`unknown` no es decorativo.** Si el `POST` no devuelve respuesta —la conexión
se corta, el tiempo se agota—, el desenlace es `PullRequestUnknown`, **nunca**
`PullRequestFailed`: el PR puede haberse creado. Quien reciba `unknown` vuelve a
llamar a `open`, y la búsqueda idempotente lo encuentra.

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/forge/test/github_test.dart` con un `HttpServer` local que hace
de API. Las cuatro pruebas que la propuesta exige de este paquete:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer api;
  late List<String> pedidos;
  late List<Map<String, Object?>> prsExistentes;
  int creados = 0;
  bool cortarLaRespuestaDelPost = false;

  setUp(() async {
    pedidos = [];
    prsExistentes = [];
    creados = 0;
    cortarLaRespuestaDelPost = false;
    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((p) async {
      pedidos.add('${p.method} ${p.uri.path}?${p.uri.query}');
      if (p.method == 'GET') {
        p.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(prsExistentes));
        await p.response.close();
        return;
      }
      if (cortarLaRespuestaDelPost) {
        await p.response.close();
        await api.close(force: true);
        return;
      }
      creados++;
      final cuerpo = jsonDecode(await utf8.decoder.bind(p).join()) as Map;
      prsExistentes.add({
        'html_url': 'https://forja/pr/$creados',
        'state': 'open',
        'merged_at': null,
        'body': cuerpo['body'],
        'head': {'sha': 'commit-1'},
      });
      p.response
        ..statusCode = 201
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(prsExistentes.last));
      await p.response.close();
    });
  });

  tearDown(() async => api.close(force: true));

  // Construí acá la solicitud con los mismos valores que la tarea 5 usa en sus
  // pruebas: `runId: 'corrida-1'`, `revision: 'commit-1'`,
  // `arbolDeLaRevision` igual a `candidato.contentRevision`.

  test('open repetido no crea un segundo PR', () async {
    final salida = construirSalida(api.port);
    final primero = await salida.open(solicitud());
    final segundo = await salida.open(solicitud());
    expect(primero, isA<PullRequestOpen>());
    expect(segundo, isA<PullRequestOpen>());
    expect((primero as PullRequestOpen).url,
        (segundo as PullRequestOpen).url);
    expect(creados, 1);
  });

  test('un PR con la misma rama pero otra revisión NO se reutiliza', () async {
    prsExistentes.add({
      'html_url': 'https://forja/pr/ajeno',
      'state': 'open',
      'merged_at': null,
      'body': '<!-- shipflow:pr formatVersion=1 runId=otra revision=OTRA -->',
      'head': {'sha': 'OTRA'},
    });
    final salida = construirSalida(api.port);
    final r = await salida.open(solicitud());
    expect(creados, 1, reason: 'rama y base no alcanzan como clave');
    expect((r as PullRequestOpen).url, isNot(contains('ajeno')));
  });

  test('una respuesta perdida produce unknown, no failed', () async {
    cortarLaRespuestaDelPost = true;
    final salida = construirSalida(api.port);
    final r = await salida.open(solicitud());
    expect(r, isA<PullRequestUnknown>());
    expect(r.retryable, isTrue);
  });

  test('un PR fusionado devuelve URL; uno cerrado da incompleto no '
      'reintentable', () async {
    prsExistentes.add({
      'html_url': 'https://forja/pr/7',
      'state': 'closed',
      'merged_at': '2026-09-14T00:00:00Z',
      'body': marcadorEsperado(),
      'head': {'sha': 'commit-1'},
    });
    expect(await construirSalida(api.port).open(solicitud()),
        isA<PullRequestMerged>());

    prsExistentes.clear();
    prsExistentes.add({
      'html_url': 'https://forja/pr/8',
      'state': 'closed',
      'merged_at': null,
      'body': marcadorEsperado(),
      'head': {'sha': 'commit-1'},
    });
    final cerrado = await construirSalida(api.port).open(solicitud());
    expect(cerrado, isA<PullRequestClosed>());
    expect(cerrado.retryable, isFalse);
    expect(cerrado.nextAction, AccionSiguiente.entregaNuevaExplicita);
  });
}
```

Escribí `construirSalida(int puerto)`, `solicitud()` y `marcadorEsperado()` como
ayudantes al final del archivo. `construirSalida` usa un `EmpujeAislado` cuyo
`programa` apunta a un script que sale con `0` sin hacer nada: esta suite prueba
la API, no el push, y el push ya tiene la suya.

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/forge/test/github_test.dart
```

Esperado: FALLA, `Undefined name 'SalidaDePrDeGitHub'`.

- [ ] **Paso 3: implementar**

`SalidaDePrDeGitHub.open` hace, en este orden:

1. **Pide la credencial** a `CredentialSource`. Si es nula, devuelve
   `PushFailed(causa: CausaDePublicacion.autenticacion)` sin tocar la red.
2. **Busca** con `GET /repos/<duenio>/<repositorio>/pulls?head=<duenio>:<rama>&base=<base>&state=all`.
   De los que vuelven, se queda con el que cumple **las tres** condiciones: el
   `head.sha` es `request.revision`, el cuerpo contiene el marcador estable con
   ese mismo `runId` y esa misma `revision`, y el estado no contradice nada.
   - `state == 'open'` → `PullRequestOpen(url: html_url)`. **No empuja de
     nuevo.**
   - `merged_at != null` → `PullRequestMerged(url: html_url)`.
   - `state == 'closed'` y `merged_at == null` → `PullRequestClosed(url: html_url)`.
3. **Si no hay ninguno, empuja** con `EmpujeAislado`. Un `NoEmpujado` se
   devuelve tal cual: su `desenlace` ya es un `PublicationOutcome`.
4. **Crea el PR** con `POST /repos/<duenio>/<repositorio>/pulls`, cuerpo
   `{'title': request.titulo, 'head': rama, 'base': base, 'body': <tarea 10>}`.
   - `201` → `PullRequestOpen(url: html_url)`.
   - `401` → `PullRequestFailed(causa: autenticacion)`.
   - `403` → `PullRequestFailed(causa: permisos)`.
   - `422` → `PullRequestFailed(causa: rechazoDeLaForja)`.
   - cualquier otro código → `PullRequestFailed(causa: desconocida)`.
   - **excepción o respuesta incompleta** → `PullRequestUnknown(causa: red)`.
     Nunca `failed`: el PR puede haberse creado, y reportarlo como fallo hace
     que el reintento cree el segundo.

La autenticación va en el encabezado, dentro de `use`:

```dart
  pedido.headers.set(
    HttpHeaders.authorizationHeader,
    credencial.use((secreto) => 'Bearer $secreto'),
  );
  pedido.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
  pedido.headers.set('X-GitHub-Api-Version', '2022-11-28');
```

**Ningún mensaje de la API se copia a `safeReason`.** El cuerpo de la respuesta
se usa para el código de estado y nada más.

- [ ] **Paso 4: correr y ver que pasa**

```
dart test packages/forge
dart analyze --fatal-infos
```

- [ ] **Paso 5: commitear**

```bash
git add packages/forge
git commit -m "Un PR repetido no es un PR nuevo, y una respuesta perdida no es un fallo"
```

---

### Tarea 10: el render, que es lo único que sabe la sintaxis del proveedor

**Archivos:**
- Crear: `packages/forge/lib/src/cuerpo.dart`
- Modificar: `packages/forge/lib/src/github.dart` (lo usa)
- Test: `packages/forge/test/cuerpo_test.dart`

**Interfaces:**
- Consume: `PullRequestRequest`, `ArtefactoDeRevision`,
  `SuperficieDeVerificacion`, `AfirmacionCubierta`, `EntradaDeCriterio`.
- Produce: `String cuerpoDeGitHub(PullRequestRequest solicitud)` y
  `String tituloDeGitHub(PullRequestRequest solicitud)`.

**Por qué vive acá y no en un renderizador neutral.** Un componente neutral
decide la **estructura**; el adapter aplica la **sintaxis**. Un renderizador
«neutral» que produjera una alerta con sintaxis de GitHub tendría neutralidad
falsa, y `forja-en-su-adapter` —la tarea 11— se pondría roja.

**Qué tiene que decir el cuerpo, y no es negociable:**

- `alcanceDeLoAfirmado` **completo y textual**, arriba de todo. Sin él,
  «cubierto» se lee como una afirmación sobre el cambio entero.
- La advertencia obligatoria cuando `solicitud.incompleto`, en una alerta de
  GitHub (`> [!WARNING]`), **antes** de cualquier cosa que se lea como verde.
- Cada `AfirmacionCubierta` con su control, su sujeto y su afirmación.
- Cada `EntradaDeCriterio` con su motivo y su detalle. **Las entradas sin
  sujeto van primero**: son las que hablan de la corrida entera.
- Si no hay plan, `sinPlanPorque` textual. Un artefacto sin plan afirmaría por
  omisión que no hacía falta ninguno.
- El marcador estable, última línea, como comentario HTML.

**Y lo que NO puede decir:** ni `excludedLocalChanges`, ni rutas del workspace
temporal, ni nada que el revisor remoto no pueda ver. Publicarle rutas locales
no es accionable y filtra nombres de trabajo local.

- [ ] **Paso 1: escribir las pruebas que fallan**

```dart
  test('el alcance va textual y la advertencia va antes de lo verde', () {
    final cuerpo = cuerpoDeGitHub(solicitudIncompleta());
    expect(cuerpo, contains(ArtefactoDeRevision.alcanceSoloPR));
    expect(cuerpo, contains('> [!WARNING]'));
    expect(cuerpo.indexOf('> [!WARNING]'),
        lessThan(cuerpo.indexOf('## Qué quedó cubierto')));
  });

  test('sin advertencia cuando la superficie está verde', () {
    expect(cuerpoDeGitHub(solicitudVerde()), isNot(contains('[!WARNING]')));
  });

  test('cada entrada que requiere criterio aparece con su motivo', () {
    final cuerpo = cuerpoDeGitHub(solicitudConCriterio());
    expect(cuerpo, contains('sin cascada'));
    expect(cuerpo, contains('el entorno no se derivó'));
  });

  test('el marcador estable es la última línea y lleva runId y revisión', () {
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    final ultima = cuerpo.trimRight().split('\n').last;
    expect(ultima, startsWith('<!-- shipflow:pr formatVersion=1'));
    expect(ultima, contains('runId=corrida-1'));
    expect(ultima, contains('revision=commit-1'));
  });

  test('no filtra nada local', () {
    final cuerpo = cuerpoDeGitHub(solicitudVerde());
    expect(cuerpo, isNot(contains(Directory.systemTemp.path)));
    expect(cuerpo.toLowerCase(), isNot(contains('excludedlocalchanges')));
  });

  test('el título sale de la solicitud y se trunca sin comerse la '
      'advertencia', () {
    final larga = solicitudIncompletaConIntencionLarga();
    final titulo = tituloDeGitHub(larga);
    expect(titulo.length, lessThanOrEqualTo(256));
    expect(titulo, startsWith(PullRequestRequest.prefijoIncompleto));
  });
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/forge/test/cuerpo_test.dart
```

- [ ] **Paso 3: implementar**

`tituloDeGitHub` devuelve `solicitud.titulo` truncado a 256 caracteres
**conservando el prefijo**: si hay que cortar, se corta la intención, nunca la
advertencia. `cuerpoDeGitHub` arma las secciones en el orden de arriba y cierra
con el marcador.

- [ ] **Paso 4: correr, y commitear**

```
dart test packages/forge && dart analyze --fatal-infos
```

```bash
git add packages/forge
git commit -m "La sintaxis del proveedor no sale de su adapter"
```

---

### Tarea 11: la regla `forja-en-su-adapter`

**Archivos:**
- Modificar: `tool/analisis/bin/check.dart`
- Modificar: `arquitectura.json`
- Test: el arnés de sabotajes, `python3 tool/checks/probar_reglas.py`

**Interfaces:**
- Produce: la regla `forja-en-su-adapter` en `arquitectura.json`, aplicada por
  `tool/analisis`, con su violación canónica, su caso ciego y sus sabotajes.

**Qué enuncia.** *Quién es la forja lo sabe `packages/forge/` y ningún otro
paquete.* Sin esto, «el adapter del proveedor vive en su propio paquete» es una
intención escrita, y la primera vez que a alguien le convenga poner una alerta
con sintaxis de GitHub en un componente neutral, nada se entera.

**Cómo se aplica, y qué NO hace.** El universo se acota **por ruta** —los `.dart`
bajo `lib/` y `bin/` de todos los paquetes MENOS `forge`—, y dentro de ese
universo se busca:

1. Un identificador `HttpClient`, derivado del árbol sintáctico. **Falso
   positivo deliberado**: una clase propia homónima se reporta igual, porque sin
   resolver no se puede decir cuál es; el precio es renombrarla. Es la misma
   decisión que ya toma `subprocesos-con-entorno-saneado` con `Process`.
2. El nombre del proveedor o su host, como texto.

**No se resuelve el árbol.** `subprocesos-con-entorno-saneado` ya lo hace y
costó que el job de arquitectura pasara de ~3 min a ~11–12 contra un límite de
20. Una segunda regla resolviendo lo empujaría al límite, y la ganancia acá es
menor: el universo ya está acotado por ruta, que es lo que la regla dura de
`CLAUDE.md` exige.

**Residuo declarado, y va en el `alcance`:** el segundo criterio es textual, así
que caza una regresión literal y no una promesa equivalente escrita con otras
palabras —«la forja principal», el host sin el nombre—. Lo que el criterio
textual **no** puede hacer es decidir qué archivos se miran: eso lo decide la
ruta. Y el primer criterio no ve un alias (`final C = HttpClient;`).

- [ ] **Paso 1: declarar la regla**

En `arquitectura.json`, agregá `forja-en-su-adapter` con la misma forma que las
otras trece: `enunciado`, `origen` (propuesta §10, enmienda `365cfc1`), `tipo`,
`aplicada_por`, `alternativa`, `por_que` (con el argumento de la neutralidad
falsa y el del costo de resolver), `alcance` con `raiz`, `que_mira` y
`residuo_declarado`, `violacion_canonica`, `violaciones_extra` y `caso_ciego`.

`violacion_canonica`: un archivo en `packages/core/lib/src/_canario_forja.dart`
que arma un cuerpo con `> [!WARNING]` y nombra al proveedor. `debe_mencionar`:
`forge`.

`violaciones_extra`, una por agujero que la regla tiene que cubrir:

1. **`HttpClient` fuera de `forge`** — un archivo en `packages/orchestration`
   que instancia un cliente HTTP. `debe_mencionar`: `HttpClient`.
2. **El host, sin el nombre del proveedor** — `packages/cli` con la URL de la
   API en una constante. `debe_mencionar`: el host.
3. **En `bin/` y no en `lib/`** — el mismo canario bajo `packages/cli/bin/`.
   Una regla que mirara solo `lib/` dejaría abierto el ejecutable, que es
   justo donde es cómodo escribir un atajo. `debe_mencionar`: `forge`.

`caso_ciego`: un archivo de `packages/` que no parsea. Es simétrico a la
violación canónica: aquella prueba que el check detecta un EXCESO, este que
detecta una OMISIÓN. `por_que_ciega`: los identificadores salen del árbol
sintáctico; de un árbol parcial no sale ninguno, y un archivo que no se pudo
leer se lee igual que uno sin referencias al proveedor. `debe_mencionar`:
`no parsea`.

- [ ] **Paso 2: correr el arnés y ver que los sabotajes NO se detectan**

```
ARNES_ORIGEN=$(pwd) python3 tool/checks/probar_reglas.py
```

Esperado: FALLA. La regla está declarada y nadie la aplica, así que los cinco
sabotajes nuevos pasan en verde.

**Antes de correr esto, cerrá todo lo demás.** El arnés trabaja sobre una copia
privada y detecta cualquier cambio en el checkout compartido, incluidas las
marcas de tiempo de `.dart_tool`. No corras `dart test` ni edites archivos
mientras corre.

- [ ] **Paso 3: aplicar la regla en `check.dart`**

Agregá un visitante `_Forja extends RecursiveAstVisitor<void>` que junte los
`SimpleIdentifier` llamados `HttpClient`, y una pasada de texto por el mismo
archivo para el segundo criterio. El universo lo arma el recorrido de archivos
que ya existe, **excluyendo `packages/forge/`**.

El mensaje tiene que nombrar el archivo, el ámbito más interno y cuál de los dos
criterios disparó. Un mensaje que solo diga «violación» obliga a quien lo lee a
buscar qué encontró el check, y eso es exactamente lo que ADR-016 llama la peor
traducción posible.

Sumá el nombre de la regla al bloque que imprime el resumen, para que
`check.dart` diga `forja: ok — N archivos` como dice las otras.

- [ ] **Paso 4: correr el arnés y ver que ahora sí**

```
ARNES_ORIGEN=$(pwd) python3 tool/checks/probar_reglas.py
```

Esperado: `probar_reglas: ok` con **14 reglas** y los sabotajes subidos en
cinco, de los cuales uno más es un caso CIEGO.

- [ ] **Paso 5: commitear**

```bash
git add tool/analisis/bin/check.dart arquitectura.json
git commit -m "Que la forja viva en su adapter deja de ser una intención escrita"
```

---

### Tarea 12: los fakes y la suite de contrato

**Archivos:**
- Crear: `packages/plugin_fake/lib/src/publicacion.dart`
- Modificar: `packages/plugin_fake/lib/plugin_fake.dart` (export)
- Modificar: `packages/cli/pubspec.yaml` (dependencia de `forge`)
- Crear: `packages/cli/test/contrato_salida_de_pr_test.dart`
- Modificar: `arquitectura.json` (registro de `PullRequestSink`)

**Interfaces:**
- Produce: `class SalidaDePrFalsa implements PullRequestSink` y
  `class FuenteDeCredencialFalsa implements CredentialSource`, las dos
  **configuradas** con lo que deben responder.

**Por qué hace falta el fake, y qué NO es.** Un fake que reimplementa la lógica
del real deja de ser un segundo punto de vista y pasa a ser el mismo error
escrito dos veces. `SalidaDePrFalsa` no busca ni empuja: se le dice qué
`PublicationOutcome` devolver, y **cuenta las llamadas** para que la suite de
contrato pueda exigirle idempotencia a las dos implementaciones con la misma
prueba.

- [ ] **Paso 1: escribir la suite de contrato**

`packages/cli/test/contrato_salida_de_pr_test.dart` corre **las mismas**
pruebas contra la implementación real —con su servidor local, como en la tarea
9— y contra el fake. Seguí la forma de `contrato_topologia_test.dart`, que ya
existe: una función que recibe la implementación y el nombre, y dos
invocaciones.

Las invariantes que valen para toda implementación del puerto:

```dart
  test('$nombre · open devuelve un desenlace, nunca lanza por un fallo remoto',
      () async {
    expect(await sink.open(solicitud()), isA<PublicationOutcome>());
  });

  test('$nombre · repetir open con la misma solicitud no crea otro PR',
      () async {
    final a = await sink.open(solicitud());
    final b = await sink.open(solicitud());
    if (a is PublicacionUtilizable) {
      expect(b, isA<PublicacionUtilizable>());
      expect((b as PublicacionUtilizable).url, a.url);
    }
  });

  test('$nombre · un desenlace utilizable siempre trae URL con contenido',
      () async {
    final r = await sink.open(solicitud());
    if (r is PublicacionUtilizable) expect(r.url.trim(), isNotEmpty);
  });
```

- [ ] **Paso 2: correr y ver que falla**

```
dart test packages/cli/test/contrato_salida_de_pr_test.dart
```

Esperado: FALLA, `Undefined name 'SalidaDePrFalsa'`.

- [ ] **Paso 3: implementar el fake**

```dart
/// Un `PullRequestSink` que no habla con nadie. **Se configura**, no adivina.
class SalidaDePrFalsa implements PullRequestSink {
  /// Qué devuelve. El contrato exige que `open` repetido no cree un segundo
  /// PR, así que la primera respuesta se recuerda y se repite.
  final PublicationOutcome respuesta;

  final List<PullRequestRequest> recibidas = [];

  SalidaDePrFalsa({required this.respuesta});

  @override
  Future<PublicationOutcome> open(PullRequestRequest request) async {
    recibidas.add(request);
    return respuesta;
  }
}

/// Una `CredentialSource` configurada. **No lee el entorno**: si lo leyera, una
/// prueba pasaría o fallaría según el shell de quien la corre.
class FuenteDeCredencialFalsa implements CredentialSource {
  final Map<String, Credential> credenciales;

  const FuenteDeCredencialFalsa({this.credenciales = const {}});

  @override
  Future<Credential?> read(String key) async => credenciales[key];
}
```

Exportalos desde `packages/plugin_fake/lib/plugin_fake.dart` y agregá `forge` a
las dependencias de `packages/cli/pubspec.yaml`.

- [ ] **Paso 4: sacar `PullRequestSink` del registro de puertos sin implementación**

En `arquitectura.json`, borralo del mapa `sin_implementacion` y sumá al texto
del campo `_` de ese mapa, después de lo que ya dice de `VerificationEnvironment`:

```
PullRequestSink salio en la rebanada de la forja con UNA implementacion real —`SalidaDePrDeGitHub` en `forge`— y UNA falsa en plugin_fake, y con suite de contrato corriendo contra las dos: el puerto tiene un consumidor a la vista —`ship`— y dos puntos de vista que contrastar, que es la condicion que a `ChangeSink` y a `VerificationEnvironment` todavia les falta.
```

- [ ] **Paso 5: correr y ver que pasa**

```
dart pub get
dart test packages/cli packages/forge
cd tool/analisis && dart run bin/check.dart && cd ../..
dart analyze --fatal-infos
```

- [ ] **Paso 6: commitear**

```bash
git add packages/plugin_fake packages/cli arquitectura.json pubspec.lock
git commit -m "El puerto de la forja sale del registro con dos puntos de vista"
```

---

### Tarea 13: el grafo, el arnés entero, y el README

**Archivos:**
- Modificar: `grafo.jsonl` y sus proyecciones (regeneradas)
- Modificar: `README.md`

- [ ] **Paso 1: regenerar el grafo**

```
cd tool/analisis && dart pub get && dart run bin/grafo.dart && cd ../..
```

Si dice que el derivado difiere del commiteado, commiteá el derivado: un mapa
desactualizado es peor que no tener mapa.

- [ ] **Paso 2: documentar en el README**

Agregá a la sección de paquetes la fila de `forge`, y a la de reglas la de
`forja-en-su-adapter`. En la sección de residuos, dejá escrito:

- que la clasificación de causas del push mira el texto del `stderr` de nuestro
  propio hijo, y que lo que no reconoce cae en `desconocida`;
- que `/proc/<pid>/cmdline` deja ver el argv de nuestro `git`, y por qué eso es
  limitación de ambiente y no un fallo propio;
- que el segundo criterio de `forja-en-su-adapter` es textual y caza una
  regresión literal, no una promesa equivalente con otras palabras.

**No escribas ninguna cuenta que nada derive.** Los números que manda los
imprime el arnés en cada corrida.

- [ ] **Paso 3: el arnés entero, en este orden y sin tocar nada mientras corre**

```
python3 tool/checks/capas.py
cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart && cd ../..
dart test packages/core packages/orchestration packages/vcs packages/cli packages/plugin_dart packages/forge
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
ARNES_ORIGEN=$(pwd) python3 tool/checks/probar_reglas.py
python3 tool/checks/probar_recuperacion.py
```

- [ ] **Paso 4: commitear y abrir el PR**

```bash
git add -A
git commit -m "El mapa y el README, al día con la forja"
git push -u origin forja-y-credencial
```

El PR va contra `develop`. El cuerpo cuenta qué se midió —las cinco filas de la
tabla de canales— y qué quedó declarado como residuo.

---

## Lo que esta rebanada NO hace

Queda para la rebanada de `ship`, y está declarado para que nadie lo lea como
olvido:

- **Nadie llama a `PullRequestSink.open` todavía.** La composición vive en las
  pruebas. `ship` es quien la va a hacer productiva.
- **`--retry-publication` no existe.** El desenlace ya sabe decir
  `retryable`; el comando que lo consume es de la rebanada siguiente.
- **`ShipOutcome`, `EstadoPublicable` y `CausaDeNoIntento` no se construyen
  acá.** Son §12 y §13.
- **El código de salida `6` no se emite.** `packages/cli/lib/src/salida.dart`
  no se toca.
- **La raíz de composición todavía no arma un `EntornoDelProceso` real**: el
  respaldo de las dos costuras lo construye a partir de `Platform.environment`,
  que es lo que hace que el invariante valga aunque nadie inyecte. Quien componga
  `ship` va a capturarlo una vez y pasarlo.

---

## El corpus, que va en su propio PR

`sdlc-agentico` es otro repositorio y otro PR, contra `production`. La enmienda
de la propuesta ya está —`365cfc1`—; falta lo normativo, y **una parte de esto
no es opcional**: `arnes-propio/checks/estados.py` cruza las reglas del corpus
contra `shipflow/arquitectura.json`, así que la regla catorce lo pone rojo hasta
que el corpus la declare.

- [ ] **ADR nuevo** que vuelva normativas §10 y §11 con su tabla de invariantes
  ejecutables, como `ADR-020` y `ADR-021`. Lo que tiene que quedar normativo:
  la jerarquía sellada con `unknown`; que `retryable`, `deliveryStatus` y
  `nextAction` sean derivados; que `safeReason` no copie nunca la excepción
  externa; la segregación del puerto de credencial; y que el push vacíe las dos
  cadenas del usuario —ganchos y credential helpers— con la credencial en la
  URL.
- [ ] **`REGISTRO-DELTAS.md`**: los deltas de esta rebanada, continuando desde
  `D-145`.
- [ ] **`docs/03` y `docs/06`**: propagación de la segregación de
  `CredentialSource` y del paquete `forge` en el mapa de dependencias.
- [ ] **`INVENTARIO.md`**: lo regenera `cifras.py --fix`.
- [ ] Correr los cuatro checks antes de commitear:

```
cd /Users/zeref/Documents/SDLC/sdlc-agentico
for f in arnes-propio/checks/*.py; do python3 "$f"; done
```

Los cuatro tienen que decir `ok`. `cifras.py` se arregla con `--fix` y se vuelve
a correr sin él.
