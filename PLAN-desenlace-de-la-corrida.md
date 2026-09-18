# El desenlace de la corrida y su documento — plan de implementación

> **Para trabajadores agénticos:** SUB-SKILL REQUERIDA: usá superpowers:subagent-driven-development (recomendada) o superpowers:executing-plans para implementar este plan tarea por tarea. Los pasos usan casillas (`- [ ]`) para seguimiento.

**Objetivo:** dar al dominio el desenlace de una corrida de `ship` como **un solo tipo cerrado** cuyas combinaciones inválidas no son construibles, y el documento autoritativo que lo persiste y permite recuperar una corrida interrumpida.

**Arquitectura:** `ShipOutcome` es una jerarquía sellada en `core` con constructores privados y **una sola entrada**: una fábrica que deriva la variante de los hechos de la corrida, con precedencia explícita. Los códigos de proceso salen de una función total sobre ese dominio cerrado, así que una variante nueva no compila hasta que alguien decida su código. El documento de la corrida es un tipo serializable de `core` con sus transiciones validadas, y su persistencia —archivo temporal y `rename`— vive en `cli`, que es quien tiene entrada y salida.

**Stack:** Dart puro, workspace de pub. Sin dependencias externas nuevas.

**Spec:** `/Users/zeref/Documents/SDLC/sdlc-agentico/borradores/PROPUESTA-ship-artefacto-y-forja.md` §9 y §12, con las enmiendas `095c993` y `24051eb`. La normativa de las rebanadas anteriores está en `adr/ADR-020`, `ADR-021` y `ADR-022` del mismo repositorio.

**Esta es la primera de tres.** La cuarta rebanada de `ship` resultó ser tres: **4a** es esta —el desenlace y el documento, sin CLI—; **4b** es el comando de punta a punta; **4c** es `--retry-publication` y la reconciliación. Nada de acá compone una corrida: se prueba el tipo, la derivación, la serialización y la persistencia.

## Restricciones globales

- **`core` no tiene dependencias externas ni entrada/salida.** Lo aplican `nucleo-sin-externas` y `nucleo-sin-entrada-salida`. Nada de `dart:io` en `core`.
- **Los tipos sellados serializan con `static fromJson` en la base y `factory` en cada variante.** Un `factory` en la base es un `ConstructorDeclaration` y el verificador lo lee como «esta clase serializa», que en una base sellada es rojo. El patrón está escrito en `packages/core/lib/src/desenlace.dart`: mirá `StepOutcome` y `ResultadoDeEntorno`.
- **Cada `factory <Variante>.fromJson` empieza leyendo `json['kind']` dentro de la fábrica**, no en un ayudante: el verificador deriva las claves de los índices que la propia `fromJson` hace sobre su parámetro.
- **Toda clase de `core` con campos que no serializa está declarada** en `arquitectura.json` bajo `opacidad-declarada`. «No serializa» sin declarar es indistinguible de «nadie lo escribió todavía».
- **Nada derivable es además un campo asignable.** Con dos campos independientes se construye el estado contradictorio.
- **Un campo concreto redeclarado en una subclase dispara `overridden_fields` bajo `--fatal-infos`.** Si necesitás esa forma, poné un getter abstracto en la base y el campo concreto en la hoja.
- **`dart analyze --fatal-infos` limpio** y `dart format` sin cambios.
- **Los commits terminan con** `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- **Nunca corras `python3 tool/checks/probar_reglas.py` mientras editás**: trabaja sobre una copia privada y detecta cualquier cambio en el checkout compartido, hasta una marca de tiempo de `.dart_tool`. Lanzalo solo, esperá, y recién después seguí.
- **Orden de comprobación:** `grafo.dart` **antes** de `capas.py` — `capas.py` lee el grafo commiteado, no el árbol vivo.

## Ruling sobre una ambigüedad de §12

§12 escribe la precedencia como `errorInterno > secretDetected > verificationGate > confirmationMissing > previewOnly`, y su tabla de códigos tiene filas para `NoIntentado(previewOnly)`, `(confirmationMissing)`, `(verificationGate)` y `(secretDetected)` — **cuatro** causas, no cinco.

**Ruling: `CausaDeNoIntento` tiene cuatro valores y `errorInterno` es el ESTADO, no una causa.** La precedencia mezcla un estado con cuatro causas, y se lee así: si la corrida terminó en `errorInterno`, eso gana sobre un secreto detectado, y la variante que sale es `NoIntentado(verificationGate)` con estado `errorInterno` → código `70`.

El motivo de elegir esta lectura y no la otra: con cinco causas, la fila «`NoIntentado(verificationGate)` con `errorInterno`» de la tabla queda **inalcanzable**, porque `NoIntentado(errorInterno)` la taparía siempre. Una tabla con una fila que no se puede producir es peor que una ambigüedad: se lee como cobertura de un caso que no existe. Con cuatro, la tabla es total y no sobra ninguna fila.

**Costo si me equivoco:** un valor más en un enum y una fila más en la función de códigos.

---

## Estructura de archivos

| Archivo | Responsabilidad |
|---|---|
| `packages/core/lib/src/corrida.dart` **(nuevo)** | `EstadoPublicable`, `CausaDeNoIntento`, `ShipOutcome` y sus cinco variantes, y la fábrica que las deriva |
| `packages/core/lib/src/documento.dart` **(nuevo)** | `EstadoDelDocumento`, `DocumentoDeCorrida` y sus transiciones validadas |
| `packages/core/lib/core.dart` | Exports e índice |
| `packages/core/test/corrida_test.dart` **(nuevo)** | El tipo, la fábrica y la precedencia |
| `packages/core/test/documento_test.dart` **(nuevo)** | Las transiciones y lo que no es construible |
| `packages/core/test/serializacion_test.dart` | Registro de ida y vuelta de lo nuevo |
| `packages/vcs/lib/src/repositorio.dart` | `IndiceDesincronizado` tipada, en lugar de la revisión interpolada en dos cadenas |
| `packages/cli/lib/src/salida.dart` | Códigos `3`, `4` y `6`, y la función total sobre `ShipOutcome` |
| `packages/cli/lib/src/corrida.dart` **(nuevo)** | La persistencia del documento: temporal + `rename`, y la lectura para recuperar |
| `packages/cli/test/corrida_test.dart` **(nuevo)** | Que el documento sobrevive a una escritura interrumpida |
| `arquitectura.json` | Declaraciones de opacidad y de puertos que esto mueva |
| `README.md` | La rebanada, sus residuos, y el enlace al plan |

---

### Tarea 1: Los dos enums del desenlace

**Archivos:**
- Crear: `packages/core/lib/src/corrida.dart`
- Modificar: `packages/core/lib/core.dart`
- Test: `packages/core/test/corrida_test.dart`

**Interfaces:**
- Consume: `EstadoDeCorrida` de `packages/core/lib/src/desenlace.dart` (valores `verde`, `rojo`, `noConcluyente`, `errorInterno`).
- Produce: `enum EstadoPublicable { verde, rojo, noConcluyente }` con `static EstadoPublicable? desde(EstadoDeCorrida)`; `enum CausaDeNoIntento { secretDetected, verificationGate, confirmationMissing, previewOnly }`.

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/core/test/corrida_test.dart`:

```dart
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  group('EstadoPublicable', () {
    test('errorInterno NO tiene equivalente publicable', () {
      expect(EstadoPublicable.desde(EstadoDeCorrida.errorInterno), isNull);
    });

    test('los otros tres sí, y conservan el nombre', () {
      for (final par in {
        EstadoDeCorrida.verde: EstadoPublicable.verde,
        EstadoDeCorrida.rojo: EstadoPublicable.rojo,
        EstadoDeCorrida.noConcluyente: EstadoPublicable.noConcluyente,
      }.entries) {
        expect(EstadoPublicable.desde(par.key), par.value);
        expect(par.value.name, par.key.name);
      }
    });

    test('la conversión cubre TODOS los estados de corrida', () {
      // Si alguien agrega un estado, esta prueba lo obliga a decidir si es
      // publicable. Sin esto, un estado nuevo caería en el `null` por omisión
      // y quedaría no publicable sin que nadie lo hubiera decidido.
      var publicables = 0;
      for (final e in EstadoDeCorrida.values) {
        if (EstadoPublicable.desde(e) != null) publicables += 1;
      }
      expect(publicables, EstadoPublicable.values.length);
    });
  });

  group('CausaDeNoIntento', () {
    test('son cuatro, y errorInterno NO es una de ellas', () {
      expect(CausaDeNoIntento.values, hasLength(4));
      expect(
        CausaDeNoIntento.values.map((c) => c.name),
        isNot(contains('errorInterno')),
        reason:
            'errorInterno es un ESTADO, no una causa: entra por '
            'verificationGate. Ver el ruling del plan.',
      );
    });
  });
}
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/core/test/corrida_test.dart
```
Esperado: FALLA al compilar, porque `EstadoPublicable` no existe.

