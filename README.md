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
(cd tool/analisis && dart pub get \
   && dart run bin/check.dart      # serialización, opacidad, puertos, colecciones
   && dart run bin/grafo.dart)     # el grafo: derivado == commiteado
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
| `serializacion-sin-perdida` | Que un campo de `core` no viaje, o vuelva vacío | `tool/analisis` |
| `opacidad-declarada` | Que «no serializa» sea indistinguible de «se olvidaron» | `tool/analisis` |
| `puertos-sin-implementacion` | Que una superficie de puertos vacía se lea como un sistema que hace esas cosas | `tool/analisis` |
| `colecciones-inmutables` | Que un invariante se pueda romper **después** de construir el objeto, mutando la lista que se le pasó | `tool/analisis` |
| `grafo-derivado` | Que el mapa del repositorio quede desactualizado, o que un archivo no lo alcance nadie | `tool/analisis` |

Una regla que `capas.py` no aplica **tiene que declarar `aplicada_por`**, ese
aplicador tiene que existir, y CI tiene que invocarlo. Sin las tres cosas es
F33: registrada y no ejecutada. El propio check lo verifica —y de hecho fue lo
primero que hizo cuando se agregaron las tres reglas nuevas.

### Por qué las cinco últimas necesitan otro motor

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

## Y que CI siga ejecutando lo que dice ejecutar

Todo lo de abajo depende de que el workflow los invoque, y **nada lo verificaba**.
`capas.py` leía `checks.yml` solo para comprobar que los *aplicadores delegados*
estuvieran mencionados —porque una regla lo declara—; `capas.py` mismo,
`probar_reglas.py`, los tests, el analizador y el formateo **no los declaraba
nadie**. Borrar cualquiera de esos pasos no lo notaba nada.

Mientras el CI no corría era una molestia teórica. **Desde que las ramas están
protegidas y el merge depende de este workflow, borrar un paso es abrir la
compuerta sin tocar ninguna regla.**

Los siete pasos obligatorios están fijados en `capas.py` —es política, no
deriva de nada— y se comprueban en tres modos de fallo distintos:

| El sabotaje | Resultado |
|---|---|
| Un paso obligatorio **borrado** del workflow | **detectado** |
| Un paso obligatorio con **`continue-on-error: true`** — corre, se ve en rojo, no detiene nada | **detectado** |
| El workflow **vaciado** | **detectado** |

**El workflow se le pide a un parser de YAML**, no se lee a mano: un parser
casero devuelve cero pasos ante una sintaxis que no reconoce, y cero pasos se
lee igual que *«están todos»*. Si el parser no está disponible, el check
**falla** — es la misma lección que ya pagó el grafo de dependencias con pub.

**Residuo declarado:** esto verifica que el workflow **ejecute** los pasos. No
verifica que la **protección de rama exija ese workflow**, porque eso vive en
la configuración de GitHub y no en el repositorio. Se comprueba intentando un
push directo, que es un acto manual y periódico.

---

## El caso ciego · la mitad que faltaba

Cada regla declara **dos** casos, y prueban cosas distintas:

| | Qué prueba | Qué le pasa al check |
|---|---|---|
| `violacion_canonica` | Detecta un **exceso** — algo que no debería estar | Se le pone algo malo delante |
| **`caso_ciego`** | Detecta una **omisión** — que no pudo mirar | **Se le quita el canal por el que observa** |

Ninguno implica al otro. Un check puede disparar impecablemente sobre una
violación y, con el alcance apuntado a un directorio vacío, pasar en verde sin
haber inspeccionado un solo archivo. Es lo que ADR-011 corolario 5 llama **el
sesgo natural de todo verificador**, y su invariante ejecutable pedía esto
desde el 25/08:

> *Test en CI: para cada paso registrado, existe un caso donde el paso **no
> puede ejecutarse** y el resultado es no concluyente, **nunca verde**.*

Estuvo **escrito y sin instalar** durante todo el diseño, que es exactamente la
enfermedad que este proyecto combate.

### Qué encontró en su primera corrida

**Cuatro controles ciegos de nueve.** No hipotéticos: verdes medidos.

| Control | Cómo estaba ciego |
|---|---|
| `agente-en-agents` · `lenguaje-en-plugin-dart` · `sin-api-de-modelo` | Con `alcance.raiz` apuntando a un directorio inexistente recorrían **cero archivos** y devolvían «ok». Verde sobre nada se leía igual que verde sobre ochenta archivos limpios |
| `grafo-derivado` | Envolvía `parseFile` en un `try/catch` que **nunca disparaba**: con `throwIfDiagnostics: false` el parser devuelve un árbol *parcial* en vez de lanzar. Un archivo de basura entraba como nodo sin aristas, el grafo salía más chico, y *regenerado == commiteado* seguía coincidiendo porque **los dos lados quedaban igual de ciegos** |

