# shipflow

CLI Dart que hace que **el agente del usuario** entregue mejor. No construye un
bucle agéntico: se integra con Claude Code, Codex o Gemini CLI.

El diseño completo —18 ADRs, el modelo D+C+E, el catálogo de fallos, el plan por
fases— vive en un repositorio aparte: **`../sdlc-agentico/`**. Empezá por su
`AGENTS.md`.

---

## Estado: fase 1. Hay contratos, no hay producto.

`core` existe: **las entidades y los puertos, como tipos, sin una sola
implementación.** No hay CLI, no hay cascada, no hay ganchos. Eso es deliberado
y está declarado más abajo, control por control.

**El problema que resuelve.** El intento anterior no falló por mala
arquitectura: falló porque todo lo que gobernaba el proceso estaba escrito en
prosa y nada lo hacía cumplir. De 27 ADRs, uno tenía invariante ejecutable. No
había CI; el único ejecutor era un `pre-push` y `--no-verify` lo salteaba.

Este proyecto llegó a tener **dieciocho ADRs con su invariante escrito y cero
instalados**. La fase 0 convirtió *"decidimos que X"* en *"no se puede mergear
algo que viole X"*. La fase 1 hace lo mismo un nivel más adentro: **los
invariantes del dominio no son comentarios sobre los tipos, son propiedades de
los tipos.** Una `Rule` prohibitiva sin alternativa no se construye. Un
`VerificationOutcome` sin testigo no puede decir «verde», porque el veredicto no
es un campo: se calcula.

---

## Qué corre

```
dart pub get                                  # PRECONDICIÓN: el grafo se le pide a pub
python3 tool/checks/capas.py                  # las reglas que se leen del texto
(cd tool/serializacion && dart pub get && dart run bin/check.dart)
python3 tool/checks/probar_reglas.py          # y la prueba de que saben fallar
dart test packages/core
dart analyze --fatal-infos
dart format --set-exit-if-changed .
```

**Las reglas viven en [`arquitectura.json`](arquitectura.json)**, en un solo
lugar y diffeable, aunque las apliquen dos motores distintos. Tocarlo es cambiar
la arquitectura y se revisa como tal.

| `id` de la regla | Qué impide | Aplica |
|---|---|---|
| `deps-hacia-core` | Que una flecha **interna** apunte a otro lado que no sea `core` | `capas.py` |
| `nucleo-sin-externas` | Que `core` gane una dependencia **de cualquier origen**, incluidas las de desarrollo | `capas.py` |
| `agente-en-agents` | Que `claude`/`codex`/`gemini` salgan de `agents/` | `capas.py` |
| `lenguaje-en-plugin-dart` | Que `dart`/`flutter`/`pubspec` salgan de `plugin_dart/` | `capas.py` |
| `sin-api-de-modelo` | Que **cualquier** paquete llame a una API de modelo | `capas.py` |
| `serializacion-sin-perdida` | Que un campo de `core` no viaje, o vuelva vacío | `tool/serializacion` |
| `opacidad-declarada` | Que «no serializa» sea indistinguible de «se olvidaron» | `tool/serializacion` |
| `puertos-sin-implementacion` | Que una superficie de puertos vacía se lea como un sistema que hace esas cosas | `tool/serializacion` |

Una regla que `capas.py` no aplica **tiene que declarar `aplicada_por`**, ese
aplicador tiene que existir, y CI tiene que invocarlo. Sin las tres cosas es
F33: registrada y no ejecutada. El propio check lo verifica —y de hecho fue lo
primero que hizo cuando se agregaron las tres reglas nuevas.

### Por qué las tres últimas necesitan otro motor

Se derivan del **árbol sintáctico** de `core`, no de su texto. Es la misma
lección que ya pagó `capas.py` con el grafo de dependencias: parsear a mano
devuelve cero resultados ante una sintaxis que el parser no reconoce, y cero se
lee igual que *"está todo bien"*. Los campos de una clase se le piden al
analizador. Su paquete está **fuera del `workspace:`** a propósito: ninguna
regla de capas debería tener que hacerle una excepción a su propio verificador.

---

## Cómo se prueba que los checks saben fallar

`probar_reglas.py` deriva sus casos del propio registro y corre **los dos
motores** contra cada sabotaje, porque un sabotaje no sabe cuál de los dos
tiene que atraparlo.

- **Violación canónica** — cada regla declara un caso sintético que tiene que
  detectar. Se inyecta y se revierte. Es compatible con el ratchet —toda regla
  nueva está verde el día que se agrega— y de hecho es su **precondición**:
  *verde* no significa nada si la regla no puede ponerse roja.