- [ ] **Paso 3: escribir los enums**

Creá `packages/core/lib/src/corrida.dart`:

```dart
/// El desenlace de una corrida de `ship`: qué pasó con el trabajo local y con
/// el efecto remoto, como **un solo tipo cerrado**.
///
/// **Por qué un tipo y no una conjunción de banderas.** La versión anterior del
/// diseño tenía una tabla que no era función: sus causas se solapaban —una
/// corrida sin confirmar puede además traer un secreto, y el arnés roto
/// coincidía con dos códigos a la vez— y admitía combinaciones que no
/// significan nada, como un pull request abierto sobre una corrida donde el
/// arnés se rompió.
library;

import 'desenlace.dart';

/// Los estados desde los que **se puede publicar**.
///
/// `errorInterno` no está, y esa ausencia es el mecanismo: sin él en el tipo,
/// una publicación sobre una corrida donde el arnés se rompió deja de ser
/// escribible. No hay que acordarse de comprobarlo.
enum EstadoPublicable {
  verde,
  rojo,
  noConcluyente;

  /// El publicable que le corresponde a un estado de corrida, o nulo si ese
  /// estado no autoriza publicar nada.
  ///
  /// **Devuelve nulo en vez de lanzar** porque «no se puede publicar» es un
  /// hecho del dominio que el llamador tiene que poder ramificar, no un error
  /// de programación.
  static EstadoPublicable? desde(EstadoDeCorrida estado) => switch (estado) {
    EstadoDeCorrida.verde => EstadoPublicable.verde,
    EstadoDeCorrida.rojo => EstadoPublicable.rojo,
    EstadoDeCorrida.noConcluyente => EstadoPublicable.noConcluyente,
    EstadoDeCorrida.errorInterno => null,
  };
}

/// Por qué una corrida no intentó publicar.
///
/// **Son cuatro y `errorInterno` no es una de ellas**: es un ESTADO, y entra
/// por [verificationGate]. Ver el ruling del plan de esta rebanada. Con cinco,
/// la fila «gate con errorInterno» de la tabla de códigos quedaría
/// inalcanzable, y una fila que no se puede producir se lee como cobertura de
/// un caso que no existe.
enum CausaDeNoIntento {
  /// El detector encontró un secreto en el diff de la rebanada.
  secretDetected,

  /// La compuerta por estado no autorizó: rojo o no concluyente sin
  /// `--allow-incomplete`, o el arnés roto, que no se autoriza con nada.
  verificationGate,

  /// Falta `--yes`. Sin él la corrida se comporta como una previsualización.
  confirmationMissing,

  /// `--dry-run`: no se pidió efecto ninguno.
  previewOnly,
}
```

Agregá a `packages/core/lib/core.dart` el export en orden alfabético y su entrada en el índice del doc comment:

```dart
/// - **corrida** — [ShipOutcome], el desenlace de una corrida de `ship`.
```

```dart
export 'src/corrida.dart';
```

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/core/test/corrida_test.dart
dart analyze --fatal-infos packages/core
dart format --output=none --set-exit-if-changed packages/core
```
Esperado: las tres pruebas pasan y las dos comprobaciones salen con 0.

- [ ] **Paso 5: commitear**

```bash
git add packages/core/lib/src/corrida.dart packages/core/lib/core.dart packages/core/test/corrida_test.dart
git commit -m "Publicar tiene estados propios, y el arnés roto no es uno

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 2: La jerarquía sellada, con constructores privados

**Archivos:**
- Modificar: `packages/core/lib/src/corrida.dart`
- Test: `packages/core/test/corrida_test.dart`

**Interfaces:**
- Consume: `EstadoPublicable`, `CausaDeNoIntento` de la tarea 1; `EstadoDeCorrida` de `desenlace.dart`; `PublicacionUtilizable` y `PublicacionNoUtilizable` de `publicacion.dart`.
- Produce: `sealed class ShipOutcome` con `String get kind`, `Map<String, Object?> toJson()` y `static ShipOutcome fromJson(Map<String, Object?>)`; y las variantes `NoIntentado`, `NoAplicado`, `LocalInconsistente`, `Publicado`, `PublicacionIncompleta`, todas con constructor privado.

- [ ] **Paso 1: escribir las pruebas que fallan**

Agregá al final del `main` de `packages/core/test/corrida_test.dart`:

```dart
  group('ShipOutcome', () {
    test('Publicado no acepta un estado que no sea publicable', () {
      // El tipo lo impide: `Publicado` lleva `EstadoPublicable`, que no tiene
      // errorInterno. Esta prueba fija que el campo sea de ese tipo y no de
      // `EstadoDeCorrida`, que es lo que lo volvería escribible.
      final publicado = ShipOutcome.publicadoParaLaPrueba(
        pr: PullRequestOpen(url: 'https://forja/pr/1'),
        verificacion: EstadoPublicable.verde,
      );
      expect(publicado.verificacion, isA<EstadoPublicable>());
    });

    test('NoIntentado sí lleva el estado ENTERO', () {
      // Es el camino por donde errorInterno sale, así que acá el tipo tiene
      // que ser el completo.
      final no = ShipOutcome.noIntentadoParaLaPrueba(
        causa: CausaDeNoIntento.verificationGate,
        verificacion: EstadoDeCorrida.errorInterno,
      );
      expect(no.verificacion, EstadoDeCorrida.errorInterno);
    });

    test('cada variante vuelve a ser ella misma por JSON', () {
      final casos = <ShipOutcome>[
        ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.previewOnly,
          verificacion: EstadoDeCorrida.verde,
        ),
        ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
        ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
        ShipOutcome.publicadoParaLaPrueba(
          pr: PullRequestMerged(url: 'https://forja/pr/2'),
          verificacion: EstadoPublicable.rojo,
        ),
        ShipOutcome.publicacionIncompletaParaLaPrueba(
          remoto: PushUnknown(causa: CausaDePublicacion.red),
          verificacion: EstadoPublicable.noConcluyente,
        ),
      ];
      for (final caso in casos) {
        final vuelta = ShipOutcome.fromJson(caso.toJson());
        expect(vuelta.toJson(), caso.toJson(), reason: caso.kind);
        expect(vuelta.runtimeType, caso.runtimeType);
      }
    });

    test('cada fromJson rechaza un discriminador ajeno', () {
      final ajenos = <String, ShipOutcome>{
        for (final caso in <ShipOutcome>[
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.previewOnly,
            verificacion: EstadoDeCorrida.verde,
          ),
          ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
          ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
          ShipOutcome.publicadoParaLaPrueba(
            pr: PullRequestOpen(url: 'https://forja/pr/3'),
            verificacion: EstadoPublicable.verde,
          ),
          ShipOutcome.publicacionIncompletaParaLaPrueba(
            remoto: PushFailed(causa: CausaDePublicacion.permisos),
            verificacion: EstadoPublicable.verde,
          ),
        ])
          caso.kind: caso,
      };
      expect(ajenos, hasLength(5), reason: 'los kind tienen que ser distintos');
      for (final entrada in ajenos.entries) {
        final impostor = Map<String, Object?>.from(entrada.value.toJson())
          ..['kind'] = 'otro-kind';
        expect(
          () => ShipOutcome.fromJson(impostor),
          throwsFormatException,
          reason: entrada.key,
        );
      }
    });

    test('un kind desconocido no se adivina', () {
      expect(
        () => ShipOutcome.fromJson({'kind': 'inventado'}),
        throwsFormatException,
      );
    });
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/core/test/corrida_test.dart
```
Esperado: FALLA al compilar, porque `ShipOutcome` no existe.

- [ ] **Paso 3: escribir la jerarquía**

Agregá a `packages/core/lib/src/corrida.dart`. Importá también `publicacion.dart`.

**Los constructores son privados y la única entrada real es la fábrica de la tarea 3.** Las entradas `…ParaLaPrueba` existen para que la suite pueda construir variantes sin pasar por la derivación; es el mismo precedente que `RepositorioGit.identidadCapturadaParaLaPrueba`.