El segundo es el que más dice: **el comentario del código describía el fallo
correctamente y el código hacía lo contrario.** Escribir el guardia no es
instalarlo, ni siquiera cuando el guardia está escrito en el archivo correcto.

### Los cinco resguardos para que esto no repita el patrón

1. **Obligatorio.** Una regla sin `caso_ciego` falla el meta-check. No hay
   ausencia silenciosa: es el mismo trato que `violacion_canonica`.
2. **Mecanismo fijado.** `caso_ciego.como` está pinneado en `capas.py`, como el
   `tipo`. Es el campo que más fácil se vuelve inofensivo — basta cambiarlo por
   algo que no ciegue nada para que el caso pase siempre.
3. **`debe_mencionar` obligatorio.** Rojo por otra razón no cuenta. Sin esto,
   cualquier fallo colateral se leería como ceguera detectada.
4. **Se ciega un sujeto que YA EXISTE y YA es alcanzable.** Agregar un archivo
   nuevo y romperlo no serviría: quedaría huérfano y el rojo vendría de Q5.
5. **El conteo cuadra o falla.** Los casos ciegos se derivan del registro y
   tienen que ser **uno por regla**. Un mecanismo desconocido tampoco pasa:
   *un caso que no se puede montar no es un caso que pasó, es uno que no se
   probó.*

**Y la prueba de que no es decorativo:** revertida la corrección de
`agente-en-agents`, su caso ciego reporta *«el check pasó en VERDE con su canal
de observación inutilizado»*. Se comprobó.

**Lo que sigue sin cubrir, declarado.** El caso ciego prueba que el control se
pone rojo cuando **no puede mirar**. No prueba que **mire en todos lados donde
dice mirar**: una exclusión que se traga un paquete donde el canario no vive
deja el canario disparando y desprotege el resto. Eso lo cubre el pinneo de
valores, y solo en parte.

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

---

## Sabotajes del estado intermedio · fase 2

### S2.1 · ¿Qué promete la fase que todavía no cumple, y el artefacto lo declara?

La fase 2 promete `verify` + `ship`. **Esta rebanada no entrega ninguno de los
dos**: no hay CLI, no hay cascada, no hay ensamblado de PR. Entrega el
**fixture** —el sujeto sobre el que todo eso va a correr— y la prueba de que
sigue siendo un proyecto que funciona.

Declarado en [`fixtures/app-minima/README.md`](fixtures/app-minima/README.md),
que también dice lo que el fixture **no** es: no entra al grafo, no es miembro
del workspace, y **no es representativo de la escala** — dos paquetes contra
las decenas de un proyecto real.

### S2.2 · ¿Qué queda a medias si se instala solo una parte?

El fixture tiene una mitad Dart pura y una mitad Flutter. **La primera se
verifica con la toolchain que CI ya tenía; la segunda necesita instalar
Flutter.** Si esa instalación se cae o alguien saca el paso, la mitad Flutter
—que es la que justifica que el fixture sea Flutter— queda sin verificar y en
verde.

| El sabotaje | Resultado |
|---|---|
| Sacar de CI el paso que verifica la mitad Flutter | **detectado** — los dos pasos del fixture son obligatorios, con su comando exacto y su directorio |

### S2.3 · ¿Se puede pasar el check de esta fase sin cumplirlo?

**Sí, y es F36.** El criterio de salida dice *«sobre un fixture real»*. Un
fixture commiteado es una **fotografía**: sus archivos están ahí porque alguien
los copió. Un árbol con la forma correcta y nada detrás satisfaría la letra del
criterio sin que nada hubiera compilado nunca.

| El sabotaje | Resultado |
|---|---|
| Romper el fixture para que deje de compilar | **detectado** — `dart analyze` sale con 3, y ese comando es un paso obligatorio de CI |

**Por eso CI ejecuta el fixture en vez de solo tenerlo.** Y ya se cobró una
pieza: al armarlo, el analizador real encontró dos errores en el test de `app`
que yo no había visto. Un fixture inventado no da eso.

---

## Sabotajes del estado intermedio · fase 0b

Obligación de cada fase, al empezarla: **tres sabotajes contra el estado en que
la fase deja el sistema, escritos, ejecutados, y con su resultado acá.**

### S0b.1 · ¿Qué promete la fase que todavía no cumple, y el artefacto lo declara?

El grafo existe para responder **ocho preguntas** que ninguna búsqueda contesta
(`GRAFO` §2). Responde **cuatro**: Q1 conteo de aristas, Q2 índice inverso, Q5
alcanzabilidad y Q8 ciclos. No responde Q3, Q4, Q6 ni Q7.

