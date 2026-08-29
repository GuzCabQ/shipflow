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
python3 tool/checks/capas.py           # la regla de capas, verificada
python3 tool/checks/probar_capas.py    # y la prueba de que sabe fallar
dart pub get && dart analyze
```

| Check | Qué impide | Origen |
|---|---|---|
| reglas registradas presentes | Que se vacíe `arquitectura.json` y el árbol quede verde con menos reglas | F33 |
| cadenas acotadas a su adapter | Que `claude`/`codex`/`gemini` salgan de `agents/`; que `dart`/`flutter` salgan de `plugin_dart/` | ADR-009, docs/03 §2 |
| dependencias entre paquetes | Que una flecha de dependencia apunte a otro lado que no sea `core` | docs/03 §2 |
| núcleo sin dependencias externas | Que `core` gane una dependencia. Ninguna | docs/03 §1 |

**La regla vive en [`arquitectura.json`](arquitectura.json)**, en un solo lugar y
diffeable. Tocarlo es cambiar la arquitectura y se revisa como tal.

`probar_capas.py` rompe cada control a propósito y verifica que el check se
entere. Corre en CI junto al check, no una vez a mano: **un check que nunca
falló no está probado**, y un guardia que existe y nunca se disparó es
indistinguible de uno roto.

---

## Qué promete esta fase y todavía no cumple

Declararlo es obligación de cada fase, y viene de una lección concreta: una
superficie incompleta que se muestra vacía se lee como *"no había nada"*.

| Falta | Cuándo |
|---|---|
| **Coherencia del registro de reglas** — ninguna `Rule` sin `alternativa` ni `evasiones_conocidas`. Es el sexto check de la fase 0 | Necesita `core`. **Fase 1** |
| **El grafo interno** y su check de *regenerado == commiteado* | **Fase 0b**, después de `core` |
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