- **Neutralización + canónica** — se degrada la regla de todas las formas que
  conservan su `id` —tipo cambiado, alcance vaciado, `solo_en` ampliado,
  exclusión que traga paquetes, `aplicada_por` apuntado a otro lado— y se
  comprueba que el check **igual** falla. Validar la *forma* de la política va
  siempre un paso atrás de quien la edita.
- **Controles negativos y de borde** — que las exclusiones excluyan de verdad, y
  que las exenciones **no** se traguen lo que la regla existe para ver.

Corre en CI junto a los checks, no una vez a mano: **un check que nunca falló no
está probado**, y un guardia que existe y nunca se disparó es indistinguible de
uno roto.

### Tres propiedades que hacen verificable el registro

- **Cada regla tiene un `id` estable y una violación canónica.**
- **Lo que no deriva, está fijado**: `solo_en`, el mapa de flechas, las
  extensiones y las **exenciones de token** se comparan contra el valor que
  viene del ADR o de `docs/03`. La canónica prueba que el instrumento dispara;
  el pinneo prueba que la política no se reescribió — son modos de fallo
  distintos.
- **Y una huella `sha256` de la política**, commiteada aparte. **Límite
  declarado:** vuelve imposible degradar la política *en silencio*, no
  degradarla. Contra alguien que edite las dos cosas no hay check: hay revisión.

### El campo más peligroso del registro

`no_cuenta` exime un **token** dentro de un contexto, y es el único campo que
neutraliza una regla **agrandando** el registro: la lista queda más larga y
todos los campos llenos. Vaciar un alcance se ve en un diff; agregar una
exención se lee como trabajo. Por eso está fijado en dos sentidos —qué regla
puede tenerlo y con qué regexes exactos— y tiene sus dos bordes probados.

Hoy hay dos exenciones, las dos en `lenguaje-en-plugin-dart`:

| Exento | Por qué | Qué sigue rojo |
|---|---|---|
| El sufijo `.dart` de un URI, dentro de una directiva | Es la extensión de **todo** archivo del repo. Sin la exención la regla es insatisfacible: el primer `export` la desactiva entera | `path.endsWith('.dart')`, porque no es una directiva. Y un import de un paquete vigilado, por su nombre |
| El esquema `dart:` de una biblioteca del SDK **de una lista blanca** | Es la biblioteca estándar del lenguaje en que está escrito *este* repo, no conocimiento del stack analizado | `dart:io`, `dart:ffi`, `dart:mirrors` y cualquier otra fuera de la lista. `core` haciendo entrada/salida directa es justo lo que la regla tiene que ver |

---

## Sabotajes del estado intermedio · fase 1

Obligación de cada fase al empezarla, del plan de desarrollo. **Escritos,
ejecutados, y con su resultado acá.** Un sabotaje que nunca se ejecutó no es un
sabotaje.

### S1.1 · ¿Qué promete la fase que todavía no cumple, y el artefacto lo declara?

`core` expone **23 puertos y cero implementaciones**. Una superficie de puertos
completa se lee como un sistema que hace esas cosas.

**Instalado:** `puertos-sin-implementacion` lista los 23 con su fase, y se
verifica **en los dos sentidos** — un puerto nuevo sin declarar falla, y una
declaración que quedó vieja porque el puerto ya se implementó, también.
**Ejecutado:** la canónica y el vaciado de la lista, detectados.

### S1.2 · ¿Qué queda a medias si se instala solo una parte?

`Rule` con sus seis campos, pero sin los invariantes que los vuelven requisitos
de instalación: el campo `alternative` existiría y podría estar vacío. Es
*"escribir un invariante no es instalarlo"* al nivel del tipo.

**Ejecutado:** se le quitó al constructor la validación de INV-11 dejando el
campo. `dart test` → rojo. Restaurado → verde. Lo mismo cubre INV-3, INV-4,
INV-8 e INV-10, cada uno con su prueba.

### S1.3 · ¿Se puede pasar el check de esta fase sin cumplirlo?

Sí, se podía. **Por tres caminos, y dos estaban abiertos.**

| | El sabotaje | Resultado |
|---|---|---|
| **a** | Un campo que nunca se agrega a `toJson` | Detectado. Es la canónica de `serializacion-sin-perdida` |
| **b** | `toJson` escribe la clave con un **valor constante** (`'path': ''`) | **Pasaba en verde por los dos controles.** Ver abajo |
| **c** | Una entidad nueva que nadie agrega a la prueba de ida y vuelta | **Pasaba en verde.** El hueco quedaba *entre* los dos controles |