```dart
sealed class ShipOutcome {
  const ShipOutcome();

  /// El discriminador. **Estable**: es lo que un consumidor automático lee.
  String get kind;

  Map<String, Object?> toJson();

  static ShipOutcome fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    return switch (kind) {
      'noIntentado' => NoIntentado.fromJson(json),
      'noAplicado' => NoAplicado.fromJson(json),
      'localInconsistente' => LocalInconsistente.fromJson(json),
      'publicado' => Publicado.fromJson(json),
      'publicacionIncompleta' => PublicacionIncompleta.fromJson(json),
      final otro => throw FormatException(
        'ShipOutcome.fromJson no conoce el desenlace «$otro». Un '
        'discriminador que nadie declaró no se adivina: un desenlace mal '
        'leído decide qué se publica.',
      ),
    };
  }

  /// Lanza si [leido] no es [propio]. La llama cada fábrica de variante, con
  /// el valor que ella misma leyó de `json['kind']`.
  static void _exigirKind(Object? leido, String propio) {
    if (leido != propio) {
      throw FormatException(
        '$propio.fromJson recibió un discriminador que no es el suyo: '
        '«$leido».',
      );
    }
  }

  // Entradas para la suite. La derivación real es `ShipOutcome.derivar`.
  static NoIntentado noIntentadoParaLaPrueba({
    required CausaDeNoIntento causa,
    required EstadoDeCorrida verificacion,
  }) => NoIntentado._(causa: causa, verificacion: verificacion);

  static NoAplicado noAplicadoParaLaPrueba({required String headObservado}) =>
      NoAplicado._(headObservado: headObservado);

  static LocalInconsistente localInconsistenteParaLaPrueba({
    required String revision,
  }) => LocalInconsistente._(revision: revision);

  static Publicado publicadoParaLaPrueba({
    required PublicacionUtilizable pr,
    required EstadoPublicable verificacion,
  }) => Publicado._(pr: pr, verificacion: verificacion);

  static PublicacionIncompleta publicacionIncompletaParaLaPrueba({
    required PublicacionNoUtilizable remoto,
    required EstadoPublicable verificacion,
  }) => PublicacionIncompleta._(remoto: remoto, verificacion: verificacion);
}

/// No se intentó publicar, y acá está por qué.
///
/// **Lleva `EstadoDeCorrida` entero y no `EstadoPublicable`**: es el camino por
/// donde `errorInterno` sale, así que acotar el tipo acá lo dejaría sin
/// representación.
final class NoIntentado extends ShipOutcome {
  final CausaDeNoIntento causa;
  final EstadoDeCorrida verificacion;

  const NoIntentado._({required this.causa, required this.verificacion});

  @override
  String get kind => 'noIntentado';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'causa': causa.name,
    'verificacion': verificacion.name,
  };

  factory NoIntentado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'noIntentado');
    return NoIntentado._(
      causa: CausaDeNoIntento.values.byName(json['causa']! as String),
      verificacion: EstadoDeCorrida.values.byName(
        json['verificacion']! as String,
      ),
    );
  }
}

/// El CAS fue rechazado porque `HEAD` se movió. **Nada más lo produce**: un
/// fallo de permisos o de entrada y salida no es una detención benigna.
///
/// La garantía es «la rama y `HEAD` no se movieron», **no «cero commit»**:
/// `commit-tree` corre antes del CAS, así que cuando el CAS falla el objeto
/// existe, inalcanzable desde cualquier referencia y recogible por el `gc`.
final class NoAplicado extends ShipOutcome {
  /// Qué `HEAD` se encontró. Es lo que le permite a quien reintente saber
  /// sobre qué se va a reconstruir el candidato.
  final String headObservado;

  const NoAplicado._({required this.headObservado});

  @override
  String get kind => 'noAplicado';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'head': headObservado};

  factory NoAplicado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'noAplicado');
    return NoAplicado._(headObservado: json['head']! as String);
  }
}

/// El commit existe y el índice quedó sin sincronizar.
///
/// **La revisión viaja como dato y no dentro de un mensaje**: quien recupere
/// tiene que poder comprobar si el índice ya coincide, y eso no se hace
/// parseando texto.
final class LocalInconsistente extends ShipOutcome {
  final String revision;

  const LocalInconsistente._({required this.revision});

  @override
  String get kind => 'localInconsistente';

  @override
  Map<String, Object?> toJson() => {'kind': kind, 'revision': revision};

  factory LocalInconsistente.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'localInconsistente');
    return LocalInconsistente._(revision: json['revision']! as String);
  }
}

/// Hay un pull request utilizable.
final class Publicado extends ShipOutcome {
  final PublicacionUtilizable pr;
  final EstadoPublicable verificacion;

  const Publicado._({required this.pr, required this.verificacion});

  @override
  String get kind => 'publicado';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'pr': pr.toJson(),
    'verificacion': verificacion.name,
  };

  factory Publicado.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'publicado');
    final pr = PublicationOutcome.fromJson(
      Map<String, Object?>.from(json['pr']! as Map),
    );
    if (pr is! PublicacionUtilizable) {
      throw FormatException(
        'Publicado.fromJson recibió un desenlace remoto que no es '
        'utilizable: «${pr.kind}». Reconstruirlo dejaría escribible por JSON '
        'exactamente lo que el tipo impide construir en memoria.',
      );
    }
    return Publicado._(
      pr: pr,
      verificacion: EstadoPublicable.values.byName(
        json['verificacion']! as String,
      ),
    );
  }
}

/// El trabajo local se completó y el efecto remoto no.
final class PublicacionIncompleta extends ShipOutcome {
  final PublicacionNoUtilizable remoto;
  final EstadoPublicable verificacion;

  const PublicacionIncompleta._({
    required this.remoto,
    required this.verificacion,
  });

  @override
  String get kind => 'publicacionIncompleta';

  @override
  Map<String, Object?> toJson() => {
    'kind': kind,
    'remoto': remoto.toJson(),
    'verificacion': verificacion.name,
  };

  factory PublicacionIncompleta.fromJson(Map<String, Object?> json) {
    ShipOutcome._exigirKind(json['kind'], 'publicacionIncompleta');
    final remoto = PublicationOutcome.fromJson(
      Map<String, Object?>.from(json['remoto']! as Map),
    );
    if (remoto is! PublicacionNoUtilizable) {
      throw FormatException(
        'PublicacionIncompleta.fromJson recibió un desenlace remoto '
        'utilizable: «${remoto.kind}». Un pull request abierto no es una '
        'publicación incompleta.',
      );
    }
    return PublicacionIncompleta._(
      remoto: remoto,
      verificacion: EstadoPublicable.values.byName(
        json['verificacion']! as String,
      ),
    );
  }
}
```

- [ ] **Paso 4: registrar la ida y vuelta**

Agregá las cinco variantes al mapa de `packages/core/test/serializacion_test.dart`, siguiendo cómo están registradas las de `StepOutcome`.

- [ ] **Paso 5: correr y comprobar que pasa**

```
dart test packages/core
dart analyze --fatal-infos packages/core
dart format --output=none --set-exit-if-changed packages/core
cd tool/analisis && dart run bin/check.dart && cd ../..
```
Esperado: todo con 0. `check.dart` tiene que mostrar **cinco clases serializables más** que antes.

- [ ] **Paso 6: commitear**

