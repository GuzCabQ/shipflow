# shipflow

CLI Dart que hace que **el agente del usuario** entregue mejor. No construye un
bucle agéntico: se integra con Claude Code, Codex o Gemini CLI.

El diseño completo —18 ADRs, el modelo D+C+E, el catálogo de fallos, el plan por
fases— vive en un repositorio aparte: **`../sdlc-agentico/`**. Empezá por su
`AGENTS.md`.

---

## Estado: fase 0. No hay producto.

Este repositorio tiene **paquetes vacíos y los controles que impiden que el
desarrollo se salga del diseño.** No hay CLI, no hay cascada, no hay ganchos.
Eso es deliberado.

**El problema que resuelve.** El intento anterior no falló por mala
arquitectura: falló porque todo lo que gobernaba el proceso estaba escrito en
prosa y nada lo hacía cumplir. De 27 ADRs, uno tenía invariante ejecutable. No
había CI; el único ejecutor era un `pre-push` y `--no-verify` lo salteaba.

Este proyecto llegó a tener **dieciocho ADRs con su invariante escrito y cero
instalados**. La fase 0 convierte *"decidimos que X"* en *"no se puede mergear
algo que viole X"*. Esa es toda la diferencia entre una decisión y una regla.

Y se hace ahora, sobre paquetes vacíos, porque es el único momento en que cuesta
cero. Una regla de frontera instalada sobre veinte mil líneas produce miles de
violaciones el primer día, y lo que pasa entonces no es que alguien corrija
veinte mil líneas: se desactiva la regla.

---

## Qué corre

```
dart pub get                           # PRECONDICIÓN: capas.py le pide el grafo a pub
python3 tool/checks/capas.py           # la regla de capas, verificada
python3 tool/checks/probar_capas.py    # y la prueba de que sabe fallar
dart analyze --fatal-infos
dart format --set-exit-if-changed .
```

| `id` de la regla | Qué impide | Origen |
|---|---|---|
| `deps-hacia-core` | Que una flecha **interna** apunte a otro lado que no sea `core` | docs/03 §1 y §2 |
| `nucleo-sin-externas` | Que `core` gane una dependencia **de cualquier origen**. Ninguna | docs/03 §1 y §2 |
| `agente-en-agents` | Que `claude`/`codex`/`gemini` salgan de `agents/` | ADR-009, 1.ª condición |
| `lenguaje-en-plugin-dart` | Que `dart`/`flutter`/`pubspec` salgan de `plugin_dart/` | docs/03 §2 |
| `sin-api-de-modelo` | Que **cualquier** paquete llame a una API de modelo | ADR-009, 2.ª condición |

Las dos primeras son independientes a propósito: una mira **nombres** de
paquetes internos, la otra el **origen** de las dependencias. Antes se tapaban
entre sí y bastaba permitir el nombre para que la externa pasara. Y `deps-hacia-core`
ya **no** gobierna dependencias externas de los demás paquetes: `docs/03` §2
enuncia esa prohibición solo para `core`.

**Las reglas viven en [`arquitectura.json`](arquitectura.json)**, en un solo
lugar y diffeable. Tocarlo es cambiar la arquitectura y se revisa como tal.

Tres propiedades que las hacen verificables, y que no estaban en la primera
versión:

- **Cada regla tiene un `id` estable** y una **violación canónica**: un caso
  sintético que la regla tiene que detectar. Se inyecta y se revierte, así que
  es compatible con el ratchet —toda regla nueva está verde el día que se
  agrega— y de hecho es su precondición: *verde* no significa nada si la regla
  no puede ponerse roja.
- **Lo que no deriva, está fijado**: `solo_en`, el mapa de flechas y las
  extensiones del alcance vienen de un ADR o de `docs/03`, y `capas.py` los
  compara contra el valor esperado. La canónica prueba que el instrumento
  dispara; el pinneo prueba que la política no se reescribió — son modos de
  fallo distintos. Ensanchar `solo_en` deja el canario disparando y desprotege
  todo lo demás.
- **Y una huella `sha256` de la política**, commiteada aparte, como respaldo de
  lo que no está fijado campo por campo. Cambiar la arquitectura pasa a ser un
  acto de dos archivos, visible y revisable. **Límite declarado:** esto vuelve
  imposible degradar la política *en silencio*, no degradarla. Contra alguien
  que edite las dos cosas no hay check: hay revisión.
- **Cada regla declara su `alcance`** — qué extensiones cubre y qué excluye, con
  el motivo y con quién lo cubre en su lugar. Un control que no dice qué mira no
  puede distinguir *"no encontré nada"* de *"no miré ahí"*, que es el corolario 5
  de ADR-011.
- **El grafo de dependencias se le pide a pub** (`dart pub deps --json`), no se
  parsea a mano. La versión anterior solo reconocía una forma textual del
  `pubspec`: un `dependencies: {http: ^1.0.0}` le devolvía cero dependencias y
  el check pasaba en verde **sin haber mirado**.

`probar_capas.py` deriva sus casos del propio registro y degrada **cada regla
de todas las formas que conservan su `id`** —tipo cambiado, alcance vaciado,
`solo_en` ampliado, exclusión que traga paquetes—, comprobando que el check
igual falla con la canónica puesta: **28 sabotajes detectados sobre 5 reglas**.
Cada neutralización regenera la huella a propósito, para que el control puntual
se pruebe solo y no quede tapado por ella. Más dos controles negativos, que
verifican que las exclusiones excluyan de verdad. Y comprueba que los sabotajes
no dejen residuo en el árbol.

Corre en CI junto al check, no una vez a mano: **un check que nunca falló no
está probado**, y un guardia que existe y nunca se disparó es indistinguible de
uno roto.

---

## Qué promete esta fase y todavía no cumple

Declararlo es obligación de cada fase, y viene de una lección concreta: una
superficie incompleta que se muestra vacía se lee como *"no había nada"*.

| Falta | Cuándo |
|---|---|
| **Coherencia del registro de reglas** — ninguna `Rule` sin `alternativa` ni `evasiones_conocidas`. Es el sexto check de la fase 0 | Necesita `core`. **Fase 1** |
| **El grafo interno** y su check de *regenerado == commiteado* | **Fase 0b**, después de `core` |
| **El check de proyección de la capa C.** Hoy `AGENTS.md` y `CLAUDE.md` están **excluidos** de la regla de cadenas —nombrar `claude` o `flutter` es su contenido, por diseño— y nada verifica que lo proyectado sea coherente | **Fase 3** |
| Todo el producto: cascada, ganchos, capa C, intake, sensores | Fases 2 a 7 |

**El arnés está partido en dos repositorios, y eso se puede instalar a medias.**
Los checks de este repo cubren las reglas de capa. Los que verifican el corpus
de diseño —coherencia documental y cifras derivadas— viven en
`../sdlc-agentico/` con su propio CI. Tener uno solo en verde **no significa que
el arnés esté completo**, y hoy nada lo detecta automáticamente.

---

## Estructura

```
packages/
  core            entidades y puertos · cero dependencias
  orchestration   compositor de etapas, AutonomyPolicy, cascada
  vcs             rama, commits, PR · agnóstico
  rules           registro, proyección a C y E, telemetría
  agents          adapters por CLI agéntico
  plugin_dart     preguntas de stack Dart/Flutter
  plugin_fake     todos los puertos, para pruebas
  cli             comandos y composition root
```

Todas las flechas de dependencia apuntan hacia `core`. `cli` es el único que
puede ver a `plugin_dart` y a `agents`.