**(b) es el hallazgo que justifica el ejercicio.** La primera versión de la
prueba comparaba `toJson → fromJson → toJson` contra `toJson`. Las dos mitades
de esa igualdad salían del mismo `toJson`, así que un campo escrito como
constante coincidía consigo mismo. Era la **clase 1** completa: el instrumento
en verde sobre algo que no midió, escrito por quien pasó tres revisiones
buscando exactamente eso en otro lado.

La corrección no fue comparar más cosas a mano —eso se desactualiza— sino que
**la instancia canónica no tenga ningún valor por defecto en ningún campo**.
Entonces *"ningún valor del JSON es un valor por defecto"* es una aserción
derivada, y cualquier campo aplastado a `''`, `0`, `null` o vacío la rompe.

**(c) se cerró** haciendo que `serializacion-sin-perdida` verifique además que
toda clase serializable tenga su caso canónico en la prueba. Cada control
cubría lo que el otro no, y nadie miraba la juntura.

### Lo que estos sabotajes encontraron fuera de su alcance

Tres huecos de la **fase 0**, que estaban verdes porque no había código:

1. **La regla de cadenas era insatisfacible.** Todo `import` contiene `.dart`.
   Estaba en verde porque los paquetes estaban vacíos: el primer `export` la
   habría puesto roja para siempre, y lo que pasa entonces no es que alguien
   reescriba los imports — se desactiva la regla.
2. **Los miembros del workspace se derivaban del directorio `packages/`**, no
   del grafo. Un miembro declarado fuera de ese directorio quedaba sin
   gobierno, y su ausencia del bucle se leía igual que *"no encontré nada"*.
   Ahora salen de pub, y un paquete que esté en uno y no en el otro falla.
3. **`nucleo-sin-externas` nunca miró las dependencias de desarrollo.** pub las
   reporta en otra clave del grafo. El enunciado dice *"ninguna"*, no *"ninguna
   de producción"*.

---

## Qué promete esta fase y todavía no cumple

Declararlo es obligación de cada fase, y viene de una lección concreta: una
superficie incompleta que se muestra vacía se lee como *"no había nada"*.

| Falta | Cuándo |
|---|---|
| **Ninguno de los 23 puertos tiene implementación.** Está declarado regla por regla, no solo acá | `plugin_fake` los implementa todos: **fase 2** |
| **Coherencia del registro de reglas en tiempo de ejecución.** El constructor de `Rule` rechaza lo que no se puede instalar, pero **nada obliga a que una regla del proyecto llegue a ser una `Rule`**: una que viva solo en prosa esquiva el tipo entero | El registro y su proyección: **fase 3** |
| **El grafo interno** y su check de *regenerado == commiteado* | **Fase 0b** |
| **El check de proyección de la capa C.** Hoy `AGENTS.md` y `CLAUDE.md` están **excluidos** de la regla de cadenas —nombrar `claude` o `flutter` es su contenido, por diseño— y nada verifica que lo proyectado sea coherente | **Fase 3** |
| Todo el producto: cascada, ganchos, capa C, intake, sensores | Fases 2 a 7 |

**El arnés está partido en dos repositorios, y eso se puede instalar a medias.**
Los checks de este repo cubren la arquitectura del código. Los que verifican el
corpus de diseño viven en `../sdlc-agentico/` con su propio CI. Tener uno solo
en verde **no significa que el arnés esté completo**. Lo único que hoy cruza los
dos es `estados.py`, que compara el inventario del arnés contra las reglas
instaladas acá — y **se degrada a «no disponible» si los repos dejan de estar
uno al lado del otro**, lo cual está impreso pero no falla.

---

## Estructura

```
packages/
  core            entidades y puertos · cero dependencias
    lib/src/      valores · entidades · regla · observacion · credencial · puertos
    test/         ida y vuelta, invariantes de Rule, opacidad, veredictos
  orchestration   compositor de etapas, AutonomyPolicy, cascada
  vcs             rama, commits, PR · agnóstico
  rules           registro, proyección a C y E, telemetría
  agents          adapters por CLI agéntico
  plugin_dart     preguntas de stack Dart/Flutter
  plugin_fake     todos los puertos, para pruebas
  cli             comandos y composition root
tool/
  checks/         capas.py · probar_reglas.py
  serializacion/  el verificador que necesita el árbol sintáctico · fuera del workspace
```

Todas las flechas de dependencia apuntan hacia `core`. `cli` es el único que
puede ver a `plugin_dart` y a `agents`.