```bash
git add packages/core/lib/src/corrida.dart packages/core/test/corrida_test.dart packages/core/test/serializacion_test.dart
git commit -m "Un PR abierto sobre una corrida rota deja de ser escribible

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 3: La fábrica que deriva, con su precedencia

**Archivos:**
- Modificar: `packages/core/lib/src/corrida.dart`
- Test: `packages/core/test/corrida_test.dart`

**Interfaces:**
- Produce: `static ShipOutcome ShipOutcome.derivar({required EstadoDeCorrida verificacion, required bool huboSecreto, required bool seConfirmo, required bool soloPreview, required bool autorizaIncompleto, PublicationOutcome? remoto, String? headQueRechazoElCas, String? revisionConIndiceSucio})`.

- [ ] **Paso 1: escribir las pruebas que fallan**

Agregá al `main` de `packages/core/test/corrida_test.dart`:

```dart
  group('ShipOutcome.derivar · la precedencia', () {
    ShipOutcome derivar({
      EstadoDeCorrida verificacion = EstadoDeCorrida.verde,
      bool huboSecreto = false,
      bool seConfirmo = true,
      bool soloPreview = false,
      bool autorizaIncompleto = false,
      PublicationOutcome? remoto,
      String? headQueRechazoElCas,
      String? revisionConIndiceSucio,
    }) => ShipOutcome.derivar(
      verificacion: verificacion,
      huboSecreto: huboSecreto,
      seConfirmo: seConfirmo,
      soloPreview: soloPreview,
      autorizaIncompleto: autorizaIncompleto,
      remoto: remoto,
      headQueRechazoElCas: headQueRechazoElCas,
      revisionConIndiceSucio: revisionConIndiceSucio,
    );

    test('el arnés roto gana sobre TODO lo demás', () {
      final r = derivar(
        verificacion: EstadoDeCorrida.errorInterno,
        huboSecreto: true,
        seConfirmo: false,
        soloPreview: true,
        autorizaIncompleto: true,
      );
      expect(r, isA<NoIntentado>());
      expect((r as NoIntentado).causa, CausaDeNoIntento.verificationGate);
      expect(r.verificacion, EstadoDeCorrida.errorInterno);
    });

    test('el secreto le gana a la confirmación que falta', () {
      // Es el punto que cambia un contrato vigente: sin `--yes` se salía con 0
      // sin condición. Que el usuario no fuera a confirmar no vuelve menos
      // cierto que hay un secreto.
      final r = derivar(huboSecreto: true, seConfirmo: false);
      expect((r as NoIntentado).causa, CausaDeNoIntento.secretDetected);
    });

    test('el secreto le gana a la previsualización', () {
      final r = derivar(huboSecreto: true, soloPreview: true);
      expect((r as NoIntentado).causa, CausaDeNoIntento.secretDetected);
    });

    test('la compuerta le gana a la confirmación que falta', () {
      final r = derivar(verificacion: EstadoDeCorrida.rojo, seConfirmo: false);
      expect((r as NoIntentado).causa, CausaDeNoIntento.verificationGate);
    });

    test('con --allow-incomplete, rojo y no concluyente SÍ pasan la compuerta',
        () {
      for (final estado in [
        EstadoDeCorrida.rojo,
        EstadoDeCorrida.noConcluyente,
      ]) {
        final r = derivar(
          verificacion: estado,
          autorizaIncompleto: true,
          remoto: PullRequestOpen(url: 'https://forja/pr/9'),
        );
        expect(r, isA<Publicado>(), reason: estado.name);
      }
    });

    test('--allow-incomplete NO autoriza el arnés roto', () {
      final r = derivar(
        verificacion: EstadoDeCorrida.errorInterno,
        autorizaIncompleto: true,
        remoto: PullRequestOpen(url: 'https://forja/pr/9'),
      );
      expect(r, isA<NoIntentado>());
    });

    test('la confirmación que falta le gana a la previsualización', () {
      final r = derivar(seConfirmo: false, soloPreview: true);
      expect((r as NoIntentado).causa, CausaDeNoIntento.confirmationMissing);
    });

    test('el CAS rechazado da NoAplicado con el head que se vio', () {
      final r = derivar(headQueRechazoElCas: 'c' * 40);
      expect(r, isA<NoAplicado>());
      expect((r as NoAplicado).headObservado, 'c' * 40);
    });

    test('el índice sucio da LocalInconsistente con la revisión', () {
      final r = derivar(revisionConIndiceSucio: 'd' * 40);
      expect(r, isA<LocalInconsistente>());
      expect((r as LocalInconsistente).revision, 'd' * 40);
    });

    test('un remoto utilizable da Publicado; uno que no, incompleta', () {
      expect(
        derivar(remoto: PullRequestOpen(url: 'https://forja/pr/1')),
        isA<Publicado>(),
      );
      expect(
        derivar(remoto: PullRequestClosed(url: 'https://forja/pr/1')),
        isA<PublicacionIncompleta>(),
      );
    });

    test('sin remoto y sin ninguna causa, la derivación LANZA', () {
      // Quedarse callada acá inventaría un desenlace: la corrida pasó todas
      // las compuertas y nadie dijo qué pasó con la publicación.
      expect(() => derivar(), throwsArgumentError);
    });
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/core/test/corrida_test.dart
```
Esperado: FALLA al compilar, porque `derivar` no existe.

- [ ] **Paso 3: escribir la fábrica**

Agregá dentro de `sealed class ShipOutcome`, antes de las entradas `…ParaLaPrueba`:

```dart
  /// **La única entrada real.** Cada variante tiene constructor privado, así
  /// que nadie puede ensamblar un desenlace eligiendo la combinación que le
  /// convenga: se derivan de los hechos.
  ///
  /// **La precedencia es por gravedad del hecho, no por el camino de
  /// autorización.** Que el usuario no fuera a confirmar no vuelve menos cierto
  /// que hay un secreto:
  ///
  ///     errorInterno > secretDetected > verificationGate
  ///                  > confirmationMissing > previewOnly
  ///
  /// `errorInterno` está en esa lista como ESTADO y sale por
  /// [CausaDeNoIntento.verificationGate]; no es una causa. Con una causa propia,
  /// la combinación «gate con arnés roto» quedaría inalcanzable.
  static ShipOutcome derivar({
    required EstadoDeCorrida verificacion,
    required bool huboSecreto,
    required bool seConfirmo,
    required bool soloPreview,
    required bool autorizaIncompleto,
    PublicationOutcome? remoto,
    String? headQueRechazoElCas,
    String? revisionConIndiceSucio,
  }) {
    NoIntentado sinIntentar(CausaDeNoIntento causa) =>
        NoIntentado._(causa: causa, verificacion: verificacion);

    // 1 · El arnés roto. No lo autoriza ninguna bandera.
    if (verificacion == EstadoDeCorrida.errorInterno) {
      return sinIntentar(CausaDeNoIntento.verificationGate);
    }
    // 2 · El secreto, antes que cualquier camino de autorización.
    if (huboSecreto) return sinIntentar(CausaDeNoIntento.secretDetected);
    // 3 · La compuerta por estado.
    if (verificacion != EstadoDeCorrida.verde && !autorizaIncompleto) {
      return sinIntentar(CausaDeNoIntento.verificationGate);
    }
    // 4 · La confirmación, antes que la previsualización: quien no confirmó
    //     pidió escribir y no llegó a autorizarlo; quien previsualiza no lo
    //     pidió nunca.
    if (!seConfirmo) return sinIntentar(CausaDeNoIntento.confirmationMissing);
    if (soloPreview) return sinIntentar(CausaDeNoIntento.previewOnly);

    // A partir de acá la corrida sí intentó escribir.
    if (headQueRechazoElCas != null) {
      return NoAplicado._(headObservado: headQueRechazoElCas);
    }
    if (revisionConIndiceSucio != null) {
      return LocalInconsistente._(revision: revisionConIndiceSucio);
    }

    final publicable = EstadoPublicable.desde(verificacion);
    if (remoto == null || publicable == null) {
      throw ArgumentError(
        'La corrida pasó todas las compuertas y no hay desenlace remoto que '
        'informar. Devolver algo acá inventaría un hecho: nadie sabe qué pasó '
        'con la publicación.',
      );
    }
    return switch (remoto) {
      PublicacionUtilizable() => Publicado._(
        pr: remoto,
        verificacion: publicable,
      ),
      PublicacionNoUtilizable() => PublicacionIncompleta._(
        remoto: remoto,
        verificacion: publicable,
      ),
    };
  }
```

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/core
dart analyze --fatal-infos packages/core
dart format --output=none --set-exit-if-changed packages/core
```
Esperado: todo con 0.

- [ ] **Paso 5: commitear**

```bash
git add packages/core/lib/src/corrida.dart packages/core/test/corrida_test.dart
git commit -m "Que no fueras a confirmar no vuelve menos cierto que hay un secreto

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 4: Los códigos de proceso, como función total sobre el desenlace

**Archivos:**
- Modificar: `packages/cli/lib/src/salida.dart`
- Test: `packages/cli/test/salida_test.dart`

**Interfaces:**
- Consume: `ShipOutcome` y sus variantes; `EstadoPublicable`; `CausaDeNoIntento`.
- Produce: `Codigo.detencionDeclarada = 3`, `Codigo.errorDeConfiguracion = 4`, `Codigo.entregaIncompleta = 6`, `static int Codigo.deShip(ShipOutcome)`, `String? accionDe(ShipOutcome)`, y `EstadoDeCorrida EstadoPublicable.comoCorrida`.

- [ ] **Paso 1: escribir las pruebas que fallan**

Agregá a `packages/cli/test/salida_test.dart`:

```dart
  group('Codigo.deShip', () {
    test('la tabla de §12, fila por fila', () {
      final esperado = <int, ShipOutcome>{
        0: ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.previewOnly,
          verificacion: EstadoDeCorrida.verde,
        ),
        1: ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.secretDetected,
          verificacion: EstadoDeCorrida.verde,
        ),
        2: ShipOutcome.noIntentadoParaLaPrueba(
          causa: CausaDeNoIntento.verificationGate,
          verificacion: EstadoDeCorrida.noConcluyente,
        ),
        3: ShipOutcome.noAplicadoParaLaPrueba(headObservado: 'a' * 40),
        6: ShipOutcome.publicacionIncompletaParaLaPrueba(
          remoto: PushUnknown(causa: CausaDePublicacion.red),
          verificacion: EstadoPublicable.verde,
        ),
        70: ShipOutcome.localInconsistenteParaLaPrueba(revision: 'b' * 40),
      };
      for (final fila in esperado.entries) {
        expect(Codigo.deShip(fila.value), fila.key, reason: fila.value.kind);
      }
    });

    test('confirmationMissing sale 0, y con un secreto sale 1', () {
      expect(
        Codigo.deShip(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.confirmationMissing,
            verificacion: EstadoDeCorrida.verde,
          ),
        ),
        0,
      );
      expect(
        Codigo.deShip(
          ShipOutcome.noIntentadoParaLaPrueba(
            causa: CausaDeNoIntento.secretDetected,
            verificacion: EstadoDeCorrida.verde,
          ),
        ),
        1,
      );
    });

    test('la compuerta lleva el código del estado que la cerró', () {
      for (final par in {
        EstadoDeCorrida.rojo: 1,
        EstadoDeCorrida.noConcluyente: 2,
        EstadoDeCorrida.errorInterno: 70,
      }.entries) {
        expect(
          Codigo.deShip(
            ShipOutcome.noIntentadoParaLaPrueba(
              causa: CausaDeNoIntento.verificationGate,
              verificacion: par.key,
            ),
          ),
          par.value,
          reason: par.key.name,
        );
      }
    });

    test('Publicado lleva el código de su verificación', () {
      for (final par in {
        EstadoPublicable.verde: 0,
        EstadoPublicable.rojo: 1,
        EstadoPublicable.noConcluyente: 2,
      }.entries) {
        expect(
          Codigo.deShip(
            ShipOutcome.publicadoParaLaPrueba(
              pr: PullRequestOpen(url: 'https://forja/pr/1'),
              verificacion: par.key,
            ),
          ),
          par.value,
          reason: par.key.name,
        );
      }
    });

    test('la entrega incompleta sale 6 AUNQUE la verificación sea roja', () {
      // Deliberado: `1` dice «el cambio no verificó» y `6` dice «el efecto
      // remoto no se completó», y la segunda es la que decide qué hacer
      // después. El precio está declarado: el estado viaja en `verdict` y en
      // `data`, no en el código.
      expect(
        Codigo.deShip(
          ShipOutcome.publicacionIncompletaParaLaPrueba(
            remoto: PullRequestUnknown(causa: CausaDePublicacion.red),
            verificacion: EstadoPublicable.rojo,
          ),
        ),
        6,
      );
    });
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/salida_test.dart
```
Esperado: FALLA al compilar, porque `Codigo.deShip` no existe.

- [ ] **Paso 3: escribir los códigos y la función**

En `packages/cli/lib/src/salida.dart`, dentro de `abstract final class Codigo`:

```dart
  /// Una detención por una precondición declarada que dejó de valer.
  ///
  /// **No es error de configuración** —nada está mal configurado—, **no es
  /// error interno** —nada se corrompió—, y no describe la verificación. Es la
  /// forma del circuit breaker.
  static const detencionDeclarada = 3;

  /// Falta configuración o credencial, y se dice cuál. **Cero escrituras.**
  ///
  /// Se clasifica por fase: una credencial ausente o rechazada en el preflight
  /// es `4`; expirada o rechazada después del commit es
  /// [entregaIncompleta], porque ahí sí hay trabajo local que quedó hecho.
  static const errorDeConfiguracion = 4;

  /// El trabajo local se completó y el efecto remoto no.
  ///
  /// Rama, commit y artefactos existen; **no hay un pull request abierto
  /// utilizable confirmado**.
  static const entregaIncompleta = 6;

  /// El código que le corresponde a un desenlace de `ship`. Es una función
  /// total: **una variante nueva no compila** hasta que alguien decida su
  /// código.
  ///
  /// Es el mismo criterio de [deCorrida], sobre un dominio cerrado más grande.
  static int deShip(ShipOutcome desenlace) => switch (desenlace) {
    NoIntentado(causa: CausaDeNoIntento.previewOnly) => exito,
    NoIntentado(causa: CausaDeNoIntento.confirmationMissing) => exito,
    NoIntentado(causa: CausaDeNoIntento.secretDetected) => fallaDeVerificacion,
    NoIntentado(causa: CausaDeNoIntento.verificationGate, :final verificacion) =>
      deCorrida(verificacion),
    NoAplicado() => detencionDeclarada,
    LocalInconsistente() => errorInterno,
    Publicado(:final verificacion) => deCorrida(verificacion.comoCorrida),
    // **`6` gana sobre el estado, y es deliberado.** Los dos códigos responden
    // preguntas distintas: `1` dice «el cambio no verificó» y `6` dice «el
    // efecto remoto no se completó», y la segunda es la que decide qué hacer
    // después. Un `1` acá mandaría a arreglar el código a alguien que además
    // tiene una rama empujada sin pull request, y el reintento que esa
    // situación pide no saldría de ningún lado. El precio: el estado de
    // verificación no viaja en el código de esta variante, solo en `verdict`
    // y en `data`.
    PublicacionIncompleta() => entregaIncompleta,
  };
```

Agregá a `EstadoPublicable`, en `packages/core/lib/src/corrida.dart`, el camino de vuelta:

```dart
  /// El estado de corrida equivalente. **Total y sin pérdida**: los tres
  /// publicables son estados de corrida.
  EstadoDeCorrida get comoCorrida => switch (this) {
    EstadoPublicable.verde => EstadoDeCorrida.verde,
    EstadoPublicable.rojo => EstadoDeCorrida.rojo,
    EstadoPublicable.noConcluyente => EstadoDeCorrida.noConcluyente,
  };
```

**Y la acción siguiente, que sale del mismo dominio cerrado.** §12 exige que toda salida que no sea verde pueda decir qué hacer, y que la acción se **derive** del desenlace. Agregá a `salida.dart`:

```dart
/// Qué hacer después de un desenlace de `ship`.
///
/// **Se deriva, como el código.** Una acción escrita a mano en cada sitio de
/// retorno diverge del desenlace en cuanto alguien agrega una variante; acá la
/// exhaustividad del `switch` la ata.
String? accionDe(ShipOutcome desenlace) => switch (desenlace) {
  NoIntentado(causa: CausaDeNoIntento.previewOnly) => null,
  NoIntentado(causa: CausaDeNoIntento.confirmationMissing) =>
    'Volvé a correrlo con --yes para autorizar la escritura.',
  NoIntentado(causa: CausaDeNoIntento.secretDetected) =>
    'Sacá el secreto del cambio y leelo del entorno por el proveedor de '
        'configuración.',
  NoIntentado(causa: CausaDeNoIntento.verificationGate, :final verificacion)
      when verificacion == EstadoDeCorrida.errorInterno =>
    'Se rompió un paso del arnés, no la verificación del cambio. Revisá la '
        'corrida antes de volver a intentar; --allow-incomplete no autoriza '
        'esto.',
  NoIntentado(causa: CausaDeNoIntento.verificationGate) =>
    'Arreglá lo que la verificación señaló, o autorizá publicarla incompleta '
        'con --allow-incomplete.',
  NoAplicado(:final headObservado) =>
    'La rama avanzó a $headObservado. Volvé a correr ship: el candidato se '
        'reconstruye sobre el HEAD nuevo. No sirve --retry-publication: no hay '
        'entrega que recuperar.',
  LocalInconsistente(:final revision) =>
    'El commit $revision existe y el índice quedó sin sincronizar. Reparalo '
        'y después --retry-publication, que comprueba que el índice ya '
        'coincide antes de publicar.',
  Publicado() => null,
  PublicacionIncompleta() =>
    'shipflow ship --retry-publication <runId>. No se creará otro commit ni '
        'un segundo pull request.',
};
```

**`previewOnly` y `Publicado` devuelven nulo a propósito**: no hay nada que corregir. Inventarles una acción sería ruido con forma de instrucción.

**Y corregí el doc comment de `ResultEnvelope.verdict`**: dice que el `3` «todavía no tiene productor». Con esta tarea lo tiene. Reescribí esa parte para que diga lo que es cierto ahora, sin borrar la distinción que el comentario hace entre la superficie documentada y la implementada.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli packages/core
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```
Esperado: todo con 0.

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/salida.dart packages/cli/test/salida_test.dart packages/core/lib/src/corrida.dart
git commit -m "El 3 tiene productor, y una variante nueva no compila sin su código

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 5: `IndiceDesincronizado`, con la revisión como dato

**Archivos:**
- Modificar: `packages/vcs/lib/src/repositorio.dart`
- Test: `packages/vcs/test/repositorio_test.dart`

**Interfaces:**
- Produce: `class IndiceDesincronizado implements Exception` con `final String revision` y `final String detalle`.

**Contexto:** hoy, cuando `apply` crea la revisión y falla al sincronizar el índice, lanza `PromesaIncumplida`, que lleva dos `String` —`sePidio` y `quedo`— con la revisión **interpolada en el texto**. Quien recupere la corrida necesita la revisión como dato: comprobar si el índice ya coincide no se hace parseando un mensaje.

- [ ] **Paso 1: escribir la prueba que falla**

Agregá a `packages/vcs/test/repositorio_test.dart` una prueba que provoque el fallo de sincronización y afirme sobre el tipo:

```dart
  test('el índice sin sincronizar lleva la revisión como DATO', () async {
    // El mensaje sigue existiendo y sigue siendo útil; lo que no puede pasar
    // es que sea el único lugar donde está la revisión.
    try {
      await repositorioConIndiceQueFalla().apply(rebanadaDePrueba);
      fail('se esperaba IndiceDesincronizado');
    } on IndiceDesincronizado catch (e) {
      expect(e.revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(e.detalle, isNotEmpty);
      expect(
        e.toString(),
        contains(e.revision),
        reason: 'el texto sigue nombrándola, además del campo',
      );
    }
  });
```

Escribí `repositorioConIndiceQueFalla()` y `rebanadaDePrueba` con los ayudantes que ya usa ese archivo. Si no hay forma de provocar el fallo real sin romper el repositorio de prueba, inyectá el fallo por la costura del programa de `git` —el mismo mecanismo que usan las pruebas de la toolchain ausente— y decilo en el reporte.

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/vcs/test/repositorio_test.dart
```
Esperado: FALLA porque `IndiceDesincronizado` no existe.

- [ ] **Paso 3: escribir el tipo y usarlo**

Agregá junto a `PromesaIncumplida` en `packages/vcs/lib/src/repositorio.dart`:

```dart
/// El commit existe y el índice quedó sin sincronizar.
///
/// **La revisión va como campo y no solo en el mensaje.** Antes esto salía
/// como una `PromesaIncumplida` con dos `String`, y la revisión vivía
/// interpolada en el texto: quien recuperara la corrida tenía que parsear un
/// mensaje para saber qué comprobar. Un dato que solo existe dentro de una
/// oración no es un dato.
class IndiceDesincronizado implements Exception {
  /// El commit que sí se creó.
  final String revision;

  /// Qué quedó mal, en las palabras de `git`.
  final String detalle;

  const IndiceDesincronizado(this.revision, this.detalle);

  @override
  String toString() =>
      'IndiceDesincronizado: la revisión $revision se creó y el índice quedó '
      'sin sincronizar. $detalle';
}
```

Reemplazá el `throw PromesaIncumplida(...)` del camino de sincronización del índice por `throw IndiceDesincronizado(revision, ...)`. **No toques los otros dos `PromesaIncumplida`**: son de otros invariantes.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/vcs
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```
Esperado: todo con 0.

- [ ] **Paso 5: commitear**

```bash
git add packages/vcs/lib/src/repositorio.dart packages/vcs/test/repositorio_test.dart
git commit -m "Un dato que solo existe dentro de una oración no es un dato

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 6: El documento de la corrida, y sus transiciones

**Archivos:**
- Crear: `packages/core/lib/src/documento.dart`
- Modificar: `packages/core/lib/core.dart`
- Modificar: `packages/core/lib/src/publicacion.dart` — `PullRequestDraft` gana `toJson` y `fromJson`
- Modificar: `arquitectura.json` — `PullRequestDraft` sale de `opacidad-declarada`
- Test: `packages/core/test/documento_test.dart`

**Interfaces:**
- Consume: `PullRequestDraft` de `publicacion.dart`; `ShipOutcome` de `corrida.dart`.
- Produce además: `PullRequestDraft.toJson()` y `static PullRequestDraft.fromJson(Map<String, Object?>)`. **`PullRequestRequest` NO serializa** y se queda declarado opaco: lo que el documento necesita reconstruir es el borrador, y la solicitud se arma de él más la revisión.
- Produce: `enum EstadoDelDocumento { prepared, committed, publicationComplete, publicationIncomplete, notApplied, localInconsistent }`; `class DocumentoDeCorrida` con la fábrica `DocumentoDeCorrida.preparado({required String revision, required PullRequestDraft draft})`, los getters `formatVersion`, `estado`, `revision`, `draft`, `desenlace`, su `toJson` y `static fromJson`, y `DocumentoDeCorrida avanzarA(EstadoDelDocumento destino, {ShipOutcome? desenlace})`.

**El grafo de §9, que es lo que las transiciones tienen que sostener:**

```
prepared ──┬──▶ committed ──┬──▶ publicationComplete
           │                └──▶ publicationIncomplete
           ├──▶ notApplied
           └──▶ localInconsistent
```

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/core/test/documento_test.dart`:

```dart
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  DocumentoDeCorrida preparado() => DocumentoDeCorrida.preparado(
    revision: 'a' * 40,
    draft: draftDePrueba(),
  );

  test('prepared LLEVA la revisión, porque commit-tree ya corrió', () {
    // La versión anterior del diseño lo persistía antes de `commit-tree`, y
    // dejaba una ventana: existía un objeto commit cuyo OID no quedaba en
    // ningún lado, así que la recuperación hablaba de «la revisión candidata»
    // sin tener identidad que consultar.
    expect(preparado().revision, isNotEmpty);
    expect(preparado().estado, EstadoDelDocumento.prepared);
  });

  test('las transiciones del grafo de §9 se aceptan', () {
    final desde = preparado();
    for (final destino in [
      EstadoDelDocumento.committed,
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.localInconsistent,
    ]) {
      expect(() => desde.avanzarA(destino), returnsNormally, reason: destino.name);
    }
    final comiteado = desde.avanzarA(EstadoDelDocumento.committed);
    for (final destino in [
      EstadoDelDocumento.publicationComplete,
      EstadoDelDocumento.publicationIncomplete,
    ]) {
      expect(
        () => comiteado.avanzarA(destino),
        returnsNormally,
        reason: destino.name,
      );
    }
  });

  test('una transición que el grafo no tiene LANZA', () {
    expect(
      () => preparado().avanzarA(EstadoDelDocumento.publicationComplete),
      throwsStateError,
      reason: 'publicar sin commitear no es un camino',
    );
    final noAplicado = preparado().avanzarA(EstadoDelDocumento.notApplied);
    expect(
      () => noAplicado.avanzarA(EstadoDelDocumento.committed),
      throwsStateError,
      reason: 'notApplied es terminal',
    );
  });

  test('el documento vuelve a ser él mismo por JSON', () {
    final ida = preparado().avanzarA(EstadoDelDocumento.committed);
    final vuelta = DocumentoDeCorrida.fromJson(ida.toJson());
    expect(vuelta.toJson(), ida.toJson());
  });

  test('un formatVersion que no conocemos NO se lee', () {
    final json = Map<String, Object?>.from(preparado().toJson())
      ..['formatVersion'] = 99;
    expect(() => DocumentoDeCorrida.fromJson(json), throwsFormatException);
  });
}
```

Escribí `draftDePrueba()` construyendo un `PullRequestDraft` con los ayudantes que ya usa `packages/core/test/publicacion_test.dart`.

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/core/test/documento_test.dart
```
Esperado: FALLA al compilar.

- [ ] **Paso 3: escribir el documento**

Creá `packages/core/lib/src/documento.dart`:

```dart
/// El documento autoritativo de una corrida de `ship`.
///
/// **Uno solo.** `intent` y el JSON de la revisión son proyecciones suyas, no
/// fuentes paralelas: dos documentos del mismo hecho divergen siempre.
library;

import 'corrida.dart';
import 'publicacion.dart';

enum EstadoDelDocumento {
  prepared,
  committed,
  publicationComplete,
  publicationIncomplete,
  notApplied,
  localInconsistent,
}

class DocumentoDeCorrida {
  /// **Del documento, no del envelope de salida.** Son dos contratos con
  /// ciclos de vida distintos.
  static const versionActual = 1;

  final EstadoDelDocumento estado;

  /// El commit candidato. **Ya existe cuando este documento se escribe.**
  ///
  /// La versión anterior del diseño persistía `prepared` ANTES de
  /// `commit-tree`, y dejaba una ventana sin cerrar: había un objeto commit
  /// cuyo OID no quedaba en ningún lado, y la recuperación hablaba de «la
  /// revisión candidata» sin tener identidad que consultar. Crear el objeto no
  /// mueve la rama, así que escribirlo antes de persistir no tiene efecto
  /// observable.
  final String revision;

  /// El borrador completo, para que la recuperación reconstruya la solicitud
  /// **sin volver a correr la cascada**.
  final PullRequestDraft draft;

  /// El desenlace, cuando ya hay uno. Nulo mientras la corrida sigue.
  final ShipOutcome? desenlace;

  const DocumentoDeCorrida._({
    required this.estado,
    required this.revision,
    required this.draft,
    this.desenlace,
  });

  /// El primer estado. **La única forma de crear un documento desde cero**:
  /// los demás se alcanzan con [avanzarA].
  factory DocumentoDeCorrida.preparado({
    required String revision,
    required PullRequestDraft draft,
  }) => DocumentoDeCorrida._(
    estado: EstadoDelDocumento.prepared,
    revision: revision,
    draft: draft,
  );

  /// El grafo de §9, como dato. Lo que no está acá no es un camino.
  static const _transiciones = <EstadoDelDocumento, Set<EstadoDelDocumento>>{
    EstadoDelDocumento.prepared: {
      EstadoDelDocumento.committed,
      EstadoDelDocumento.notApplied,
      EstadoDelDocumento.localInconsistent,
    },
    EstadoDelDocumento.committed: {
      EstadoDelDocumento.publicationComplete,
      EstadoDelDocumento.publicationIncomplete,
    },
    EstadoDelDocumento.publicationIncomplete: {
      EstadoDelDocumento.publicationComplete,
    },
    EstadoDelDocumento.publicationComplete: {},
    EstadoDelDocumento.notApplied: {},
    EstadoDelDocumento.localInconsistent: {},
  };

  /// Avanza, o lanza. **Devuelve un documento nuevo** en vez de mutar este:
  /// con un campo mutable, alguien escribe `committed` sin pasar por acá y la
  /// comprobación deja de ser un invariante para ser una costumbre.
  DocumentoDeCorrida avanzarA(
    EstadoDelDocumento destino, {
    ShipOutcome? desenlace,
  }) {
    final permitidos = _transiciones[estado]!;
    if (!permitidos.contains(destino)) {
      throw StateError(
        'De ${estado.name} no se va a ${destino.name}. Los caminos desde acá '
        'son: ${permitidos.isEmpty ? "ninguno, es terminal" : permitidos.map((e) => e.name).join(", ")}.',
      );
    }
    return DocumentoDeCorrida._(
      estado: destino,
      revision: revision,
      draft: draft,
      desenlace: desenlace ?? this.desenlace,
    );
  }

  Map<String, Object?> toJson() => {
    'formatVersion': versionActual,
    'estado': estado.name,
    'revision': revision,
    'draft': draft.toJson(),
    if (desenlace != null) 'desenlace': desenlace!.toJson(),
  };

  /// **Exige la versión que conocemos.** Leer un documento de otra versión y
  /// actuar sobre él es peor que no leerlo: las decisiones que salen de acá
  /// deciden si se commitea y si se publica.
  static DocumentoDeCorrida fromJson(Map<String, Object?> json) {
    final version = json['formatVersion'];
    if (version != versionActual) {
      throw FormatException(
        'El documento de la corrida dice formatVersion «$version» y esta '
        'versión solo sabe leer $versionActual.',
      );
    }
    final crudo = json['desenlace'];
    return DocumentoDeCorrida._(
      estado: EstadoDelDocumento.values.byName(json['estado']! as String),
      revision: json['revision']! as String,
      draft: PullRequestDraft.fromJson(
        Map<String, Object?>.from(json['draft']! as Map),
      ),
      desenlace: crudo == null
          ? null
          : ShipOutcome.fromJson(Map<String, Object?>.from(crudo as Map)),
    );
  }
}
```

**`PullRequestDraft` no serializa hoy** —está declarado opaco en `arquitectura.json`—. Esta tarea le agrega `toJson`/`fromJson` y **lo saca de `opacidad-declarada`**: el documento lo necesita para reconstruir la solicitud sin volver a correr la cascada. Al sacarlo, comprobá que `check.dart` siga en verde: la lista se verifica en los dos sentidos.

- [ ] **Paso 4: registrar la ida y vuelta y correr**

Agregá `DocumentoDeCorrida` al mapa de `serializacion_test.dart`, y corré:

```
dart test packages/core
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
cd tool/analisis && dart run bin/check.dart && cd ../..
```

- [ ] **Paso 5: commitear**

```bash
git add packages/core/lib/src/documento.dart packages/core/lib/core.dart packages/core/test/documento_test.dart packages/core/test/serializacion_test.dart
git commit -m "Un documento que se puede mutar no tiene transiciones, tiene campos

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 7: La persistencia: temporal y `rename`

**Archivos:**
- Crear: `packages/cli/lib/src/corrida.dart`
- Modificar: `packages/cli/lib/cli.dart`
- Test: `packages/cli/test/corrida_test.dart`

**Interfaces:**
- Consume: `DocumentoDeCorrida` de la tarea 6.
- Produce: `class RegistroDeCorridas` con `RegistroDeCorridas({required String raiz})`, `Future<void> escribir(String runId, DocumentoDeCorrida)`, `Future<DocumentoDeCorrida?> leer(String runId)`.

- [ ] **Paso 1: escribir las pruebas que fallan**

Creá `packages/cli/test/corrida_test.dart` con tres pruebas:

```dart
  test('lo escrito se vuelve a leer igual', () async {
    final registro = RegistroDeCorridas(raiz: temporal.path);
    final doc = documentoDePrueba();
    await registro.escribir('r-1', doc);
    expect((await registro.leer('r-1'))!.toJson(), doc.toJson());
  });

  test('una corrida que no existe devuelve nulo, no lanza', () async {
    // «No hay documento» es un hecho que la recuperación tiene que poder
    // ramificar: significa que el proceso murió antes de `prepared`, y lo
    // único que quedó es un objeto inalcanzable que el `gc` recoge.
    final registro = RegistroDeCorridas(raiz: temporal.path);
    expect(await registro.leer('nunca-existio'), isNull);
  });

  test('un temporal huérfano NO se lee como documento', () async {
    // El escritor usa temporal + `rename` para que nadie lea a medias. Si el
    // proceso muere entre los dos, el temporal queda; leerlo sería leer un
    // documento a medio escribir.
    final registro = RegistroDeCorridas(raiz: temporal.path);
    await registro.escribir('r-2', documentoDePrueba());
    final dir = Directory(rutas.join(temporal.path, 'runs'));
    final huerfano = File(rutas.join(dir.path, 'r-3.json.tmp'));
    await huerfano.writeAsString('{"formatVersion":1,"estado":"prepared"');
    expect(await registro.leer('r-3'), isNull);
    expect(await huerfano.exists(), isTrue, reason: 'no se borra a escondidas');
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/corrida_test.dart
```
Esperado: FALLA al compilar.

- [ ] **Paso 3: escribir el registro**

Creá `packages/cli/lib/src/corrida.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:path/path.dart' as rutas;

/// Dónde viven los documentos de las corridas.
///
/// **Se escribe a un temporal y se renombra.** El `rename` es atómico dentro
/// del mismo sistema de archivos, así que el nombre final aparece con el
/// contenido entero o no aparece: nadie lee un documento a medio escribir. Ese
/// es todo el mecanismo.
///
/// **Límite declarado:** la atomicidad es *dentro del mismo sistema de
/// archivos*. El temporal se crea al lado del destino justamente por eso; si
/// `.shipflow/` viviera en otro sistema de archivos que el temporal, la
/// garantía no valdría. Como los dos salen de [raiz], no puede pasar sin que
/// alguien cambie esta clase.
class RegistroDeCorridas {
  final String raiz;

  const RegistroDeCorridas({required this.raiz});

  Directory get _directorio => Directory(rutas.join(raiz, 'runs'));

  File _archivo(String runId) => File(rutas.join(_directorio.path, '\$runId.json'));

  Future<void> escribir(String runId, DocumentoDeCorrida documento) async {
    await _directorio.create(recursive: true);
    final destino = _archivo(runId);
    // Al lado del destino, no en el temporal del sistema: cruzar sistemas de
    // archivos convertiría el `rename` en copiar y borrar, que no es atómico.
    final temporal = File('${destino.path}.tmp');
    await temporal.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(documento.toJson())}\n',
      flush: true,
    );
    await temporal.rename(destino.path);
  }

  /// El documento de [runId], o nulo si no hay ninguno.
  ///
  /// **Nulo es un hecho, no un fallo:** significa que el proceso murió antes
  /// de persistir `prepared`, y entonces lo único que quedó es un objeto
  /// commit inalcanzable que el `gc` recoge. La recuperación tiene que poder
  /// ramificar sobre eso.
  ///
  /// **Un temporal huérfano no se lee y no se borra.** No se lee porque sería
  /// leer un documento a medio escribir; no se borra porque esta clase no sabe
  /// si alguien lo está escribiendo ahora mismo.
  Future<DocumentoDeCorrida?> leer(String runId) async {
    final archivo = _archivo(runId);
    if (!await archivo.exists()) return null;
    return DocumentoDeCorrida.fromJson(
      Map<String, Object?>.from(
        jsonDecode(await archivo.readAsString()) as Map,
      ),
    );
  }
}
```

Agregá el export a `packages/cli/lib/cli.dart` en orden alfabético.

**`cli` NO declara `package:path` todavía**, aunque `plugin_dart` y `plugin_fake` sí, con `^1.9.0`. Agregala a `packages/cli/pubspec.yaml` con esa misma restricción, **en el mismo commit que la importa**: la regla `dependencias-declaradas-se-usan` exige que una dependencia declarada esté efectivamente importada, y su propio texto dice que «la dependencia vuelve en el mismo commit que la importe». Después corré `dart pub get` desde la raíz.

**Y el alias es `rutas`, no `p`:** es como la importan los tres archivos de `plugin_dart` que ya la usan. Escribí `import 'package:path/path.dart' as rutas;` y ajustá el cuerpo.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/corrida.dart packages/cli/lib/cli.dart packages/cli/test/corrida_test.dart
git commit -m "El documento aparece entero o no aparece

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 8: La recuperación: tres casos de `HEAD`, y ninguna adivinanza

**Archivos:**
- Modificar: `packages/cli/lib/src/corrida.dart`
- Test: `packages/cli/test/corrida_test.dart`

**Interfaces:**
- Produce: `enum QueHacerAlRecuperar { reintentarElCas, promoverACommitted, alguienMasAvanzo }` y `QueHacerAlRecuperar decidirRecuperacion({required DocumentoDeCorrida documento, required String headActual})`.

**La comparación de §9, que es una función y no una búsqueda:**

| `HEAD` al recuperar | Qué hacer |
|---|---|
| `== baseRevision` del candidato | Reintentar el CAS: nada se movió |
| `== revision` del documento | El CAS sí corrió. Promover a `committed` |
| Cualquier otro | `NoAplicado`: alguien más avanzó |

- [ ] **Paso 1: escribir la prueba que falla**

```dart
  test('los tres casos de HEAD, y ninguno más', () {
    final doc = documentoPreparado(base: 'b' * 40, revision: 'r' * 40);
    expect(
      decidirRecuperacion(documento: doc, headActual: 'b' * 40),
      QueHacerAlRecuperar.reintentarElCas,
    );
    expect(
      decidirRecuperacion(documento: doc, headActual: 'r' * 40),
      QueHacerAlRecuperar.promoverACommitted,
    );
    expect(
      decidirRecuperacion(documento: doc, headActual: 'x' * 40),
      QueHacerAlRecuperar.alguienMasAvanzo,
    );
  });

  test('la decisión no depende de leer el repositorio', () {
    // Es una comparación de tres cadenas que ya están en el documento. Si
    // hiciera falta consultar git, la recuperación sería una búsqueda, y §9
    // existe justamente para que no lo sea.
    expect(decidirRecuperacion, isA<Function>());
  });
```

- [ ] **Paso 2: correr y comprobar que falla**

```
dart test packages/cli/test/corrida_test.dart
```

- [ ] **Paso 3: escribir la decisión**

Agregá a `packages/cli/lib/src/corrida.dart`:

```dart
/// Qué hacer con una corrida interrumpida.
enum QueHacerAlRecuperar {
  /// Nada se movió: el CAS se puede reintentar tal cual.
  reintentarElCas,

  /// El CAS sí corrió antes de morir. El commit está en la rama.
  promoverACommitted,

  /// La rama avanzó a otra cosa. El candidato hay que reconstruirlo.
  alguienMasAvanzo,
}

/// La comparación de §9. **Es una función de tres casos, no una búsqueda.**
///
/// Con `prepared` llevando ya la revisión, los tres datos que hacen falta
/// —la base, la revisión candidata y el `HEAD` observado— están todos sobre la
/// mesa. Antes, sin la revisión persistida, esto tenía que salir a buscar qué
/// commit podía ser el candidato.
///
/// **No lee el repositorio**: quien la llama ya leyó el `HEAD`. Así se puede
/// probar los tres casos sin montar un repositorio por cada uno.
QueHacerAlRecuperar decidirRecuperacion({
  required DocumentoDeCorrida documento,
  required String headActual,
}) {
  final base = documento.draft.artefacto.candidato.baseRevision;
  if (headActual == base) return QueHacerAlRecuperar.reintentarElCas;
  if (headActual == documento.revision) {
    return QueHacerAlRecuperar.promoverACommitted;
  }
  return QueHacerAlRecuperar.alguienMasAvanzo;
}
```

**Si `base` y `revision` fueran iguales**, el primer `if` gana y se reintenta un CAS que ya corrió. No puede pasar: una revisión es hija de la base, así que sus OIDs difieren. Dejalo dicho en el doc comment en vez de agregar una guarda para un caso que git no produce.

- [ ] **Paso 4: correr y comprobar que pasa**

```
dart test packages/cli
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed .
```

- [ ] **Paso 5: commitear**

```bash
git add packages/cli/lib/src/corrida.dart packages/cli/test/corrida_test.dart
git commit -m "La recuperación es una comparación de tres casos, no una búsqueda

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Tarea 9: El cierre — declaraciones, grafo y arnés entero

**Archivos:**
- Modificar: `arquitectura.json`, `README.md`, `grafo.jsonl`

- [ ] **Paso 1: declarar lo que no serializa**

Toda clase nueva de `core` con campos que no serialice va a `opacidad-declarada` con su motivo. Si todas serializan, no agregues nada: una declaración de más es tan defecto como una de menos.

- [ ] **Paso 2: enlazar el plan desde el README**

`grafo.dart` trata un archivo que ningún punto de entrada alcanza como huérfano, y los planes se alcanzan desde el `README`. Agregá el párrafo que enlaza `PLAN-desenlace-de-la-corrida.md`, con el mismo estilo que los de las rebanadas anteriores.

- [ ] **Paso 3: documentar la rebanada y sus residuos**

En el README, la sección de esta rebanada. Los residuos que tienen que quedar escritos:

- **Nada de esto tiene productor todavía.** `ShipOutcome.derivar` no lo llama nadie: el comando llega en 4b. Un tipo sin productor es exactamente lo que este repositorio declara en vez de disimular.
- **`rename` es atómico dentro del mismo sistema de archivos.** Si `.shipflow/` viviera en otro, la garantía de «entero o nada» no vale.
- **El ruling sobre las cuatro causas**, con su motivo: con cinco, la fila «gate con arnés roto» de la tabla de códigos quedaba inalcanzable.
- **`PublicacionIncompleta` sale `6` aunque la verificación sea roja**, y el estado viaja en `verdict` y en `data`, no en el código.

- [ ] **Paso 4: regenerar el grafo y correr todo**

```
cd tool/analisis && dart run bin/check.dart && dart run bin/grafo.dart && cd ../..
python3 tool/checks/capas.py
```
Si `grafo.dart` pide regenerar el grafo commiteado, hacelo y commitealo.

- [ ] **Paso 5: el arnés entero, solo**

```
ARNES_ORIGEN=$(pwd) python3 tool/checks/probar_reglas.py
python3 tool/checks/probar_recuperacion.py
```
**Sin tocar nada mientras corre.**

- [ ] **Paso 6: commitear**

```bash
git add arquitectura.json README.md grafo.jsonl
git commit -m "El desenlace de la corrida, declarado: lo que hace y lo que no tiene productor

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```
