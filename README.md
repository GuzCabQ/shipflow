# shipflow

CLI Dart que hace que **el agente del usuario** entregue mejor. No construye un
bucle agéntico: se integra con Claude Code, Codex o Gemini CLI.

El diseño completo —18 ADRs, el modelo D+C+E, el catálogo de fallos, el plan por
fases— vive en un repositorio aparte: **`../sdlc-agentico/`**. Empezá por su
`AGENTS.md`.

---

## Estado: fase 2, cuarta rebanada. **Hay un comando.**

`core` existe: **las entidades y los puertos, como tipos.** 6 de los 25
puertos ya tienen implementación viva. Y existe el **fixture**: un proyecto
de verdad, con toolchain de verdad.

**Y existe `shipflow verify`.** Corre los dos primeros pasos de la cascada
—`FormatCheck` y `StaticAnalysis`—, reporta sus diagnósticos con el testigo de
cada uno, y sale con un código que **se deriva** del estado de la corrida.

```
$ shipflow verify lib
  ok        FormatCheck
  ok        StaticAnalysis
verify: ok — 2 de 2 pasos ejecutados, 0 diagnóstico(s).
```

**El desenlace de un paso ya es un tipo cerrado, y la aplicabilidad ya salió del verificador.** Ver [El desenlace se cierra, y la aplicabilidad sale del verificador](#el-desenlace-se-cierra-y-la-aplicabilidad-sale-del-verificador). El plan, tarea por tarea, está en [PLAN-desenlace-cerrado.md](PLAN-desenlace-cerrado.md); lo que queda de él es propagar el registro de deltas al otro repositorio, no código de este.

**No existe `ship`**, ni el agente, ni los tickets, ni los ganchos.
Y a la cascada le falta lo que la vuelve una cascada: el corte temprano y el
presupuesto. Todo eso es deliberado y está declarado más abajo, control por
control.

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
python3 tool/checks/probar_recuperacion.py    # y de que se recupera de una corrida muerta
dart test packages/core                       # invariantes del dominio
dart test packages/orchestration              # el registro de pasos y la cuenta
dart test packages/vcs                        # la rama y el commit, contra git de verdad
dart test packages/cli                        # las suites de CONTRATO entre implementaciones
dart test packages/plugin_dart                # unitarias, y las que corren la toolchain de verdad
dart analyze --fatal-infos
dart format --set-exit-if-changed packages tool
(cd fixtures/app-minima/dominio && dart test)  # el fixture se verifica solo
(cd fixtures/app-minima/app && flutter test)
```

**Son 15 pasos y `capas.py` lo verifica contra el workflow**, comando por
comando: un paso borrado de CI, o neutralizado con un `if:` o un
`continue-on-error`, pone el check en rojo.

**Las reglas viven en [`arquitectura.json`](arquitectura.json)**, en un solo
lugar y diffeable, aunque las apliquen dos motores distintos. Tocarlo es cambiar
la arquitectura y se revisa como tal.

| `id` de la regla | Qué impide | Aplica |
|---|---|---|
| `deps-hacia-core` | Que una flecha **interna** apunte a otro lado que no sea `core` | `capas.py` |
| `nucleo-sin-externas` | Que `core` gane una dependencia **de cualquier origen**, incluidas las de desarrollo | `capas.py` |
| `nucleo-sin-entrada-salida` | Que `core` toque el mundo directamente en vez de pedirlo por un puerto | `capas.py` |
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

Los 15 pasos obligatorios están fijados en `capas.py` —es política, no deriva
de nada— y se comprueban en varios modos de fallo, que son distintos entre sí:

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

## Las suites de contrato

Un puerto con **una sola implementación** no es una abstracción: es una
indirección que todavía no se contradijo. El intento anterior tenía quince
adaptadores vacíos.

`docs/08` §2: *un fake solo es sustituto válido si cumple el mismo contrato que
el real. Sin eso se testea contra un fake que miente y la suite queda verde por
construcción.*

Cada puerto implementado tiene su suite. **No todos la corren contra un
fake**, y por eso la columna existe: la tabla dice cuál tiene qué, en vez
de afirmar de todos lo que vale para algunos. Va sin número a propósito —
hoy nada deriva cuántos fakes hay, y una cifra que nadie deriva envejece
sola.

| Puerto | Real | Fake |
|---|---|---|
| `ProjectTopology` | lee el fixture del disco | se le declara la topología |
| `ArtifactPolicy` | clasifica con los patrones de `N1-02` y `N1-03` | se le declaran las respuestas |
| `DiagnosticNormalizer` | **dos** reales, una por herramienta | formato propio, trivial |
| `Verifier` | **dos** reales: los dos primeros pasos | **no hay**, y está declarado |
| `ChangeSink` | `git` de verdad, sin doble | **no hay**, y está declarado |

`DiagnosticNormalizer` tiene dos implementaciones reales y no una: el puerto es
uno y los formatos que tiene que leer son varios. La suite corre contra las
tres, y cada una trae su propia muestra — el contrato no conoce ningún formato.

`Verifier` salió con **dos reales y ningún fake**, y eso está escrito en el
registro en vez de disimulado. El motivo por el que un puerto pide dos
implementaciones —que una sola es una indirección que todavía no se
contradijo— ya está cubierto: sus dos pasos difieren en lo que importa, y esa
divergencia produjo la quinta cláusula del puerto. Falta un `Verifier` falso
para que `orchestration` pueda probar la cascada sin toolchain; llega con la
fase que lo necesite.

`ChangeSink` salió igual, con **una real y ningún fake**, y un review lo
cobró: no por faltarle el fake, sino porque **salió de la lista de puertos
sin implementación sin declarar con qué salía**. La lista decía quién falta;
hacía falta que también dijera con qué se fue el que ya no está. Hoy no hay
etapa que lo consuma —no existe `ship`— así que no hay nada que probar
contra un fake, y una suite de contrato con una sola implementación no
contrasta nada: corre la misma lógica dos veces. El fake llega con `ship`.

**El fake no reimplementa los patrones del real, a propósito.** Si los copiara,
un error en ellos estaría en las dos implementaciones y la suite lo confirmaría
en verde: dos copias del mismo error se ponen de acuerdo.

Y cada suite abre con un test que comprueba que **son dos**. Sin eso, sacar la
real —porque tarda, porque necesita disco, porque falló una vez— dejaría todo
en verde probando el fake contra sí mismo, que es el modo de fallo exacto que
`docs/08` nombra.

### Lo que encontraron en su primera corrida

Una **divergencia real**: para la ruta vacía, la implementación real decía «no
editable» y el fake decía «editable».

Ninguna de las dos estaba mal — **faltaba una cláusula del contrato**. Se
escribió en el puerto, en `core`, donde vale para cualquier stack:

1. Lo generado nunca es editable. No son dos hechos: el segundo se sigue del primero.
2. Una ruta vacía no es editable. Devolver `true` dejaría al arnés intentando escribir en ninguna parte.

Eso es lo que una suite de contrato produce cuando funciona: no un error en una
implementación, **sino una parte del acuerdo que nadie había escrito**.

### Y lo que encontró la segunda corrida, midiendo las herramientas

Antes de escribir los normalizadores se midió qué escribe cada herramienta en
cada situación. Tres resultados, reproducibles:

| Invocación | Código | Escribe |
|---|---|---|
| formateador sobre un directorio **inexistente** | **0** | `Formatted no files` |
| analizador, formato `machine`, sin hallazgos | 0 | **cero bytes** |
| analizador, formato `json`, sin hallazgos | 0 | `{"version":1,"diagnostics":[]}` |

Las dos primeras son **verdes indistinguibles de la ceguera**: un paso que
confíe en el código de salida da verde sobre un alcance que nunca miró. La
tercera afirma haber mirado.

Eso decidió dos cosas. Que el plugin use el formato **más incómodo de parsear**,
porque es el único cuyo caso vacío se distingue del silencio. Y que la línea de
resumen del formateador sea **obligatoria**: es el denominador, y sin ella cero
hallazgos no significa nada.

Las cuatro cláusulas que quedaron escritas en el puerto salen de ahí. La
primera es la que sostiene a las demás: **una entrada que no se puede
interpretar lanza; nunca devuelve la lista vacía.** La lista vacía tiene una
sola lectura posible —«leí todo y no había nada»— y si además significara «no
entendí», el verde del paso sería indistinguible de la ceguera.

### Los guardias se probaron rompiéndolos

Los treinta y dos tests de contrato y los once unitarios pasaron **en la primera
corrida**, que no prueba nada: un test que nunca falló no está probado. Se
mutaron los nueve guardias, uno por vez, corriendo las dos suites contra cada
mutación:

| Se rompió | Murió |
|---|---|
| el guardia del vacío | 1 test |
| la versión de esquema | 2 |
| la severidad sin mapeo cae en la más suave | 1 |
| exigir el denominador | 4 |
| el bloque de parseo sin líneas legibles | 1 |
| el patrón del archivo que no parsea | 4 |
| la lista inmodificable | 1 |
| los campos exactos, en el fake | 1 |
| recorrer **todas** las líneas, en el fake | 1 |

**Cero sobrevivientes.** El primero es el que justifica el ejercicio: el guardia
del vacío parecía código muerto, porque el decodificador de JSON también falla
ante una entrada vacía. Un guardia al que otro le tapa el caso no está
instalado, está de adorno — así que el test que lo cubre lo identifica **por su
motivo**, no solo por el tipo de la excepción.

### Y lo que la mutación no encontró, porque los casos los elegía yo

Un review externo encontró dos incumplimientos que las dos suites daban por
buenos.

**El primero es el patrón que este repositorio ya tiene nombrado.** El
comentario del normalizador decía «el resumen es obligatorio, **es el
denominador**, dice cuántos archivos miró de verdad» — y el código solo
comprobaba que la línea **existiera**. Así, `Formatted 2 files (1 changed)` sin
ninguna línea `Changed` devolvía cero hallazgos: la herramienta declaraba un
archivo sin formatear y el normalizador lo reportaba como limpio. Comprobar
PRESENCIA cuando había que comprobar CONTENIDO es exactamente lo que `Rule`
tiene escrito a propósito de las evasiones en blanco. Ahora se reconcilia, y en
los dos sentidos.

**El segundo es de tipo, no de lógica.** Un número de línea inválido hacía que
el normalizador lanzara `FormatException` y no `UnreadableToolOutput`. Importa
porque el paso de cascada va a atrapar solo el segundo: una excepción de otro
tipo aborta la corrida en vez de producir un veredicto no concluyente. El
review lo vio en el fake; estaba también en el real, por un `int.parse` que solo
se rompe con un número de veinte dígitos.

**Lo que fallaba no era la atención: era que cada implementación elegía sus
propios casos ilegibles**, así que podía elegir los fáciles. La suite ahora
**deriva** las entradas corruptas del texto bueno con mutaciones mecánicas
—truncar, borrar una línea, volver letras los dígitos, alargarlos— y exige que
cada una se lea bien o lance **el tipo que el puerto promete**, nunca otro. Es
el mismo criterio por el que el grafo se le pide a `pub` y los campos al árbol
sintáctico.

Y esa red nació tapada. Las mutaciones tocaban todas las líneas a la vez,
incluida la de encabezado del fake: el guardia del encabezado disparaba primero
y el número de línea nunca se alcanzaba. **El sobreviviente de la corrida de
mutación era justo el bug del review.** Se corrompe una línea por vez, y ahora
son cero sobre catorce guardias.

---

## Los dos primeros pasos de la cascada

`FormatCheck` y `StaticAnalysis`. Invocan la herramienta, normalizan su salida
y **devuelven su testigo**. Toda la disciplina de atestación vive en la clase
base y en ningún otro lado: un paso nuevo no puede olvidarse de construir su
testigo porque no es él quien lo construye. Aporta qué invocar y sobre qué
puede atestiguar, y el veredicto sale de ahí.

### Los dos no ven lo mismo, y eso se declara

| | ¿Puede detectar que no miró nada? | Cómo |
|---|---|---|
| `FormatCheck` | **sí** | la herramienta informa cuántos archivos miró |
| `StaticAnalysis` | **no** | sobre un alcance vacío devuelve lo mismo que sobre uno limpio |

Está medido, no supuesto. El formateador sobre un directorio inexistente sale
con **código 0**; el analizador sobre un directorio vacío devuelve
`{"version":1,"diagnostics":[]}`, byte por byte lo mismo que sobre código
impecable.

Así que `FormatCheck` deriva su cobertura del resumen de la herramienta, y
cero archivos mirados deja el testigo **sin sujetos** — y sin sujetos no hay
verde, por la mecánica que ya estaba en `core`. Nadie tiene que acordarse de
ponerlo en rojo.

`StaticAnalysis` no puede hacer eso, así que hace dos cosas y escribe las dos
en su testigo: una ruta inexistente le hace devolver un código que no está en
su lista blanca, y **la cantidad de archivos del alcance la cuenta el arnés**,
porque la herramienta no la dice. Lo que sigue sin cubrirse —que los haya
leído todos— es residuo declarado.

Los códigos de salida que significan «corrí» son una **lista blanca**. Un
código que no está deja el resultado no concluyente en vez de leerse como el
más benigno: una herramienta que empieza a devolver un código nuevo tiene que
hacernos parar, no pasar.

### `Witness` no tenía dónde escribir eso

ADR-011 pide un testigo de *«qué corrió, sobre qué alcance, **qué omitió y por
qué**»*. Las tres primeras estaban en el tipo desde la fase 1. La cuarta no, y
se notó en el primer paso que la necesitó. Ahora es un campo, `omitted`, y es
el corolario 5 vuelto dato: **cada control declara si puede detectar una
omisión**, en el testigo y no en un comentario del código.

No entra en `attests`. Declarar una omisión es parte de un reporte honesto, no
un motivo para invalidarlo: un paso que corrió sobre nueve de diez archivos y
lo dice atestigua; uno que corrió sobre diez y no lo dice no es mejor.

### Contra la toolchain de verdad

Siete pruebas más corren los pasos con la herramienta instalada, sobre archivos
escritos en el momento. **Cierran el residuo que la suite de contrato había
declarado**: allá las muestras son salida capturada pero congelada, y si la
herramienta cambiara de formato aquella suite seguiría verde contra un formato
que ya nadie emite.

Una de esas siete afirma que el código de salida del formateador sobre un
alcance inexistente **es 0**. Si algún día deja de serlo, la prueba se pone
roja y avisa que este paso tiene más defensa de la que necesita — que es la
forma correcta de enterarse.

### Y el motor de checks tenía su propio punto ciego

Al sacar `Verifier` de la lista de puertos sin implementación, el check dijo
**ok**. No debía: `Verifier` ya tenía dos implementaciones vivas.

Miraba los supertipos **directos** de las clases concretas. Una base abstracta
que implementa el puerto no contaba —es abstracta— y la clase concreta solo
nombraba a la base, así que el puerto quedaba invisible. Es la forma exacta que
ese control existe para cazar, aplicada al control mismo: mirar donde es cómodo
y llamar a eso el invariante.

Ahora sigue la herencia hasta arriba. Y como arreglar algo no es instalarlo,
la regla ganó una **segunda violación canónica** —un puerto implementado a
través de una base abstracta— para que el arreglo no se pueda deshacer en
silencio. El arnés pasó de 86 sabotajes a 87.

### Lo que encontró un review, y por qué esta suite no

Ocho hallazgos, todos reproducidos antes de tocar nada. Los tres primeros
tienen la misma raíz: **escribí las cinco cláusulas del puerto y las rompí en
el mismo archivo.**

| Lo que la cláusula dice | Lo que el código hacía |
|---|---|
| el testigo nombra la invocación que de verdad se hizo | con alcance vacío nombraba un comando que nunca corrió |
| lo no cubierto va en `omitted` | devolvía **todos** los sujetos pedidos si la herramienta miró **uno** |
| `Termination` es un hecho, no una interpretación | lo reescribía a `interrumpida` cuando no sabía leer la salida |

El peor es el segundo, y el corpus lo agrava. **ADR-012:** *«la superficie
"cubierto" le pide al revisor que **no mire** algo. Eso solo es legítimo si el
paso realmente corrió sobre el alcance que declara.»* Con una ruta buena y una
inexistente, el testigo certificaba la que la herramienta había dicho que no
encontraba — es decir, le habría pedido a una persona que se salteara un
alcance que nadie miró. La cobertura ahora es por sujeto, y el arnés comprueba
cada uno antes de creerle a la herramienta.

Un sujeto omitido **no** vuelve rojo el paso: sale de «cubierto», que es donde
importa, y queda en `omitted` con su motivo. Si una omisión debe detener algo
es política de `orchestration` —*«orden, corte temprano y presupuesto son
política de `orchestration`, no del plugin»*, `docs/03` §6—, y ese paquete
todavía no existe.

Y había más, todos medidos:

- La lista de sujetos es del llamador y **se usaba después del `await`**:
  mutándola durante la corrida, el testigo nombraba una invocación sobre un
  alcance y declaraba cobertura sobre otro. Se copia y se congela al entrar.
- Un directorio sin permisos hacía que `run` **lanzara**, y el paso no devolvía
  testigo ninguno — que rompe la primera cláusula. No poder mirar es un dato.
- Al agotarse el presupuesto, el ejecutor devolvía **sin esperar** a que el
  proceso muriera. Ahora dispara y espera, con un tope.
- La decodificación toleraba bytes inválidos reemplazándolos, y eso contradice
  a `QuotedText`, que promete el texto «tal cual llegó». Ahora es estricta, y
  el costo queda declarado: una ruta con bytes que no son UTF-8 vuelve **no
  concluyente el paso entero**, no solo ese archivo.
- El error de una corriente **se tragaba**: una lectura rota producía una
  terminación «completa» con la salida cortada.
- `omitted` tenía `= const []`, así que una implementación que se olvidara del
  campo declaraba cobertura total sin haberlo afirmado. Es el agujero que el
  propio archivo describe para `Termination`, reabierto por la puerta de al
  lado. Ahora es obligatorio, y los motivos en blanco se rechazan.

**Por qué la suite de contrato no encontró nada de esto: yo elegí sus casos.**
Un solo sujeto, siempre válido, siempre existente. Es la misma lección que la
rebanada anterior ya había aprendido con los normalizadores y que no alcancé a
aplicar acá — un conjunto de casos que alguien enumera cubre los que ese
alguien pensó.

### Y dos meta-checks que también fallaban en verde

El del canario nuevo: **se podía borrar sin que nada fallara**. El arnés leía
`violaciones_extra` con un valor por defecto vacío, así que la ausencia del
canario se leía como «esta regla no tiene extras» — 86 sabotajes y exit 0,
contra un README que afirmaba que el arreglo no se podía deshacer en silencio.
Ahora el arnés declara qué violaciones **tiene** que encontrar en el registro.

El del árbol sintáctico: resolvía la herencia por **nombre simple** en un mapa
global. Dos clases homónimas en bibliotecas distintas se pisaban, y una
concreta podía heredar los ancestros de la otra. Resolverlo de verdad pide
identidad calificada; hasta entonces **falla ante el nombre repetido que
participa de una herencia que tiene que resolver** — y solo ese. Fallar ante
cualquier homónimo del repositorio le impondría a todo plugin futuro no repetir
un nombre que ya use otro, y esa es una restricción de diseño que un check no
tiene por qué imponer de contrabando.

### Y una segunda vuelta, porque los dos arreglos estaban a medias

Con las correcciones puestas, el review volvió a correr y encontró que **dos de
los arreglos cubrían el caso que yo les había puesto delante y nada más.**

**La cobertura del formateador seguía siendo agregada.** Arreglé «un sujeto que
el arnés no puede ver» y no toqué «la herramienta miró menos de lo que hay»:
con dos sujetos de un archivo cada uno y un resumen que decía `Formatted 1
file`, el testigo certificaba los dos. Tenía los dos números a la vista —el
arnés cuenta los archivos de cada sujeto, la herramienta informa cuántos
miró— y no los comparé. **La misma reconciliación que acababa de escribir un
nivel más abajo**, entre las líneas `Changed` y el `(N changed)` del resumen:
aplicada a los diagnósticos y no a la cobertura, que es donde decide el verde.

Ahora se reconcilia, sumando de vuelta los archivos que no parsean —la
herramienta los salta, así que no entran en su cuenta—. Y si no cierra no se
certifica **ningún** sujeto: el resumen es un total, no una lista, así que no
hay forma de saber a cuál le faltó.

Eso obligó a medir algo más: **la herramienta salta los componentes ocultos al
recorrer, pero procesa un camino oculto si se lo nombran explícitamente.** Sin
esa fidelidad la cuenta no cerraría nunca y todo saldría no concluyente — un
fallo ruidoso, pero igual de inservible. Hay una prueba contra la toolchain de
verdad que existe solo para eso: si mi forma de contar deja de coincidir con la
suya, se pone roja.

**Y el control de homónimas marcaba los nodos visitados, no el de arranque.**
El mapa de herencia devuelve la última declaración: una clase concreta con
homónima tomaba los ancestros de la otra desde el primer paso, y un puerto
huérfano quedaba tapado en verde. Cuando verifiqué ese arreglo usé una *base*
duplicada — que es exactamente el caso para el que lo había escrito.

La condición tampoco era la que puse. La primera versión fallaba ante cualquier
repetición; la segunda, ante ninguna en el origen. Ahí quedó una tercera —un
nombre repetido es ambiguo si sus declaraciones no coinciden en lo que
heredan— y **tampoco era la condición**, porque respondía la pregunta
equivocada.

### Tercera vuelta: la herencia describe relaciones, no identidad

Dos puertos pueden tener exactamente los mismos ancestros —ninguno— y seguir
siendo **contratos distintos**. Con un implementador de uno solo, el otro
quedaba huérfano y el check daba verde.

El error de fondo era usar un criterio para dos preguntas que no son la misma:

| El nombre se usa para… | ¿Cuándo es ambiguo? |
|---|---|
| **resolver** herencia (`superDe`) | solo si las declaraciones heredan cosas distintas |
| **identificar** una clase en un registro | **siempre**: la identidad no se comparte |

Y `arquitectura.json` direcciona las clases de `core` por su nombre en **tres**
registros: cuáles son opacas, cuáles son puertos sin implementación, y cuáles
serializan. El review encontró el segundo; **el mismo agujero estaba en el
primero** — una clase declarada opaca le daba vía libre a su homónima, que ni
serializaba ni estaba declarada.

Así que la regla no es sobre puertos: **dentro de `core`, cualquier nombre
repetido es fatal**, tengan los ancestros que tengan. Afuera de `core` el nombre
solo se usa para resolver herencia, y ahí el criterio estructural sigue siendo
el correcto — imponerle a todo plugin futuro no repetir un nombre sería una
restricción de diseño que un check no tiene por qué imponer.

Cuarta violación canónica registrada: **89 sabotajes**.

### Dónde el review se apoyó en un invariante que no dice eso

Justificaba la decodificación estricta con **INV-6**. INV-6 dice *«todo texto
de fuente externa se encapsula»*: es contra la inyección —`ASI01`, `docs/06`—
y no habla de fidelidad de bytes. La exigencia de fidelidad la puso
`QuotedText` en la fase 1, y es la que sostiene el cambio. La conclusión no se
mueve; el fundamento sí, y citar mal un invariante es la clase de cosa que este
repositorio no se puede permitir.

También queda **un hueco que este cambio no introdujo y no cierra**: el esquema
de traza no tiene número de versión, ni `Trace` ni `Witness`. `docs/09` habla de
«la primera versión del esquema de traza» y el tipo no la lleva. Hoy no hay
trazas persistidas, así que exigir `omitted` no rompe nada real; cuando las
haya, esto va a hacer falta antes.

---

## `shipflow verify`

La primera rebanada **vertical**: atraviesa el CLI, la orquestación, la cascada
y el protocolo de salida. No agrega un puerto — usa los que hay.

Se cortó así a propósito. La fase 2 promete `verify` + `ship`, y `ship` necesita
el agente, los tickets y `vcs`: más de la mitad de los puertos que faltan. `verify`
no necesita ninguno, y el plan ya había nombrado el riesgo de quedarse del lado
cómodo: *"la cascada es lo que sabemos hacer; es donde el proyecto puede
quedarse"*.

### El código de salida se deriva

Estaba escrito en prosa como una tabla de precedencia. Una tabla no impide que
alguien devuelva `1` desde un `catch`:

```
errorInterno  >  noConcluyente  >  rojo  >  verde
     70               2             1        0
```

Ahora sale de `EstadoDeCorrida` y de ningún otro lado, con un `switch`
exhaustivo: **un estado nuevo no compila hasta que alguien decida su código.**

Que lo no concluyente gane sobre el rojo no es un descuido. No se puede afirmar
que el cambio falló cuando parte de la verificación no se ejecutó: el rojo
invita a arreglar y volver a correr, y volver a correr puede seguir sin observar
lo que faltó. **Los diagnósticos bloqueantes se reportan igual**; lo que cambia
es qué se afirma del conjunto.

### El corolario 2 quedó instalado

ADR-011 pide un *"meta-check de cobertura: reglas ejecutadas contra reglas
registradas; la diferencia se reporta"*. Estaba escrito desde el 25/08 y nunca
se había instalado, porque no había nada que registrar.

La cascada es un **registro ordenado**, y el resultado lleva `registrados`,
`ejecutados` y `sinEjecutar`. Un hueco vuelve la corrida no concluyente. Es
`docs/03` §6 con nombre y apellido: *"si el registro dice cinco, dos pasos
pueden no correr y nadie se entera"*.

Con dos consecuencias que no estaban en el plan:

- **Una cascada sin pasos no es verde.** Es el falso verde más barato de todos:
  no miró nada y nadie se lo preguntó.
- **El id de un paso es una clave, no una etiqueta.** Dos pasos con el mismo id
  dejarían la cuenta ciega —uno taparía al otro— así que el registro los
  rechaza al construirse. Es la misma lección que el motor de checks acababa de
  aprender con las clases homónimas de `core`.

### Un paso que se rompe no es un veredicto

Si un paso lanza, la corrida sale con `70` y **los demás corren igual**. Cortar
ahí dejaría a los siguientes sin ejecutar *y* sin explicación, y las dos cosas
se confundirían en la cuenta.

Y hay un caso que no se me habría ocurrido buscar hasta escribir la cuenta: un
paso que devuelve el resultado de **otro** paso. Su id no coincidiría con el
registrado y la cuenta diría que corrió algo que no corrió. Se rechaza.

### El protocolo, y lo que promete

Con `--json`, todo va a la salida estándar como JSON Lines: cero o más eventos
y **exactamente un resultado, último**. Esa promesa no la comprobaba nadie, así
que la impresora lleva la cuenta y **lanza** si alguien emite un segundo.

Cada envelope lleva su versión de esquema, por la misma razón que el
normalizador exige la del analizador: leer un formato nuevo con reglas viejas
devuelve menos de lo que hay, y en silencio.

### Y por fin se ve un testigo

`--verbose` imprime lo que estaba construido y nadie había leído nunca:

```
  FALLA     FormatCheck
            invocación: dart format --output=none lib
            terminación: completa · código 0
            cubrió: lib
  bloquea lib/feo.dart · formato/sin-formatear · Changed lib/feo.dart
  ok        StaticAnalysis
            omitió: La herramienta no informa qué archivos leyó: sobre un
            alcance vacío devuelve lo mismo que sobre uno limpio…
```

Esa última línea aparece en **cada corrida verde** de `StaticAnalysis`, y está
bien que aparezca: es el paso diciendo, cada vez, qué no puede afirmar.

### Lo que ya se puede exigir de la superficie

Cinco de los sabotajes de superficie del documento de CLI dejaron de ser prosa:
una bandera desconocida no se ignora, `--quiet --verbose` sale con `5`, una
invocación sin acción **no sale con `0`** —no cumplió ningún contrato—, con
`--json` no se cuela texto suelto, y hay exactamente un resultado.

### Y lo que encontró un review sobre la primera versión

Siete bloqueantes, todos reproducidos. La mayoría son la misma forma: **el
comando cumplía el contrato en el camino feliz y lo rompía en los bordes.**

| Estaba mal | Ahora |
|---|---|
| `--json verify` leía `--json` como un comando | las banderas globales valen antes o después |
| un error de uso con `--json` imprimía texto humano | también sale como envelope |
| `verify --help` era un bucle: código `5`, y el error recomendaba `--help` | se reconoce y sale con `0` |
| `--quiet` callaba también los diagnósticos | calla el progreso, **no** los hallazgos |
| una excepción fuera de la cascada escapaba del comando | nada sale sin resultado, y sin `70` |
| «uno solo, y último» no cubría **cero** ni «un evento después» | las dos rompen ahora |
| la cascada vacía mandaba a mirar testigos que no existen | dice que no hay verificadores y señala el composition root |

Los dos primeros y el tercero son el mismo error de fondo: **probé el protocolo
solo donde el protocolo se cumple.** Con `--json` había un test de una corrida
normal y ninguno de una corrida que falla antes de empezar.

El más caro para el futuro es otro: **`cascadaPorDefecto` no tenía ninguna
prueba.** Todas inyectaban la cascada, así que los dos pasos podían borrarse,
invertirse o reemplazarse y todo seguía verde — la composición real, que es lo
único que un usuario ejecuta, era exactamente lo que nadie miraba. Ahora hay una
prueba que corre el binario sobre un proyecto de verdad y exige que
`FormatCheck` y `StaticAnalysis` estén registrados, **en ese orden**, y que
encuentren el archivo sin formatear.

Y dos observaciones que también eran reales: `exit()` cortaba el proceso sin
dejar drenar la salida —una corrida `--json` larga se truncaba en silencio— y
`Cascada.correr` no congelaba el alcance, así que el llamador podía cambiarlo
entre paso y paso.

### Tercera vuelta: la frontera estaba duplicada

El review siguiente encontró que el arreglo del protocolo **había quedado
adentro de `verify`**, y el ruteo y el `main` tenían salidas propias: con
`--json`, tres invocaciones distintas —sin comando, con un comando que no
existe, y `--help`— imprimían texto suelto. Cada una habría que haberla
arreglado por separado.

Ahora hay **una sola frontera**. Si el único camino de salida construye
envelopes, ningún camino puede no construirlos.

| Y además | |
|---|---|
| el progreso se emitía **después** de que todo terminara | sale mientras la corrida ocurre, con la hora del paso |
| `--quiet` mostraba cualquier diagnóstico | «solo errores» es lo que **bloquea** |
| `Severity.silencia` se imprimía | no se muestra nunca, ni sin banderas |
| la corriente de error estaba declarada y **sin usar** | hay una última salida que no serializa nada |
| el rescate en modo humano no decía qué hacer | lo dice, como el envelope |

Lo del progreso es el más de fondo: la cascada devolvía todo junto y el CLI
recorría los resultados al final. No había nada que mirar mientras una
herramienta tardaba, y la marca de tiempo era la de armar el reporte. Ahora la
cascada avisa cuándo empieza y cuándo termina cada paso, que es lo que la
superficie pide de toda operación de más de tres segundos.

Y el de `Severity.silencia` no lo trajo el review: apareció al mirar por qué el
filtro estaba en el tipo del evento y no en la severidad. `core` dice de esa
severidad «registra para telemetría y **no se muestra**», y se estaba
mostrando.

### Cuarta vuelta: comprobar que una bandera está no es interpretarla

La frontera nueva usaba `contains` para algunas banderas y resolvía la ayuda
sin haber mirado el resto. Con eso, `shipflow --inventada --help` salía con
`0`; `--quiet --verbose --help` también, cuando SC-17 exige `5`; y
`--quiet --help` no mostraba la ayuda que se le había pedido.

Ahora hay **un intérprete, y corre antes que nada**. El orden de sus
comprobaciones es parte del contrato: primero la contradicción entre banderas
—no hay forma de honrar las dos, y elegir una es adivinar—, después las que
nadie puede aceptar, y recién ahí la ayuda, que **gana sobre `--quiet`**:
callar lo que alguien pidió explícitamente no es silencio, es no hacerlo.

Una bandera desconocida **con** comando no se rechaza en la frontera: se le
pasa al subcomando. Hoy `verify` no tiene banderas propias y la rechaza, pero
rechazarla arriba cerraría la puerta a las que el documento ya declara para
otros comandos —`--dry-run`, `--budget`—.

Y una cosa más que el review encontró: `alTerminar` estaba **dentro** del
`try` que clasifica fallos del paso, así que una excepción del observador de
progreso se le atribuía al verificador. El mismo paso quedaba registrado como
ejecutado *y* como fallido, y el reporte culpaba a quien había hecho su
trabajo.

### Una divergencia declarada con el documento de superficie

**`verdict` va nulo cuando la invocación no alcanzó una operación de dominio.**

La superficie enumera `ok · failed · inconclusive · stopped · internalError`, y
ninguno describe «escribiste mal el comando». El código de salida `5` no es
`failed` —la verificación no falló, no corrió— ni `inconclusive`, que es un
verificador que intentó y no pudo. El `4` va a tener el mismo problema cuando
exista `doctor`.

**No se inventa un veredicto todavía, y es deliberado:** nadie lee ese campo.
El único consumidor del `--json` hoy es esta suite. Decidir la semántica de un
campo para un lector que no existe es la misma forma que este proyecto persigue
—un invariante escrito y sin instalar—, del revés.

Se decide cuando haya un consumidor real que necesite hacer `switch` sobre
`verdict`. Hasta entonces queda acá, en el tipo, y en las pruebas: los tres
dicen lo mismo.

---

## `vcs`: el corte que ADR-014 ya había decidido

`vcs` conoce `git` y nada más. Ni el lenguaje del proyecto, ni el CLI agéntico,
ni la forja.

### Dos puertos, no uno

`ChangeSink` era un solo puerto con `apply(Plan)`. Ahora son dos:

| | Qué sabe | Qué necesita |
|---|---|---|
| `ChangeSink` | `git`: rama y commits | nada, funciona sin red |
| `PullRequestSink` | la forja | credencial, un proveedor |

**Lo decidió ADR-014 sin nombrarlo.** Su invariante ejecutable exige que tras
una detención por presupuesto *"la rama y todos los artefactos existen, y **no
hay PR abierto**"*. Ese estado tiene que ser alcanzable, estable e
inspeccionable — y un puerto cuya operación es atómica no tiene un medio.
Sería una bandera adentro fingiendo que no lo es.

El criterio no es cuántas responsabilidades tiene un puerto: es **cuántos
estados intermedios el diseño exige que sean observables**. Es el mismo
razonamiento por el que `VerificationOutcome` lleva testigo.

### Y `apply` dejó de recibir un `Plan`

`Plan.workItemId` es obligatorio, y el caso «solo PR» de `docs/04` entra **sin
`WorkItem`**. El puerto no podía expresar el caso que la fase promete soportar.

Ahora recibe una `PullRequestSlice`, que lleva exactamente lo que hace falta
para commitear: qué archivos y **por qué** — su `intent`, que es lo que ADR-014
llama intención, y que termina siendo el mensaje del commit.

### La cláusula que necesitó una medición

**`apply` commitea exactamente los archivos de la rebanada. Ni uno más.**

Barrer lo que hubiera suelto en el árbol metería en el PR cambios que nadie
planeó, y —por ADR-012— el artefacto de revisión los declararía **cubiertos**,
que es pedirle a una persona que no los mire.

Se midió cómo se hace: `git commit --message … -- <rutas>` ignora el índice.
Con un archivo dejado en *staging* de antes, queda afuera. Sin las rutas
explícitas, entra.

**Y la medición cubrió el caso que tenía delante.** Un review la rompió por
otros dos lados, los dos reproducidos contra `git` de verdad antes de tocar
nada:

| Lo que decía la rebanada | Lo que commiteaba `git` |
|---|---|
| `files: ['*.txt']` | `a.txt` **y** `b.txt` |
| `files: [':(glob)*.txt']` | `a.txt` **y** `b.txt` |
| `files: ['dir']` | `dir/x.txt` **y** `dir/y.txt` |
| `files: ['.']` | todo |

`--` evita que una ruta se lea como una **opción**. No hace nada contra que se
lea como un **patrón**, que es otra cosa. La cláusula decía «exactamente», y el
comando decía «lo que estos pathspecs abarquen».

Y el mismo error, otra vez, en la rama:

```
$ git tag release && useBranch('release')
GitFallo(git switch release → 128):
fatal: a branch is expected, got tag 'release'
```

`rev-parse --verify` resuelve **cualquier revisión**. Con una etiqueta
homónima el adapter creía que la rama ya existía, y una reanudación legítima
—lo que ADR-014 exige de `--resume`— quedaba rota por un nombre que ni
siquiera era una rama.

**La raíz es una sola: una cadena del dominio no es un argumento de `git`.** El
adapter no fallaba por ignorar `git`, sino por confiar en que la semántica de
`git` coincidía con la del dominio. «Una ruta» no es un *pathspec* y «un
nombre» no es una *revisión*.

Lo instalado va en dos capas, y la segunda es la que importa:

| | Qué hace | Qué cubre |
|---|---|---|
| **Validar** | `--literal-pathspecs`, forma canónica de ruta, se rechaza un directorio, y un borrado tiene que ser el de **un** archivo rastreado; el nombre lo valida `git check-ref-format` y la rama se busca en `refs/heads/` | los casos que alguien enumeró, con un «qué hacer» en cada rechazo |
| **Preguntar** | el índice aislado **es** el contenido del commit: `git diff --cached --name-only -z` sobre él dice qué va a entrar, y se compara contra lo declarado en **las dos direcciones** antes de commitear | **la cláusula**, incluido el caso que nadie enumeró |

### Y la segunda capa estaba del lado equivocado del commit

La primera versión de esto comprobaba el commit **ya hecho**. Un segundo review
lo cobró con el argumento correcto: *una postcondición solo garantiza integridad
si puede impedir o revertir lo que valida*. La excepción decía la verdad y la
rama ya tenía el commit indebido. Un invariante que solo se puede reportar no es
un invariante, es una crónica.

Y traía dos fallos propios, los dos reproducidos:

| | Qué pasaba |
|---|---|
| `á.txt` | `git show --name-only` **cita** lo que no es ASCII: devolvía `"\303\241.txt"` y un archivo válido daba incumplimiento falso |
| `files: ['dir']` con `dir/` ya borrado | `ls-files --error-unmatch` coincide por **prefijo**: el borrado del directorio pasaba como si fuera un archivo |

La primera respuesta a esto fue `git commit --dry-run --porcelain`, que dice
qué entraría sin tocar nada. **Duró hasta el review siguiente**, que mostró que
seguían siendo dos consultas sobre dos objetos: `commit -- <rutas>` vuelve a
leer el árbol. Lo que quedó instalado —el índice aislado— está más abajo.

**Y queda un hueco, declarado:** entre la inspección y el commit nada más puede
tocar el árbol. Eso es un lock de concurrencia que **no es `A-5`**, y un review
lo cobró: `A-5` es el lock sobre `.sdlc/` para que dos corridas no se pisen la
configuración de ganchos, no un lock del árbol ni del índice. Queda como
decisión propia y abierta.

### «Exactamente» tenía una sola dirección

Se comprobaba que no entrara nada de más. Una rebanada que declaraba
`['a.txt', 'b.txt']` con `b.txt` sin cambios commiteaba `a.txt` y daba verde: un
plan que dijo que iba a tocar algo y no lo tocó. Ahora las dos direcciones, con
dos desenlaces distintos — **de más** es la cláusula rota y **de menos** es la
rebanada mal armada.

Se prueba con envoltorios que le sacan a `git` una salvaguarda —el que le hace
contestar de más a la consulta, el que desprende `HEAD` en el `switch`, el que
rompe el `reset` final— para que la promesa tenga cómo romperse; un control que
nunca se vio en rojo no está instalado. Y cada caso comprueba también que
**`HEAD` no se movió**.

Y un **control negativo**: un archivo que de verdad se llama `*.txt` sí se
commitea, y uno con acento o con espacios también. La corrección no podía
volverse «prohibido lo que parezca un patrón» — y ese caso, antes, era
imposible.

**Veinte mutaciones, ninguna sobrevivió** — y dos de ellas encontraron lo que 38
tests verdes no vieron: la guardia de ruta absoluta se podía borrar entera
porque el rechazo genérico la tapaba, y el filtro de archivos no rastreados era
código muerto, porque `--untracked-files=no` ya los quitaba. Una redundancia que
no puede fallar se lee como defensa y no defiende nada.

### Y rechazar tampoco puede tocar lo que preparó otro

El índice es del usuario. Una rebanada rechazada no hizo nada, así que no puede
haber cambiado nada — y la primera limpieza usaba `git reset -- <rutas>`, que
**no restaura el índice anterior sino `HEAD`**. Medido con tres versiones
distintas, porque con dos la tabla se leía mal y un review lo cobró:

| `a.txt` en… | Antes | Tras `git reset -- a.txt` |
|---|---|---|
| `HEAD` | `BASE` | `BASE` |
| **el índice** | `STAGED` | **`BASE`** — la versión preparada se perdió |
| el árbol | `ARBOL` | `ARBOL` — intacto |

Un tercer review lo encontró, y es la misma confusión de todo este archivo —un
comando que *se parece* a lo que quiero no es lo que quiero— cometida esta vez
**en el código que existía para reparar**. Y traía dos agujeros más: la limpieza
corría solo en la rama del rechazo por contenido, así que un `git add` que
fallaba a medias dejaba rastro —está medido que `git add -- a.txt ignorado.txt`
sale con 1 y deja `a.txt` preparado igual—, y el `reset` usaba la llamada que
**no lanza** por código distinto de cero: un reparador que no podía fallar.

### Y hubo una foto del índice, que también se fue

Entre medio existió una tercera capa: fotografiar el índice del usuario antes de
tocarlo y reponerlo ante cualquier fallo. La pidió un review, se construyó, se
probó y se mutó — y encontró de paso que reponerlo desde `ls-files --stage`
pierde `intent-to-add`, porque el índice tiene más estado del que esa lectura
muestra.

**Se borró entera al llegar el índice aislado**, que no toca el índice del
usuario y deja la reposición sin nada que reparar. Queda anotado porque el
recorrido dice algo: la pregunta *«¿cómo reparo el daño?»* tuvo tres respuestas
cada vez mejores, y la buena era *«¿por qué hay daño?»*.

### Dos pruebas que anunciaban un escenario y ejercían otro

El mismo review encontró que la prueba del «SHA homónimo» usaba `rama-<sha>` —un
nombre que no es homónimo de nada y jamás se habría resuelto como el commit— y
que la del «salto de línea» solo creaba un archivo con espacios. **Un caso que se
anuncia y no se ejerce es peor que uno que falta: se lee como cubierto.** Es
`cubierto` de ADR-012 aplicado a la suite en vez de al PR.

### Lo que encontró al construirse: dos invariantes en un solo control

`vcs` necesita `dart:io` para correr `git`, y la regla de cadenas lo rechazaba.
No era un falso positivo: **esa regla era lo único que impedía que `core`
hiciera entrada y salida directa**, porque `dart:io` contiene la cadena `dart`.

Protección real, pero de rebote. `nucleo-sin-externas` mira las dependencias
que resuelve pub, y una biblioteca del SDK no es una dependencia: `core` podía
abrir archivos sin declarar nada.

No se podía habilitar una sin perder la otra, así que se separaron.
**`nucleo-sin-entrada-salida`** es la undécima regla, con su violación canónica
y su caso ciego. **El arnés aplica 103 sabotajes.**

---

## El falso rojo simétrico

El arnés entero está construido contra un error de dirección: **un verde que
nadie miró**. Este es el mismo error en la otra dirección, y estaba en
producción.

```
$ shipflow verify lib          # lib solo tiene markdown

verify: inconclusive — 2 de 2 pasos ejecutados, 0 diagnóstico(s).
  → Algún paso no pudo observar su alcance.
```

**Falso.** Los dos pasos observaron. El testigo lo decía:

```
terminación: completa · código 0     ← la herramienta corrió
cubrió: (nada)
omitió: lib: no contiene ningún archivo de fuente
```

La herramienta corrió, terminó completa con código 0, y no tenía nada suyo que
mirar. Eso no es «no pude observar»: es **no había nada que observar**, y son
cosas distintas.

### El techo del contrato

El hecho ya se estaba diciendo — **en prosa**, dentro de `omitted`, donde nadie
aguas arriba puede leerlo. `docs/03` §2 le pone nombre exacto a eso:

> *«Un adapter que empieza a **codificar información en cadenas de texto** está
> chocando contra el techo del contrato. Se reporta como hallazgo, no se
> absorbe en silencio.»*

El techo era un campo que no existía. `Witness` gana `ownSubjects`: cuántos
elementos del alcance eran de la incumbencia del paso. **`null` y cero son
distintos** — uno dice «no lo puedo contar» y el otro «no había nada mío» — y
ya hay un paso que no puede contar, porque su herramienta no informa qué leyó.

### Quién decide que eso es un salto

**No el paso.** ADR-011 corolario 4: *«ningún verificador juzga su propia
cobertura; un oráculo autorreportado no es un oráculo»*. Un salto es una
exención de ser mirado, que es la superficie `cubierto` de ADR-012 vista desde
el otro lado.

El paso **declara un número contable sobre su entrada**, que cualquiera puede
falsar contando. La cascada lo lee y clasifica: cero de los suyos, con la
herramienta terminada, es un paso saltado con su motivo.

| | Qué significa | Cómo lo cuenta el meta-check |
|---|---|---|
| ejecutado | corrió y produjo veredicto | numerador |
| **saltado** | no corrió: el observador de alcance ya lo excluyó antes de invocar nada | contado aparte, **sin discrepancia** |
| sin ejecutar | no corrió y nadie lo explicó | discrepancia |
| fallo interno | se rompió | error del arnés |

Es el trazado del corpus, ahora ejecutable: *«registrados: 7 · ejecutados: 6 ·
saltados: 1 con motivo → sin discrepancia»*.

**Nota, para quien lea esto después de «El desenlace se cierra» más abajo:**
lo de arriba —«el paso declara un número contable», «corrió y no tenía nada
suyo»— describe el mecanismo tal como estaba en ese momento. Ya no es así: el
salto lo decide el `ScopeObserver`, en una sola observación por corrida, antes
de invocar cualquier herramienta, y un paso saltado **no corre**. El «quién
decide» de este título seguía siendo correcto un nivel más arriba —no el
paso—, pero el reemplazo removió también la herramienta terminando en falso.

### Y el falso verde que se abría al cerrarlo

Si **todos** los pasos se saltan, la corrida no verificó nada. Cada salto por
separado es legítimo; todos juntos son una cascada que no miró — el mismo falso
verde que la cascada vacía ya tenía prohibido, entrando por la otra puerta.

```
verify: inconclusive — 0 de 2 pasos ejecutados, 2 saltado(s) con motivo,
                       0 diagnóstico(s).
  → Ningún paso tuvo nada que hacer sobre este alcance: FormatCheck,
    StaticAnalysis. No es un fallo, pero tampoco se verificó nada.
```

### Y el falso verde llegó igual

Una mutación avisó a tiempo —cambiar `ownSubjects == 0` por `!= null`
sobrevivía, porque ningún test tenía un paso con archivos propios— y aun así
**un review encontró el falso verde por otra combinación**:

```
un paso verde  +  un paso con diagnóstico BLOQUEANTE y cero archivos propios
→ estado: verde · diagnósticos: 0
```

El paso con el hallazgo se clasificaba como saltado, su resultado nunca entraba
en `resultados`, y **el diagnóstico desaparecía**. Un salto es la ausencia de
trabajo, no la desaparición de un hallazgo.

Y por la misma puerta entraban otras dos: una ruta **inexistente** salía como
«no tuvo nada que hacer» —el arnés no pudo mirar, no es que no había nada— y un
salto podía no decir **por qué**, cuando el corolario 1 de ADR-011 prohíbe el
salto silencioso y este README lo prometía en prosa.

### La causa era una sola, y la nombró el review

> *«El dato `ownSubjects` intenta representar aplicabilidad, observabilidad y
> cantidad con un solo número. Mientras esas tres dimensiones no se distingan,
> cada corrección local puede abrir un falso verde por otra combinación.»*

Corregir los tres síntomas por separado habría dejado el cuarto. El alcance
distingue ahora **si se lo pudo mirar entero**, y el conteo es `null` cuando no:
una ruta que no existe o que no se deja leer no aporta un cero, aporta un
desconocido. Los caminos anómalos —código de salida que no se entiende, salida
ilegible— también declaran `null`: no son «no tenía nada que hacer», son «no sé».

Y el clasificador exige tres cosas más: **ningún diagnóstico**, terminación
completa, y **al menos un motivo**. El tipo `PasoSaltado` rechaza el salto mudo
en el constructor, como `Witness` rechaza un motivo en blanco.

### El testigo salía de dos fotografías del árbol

`ownSubjects` se calculaba al empezar y `cobertura` volvía a separar el alcance
**después del `await`**. Con un ejecutor que crea un archivo durante la espera,
el mismo testigo afirmaba «cero elementos propios» y «cubrí lib» a la vez.

Ahora hay una foto y **viaja**: `cobertura` recibe el `Alcance` ya separado y no
tiene con qué volver a mirar. La propiedad la sostiene la firma, no un
comentario — y la mutación que reintroduce el segundo `separar` muere.

### Y todavía había cuatro combinaciones más

Un segundo review sobre la misma rebanada encontró que la corrección abría el
falso verde por otras puertas. Las cuatro reproducidas:

| | Qué pasaba |
|---|---|
| `verify README.md` | el sujeto descartado **llegaba igual a la herramienta**: `separar` lo clasificaba y la invocación se armaba con los pedidos enteros. Cinco diagnósticos sobre un markdown |
| alcance con una parte inobservable | el plugin calculaba bien el «no sé» y **la cascada nunca lo consumía**: con otro paso en verde, la corrida salía verde sobre un alcance parcialmente no observado |
| un testigo que cubrió algo **y** dice cero propios | dos afirmaciones incompatibles, clasificado como salto igual |
| la prosa de `PasoSaltado` | afirmaba que la herramienta corrió, y el clasificador no lo comprobaba |

La primera es la más vieja y la que más pega: afecta a cualquier cambio normal
que mezcle código y documentación. Ahora la herramienta recibe **solo los
sujetos utilizables**, y lo descartado sigue en `omitted` con su motivo — sale
de «cubierto», que es donde importa, no del reporte.

La segunda es la política que `docs/03` §6 dejaba explícitamente acá: *«si una
omisión debe detener algo es política de `orchestration`»*. Está tomada: un
alcance que no se pudo observar entero **no da verde**.

Y la cuarta se resolvió al revés de lo esperable — **no** agregando la
comprobación, sino corrigiendo la prosa: cuando no queda ningún sujeto
utilizable no hay nada que invocar, y llamar a la herramienta sin rutas la haría
mirar el directorio entero. Un salto no afirma que algo corrió: afirma que **la
ausencia de trabajo quedó establecida**.

Un caso ciego cambió de mecanismo: la ruta inexistente la delataba el código 64
del analizador, y ahora la delata el arnés antes de invocar. **Es más fuerte, no
menos** — deja de depender de que una herramienta ajena se moleste en avisar — y
el test comprueba la propiedad en vez del mecanismo.

### Y al final la corrección no era otra guardia: era un tipo

Un tercer review encontró que **la clasificación correcta dependía de un hecho
falso**. Cuando no quedaba ningún sujeto utilizable, el paso devolvía un testigo
con `Termination.completa` y código 0 — que significa literalmente *«la
herramienta corrió y produjo un resultado»*— y la cascada **exigía ese valor**
para aceptar el salto.

Su diagnóstico nombra la raíz de las tres rondas:

> *«El sistema necesita un desenlace de paso más rico que `VerificationOutcome`;
> intentar representar ejecución, inaplicabilidad y observabilidad con los
> mismos campos está trasladando contradicciones hacia el CLI y la
> documentación.»*

Tenía razón, y explica por qué cada corrección abría una combinación nueva: el
clasificador reconstruía desde cuatro campos —cero propios, nada cubierto,
terminación completa, algún motivo— un hecho que el tipo no sabía expresar.

`VerificationOutcome` gana `notApplicable`, **excluyente con `witness`**: o hubo
invocación y hay testigo, o no la hubo y hay motivo. Las cuatro condiciones
colapsan en una distinción de tipo más una sola guardia — *un salto es la
ausencia de trabajo, no la desaparición de un hallazgo*.

**Y el `started` que nunca cerraba.** Solo se avisaba de los pasos con
resultado: un salto y un fallo interno dejaban su evento de inicio abierto para
siempre. Ahora hay un desenlace por paso —ejecutado, saltado, roto— y el
analizador **prueba** que las tres ramas lo asignan: la garantía la sostiene el
compilador, no un comentario.

```
$ shipflow verify README.md --verbose
  SALTADO   FormatCheck
            motivo: README.md: no es un archivo de fuente de este stack
```

**Y el meta-check del presupuesto tenía su propio falso verde**: contaba
constructores y multiplicaba, sin leer qué se les pasa. Cambiar un solo paso a
`presupuesto * 2` lo dejaba en verde. Al arreglarlo, el patrón nuevo contó
**cinco** pasos donde hay dos —el `switch` que imprime los desenlaces tiene
`PasoEjecutado(` en la misma indentación— y después cortaba en el primer
espacio, así que `presupuesto * 2` se leía como `presupuesto`. Dos formas de
mirar mal antes de mirar bien, las dos encontradas midiendo.

Veintiuna mutaciones sobre el clasificador, la separación del alcance y los
desenlaces. Ninguna sobrevive.

### Lo que NO instala, y por qué

**El corte temprano.** `D-099` lo congeló: aparece dos veces en el corpus y
ninguna dice **cuándo** corta. Esta rebanada instala su precondición —un paso
que no ejecuta y no es una falla— y nada más.

**La aplicabilidad general.** El corpus tiene un solo puerto que responde «¿le
toca a este paso?», `CodegenTrigger`, y es específico. Un mecanismo general
sería inventar el criterio que falta.

---

## El desenlace se cierra, y la aplicabilidad sale del verificador

Todo lo anterior —`ownSubjects`, `PasoSaltado`, `NotApplicable` excluyente con
`witness`— quedó retirado. No porque estuviera mal escrito: porque seguía
pidiéndole al **verificador** que corriera su herramienta, contara lo suyo y se
declarara sin trabajo. ADR-011 corolario 4 ya lo nombraba —*«ningún verificador
juzga su propia cobertura»*— y esta rebanada lo instala como tipo, no como
disciplina.

### Dos niveles, y el segundo es un subconjunto propio del primero

[`StepOutcome`](packages/core/lib/src/desenlace.dart) es todo lo que la cascada
puede producir: `Executed`, `Aborted`, `Skipped`, `Unobservable`, `Broken`.
[`VerificationOutcome`](packages/core/lib/src/desenlace.dart) —lo único que un
`Verifier.run` puede devolver— es solo las dos primeras. El salto, lo no
observable y lo roto **no cuelgan de ahí**: los decide quien compone la
corrida.

```dart
static VerificationOutcome fromJson(Map<String, Object?> json) {
  final outcome = StepOutcome.fromJson(json);
  if (outcome is VerificationOutcome) return outcome;
  throw ArgumentError.value(outcome.kind.name, 'kind',
      'Un Verifier no puede devolver esto: el salto, lo no observable y lo '
      'roto los decide quien compone la corrida, no un verificador');
}
```

No es una convención: es un `sealed` con jerarquía de dos niveles, y un
`Verifier` que intentara colar un `Skipped` como si fuera su resultado no
compila contra la firma, y si llegara por JSON, `fromJson` lo rechaza. El
canario que lo prueba es literal: **`C1 · un verificador no puede declarar que
un archivo no es suyo`**, en `packages/cli/test/verify_test.dart`.

### El alcance se mira una vez, y devuelve hechos — no decisiones

El puerto nuevo es [`ScopeObserver`](packages/core/lib/src/puertos.dart):
`Future<ScopeObservation> observe(List<String> requested)`. Su contrato tiene
cuatro cláusulas, y la que cierra la clase entera de bug que motivó todo esto
es la cuarta: **se llama UNA vez por corrida**. Antes cada paso separaba su
propio alcance, con su propio `await` de por medio; dos lecturas del árbol
podían diferir y dos pasos terminaban verificando alcances distintos que el
reporte declaraba iguales.

`ScopeObservation` particiona lo pedido en `ObservedSubject` (con `ofStack` y,
si es ajeno, su motivo) y `UnobservedSubject` (lo que no se pudo mirar, con su
causa) — **hechos por sujeto**, no un salto ya decidido. La orquestación
(`Cascada`) es quien los lee y produce `Skipped` o `Unobservable`; un
`Verifier` ni siquiera recibe los sujetos ajenos en su lista de `subjects`, así
que estructuralmente no tiene sobre qué declararse incompetente.

### El libro de obligaciones es por par paso-sujeto, no por unión

`ResultadoDeCascada.obligacionesSinSaldar` recorre cada paso que ejecutó y,
para cada sujeto de **su** `expectedScope`, exige que el testigo lo cubra o
una omisión lo nombre. La versión anterior —«¿algún paso cubrió este
sujeto?»— es existencial, y una existencial no repara nada: que otro paso
haya cubierto un sujeto no dice qué hizo este con él.

### Tres falsos verdes que las pruebas dirigidas no vieron

Ninguno lo encontró una prueba escrita para ese caso. Los tres se cerraron
**en el constructor de `ResultadoDeCascada`**, no con una guardia suelta en el
sitio de uso:

| Falso verde | Lo que lo cerró |
|---|---|
| Un paso cubre la mitad de su alcance y no explica el resto; otro paso cubrió todo | El libro por par paso-sujeto (arriba). Canario `C3 · cubrir la mitad sin explicar el resto no da verde` |
| Un `expectedScope` fabricado —más chico que lo utilizable— vacía el libro sin que nadie lo note | El constructor exige `expectedScope == alcance.usable()`, en las dos direcciones: ni le faltan sujetos utilizables ni le sobran inventados |
| Un `Skipped`/`Unobservable` nombra un sujeto que la observación de esa corrida no respalda; `causas` queda vacía y deriva verde | El constructor cruza cada desenlace contra `alcance.observed`/`unobserved` y **lanza** si no coincide. El test lo dice en el nombre: `un Skipped no puede declarar ajeno a un sujeto que la observación no dio como tal — antes daba VERDE` |

Los tres viven en `packages/orchestration/test/cascada_test.dart`, en los
grupos «el libro de obligaciones», «el invariante del alcance esperado» y «el
desenlace no puede contradecir a la observación».

### Una causa solo se dispara si existe la evidencia que va a nombrar

`nadaEjecutado` enumera los sujetos ajenos al stack en su texto, y disparaba
con solo `ejecutados.isEmpty` — sin mirar si había alguno que nombrar. Con un
alcance sano donde todos los pasos abortan, `ejecutados` también queda vacío,
y la causa citaba una lista vacía: el mismo error original, con otra
combinación, y lo encontró un review después de que reordenar la lista de
causas ya había tapado la anterior sin cerrar la clase de bug.

La regla que queda escrita para la próxima causa que se agregue: **se agrega
solo si existe el contenido que su texto va a citar**, no una posición en la
lista. Es la misma disciplina que `docs/03` exige de la acción siguiente sobre
un documento —no nombrar lo que no está ahí— movida un nivel adentro, a la
causa que la habilita.

### Y la propia cobertura de las propiedades falló dos veces por el mismo mecanismo

Vale contarlo con la misma honestidad que el resto de este archivo: las
propiedades exhaustivas de `Cascada` (`propiedades_test.dart`) no llegaron
bien a la primera. Dos rondas de revisión encontraron **el mismo tipo de
hueco** en generadores distintos —dos guardias que se disparan siempre
juntas, así que una mutación que rompe solo una queda tapada por la otra—:

- **Ronda 2.** Un escenario mixto (un sujeto ajeno y uno no observado a la
  vez) hacía que `nadaEjecutado` y `alcanceNoObservable` dispararan siempre
  juntas. Se separó en dos escenarios angostos, uno por causa.
- **Ronda 3.** La rejilla de omisiones nunca nombraba los dos sujetos a la
  vez, así que con cobertura vacía `pasoNoConcluyente` y `obligacionSinSaldar`
  disparaban siempre juntas. Se agregó una omisión que nombra a los dos.

Se cerró verificando, para cada causa, que existe **al menos un caso donde
dispara sola** — no alcanza con que dispare; tiene que poder hacerlo sin
compañía, o una mutación sobre la otra la tapa sin que nadie lo note.

---

## Lo que este arnés todavía no sabe de sí mismo

Tres propiedades del código construido que **nadie había enunciado**. Las
encontró un contraste con documentación externa sobre grafos de agentes, y
ninguna es un falso verde: son cosas ciertas que no estaban escritas.

### El presupuesto es por paso, y se multiplica

`cascadaPorDefecto` recibe un `Duration` con un default de **5 minutos**, y le
pasa **el mismo** a cada paso. Con los 2 pasos de hoy, una corrida puede tardar
10 minutos; con los 7 que `docs/03` declara, 35.

**No hay tope de corrida**, y ese timeout por invocación es hoy el único
mecanismo que detiene algo — es decir, el disyuntor físico haciendo de política.
Construir el tope de corrida sería el presupuesto de cascada, que `D-101`
congeló por no tener base en el corpus. Lo que sí corresponde es que la cifra
esté escrita y **derivada**: `capas.py` la saca de `verify.dart`, porque una
cantidad en prosa que nadie deriva ya envejeció cuatro veces en este README.

`--budget` está declarada en la superficie del CLI y no existe, así que hoy el
valor solo se puede cambiar desde Dart.

### `PullRequestSlice.id` no tiene lectores

Viaja en el dominio, se serializa, y ningún consumidor lo usa. **Se queda sin
uso a propósito.** Es la llave natural para saber si una rebanada ya se aplicó,
pero usarla exige marcar el commit con su identidad —metadata nuestra en el
historial del usuario, para siempre— y eso es una decisión de diseño que
pertenece a la política de reanudación, que el corpus declara faltante
(`D-032`). Inventarle un consumidor ahora para que no parezca muerto sería peor
que dejarlo declarado.

### La reanudación le impone a `apply` una condición que nadie enunció

`useBranch` es idempotente **a propósito**, y su comentario dice por qué:
*«la orquestación la pide al empezar y `--resume` la vuelve a pedir»*. A `apply`
nunca se le hizo la misma pregunta, y es la operación con el efecto
irreversible.

Medido: aplicar dos veces la misma rebanada **no** produce un segundo commit.
Lo impide la cláusula «ni uno menos» — que entró por un review, por una razón
distinta, y que nadie diseñó para esto. Una mutación lo confirma: sin ella, el
segundo `apply` commitea.

**Esa protección era accidental y ahora tiene su propio test.** Una guardia que
protege algo que su autor no sabía que protegía se puede quitar en la próxima
refactorización sin que nada lo note, porque su prueba habla de otro escenario.

Lo que sí quedaba mal era el diagnóstico: decía que la rebanada estaba mal
armada, cuando en una reanudación no hay nada que arreglar. Ahora nombra **las
dos lecturas**, que es lo único que desde ahí se puede afirmar con verdad.

---

## Lo que `apply` pregunta antes de commitear

El pseudocódigo del corpus le da a `ChangeSink` seis líneas antes del PR. La
rebanada anterior entregó una: el **commit local**. Esta entrega dos más.

El `push` no es de acá: `D-097` lo asignó a la forja, que ya necesita
credencial. `ChangeSink` funciona sin red, y eso es lo que hace observable el
estado que ADR-014 exige tras una detención.

```
SNK → PLG:  ArtifactPolicy → qué se commitea          ← esta
SNK → PLG:  ProjectTopology → límites de paquete         declarada, no hecha
SNK:        escanea secretos                          ← esta
SNK:        commit LOCAL                                  ya estaba
SNK:        arma el artefacto de DOS SUPERFICIES         falta
SNK → HOST: PR en draft                                  falta
```

### Rechaza, no excluye

El pseudocódigo dice *«excluye generados del stage»* y **el corpus nunca dijo
si eso es en silencio**. No hay texto que lo autorice ni que lo prohíba.

Lo decide la cláusula 1, que ya estaba instalada: *exactamente los archivos de
la rebanada, en los dos sentidos*. Quitar un archivo que la rebanada declara la
rompería. Y `docs/03` tiene el principio general, aunque nunca lo aplicó a
`vcs`: *«se reporta como hallazgo, no se absorbe en silencio»*.

Se le pregunta `isEditable` y no `isGenerated`, que son dos cosas: `isEditable`
es la negación de las dos —lo generado se regenera, lo de build no es fuente— y
preguntar solo por lo generado dejaba pasar los directorios de build. Hay un
test que le pasa una política **al revés** y comprueba que el veredicto se da
vuelta sobre el mismo nombre: `vcs` no sabe qué hace que algo sea generado, y
esa ignorancia es comprobable.

### Los secretos cortan el commit, y esa decisión no estaba tomada

El corpus asigna la detección a `vcs` en cuatro lugares y **nunca le dio
severidad**: no hay ADR, ni delta, ni invariante; no figura en la tabla de
severidades de `docs/08` ni entre los seis deltas que ADR-013 reconcilió. La
única pista era que el plan la ubica en «Requiere criterio», que por ADR-012 es
la superficie de **mirar**.

Bloquea. Un secreto commiteado no se des-commitea: queda en el historial, y
reportarlo entonces no es un control sino una crónica — es el mismo argumento
por el que el check de anonimato de este repositorio mira el historial y no el
árbol. Cumple INV-8 porque la alternativa la escribe el propio corpus en `P-07`
y `L-09`: *«leé de `env` vía provider de configuración»*.

**El hallazgo nunca lleva el secreto.** INV-5 le exige eso a las credenciales
del arnés; vale igual para las del usuario. Un detector que para avisarte de una
filtración te la escribe en un log la filtra otra vez, y en un lugar que nadie
está mirando. Hay un test que lo comprueba sobre el mensaje entero.

**No es exhaustivo, y va escrito.** Reconoce formas con estructura —encabezados
de clave privada, prefijos de token de proveedores— y asignaciones a nombres que
declaran su contenido. Una cadena sin ninguna de esas dos cosas pasa: un secreto
sin forma reconocible es indistinguible de cualquier otra cadena, y prometer lo
contrario sería el falso verde que este arnés existe para cazar.

La suite **se deriva de la tabla de patrones**, no de una lista paralela: hay un
test que compara las muestras contra `DetectorDeSecretos.loQueReconoce`, así que
un patrón nuevo sin caso deja la suite en rojo en vez de entrar sin que nadie lo
haya visto fallar.

### Y `ProjectTopology` no entra, con su motivo

Su única función descrita es *«corta commits atómicos por unidad coherente»*
(`happy-path.md`, una sola línea en todo el corpus). **«Unidad coherente» no
está definida en ninguna parte**, y hay una contradicción sin resolver:
`docs/05` §4 asigna la descomposición a `orchestration`, y el plan la congela —
*«un PR por corrida hasta que el corpus muestre que hace falta»*—. Construirla
ahora sería inventar el criterio que falta.

### Lo que la regla de cadenas cobró en el camino

Los fixtures de los tests se llamaban `generado.g.dart` y `config.dart`, y
`lenguaje-en-plugin-dart` los rechazó. Tenía razón: `vcs` no puede saber qué
extensión significa «generado» —eso es justamente lo que la política inyectada
viene a decidir— y un fixture con esa forma lo enseñaba de contrabando. Ahora se
llaman `generado.gen` y `ajustes.conf`, y el test es más honesto que antes.

También cobró un comentario que decía *«una credencial filtrada no es una
pregunta sobre X ni sobre Y»*: al escribirlo, `vcs` conocía X e Y. Es el mismo
caso que ya había corregido `ArtifactPolicy` en `core`, palabra por palabra.

### Tres formas de colar un secreto, y una cuarta que salió midiendo

Un review encontró que el detector se podía evadir de tres maneras. Las tres
reproducidas contra `git` de verdad, y **la raíz de las tres es la misma**: el
detector inspeccionaba una *representación* del cambio, y el commit consumía
otra.

| La evasión | Por qué pasaba |
|---|---|
| contenido `++ AKIA…` | `git` lo representa como `+++ AKIA…`, y el detector descartaba toda línea `+++` por su **forma**, dando por hecho que solo el encabezado la tiene |
| un `textconv` en `.gitattributes` | el repositorio inspeccionado configura cómo se ve su propio diff; con uno que no imprime nada, el detector recibía un diff vacío |
| un gancho `pre-commit` | reescribe el archivo y hace `git add` **entre** la inspección y el commit: se escaneaba «inocente» y `HEAD` quedaba con la clave |
| **un driver de diff externo** | la cuarta, que el review no nombró: `diff.<driver>.command` también oculta el contenido, y **`--no-textconv` no lo tapa** |

La primera se arregla con estado del parser en vez de forma de la línea: el
encabezado `+++ b/…` aparece **siempre antes** del primer `@@`, así que lo que
distingue no es cómo se ve la línea sino dónde está. La segunda y la cuarta,
con `--no-textconv` y `--no-ext-diff`, que son dos banderas porque son dos
agujeros — lo comprobé midiendo, no leyéndolo.

**La tercera cambió el diseño.** No era la concurrencia futura: era la propia
operación invocando al gancho adentro suyo. `apply` arma ahora un **índice
aparte** con `GIT_INDEX_FILE`, lo inspecciona y commitea **ese** índice con
`core.hooksPath` a un directorio que no existe — `--no-verify` no alcanzaba,
porque no frena `prepare-commit-msg` ni `post-commit`. Deja de haber dos
consultas cercanas en el tiempo sobre
representaciones distintas: hay un objeto.

Y tuvo una consecuencia que no busqué: **el índice del usuario ya no se toca**,
así que la maquinaria de fotografiarlo y reponerlo —que otro review había
pedido, y que construí y probé— quedó sin nada que reparar. Se fue con sus
tests de reposición. Los que comprueban que el índice del usuario sobrevive a
un rechazo se quedan, y ahora pasan por construcción en vez de por reparación.

**Costo declarado:** los ganchos del usuario no corren sobre los commits del
arnés. INV-10 ya dice que ningún control cuya ausencia sea inaceptable se funda
en ganchos; acá el gancho no era el control, era lo que lo evadía.

### Doce mutaciones, y dos encontraron lo que 70 tests verdes no

| La mutación | Lo que reveló |
|---|---|
| saltar los binarios → no saltarlos | **rama muerta**: sin `--binary`, `git diff` no emite ninguna línea de contenido para un binario, así que no había nada que saltar |
| `{12,}` → `*` en el literal | ningún test daba un valor **corto** a un nombre sensible, así que el umbral no estaba probado |
| `break` → `continue` por línea | una línea que encaja en dos patrones se contaba dos veces, inflando el «hay N secretos» |

La primera es la tercera rama muerta que este proyecto borra en dos días. Una
redundancia que no puede fallar se lee como defensa en profundidad y no defiende
nada. Ahora la premisa —que `git` no emite contenido de binarios— **está
comprobada en la suite** en vez de asumida por una rama que la protegía de nada.

---

## Cuando una corrida no termina

El arnés aplica sabotajes sobre el árbol de trabajo y los revierte. El `finally`
cubre las excepciones; **no cubre que al proceso lo maten**. Ya pasó: una
corrida terminada desde afuera dejó `arquitectura.json` saboteado y un canario
suelto, y hubo que averiguar a mano qué tocar.

Hay un **diario de escritura anticipada**: se escribe antes de la primera
modificación y se borra después de revertir, así que su existencia significa
exactamente una cosa — hay un sabotaje aplicado y sin revertir.

**No repara solo, y esa es la decisión.** El arnés ya se niega a arrancar con el
árbol tocado, y esa negativa *es* el control. Reparar en silencio pisaría con
contenido viejo cualquier cosa editada después del corte, y escondería lo que
había que mostrar — ADR-015 dice lo mismo de un hallazgo: *no se corrige solo ni
se reporta en silencio*.

Lo que faltaba no era reparar: era **saber qué reparar**.

```
Una corrida anterior no terminó y dejó el árbol saboteado.

  arquitectura.json
  packages/orchestration/lib/_canario.dart
  tool/checks/arquitectura.huella
```

`--recuperar` lo deshace, y es explícito a propósito — mismo patrón que
`cifras.py --fix`. **Y devuelve los archivos a su contenido previo al sabotaje,
no al último commit**: a diferencia de `git checkout`, no pierde trabajo sin
commitear.

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

`core` exponía **toda su superficie de puertos y cero implementaciones**. Una
superficie de puertos completa se lee como un sistema que hace esas cosas.

**Instalado:** `puertos-sin-implementacion` lista los pendientes con su fase,
y se
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
dos.** Entrega los dos primeros **pasos** —que saben invocar, normalizar y
atestiguar— y el **fixture** sobre el que corren.

La distancia que queda está en la palabra: hay pasos, no hay **cascada**. Nadie
los ordena por costo, nadie corta temprano, nadie administra el presupuesto —
eso es política de `orchestration`, que no existe. Y sin `vcs` ni ensamblado de
PR no hay `ship`. Lo que sí se puede afirmar es lo de siempre: **ningún paso da
verde sobre algo que no miró.**

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
| **19 de los 25 puertos siguen sin implementación.** Está declarado puerto por puerto en `arquitectura.json`, y verificado en los dos sentidos: uno nuevo sin declarar falla, y una declaración que quedó vieja también | **fase 2**, rebanadas siguientes |
| **Coherencia del registro de reglas en tiempo de ejecución.** El constructor de `Rule` rechaza lo que no se puede instalar, pero **nada obliga a que una regla del proyecto llegue a ser una `Rule`**: una que viva solo en prosa esquiva el tipo entero | El registro y su proyección: **fase 3** |
| **El check de proyección de la capa C.** Hoy `AGENTS.md` y `CLAUDE.md` están **excluidos** de la regla de cadenas —nombrar `claude` o `flutter` es su contenido, por diseño— y nada verifica que lo proyectado sea coherente | **Fase 3** |
| **`ship`.** `verify` existe y corre, y `apply` ya consulta la política de artefactos y corta por secretos; falta el agente, los tickets, el ensamblado del PR y el artefacto de revisión | **Fase 2**, rebanadas siguientes |
| **`ProjectTopology` en `vcs`.** Declarada y no hecha: su única función descrita es «cortar commits por unidad coherente», que no está definida en el corpus, y la descomposición está asignada a `orchestration` y congelada por el plan | Cuando el corpus defina «unidad coherente» |
| **La omisión del detector de secretos, por corrida.** Hoy es un límite declarado del método —lo binario no se revisa— y no una omisión reportada en cada ejecución, que es lo que pide el corolario 5 de ADR-011 | Con el artefacto de revisión, en `ship` |
| **El corte temprano y el presupuesto de la cascada.** Hoy corren todos los pasos. El corte necesita que el reporte de registrados contra ejecutados exista primero, que es lo que instaló esta rebanada | **Fase 2**, rebanadas siguientes |
| Todo el producto: cascada, ganchos, capa C, intake, sensores | Fases 2 a 7 |

**El arnés está partido en dos repositorios, y eso se puede instalar a medias.**
Los checks de este repo cubren la arquitectura del código. Los que verifican el
corpus de diseño viven en `../sdlc-agentico/` con su propio CI. Tener uno solo
en verde **no significa que el arnés esté completo**. Lo único que hoy cruza los
dos es `estados.py`, que compara el inventario del arnés contra las reglas
instaladas acá. **Si los repos dejan de estar uno al lado del otro, falla**: no
poder mirar no es «no disponible». La única evasión es `--sin-repo-de-codigo`,
que hay que escribir a mano y que imprime que no miró.

Este párrafo decía lo contrario —que se degradaba en silencio— y lo encontró un
review. Es la peor clase de documentación vencida: describía un agujero que ya
no existe, y quien la leyera creería el arnés más débil de lo que es.

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
  plugin_fake     los fakes de los puertos que ya tienen contrato
  cli             comandos y composition root
tool/
  checks/         capas.py · probar_reglas.py
  analisis/      lo que necesita el árbol sintáctico · fuera del workspace
```

Todas las flechas de dependencia apuntan hacia `core`. `cli` es el único que
puede ver a `plugin_dart` y a `agents`.