**Q4 es la que motivaba la idea entera** —*si algo cambia en código que afecta
la prosa, saberlo*— y necesita la arista `describe`, que el freno de `GRAFO` §8
congela hasta que exista un caso real de prosa desincronizada.

**El sabotaje encontró algo, y no fue una omisión: fue de más.** El esquema
propuesto en `GRAFO` §5 incluye `hash` y `hash_destino`, y los dos existen para
responder Q4. Escribirlos hoy habría sido andamiaje inventado — exactamente lo
que §1 prohíbe: *cada campo debe poder nombrar la pregunta que responde*. **No
se escriben.** El residuo está declarado en `arquitectura.json` →
`grafo-derivado.alcance.residuo_declarado`.

### S0b.2 · ¿Qué queda a medias si se instala solo una parte?

El generador sin la comparación en CI. `GRAFO` §4 lo dice sin rodeos: **un mapa
desactualizado es peor que no tener mapa**, porque las reglas derivadas de él
pasan a ser mentira con aspecto de evidencia.

Son **dos** modos de fallo distintos, y los dos están en el arnés:

| El sabotaje | Resultado |
|---|---|
| Un archivo nuevo, sin regenerar el grafo | **detectado** — es la violación canónica de `grafo-derivado` |
| El `grafo.jsonl` commiteado editado a mano | **detectado** — un caso propio, porque *olvidarse de regenerar* y *editar lo derivado* no son lo mismo |

### S0b.3 · ¿Se puede pasar el check de esta fase sin cumplirlo?

**Sí, de dos maneras, y las dos aparecieron al construirlo.**

**La primera es la grave.** Si el generador **saltea en silencio** un archivo
que no pudo parsear, el grafo sale más chico — y *regenerado == commiteado*
sigue pasando en verde, porque **los dos lados están igual de ciegos**. El
check no compara contra la realidad: compara contra sí mismo.

Corregido con dos controles: un archivo ilegible es **rojo**, no un `continue`;
y el número de nodos se compara contra el número de archivos candidatos, así
que perder uno en el camino falla aunque no haya lanzado excepción.

**La segunda fue un error de criterio, no de código.** La primera versión medía
`saltos` solo desde `README.md`, y dejó **20 de 21 nodos huérfanos** — porque un
README no enlaza código. La salida cómoda era declarar veinte excepciones en
`grafo-huerfanos.txt` y seguir.

**Eso habría sido una lista que no protege nada.** El criterio estaba mal, no
el árbol: en un repo de código los puntos de entrada son el barril público de
cada paquete, los tests y los `bin/`. Corregido el criterio, los huérfanos son
**cero** y la lista está vacía — que es su estado correcto.

> La lección es la del catálogo de fallos: **cuando una regla nueva produce
> veinte violaciones el primer día, lo que suele estar mal es la regla.**
> Declarar las veinte la desactiva sin borrarla.

## Qué prometen estas fases y todavía no cumplen

Declararlo es obligación de cada fase, y viene de una lección concreta: una
superficie incompleta que se muestra vacía se lee como *"no había nada"*.

| Falta | Cuándo |
|---|---|
| **Ninguno de los 23 puertos tiene implementación.** Está declarado regla por regla, no solo acá | `plugin_fake` los implementa todos: **fase 2** |
| **Coherencia del registro de reglas en tiempo de ejecución.** El constructor de `Rule` rechaza lo que no se puede instalar, pero **nada obliga a que una regla del proyecto llegue a ser una `Rule`**: una que viva solo en prosa esquiva el tipo entero | El registro y su proyección: **fase 3** |
| **El check de proyección de la capa C.** Hoy `AGENTS.md` y `CLAUDE.md` están **excluidos** de la regla de cadenas —nombrar `claude` o `flutter` es su contenido, por diseño— y nada verifica que lo proyectado sea coherente | **Fase 3** |
| **`verify` y `ship`.** El fixture ya existe y se verifica solo; falta todo lo que va a correr sobre él: los once puertos del plugin de stack, la cascada, `vcs` y el ensamblado del PR | **Fase 2**, rebanadas siguientes |
| **La suite de contrato.** Sin ella `plugin_fake` no es un sustituto válido, y todo lo que se pruebe contra él queda verde por construcción (`docs/08` §2) | **Fase 2**, con los primeros puertos |
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
  analisis/      lo que necesita el árbol sintáctico · fuera del workspace
```

Todas las flechas de dependencia apuntan hacia `core`. `cli` es el único que
puede ver a `plugin_dart` y a `agents`.
