# shipflow

CLI Dart que hace que **el agente del usuario** entregue mejor. No construye un
bucle agéntico: se integra con Claude Code, Codex o Gemini CLI.

El diseño completo —18 ADRs, el modelo D+C+E, el catálogo de fallos, el plan por
fases— vive en un repositorio aparte: **`../sdlc-agentico/`**. Empezá por su
`AGENTS.md`.

---

## Estado: fase 2, quinta rebanada. **Hay un comando.**

`core` existe: **las entidades y los puertos, como tipos.** 10 de los 28
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

**El entorno de verificación ya se deriva del candidato, y ningún subproceso hereda el del padre.** Ver [El entorno de verificación se deriva del candidato](#el-entorno-de-verificación-se-deriva-del-candidato). El plan, tarea por tarea, está en [PLAN-entorno-de-verificacion.md](PLAN-entorno-de-verificacion.md); no le queda nada pendiente — los tres refinamientos que se apartaban del diseño ya se propagaron al corpus.

**El desenlace de un paso ya es un tipo cerrado, y la aplicabilidad ya salió del verificador.** Ver [El desenlace se cierra, y la aplicabilidad sale del verificador](#el-desenlace-se-cierra-y-la-aplicabilidad-sale-del-verificador). El plan, tarea por tarea, está en [PLAN-desenlace-cerrado.md](PLAN-desenlace-cerrado.md); lo que queda de él es propagar el registro de deltas al otro repositorio, no código de este.

**La superficie de verificación se está implementando en esta rama.** Ver [La superficie de verificación](#la-superficie-de-verificación). El plan, tarea por tarea, está en [PLAN-superficie-de-verificacion.md](PLAN-superficie-de-verificacion.md), y el diseño que implementa vive en el otro repositorio.

**La forja y el aislamiento de la credencial se implementaron en esta rama.** Le da a la salida del pull request un desenlace sellado que distingue abierto, cerrado, fusionado y *no sé si llegó*; parte el puerto de credenciales para que quien solo lee no tenga métodos que solo lanzan; y saca la credencial del entorno que heredan los subprocesos, en un solo sitio. Ver [La forja y el aislamiento de la credencial](#la-forja-y-el-aislamiento-de-la-credencial). El plan, tarea por tarea, está en [PLAN-forja-y-credencial.md](PLAN-forja-y-credencial.md); no le queda nada pendiente de esta rebanada — `ship`, que es quien va a llamar a `PullRequestSink.open` de verdad, es la rebanada siguiente.

**El candidato ya existe**: `ChangeSink` sabe fijar qué bytes se verifican y
commitear exactamente esos, con un compare-and-swap que falla cerrado. Pero
**no existe `ship`**, ni el agente, ni los tickets, ni los ganchos.
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
dart test packages/forge                      # push aislado, cliente de GitHub, búsqueda idempotente
dart analyze --fatal-infos
dart format --set-exit-if-changed packages tool
(cd fixtures/app-minima/dominio && dart test)  # el fixture se verifica solo
(cd fixtures/app-minima/app && flutter test)
```

**Son 16 pasos y `capas.py` lo verifica contra el workflow**, comando por
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
| `dependencias-declaradas-se-usan` | Que un pubspec declare una flecha interna que ninguna línea importa | `capas.py` |
| `subprocesos-con-entorno-saneado` | Que un subproceso **herede** el entorno del padre —el token de la forja, un `GIT_*` del shell— en vez de recibir la lista blanca | `tool/analisis` |
| `agente-en-agents` | Que `claude`/`codex`/`gemini` salgan de `agents/` | `capas.py` |
| `lenguaje-en-plugin-dart` | Que `dart`/`flutter`/`pubspec` salgan de `plugin_dart/` | `capas.py` |
| `sin-api-de-modelo` | Que **cualquier** paquete llame a una API de modelo | `capas.py` |
| `serializacion-sin-perdida` | Que un campo de `core` no viaje, o vuelva vacío | `tool/analisis` |
| `opacidad-declarada` | Que «no serializa» sea indistinguible de «se olvidaron» | `tool/analisis` |
| `puertos-sin-implementacion` | Que una superficie de puertos vacía se lea como un sistema que hace esas cosas | `tool/analisis` |
| `colecciones-inmutables` | Que un invariante se pueda romper **después** de construir el objeto, mutando la lista que se le pasó | `tool/analisis` |
| `grafo-derivado` | Que el mapa del repositorio quede desactualizado, o que un archivo no lo alcance nadie | `tool/analisis` |
| `forja-en-su-adapter` | Que el nombre de la forja, su host o un `HttpClient` salgan de `packages/forge/` | `tool/analisis` |

Una regla que `capas.py` no aplica **tiene que declarar `aplicada_por`**, ese
aplicador tiene que existir, y CI tiene que invocarlo. Sin las tres cosas es
F33: registrada y no ejecutada. El propio check lo verifica —y de hecho fue lo
primero que hizo cuando se agregaron las tres reglas nuevas.

### Por qué siete de estas reglas necesitan otro motor

**Siete, y no son un bloque contiguo de la tabla:** las seis últimas más
`subprocesos-con-entorno-saneado`, que es la quinta fila. El registro es la
fuente —`aplicada_por: tool/analisis`—, no la posición en la tabla.

Lo único que las siete comparten es la razón: **ninguna se puede derivar
leyendo el archivo como texto plano.** Es la misma lección que ya pagó
`capas.py` con el grafo de dependencias: parsear a mano devuelve cero
resultados ante una sintaxis que el parser no reconoce, y cero se lee igual que
*"está todo bien"*. Su paquete está **fuera del `workspace:`** a propósito:
ninguna regla de capas debería tener que hacerle una excepción a su propio
verificador.

**Lo que mira cada una no es lo mismo, y agruparlas bajo «se derivan del árbol
sintáctico de `core`» era falso.** Medido sobre `tool/analisis`:

- `serializacion-sin-perdida`, `opacidad-declarada` y `colecciones-inmutables`
  — y solo estas tres — se derivan del árbol sintáctico de `packages/core/lib`.
- `puertos-sin-implementacion` saca los puertos de ahí, pero **quién los
  implementa lo busca en todos los paquetes**: una implementación que viviera
  solo en `core` no es la pregunta que responde.
- `subprocesos-con-entorno-saneado` mira `lib/` y `bin/` de cada paquete, y es
  la única que además **resuelve** la identidad de `Process` contra el SDK en
  vez de conformarse con el nombre.
- `forja-en-su-adapter` mira `lib/` y `bin/` de cada paquete **menos `forge`**,
  y de sus dos criterios solo el primero sale del árbol: el segundo es
  **textual** sobre el contenido del archivo, y lo único que le pide al parser
  es el stream de tokens con el que descarta los comentarios.
- `grafo-derivado` mira el repositorio entero, `.dart` **y `.md`**: los `.dart`
  por sus directivas en el árbol, pero las aristas de cita de los `.md` salen
  de la **prosa**, no de ningún árbol.

Los residuos de cada criterio están en
[`arquitectura.json`](arquitectura.json), no acá.

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

### El verificador no obedecía la regla que hace cumplir

`_check_readme` encadenaba seis `return`. Un fallo cualquiera —el presupuesto
que cambió de forma, la lista de pasos que no se pudo leer— abortaba la función
entera y apagaba **en silencio** los controles que venían después: la cantidad
de puertos, la prohibición de cifras sueltas, los nombres retirados. Tres
controles no relacionados, apagados por una causa ajena.

Reproducido:

| | exit | ¿reporta el defecto tardío? |
|---|---|---|
| Solo un defecto tardío | `1` | **sí** |
| El mismo, más un fallo temprano y ajeno | `1` | **no** |

**No era un falso verde** —el código de salida seguía en 1, porque cada `return`
reporta antes de salir—. Era enmascaramiento: un problema esconde a los demás y
aparecen de a uno, corrida por corrida.

Y había un borde peor. `capas.py` leía la lista de pasos de la cascada con un
`.index("Cascada([")` **sin guardia**. Con un cambio realista —ponerle el tipo
explícito al literal— el proceso moría con `ValueError: substring not found`, y
como `_paso` no atrapaba nada, los cuatro pasos quedaban sin imprimir ni una
línea. Diez controles saltados y un traceback en lugar de un diagnóstico. Es la
misma clase de ancla que `probar_reglas.py` documenta como rota **veinticuatro
commits** sin que nadie lo notara: la lección estaba escrita en un archivo y no
aplicada en el de al lado.

**La cascada del producto ya tenía esto resuelto**: un paso que se rompe no
aborta la corrida — es `Broken`, se reporta, y los demás siguen. Ahora cada
sección del README se verifica aislada, y una excepción se convierte en
hallazgo en vez de en corte.

### Los anclajes, con el fallo a la vista

El otro archivo se acusaba solo: cinco bloques marcados «FRÁGIL, SIN GUARDIA»
por su propio autor. El patrón era siempre el mismo —buscar un texto literal en
el workflow o el README y reemplazarlo— y la mitad no tenía nada que lo
respaldara. Los dos modos de fallo son distintos, y el silencioso es el peor:

| | Qué pasa si el ancla se pierde |
|---|---|
| `.index` sin guardia | revienta sin decir qué buscaba ni para qué |
| `.replace` sin guardia | **no revienta**: devuelve el texto intacto, el sabotaje no sabotea, y el arnés lo reporta como «la regla quedó sin efecto» — acusando al control equivocado |

`tool/checks/_comun.py` los cierra con tres funciones: `exige_unica` para los
anclajes que solo localizan, `ancla` para los que reemplazan exigiendo una
ocurrencia, y `ancla_multiple` para los que se repiten por diseño —donde
exigir unicidad sería exigir lo contrario de lo que el formato garantiza—.

Es un tercero neutral a propósito: `probar_reglas.py` invoca a `capas.py` **como
subproceso** para que un sabotaje no pueda romper el arnés que lo aplica, así
que importarse entre ellos deshacía esa separación.

**Instalarlo encontró dos suposiciones falsas de inmediato.** Dos anclajes que
el código trataba como únicos no lo eran: `` `tool/analisis` `` aparece cinco
veces en el README y `presupuesto: presupuesto` dos veces en la cascada. Los dos
funcionaban por el `, 1` del `.replace`, no porque alguien lo hubiera
comprobado.

### Y dos sabotajes nuevos

| Sabotaje | Qué exige |
|---|---|
| Dos defectos independientes a la vez | que el informe nombre **los dos** |
| Un control que revienta | que se reporte **y** que un control posterior igual corra |

**Los dos empezaron probando menos de lo que decían.** El primero rompía la
forma del presupuesto con un espacio de más, y dejó de sabotear el día que la
derivación se mudó al árbol sintáctico. El segundo exigía que apareciera el
nombre de un paso que estaba *fuera* del grupo fusionado, así que pasaba con los
controles otra vez juntos. Los dos están reapuntados, y los dos se vieron en
rojo sobre su propio caso.

### El parser que contaba corchetes se fue, no se arregló

`capas.py` encontraba la lista de pasos de la cascada contando `[` y `]` sobre
el texto. Una revisión lo reprodujo: con `// ]` antes del segundo paso, el
recorte veía **uno donde hay dos** y ningún guardia disparaba —el README podía
afirmar un paso y el check quedaba verde—. El comentario de aquel parser decía
que el llamador lo cazaría.

Contar caracteres para leer sintaxis no se arregla contando mejor. La derivación
vive ahora en `tool/analisis/bin/check.dart`, sobre el árbol sintáctico, que es
quien sabe qué es un comentario y qué es un corchete — el mismo criterio por el
que el grafo se le pide a pub y el workflow a un parser de YAML.

**Y escribirla produjo un falso rojo antes de commitear:** sin resolución,
`Cascada([...])` llega como `MethodInvocation`, no como
`InstanceCreationExpression`. La primera versión buscaba solo la segunda forma y
reportaba «no encontré la lista» sobre un árbol sano.

### Cada control es un paso, no cada grupo

`check_meta` corría diez controles adentro de una sola llamada, así que una
excepción en el segundo —un campo del registro con la forma estructural
equivocada— dejaba sin ejecutar al de CI y al del README. El resultado global
quedaba rojo y los defectos aparecían de a uno por corrida: el problema que el
aislamiento vino a cerrar, a mitad de camino. Y `grafo()` corría fuera de
`_paso`, así que un fallo suyo se llevaba el proceso antes de llegar a las
cadenas.

Ahora son **catorce pasos independientes**. Con el campo roto, el que revienta
se reporta y los trece restantes corren.

### El arnés no toca el checkout compartido

Escribía cada sabotaje sobre el árbol de trabajo y restauraba después. El diario
cubría las interrupciones y **no cubría la concurrencia**: mientras una corrida
tenía un sabotaje puesto, otro proceso commiteó. El commit se llevó el
`aplicada_por` de una regla apuntado a un aplicador inexistente, un canario
sintético versionado, y la huella del JSON saboteado — los tres estados internamente coherentes, así que nada
local se puso rojo. **Un checkout limpio de ese commit fallaba `capas.py` con dos
errores.**

Y el motivo por el que ningún control lo vio es el que vale registrar: **todos
miran el árbol de trabajo, y ninguno mira lo commiteado.**

```
probar_reglas.py                                   ← el árbol compartido
  ├─ huella del original
  ├─ copytree → /tmp/arnes-copia-XXXX/             0,11 s
  ├─ los sabotajes, adentro de la copia
  ├─ borrar la copia
  └─ la huella del original tiene que coincidir
```

**`.dart_tool` se copia, y por eso no hace falta `pub get`.** Sus rutas a los
miembros del workspace son relativas, así que en la copia resuelven a la copia —
el mismo hecho medido que hace funcionar el candidato. Copiar 84 MB cuesta una
décima de segundo; resolver de nuevo costaría más y necesitaría el cache.

**La detección de residuo dejó de preguntarle a git.** `estado_git` tenía dos
límites: solo veía lo versionado —un canario en un directorio ignorado no
aparecía— y necesitaba un `.git` que la copia no tiene. Ahora es una huella de
contenido, y son dos preguntas distintas: **afuera**, que el original no cambió,
con lo generado incluido; **adentro**, que los sabotajes no dejaron residuo, con
lo generado excluido, porque `package_config.json` lleva fecha de generación y
los casos que corren `pub get` la cambian sin que eso sea residuo.

**Con su alcance escrito, no «en absoluto».** Compara ruta, tipo, modo y
contenido de cada archivo y enlace, con las longitudes por delante. Quedan
afuera `.git`, `build/` y los snapshots `.dill` —que se regeneran— y el modo de
los directorios. Decir «no cambió en absoluto» afirmaba más de lo que mide.

### Y el arnés se niega antes de escribir donde no debe

Una revisión pidió una prueba de que el árbol compartido no cambia. La huella
que se compara antes y después ya lo mide **en cada corrida** — pero tiene un
hueco: si alguien saca el desvío a la copia, la comprobación se va con él.

Una negativa cierra eso mejor que una prueba. El proceso externo le dice al
interno de dónde salió la copia; si esa variable no está, o apunta al árbol
donde el proceso está parado, **no sabotea nada**:

```
$ python3 tool/checks/probar_reglas.py --en-copia
Me niego a sabotear este árbol.
```

Sacar el desvío no deja al arnés escribiendo sobre el checkout compartido: lo
deja rojo.

**Lo que queda declarado:** `--recuperar` y `probar_recuperacion.py` siguen
existiendo y siguen pasando, pero su motivo original —recuperar el checkout
compartido tras una corrida muerta— ya no aplica, porque ese checkout no se
toca. Retirarlos es un cambio coordinado aparte: son un paso obligatorio de CI y
una cifra derivada de este README.

### La derivación falla cerrada, o no deriva nada

Mover la cuenta al árbol sintáctico cerró el falso verde del parser de texto y
dejó dos abiertos. Los encontró una revisión, y los dos tienen la misma forma:
**el árbol se leía a medias y lo no reconocido se omitía.**

| Qué se omitía | Qué pasaba |
|---|---|
| `whereType<Expression>()` descarta `...spread`, `if` y `for` | Los pasos entran por un spread: la cascada corre dos, el README declara uno, y el verificador sale con **cero** |
| El visitante se quedaba con la **primera** `Cascada(` del cuerpo | Una rama condicional antes del `return` construye una de un paso y se vuelve la fuente documental |

Ahora **todo elemento tiene que tener una forma que la derivación sepa leer**, y
lo que se lee es la cascada que la función **retorna** — el `return`, uno solo;
más de uno es ambiguo y ambiguo falla. Contar los `return` de closures anidados
de más es deliberado: si hay uno, esta derivación no puede saber cuál es el de
la función, y prefiere declararse ambigua a elegir.

```
la lista de pasos tiene un elemento de forma `SpreadElementImpl`,
que esta derivación no sabe contar.

no pude derivar la cascada: tiene 2 `return`, y hace falta uno solo
para saber cuál cascada es la que se usa.
```

Las tres formas de elemento y la cascada auxiliar tienen su sabotaje permanente.

### La huella distingue lo que dice distinguir

La que sostiene «el checkout compartido no cambió» concatenaba ruta y contenido
con un `\0` en medio, y eso no es una representación inequívoca: un árbol con
`a=«b»` y `c=«d»` entregaba al hash **exactamente los mismos bytes** que uno con
`a=«bc\0d»`. No era una colisión de SHA-256 — eran dos árboles distintos con la
misma entrada. Y el modo no viajaba, así que cambiar el bit ejecutable de un
archivo no la movía.

Ahora cada entrada lleva tipo, modo y las longitudes por delante. **Y la huella
se comprueba a sí misma en cada corrida**, antes de que nadie se apoye en ella:
no hay dónde poner una prueba unitaria de ese archivo, y dejar la propiedad sin
comprobar sería la misma confianza que el arnés persigue.

### Lo permitido y lo usado son dos cosas, y ahora hay una regla

`deps-hacia-core` dice qué flechas **están permitidas**. Nada decía que las
declaradas **se usaran**, y un review encontró tres en `cli` —`vcs`, `rules` y
`agents`— con cero imports. Ninguna otra regla podía verlas: estaban permitidas,
así que para `deps-hacia-core` no había nada mal.

Una dependencia declarada y no importada afirma un uso que no existe. Leer
`cli/pubspec.yaml` y encontrar `vcs` sugiere que el CLI hace cosas de
repositorio, y no las hace — `ship` no existe todavía.

**Escribir el check encontró dos más.** `rules` y `agents` declaraban `core` y no
importan nada: son stubs de dos líneas que dicen «sin API todavía». Salieron con
el mismo criterio, y `pubspec.lock` no se movió en ninguno de los dos casos.

> **`dependencias-declaradas-se-usan`** — toda dependencia interna declarada en
> un pubspec se importa en ese paquete. Su violación canónica es exactamente la
> flecha que se acaba de quitar: `cli` declarando `vcs`.

**La evidencia sale del árbol sintáctico, no de un regex.** La primera versión
buscaba `package:<nombre>/` en todo el texto del archivo, así que un comentario
contaba como uso: una revisión lo reprodujo declarando `rules` en `cli`, sin
ningún import, con una sola línea `// package:rules/rules.dart` — y `capas.py`
salió con cero. Era el mismo error de leer sintaxis con una expresión regular que
este arnés acababa de sacar de otra parte.

Ahora la evidencia sale de `grafo.jsonl`, que `tool/analisis` deriva mirando
`ImportDirective` y `ExportDirective`, y que `grafo-derivado` verifica contra el
árbol en cada corrida. Un comentario no es una directiva.

**Y la sección importa.** El grafo distingue `test/` de `lib/` y `bin/`, así que
la regla contesta dos preguntas y no una: si la dependencia se importa, y si está
declarada donde corresponde. Eso encontró que `plugin_fake` era dependencia de
producción de `cli` con sus siete imports en `test/`, mientras `plugin_dart` ya
usaba el patrón correcto.

Las tres ramas —producción sin usar, desarrollo sin usar, y producción usada solo
en pruebas— tienen su sabotaje. La segunda faltaba, y una revisión lo comprobó
borrando esa rama del bucle: los sabotajes seguían todos verdes.

**Quién controla qué, para no duplicar al analizador.** `capas.py` mira una
dependencia de **producción** usada solo por pruebas; el caso simétrico —una
dependencia de **desarrollo** usada desde `lib/` o `bin/`— ya lo detecta
`dart analyze --fatal-infos` con `depend_on_referenced_packages`, verificado
importando un dev-dep desde `lib/` y viéndolo fallar. Construirlo de nuevo sería
un segundo control sobre el mismo hecho.

**Límite declarado, y hay que decirlo porque ya cobró.** Esto mira el pubspec
contra los imports; **no mira la prosa**. Quitar las tres de `cli` dejó dos
frases falsas —el barril de `cli` y este README— que nombraban a `agents` de
ejemplo, y esta regla no las habría visto. Son dos controles distintos, y solo
uno está claro cómo se automatiza sin producir ruido.

### El piso del SDK, y quién decide el estilo del formato

Los diez pubspec declaraban `sdk: ^3.6.0` mientras el lock del workspace exige
`>=3.11.0`: seis versiones menores de soporte prometido que nadie podía cumplir.
No era un hueco de verificación —el workflow ya declaraba que la matriz no prueba
el mínimo— sino **una afirmación falsa**, y el fixture se había corregido por esto
mismo sin propagarse.

Alinearlo cuesta diez líneas y **arrastra 49 archivos**: el formateador toma su
estilo de la versión de lenguaje, y esa sale del pubspec.

```
con sdk: ^3.6.0     →  dart format:  0 archivos cambiados
con sdk: ^3.11.0    →  dart format: 49 archivos cambiados
```

Y el estilo nuevo **todavía se mueve entre versiones menores**. Con el árbol
formateado por 3.12, la pata `stable` —3.13.3— reformateaba cinco archivos: el
canario quedaba rojo por construcción, y un canario que no puede ponerse verde
deja de mirarse.

**El primer arreglo estaba mal, y lo encontró un review.** Fue fijar el estilo
con `--language-version=3.6`, creyendo que esa opción elige estética. Elige
también **gramática**: con ella, sintaxis válida en 3.11 —`dot-shorthands`— falla
al formatear mientras `dart analyze` la acepta. Era un techo sintáctico en 3.6
instalado en silencio, que es peor que el canario rojo.

Lo que quedó: el piso en `^3.11.0`, el formato con la versión que el pubspec
declara, y **el estilo lo decide un solo SDK** — el bloqueante, en un job propio.
La pata `stable` sigue comprobando análisis y pruebas; el estilo no lo decide.

**Acople declarado:** el `sdk` de ese job tiene que ser el mismo que la pata no
canario de la matriz. Son dos lugares y se mueven juntos; nada lo verifica
todavía.

Y `tool/analisis` sube a `^3.11.0` **por uniformidad, no por necesidad**: su
lockfile exigía `>=3.9.0`. El piso falso era el del workspace. Queda dicho porque
el comentario que se escribió primero afirmaba que su lock ya pedía 3.11, y no
era cierto.

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

Los 16 pasos obligatorios están fijados en `capas.py` —es política, no deriva
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
| `VerificationEnvironment` | el resolvedor sobre el candidato, una raíz por vez | **no hay**, y está declarado |

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

`VerificationEnvironment` salió con **una real y ningún fake**, por el mismo
motivo y escrito en el mismo registro: no hay etapa que lo consuma —la
composición vive en una prueba de `cli`— así que una suite de contrato con una
sola implementación no contrasta nada, corre la misma lógica dos veces. El fake
llega con la etapa que lo use.

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
y su caso ciego. **El arnés aplica 142 sabotajes.**

---

## El candidato: los bytes que se verifican son los que se commitean

`apply` tenía una ventana abierta que ninguna prueba veía. Entre que la cascada
mira los archivos y `git add` los stagea, el contenido puede cambiar —el
usuario, el IDE, un watcher, un generador, otro proceso— y `apply` commitea lo
que exista **en ese momento**. No hace falta concurrencia exótica: la propia
operación ya se lo hizo a sí misma una vez, con un gancho que reescribía el
archivo adentro del commit.

`ChangeSink` gana un segundo verbo. `prepareCandidate` **fija** el contenido, y
`commit()` se lleva exactamente eso:

```
árbol EXPUESTO a los controles  =  árbol del candidato  =  árbol commiteado
```

**Igualdad de objeto, nunca cobertura.** Que el contenido verificado sea el
commiteado no dice que ningún control lo haya mirado entero — está medido que
`dart analyze` no informa qué archivos leyó. La cobertura la acota cada testigo,
y solo hasta sus sujetos.

### Lo que la medición descartó antes de escribir una línea

El diseño afirmaba «los mismos bytes del archivo de trabajo». Una sonda
ejecutable lo falsificó, y con él tres invariantes más:

| Hecho medido | Qué invalidó |
|---|---|
| Con `text eol=lf`, un filtro `clean` o `core.autocrlf`, **el objeto difiere de los bytes del archivo** | «los mismos bytes del archivo de trabajo» |
| Con un filtro no determinista, el mismo archivo sin tocar da objetos distintos en dos stagings | un digest capturado antes de la cascada sería incomparable después |
| Un cambio de bit ejecutable **conserva** el objeto del archivo y cambia el commit | el objeto solo no identifica lo que se commitea |
| Un borrado no tiene ningún objeto resultante | un `digest` obligatorio por ruta es un tipo mal formado |
| `check-attr` da `unspecified` en las tres claves con `core.autocrlf` activo | **no hay preflight barato**: hay que materializar siempre |

Por eso la identidad es **un árbol**: cubre contenido, modo, altas,
modificaciones y bajas con un solo identificador, y no tiene el problema del
borrado sin digest.

### Se materializa por plumbing, nunca con `checkout`

`checkout-index` aplica la conversión **inversa** —`smudge`, normalización de
fin de línea, `working-tree-encoding`— y rompe la igualdad. Medido, en los dos
casos:

| Archivo | objeto | tras `checkout-index` | |
|---|---|---|---|
| con filtro `smudge` | `5186921034` | `12dc3238e9` | **distinto** |
| con `text eol=crlf` | `8a8f4b9135` | `8feab959bc` | **distinto** |

La materialización enumera el árbol y vuelca cada objeto sin pasar por ninguna
conversión. Los registros se parsean **por bytes delimitados por `NUL`**: un
nombre con salto de línea partiría un registro en dos con cualquier lectura por
líneas.

### Lo que NO se materializa queda declarado, no recortado

| Modo | Qué pasa |
|---|---|
| `100644` · `100755` | se vuelca; el bit ejecutable sale del árbol, no del objeto |
| `120000` interno | se crea el enlace |
| `120000` absoluto o con `..` | **no se recrea**, y se declara. Recrearlo dejaría que una herramienta lo siguiera y leyera algo que ningún testigo cubre |
| `160000` | **no soportado**, y se declara |

Una ruta que no sea UTF-8 tampoco se adivina: se rechaza nombrándola en
hexadecimal. Decodificarla con reemplazo produciría una ruta *parecida* a la
real, que es peor que no tenerla.

### Cero efectos hasta que alguien autorice

La preparación entera ocurre en un almacén de objetos **aislado** —no solo en
un ensayo—. Está medido que preparar contra el almacén real deja objetos
inalcanzables antes de que nadie confirme nada, y hay tres caminos que prometen
cero efectos: el ensayo, la ausencia de terminal, y el usuario que dice que no.

`commit()` promueve los objetos **recursivamente y preservando el tipo**. Una
versión del diseño promovía solo los objetos de archivo; medido, con el
temporal borrado `commit-tree` falla con *«is not a valid object»*, porque los
árboles —incluidos los subárboles— también nacen ahí.

### El secreto corta el commit por los dos caminos

`apply` bloquea secretos porque el escaneo está adentro. El candidato, en su
primera versión, no: se dejaba para el llamador y se declaraba como límite. Una
revisión externa lo reprodujo commiteando una clave AWS, y tenía razón —
**declarar un hueco en el README no vuelve seguro el puerto**. `ChangeSink`
quedaba con dos caminos de escritura y dos garantías distintas según por cuál se
entrara, que es peor que no tener el camino nuevo.

Ahora `createRevision()` escanea el diff del par de revisiones **antes de
promover un solo objeto**, y los dos caminos lanzan la misma causa tipada, con
los hallazgos como dato y no como mensaje.

Lo que el escaneo **no** cubre sigue igual y sigue escrito: el detector revisa
las líneas agregadas de un diff, no el árbol, y lo que `git` declara binario
queda afuera por límite declarado.

### La rama se mueve con un compare-and-swap

```
NEW=$(git commit-tree $ARBOL -p $base -m "<intent>")   ← createRevision()
git update-ref refs/heads/<rama> $NEW $base            ← applyRevision()
```

**No hay `git add` en el momento del commit.** Ahí muere el TOCTOU. Y
`update-ref` de tres argumentos falla cerrado: con `HEAD` movido por otro
proceso, el commit ajeno sobrevive y el nuestro queda inalcanzable —basura que
`git gc` recoge, no daño—.

**Son dos métodos y no uno, y la razón es la recuperación.** Entre crear el
objeto y mover la referencia hay que poder **persistir la revisión**. Con una
sola operación, un proceso que muriera en el medio dejaba una revisión que no
quedó anotada en ningún lado, y quien intentara recuperar no tenía identidad que
consultar. Como crear un commit no mueve nada, hacerlo antes no tiene efecto
observable — y el coordinador tiene dónde escribir.

El desenlace es un tipo sellado de tres variantes, no una excepción con dos
casos felices: `Committed`, `NotApplied` y `LocalInconsistent`. Que la rama no
se haya movido **no es un fallo de la herramienta**, y modelarlo como excepción
deja que quien llama se olvide de atraparlo y reporte éxito.

Y las tres **validan en el constructor**. `NotApplied` llegó a construirse con
la revisión en blanco —cuando el usuario cambiaba de rama entre preparar y
aplicar— y el tipo lo aceptaba sin decir nada: un desenlace que dice «no se
aplicó esto» sin decir qué. La causa también se partió en dos, `baseMovida` y
`ramaCambiada`, porque un solo campo que unas veces trae una revisión y otras una
frase sobre la rama obliga a quien lo lee a adivinar cuál le tocó.

### Cinco sabotajes, y uno que no se puso rojo

Cada premisa medida tiene su prueba permanente, y cada prueba se vio en rojo:

| Sabotaje | Qué se puso rojo |
|---|---|
| Recomputar el árbol al commitear | 13 pruebas, incluida la del TOCTOU |
| Materializar con `checkout-index` | 4 pruebas, entre ellas la igualdad con `smudge` y con `eol=crlf` |
| Promover solo los objetos de archivo | 14 pruebas: `commit-tree` no encuentra el árbol |
| `update-ref` sin el valor viejo | **una sola**: la del `HEAD` movido |
| Preparar contra el almacén real | **una sola**: la de cero objetos |
| Sacar el escaneo de secretos | las dos del secreto |
| Volver a fijar el identificador en 40 | **una sola**: la del repositorio `sha256` |
| Decodificar el destino del enlace con reemplazo | **una sola**: la del enlace no UTF-8 |
| Ignorar el fallo al sincronizar el índice | **una sola**: la de `LocalInconsistent` |

El sexto no está en la tabla porque **falló como sabotaje**: reintroducir un
`git add` justo antes de commitear no puso nada en rojo. No es un hueco de las
pruebas — es que el árbol ya está fijado y volver a stagear no cambia lo que
`commit-tree` recibe. La única forma de reabrir la ventana es recomputar el
árbol, y ese es el sabotaje que sí quedó.

### Lo que esta rebanada NO hace

- **No existe `ship`.** El candidato es un puerto; no hay comando que lo use,
  ni preview, ni confirmación, ni compuerta por estado, ni PR. En particular,
  **nadie persiste la revisión entre `createRevision` y `applyRevision`**: el
  puerto deja el lugar, y el coordinador que lo va a ocupar todavía no existe.
- **Los assets de ejecución no se preparan.** El candidato materializa el árbol
  y nada más: sin `pubspec.lock` resuelto ni `.dart_tool`, correr la cascada
  ahí adentro todavía no está construido.
- **El entorno de los subprocesos no está saneado.** `git` hereda el del padre.
- **Un destino de enlace con `..` se rechaza aunque se quede adentro.**
  `sub/../a` no escapa y también se declara: resolverlo exigiría reimplementar
  la resolución de enlaces del sistema. El motivo registrado lo dice así, y no
  afirma que el destino escape.
- **`ChangeSink` sigue con una sola implementación y ningún fake**, por el
  mismo motivo que ya estaba declarado: no hay etapa que lo consuma.

---

## El entorno de verificación se deriva del candidato

El candidato ya fijaba **qué bytes** se verifican. Faltaba lo otro: **con qué se
ejecutan**. Un árbol recién materializado no trae resolución de dependencias
—está medido: lo que se genera al resolver no se versiona— así que la cascada no
podía correr adentro, y correr afuera es medir el árbol de trabajo del usuario,
que es el problema que el candidato existe para cerrar.

Esta rebanada deriva el entorno **del propio candidato**, comprueba que derivar
no lo alteró, y saca del camino un defecto latente que nadie había mirado: todo
subproceso heredaba el entorno del padre.

### Por qué derivar y no prestar

Prestar el entorno del usuario haría que la cascada midiera sobre resoluciones
que ningún commit contiene: un paquete agregado al árbol de trabajo y no
commiteado resolvería igual, y el verde diría algo falso sobre lo que se va a
commitear. Derivar es `pub get --offline --enforce-lockfile` dentro del
candidato: `--offline` impide salir a buscar lo que el candidato no fijó, y
`--enforce-lockfile` impide reescribir el lockfile. **El lockfile del candidato
manda**; si no alcanza, el candidato se rechaza en vez de resolverse otra cosa.

Sacar `--enforce-lockfile` pone rojas dos pruebas, y eso no es casualidad: es el
sabotaje del estado intermedio, comprobado.

### Resolver borra lo que el candidato versiona, y por eso la integridad se comprueba

La primera versión del diseño afirmaba que bastaba con mirar si existía el
directorio de lo generado. Es falso, y está reproducido: **pub borra el lockfile
y el mapa de paquetes de un paquete miembro** cuando ese paquete pasa a
resolverse desde la raíz del workspace. Si el candidato versiona esos archivos,
derivar los borra y la cascada verifica un árbol al que le falta contenido que el
commit sí tiene.

Este repositorio no lo exhibe, y eso es parte del hallazgo: sus cuatro lockfiles
versionados pertenecen a proyectos que no son miembros, así que sobreviven
intactos. **Una prueba escrita sobre este árbol nunca lo habría encontrado.**

Así que la integridad se comprueba, y no se le pregunta a nuestro código: se le
pide a `git`, igual que el grafo de dependencias se le pide a pub. Con un índice
propio —aparte del que fijó el contenido—, leído del árbol del candidato,
refrescado contra el disco y comparado. Cada bandera tiene su medición detrás:

| Bandera | Qué pasa sin ella |
|---|---|
| `update-index --refresh` | el índice recién leído no tiene información de `stat` y **el árbol entero sale modificado**: cien diferencias falsas |
| `-q` en el refresco | sale con **1** justo cuando hay algo que reportar, y la costura que exige éxito lo convierte en fallo **antes** de que la comparación lo describa |
| `--raw` en vez de `--name-status` | aquel **pliega un cambio de modo en una `M`** indistinguible de un cambio de contenido, y la fila «bit ejecutable» era inimplementable |

Y una letra que no sea `M`, `D` ni `T` **falla cerrado**. Con un índice recién
leído no puede aparecer una `A`, y una `R` solo con detección de renombres, que
no se pide: si aparece, `git` vio algo que este control no previó, y descartarlo
sería leer un hueco como un candidato intacto.

### Un archivo nuevo tampoco es siempre inocente

**La primera versión de este control decía que ningún archivo nuevo contaba**, con
el argumento de que todos serían generados por la derivación. Es falso, y lo
reprodujo una revisión: la comparación de entradas versionadas **no ve** un
archivo sin seguimiento, así que un archivo de fuente creado entre la derivación
y el segundo control quedaba invisible. La cascada lo leía —está dentro del
alcance que analiza— y la corrida salía **roja**, concluyendo sobre bytes que el
candidato nunca fijó. Es el falso verde que esta rebanada existe para cerrar,
abierto por una generalización cómoda.

La corrección no es contar todo archivo nuevo como alteración: **derivar genera
archivos, y generarlos es su trabajo**. Es preguntarle a quien ya decide eso.
`ArtifactPolicy` existe desde la fase 2 y el repositorio ya la sostiene, así que
la regla queda: *una ruta nueva es una alteración salvo que la política la
declare artefacto*.

Y **sin las exclusiones del repositorio**: usar `--exclude-standard` haría del
`.gitignore` una segunda autoridad sobre la misma pregunta, callando rutas que la
política sí considera fuente. La autoridad ya estaba decidida.

### Lo que el candidato declaró no materializar no es una alteración

El candidato no recrea enlaces absolutos, enlaces con `..`, enlaces cuyo destino
no es UTF-8 ni submódulos, y los declara. Para la comparación esas rutas están en
el árbol y no en el disco, así que **salen como borradas**: los cuatro casos,
medidos. Sin restarlas, todo candidato con un enlace absoluto sería no
concluyente para siempre.

La resta es estrecha: una borradura sobre una ruta declarada no cuenta,
**cualquier otra cosa sobre ella sí**. Si un verificador escribió un archivo
regular donde el candidato dejó un hueco a sabiendas, eso es un cambio de tipo, y
es una alteración.

### Y un límite declarado, en vez de tapado

El refresco del índice **corre el filtro `clean`** sobre cada archivo antes de
comparar —la traza lo muestra— y la materialización escribe los bytes del objeto
sin `smudge`. Con filtros idempotentes eso cierra en cero, incluido `eol=crlf`.
Con un `clean` que no es idempotente, un candidato intacto sale **modificado**, y
el control no puede distinguir intacto de alterado.

No se compensa comparando bytes a mano: **el límite es de `git` antes que
nuestro** —`gitattributes(5)` pide que `clean → clean` equivalga a `clean`, y un
repositorio que lo viola ya ve sus archivos perpetuamente modificados en `git
status`—. La prueba lo **fija**: si algún día da cero, lo que hay que revisar es
la decisión, no el código.

### Tres desenlaces, y la línea que los separa

Que el candidato sea defectuoso y que nuestro instrumento no llegue a medir son
dos hechos distintos, y la primera versión los mezclaba en un solo enum. Es la
misma confusión que ADR-019 cerró del lado de los pasos: un instrumento roto no
es un veredicto.

| Desenlace | Qué afirma |
|---|---|
| `EntornoDerivado` | se derivó, y lleva cuántos paquetes, cuántas raíces y **la versión de la toolchain citada** |
| `CandidatoRechazado` | no se puede verificar **por lo que el candidato es** |
| `DerivacionAbortada` | no se pudo derivar **por lo que pasó al intentarlo**; no dice nada del candidato |

**Todo «no» del resolvedor es un rechazo, no un aborto**, y eso salió de medir:
el mismo código de salida cubre un cache frío y un SDK desconocido en el
manifiesto. Distinguirlos exigiría leerle frases a la salida de error, que es el
parser frágil que este proyecto rechaza en todas partes. La evidencia va citada
literal, y quien lea la corrida ve lo que la herramienta dijo. Abortar queda para
lo que el instrumento no llegó a decir: herramienta ausente y presupuesto
agotado, que la costura de procesos ya distingue.

La versión de la toolchain **no se parsea: se cita**. Un número extraído de una
frase es un parser más, y lo que hace falta es que el testigo diga con qué se
midió.

### Una raíz por cada resolución que la rebanada toca

La versión anterior del diseño exigía un único workspace con raíz en el
candidato, y **eso excluía a este repositorio de verificarse a sí mismo**: tiene
tres manifiestos fuera del workspace, a propósito. Lo encontró la aprobación del
diseño, no una prueba, y es exactamente la clase de defecto que una prueba sobre
este árbol habría encontrado en la primera corrida.

La regla quedó así: se deriva **una vez por raíz de resolución que la rebanada
toca, y ninguna más**. Un manifiesto que la rebanada no toca no existe para ella.

| La rebanada toca | Raíces | Los demás manifiestos |
|---|---|---|
| solo un miembro del workspace | **una**: la raíz, con su lockfile | los otros no se derivan **ni se rechazan** |
| un miembro **y** el paquete que no es miembro | **dos** | el del fixture sigue sin tocarse |
| nada que cuelgue de un manifiesto | **cero**, y derivado igual | el testigo lleva la toolchain aunque no haya nada que medir |

«Derivar todas las raíces» parecía la salida obvia y se midió: resolver el
fixture de Flutter **funciona en esta máquina**, porque acá la herramienta vive
dentro del SDK de Flutter. En el runner, con un SDK puro, fallaría. Derivar
raíces que nadie necesita es pagar ese riesgo por nada.

Las raíces se calculan **sin resolver nada**, como función pura sobre rutas y
manifiestos, y su prueba usa un fixture con **la forma exacta de este
repositorio**. Un fixture de un solo manifiesto no habría encontrado nada.

### Derivar dos veces rechaza la segunda, y está declarado

El rechazo por «el árbol versiona lo que la derivación genera» mira **el disco**,
que es lo único que el plugin puede mirar: no conoce `git` y no debe conocerlo.
Después de derivar, ese disco ya tiene lo generado, así que una segunda llamada
sobre el mismo candidato lo rechaza — y tiene razón según lo que puede ver.

Es una precondición del puerto, escrita ahí y con su prueba, en vez de algo que
alguien descubra en producción. Quien recomponga una corrida prepara un candidato
nuevo, que es lo que el candidato hace con su raíz temporal.

### La lista blanca, y la identidad capturada

Hasta acá, **todo subproceso heredaba el entorno del padre**. Con eso el token de
la forja llegaba a toda herramienta que lanzáramos y a todo lo que esa
herramienta lanzara, y un `GIT_DIR` en el shell del usuario podía corromper
nuestras operaciones sin que nada lo notara. Los dos están medidos.

Una lista negra promete solo sobre lo que alguien enumeró: la variable secreta que
alguien agregue el mes que viene se filtra sola. Así que el entorno se arma con
una **lista blanca** —`PATH`, `HOME`, `PUB_CACHE`— más lo que cada invocación
declara necesitar.

Y con eso se pierde algo que hace falta: **`HOME` no alcanza para la identidad
del autor**. La primera versión del diseño decía que sí, y se había medido en una
máquina donde la identidad vive en `~/.gitconfig`. Con la identidad configurada
**solo** por XDG, `git` no falla: **fabrica** un autor con el usuario del sistema
y el hostname. Agregar `XDG_CONFIG_HOME` a la lista tampoco cierra el caso,
porque `git` admite además `GIT_CONFIG_GLOBAL`: enumerar por dónde `git` puede
leer su configuración es la misma carrera que una lista negra.

Entonces la identidad **se captura**, una vez, con el entorno del padre, y viaja
como `GIT_AUTHOR_*`/`GIT_COMMITTER_*`. Esa captura es **la única excepción** a la
regla, y está declarada con su motivo y **contada**: el check admite exactamente
un lanzamiento sin sanear en esa biblioteca, y un `part` que le agregue otro es
rojo.

Además va `user.useConfigOnly=true` en **los dos** caminos que commitean, no solo
en el del candidato: el otro usa `git commit` y tenía el mismo agujero. Sin esa
opción, `git` no falla cuando no encuentra identidad — inventa una. Es la
diferencia entre un fallo y un dato falso, y dos caminos que escriben en el
historial no pueden tener garantías distintas según por dónde se entre.

### La regla comprueba semántica, no forma

La primera versión del diseño proponía exigir que existieran `environment:` e
`includeParentEnvironment: false`. Eso lo cumple al pie esto, que filtra cero:

```dart
Process.run(exe, args,
    environment: Platform.environment,   // ← cumple la regla
    includeParentEnvironment: false);    // ← y no sanea nada
```

Así que lo que la regla exige es que la expresión de `environment:` **sea una
llamada a la función de saneamiento**, derivado del árbol sintáctico, en los tres
lanzadores. Y la excepción mira el **ámbito completo**, no el nivel más interno:
el lanzamiento exceptuado vive en una función local del método declarado, y mirar
solo lo de adentro leía el ayudante donde la declaración dice el método.

El propio check encontró dos cosas al instalarse: que la declaración nombraba un
método que yo había renombrado —y lo dijo en los dos sentidos, el lanzamiento
fuera del ámbito **y** la declaración sin nada que exceptuar— y que este README
afirmaba una cuenta de sabotajes que ya no era la del arnés.

**Y le faltaba la mitad del trabajo**, que encontró una revisión: comparaba el
**nombre** `entornoSaneado` sobre un árbol sin resolver. Una función local
llamada igual, que devolvía el entorno del padre intacto, pasaba en verde — y el
check anunciaba siete lanzamientos saneados. Comparar nombres es comprobar
sintaxis, que es exactamente lo que este control existe para no hacer.

Ahora el árbol se **resuelve** y se compara la identidad: la función tiene que
venir de `core`, y el lanzamiento, de la biblioteca de entrada y salida del SDK.
**No poder resolver un archivo es rojo**: no saber no es no tener lanzamientos.

**Y una segunda revisión encontró que eso todavía no alcanzaba.** La resolución
era correcta, pero antes había dos filtros sintácticos que decidían **qué
mirar**, y los dos se esquivaban con sintaxis corriente que el formateador deja
intacta:

| Forma | Por qué se escapaba |
|---|---|
| un comentario entre la clase y el punto | el prefiltro buscaba una cadena de texto en el archivo, y el comentario la parte: **el archivo ni se resolvía** |
| la clase a través del prefijo de una importación | el destino escrito no es el nombre de la clase, y el visitante salía antes de mirar el símbolo |

Las dos terminaban con código 0 **sin contar siquiera el lanzamiento**. No son
residuos declarables: son sintaxis ordinaria, y el invariante afirma cubrir
**todo** lanzamiento.

La corrección es dejar de mirar texto en los dos lados. El prefiltro pasa a ser
**estructural** —cualquier invocación de un método con uno de los tres nombres,
sobre cualquier destino— y la identificación la hace el elemento resuelto: **de
qué clase y de qué biblioteca es el método que se invoca**. Las cinco formas son
sabotajes permanentes.

Queda un **falso positivo deliberado**: una clase propia que se llame igual que
la que lanza se reporta igual, porque ahí el control no puede decir qué corre.
Su precio es renombrarla; el de la alternativa es no ver un lanzamiento envuelto
en un homónimo.

### La toolchain que no dice su versión no identifica nada

Otro hallazgo de la misma revisión. La atestación comprobaba solo la
**terminación** del proceso, no su código de salida ni su salida real, así que
dos casos producían un entorno «derivado»: la herramienta saliendo con código
distinto de cero, y la herramienta **muda**.

El segundo es el peor. El texto que se arma para poder citar un proceso mudo
—«sin salida; código 0»— terminaba **siendo la identidad de la toolchain**: una
cadena nuestra satisfaciendo al constructor que existe para rechazar exactamente
eso. Ahora la identidad es lo que la herramienta dijo, y si no dijo nada hay un
aborto con su causa propia, no una identidad fabricada.

### La prueba decisiva

Un error inyectado **solo en el candidato**: la cascada da rojo, los diagnósticos
apuntan al candidato, el árbol del usuario queda byte a byte igual y sin nada
generado, y el candidato sigue íntegro después. Y una alteración **después** de la
cascada hace la corrida no concluyente aunque la cascada haya dado rojo: no se
puede afirmar ni eso sobre un árbol que dejó de ser el que se fijó.

Sobre este árbol, derivar tarda unos 200 ms y el control de integridad unas
decenas. **El techo es la aserción; la cifra, el dato**: cuánto cuestan en un
monorepo sigue siendo una pregunta abierta, y esto la acota en vez de contestarla.

### Lo que esta rebanada NO hace

- **No hay coordinador productivo.** La cascada deriva su estado del desenlace de
  los pasos y no tiene dónde meter «el entorno no se pudo derivar». La
  composición —preparar, derivar, comprobar, cascada, comprobar— vive en una
  prueba de `cli`, que es el único paquete que ve `vcs` y el plugin a la vez. Va
  declarado en `arquitectura.json` y en la tabla de puertos de más arriba.
- **No hay implementación falsa del puerto**, y por el mismo motivo que
  `ChangeSink` no la tiene: sin etapa que lo consuma, una suite de contrato con
  una sola implementación corre la misma lógica dos veces.
- **Windows queda rechazado, no pendiente.** Ahí `Process.start` no usa el `PATH`
  del mapa de entorno para resolver el ejecutable, así que un entorno saneado no
  gobierna qué binario corre; y el cache de paquetes no se deriva de `HOME`. No se
  pudo ejecutar acá, así que la fuente es secundaria y va marcada — pero la
  decisión sí se toma, en vez de dejarla como una pregunta que alguien lea como
  «probablemente funcione».
- Tampoco: el comando de envío, la forja, el presupuesto de corrida ni el
  corte temprano. **La superficie de verificación y el artefacto de revisión
  estaban en esta lista y ya no**: los construye la rebanada siguiente, que
  empieza acá abajo. Lo que sí sigue faltando de ellos está en su propia lista,
  al final de esa sección.

## La superficie de verificación

Todo lo anterior produce diagnósticos, testigos y un veredicto por paso. Nada de
eso le dice a un revisor humano **qué puede saltear con seguridad y qué
requiere que mire**. Esta rebanada deriva esa respuesta de una corrida entera
—entorno, integridad, cascada— en vez de dejar que cada quien la infiera del
resultado crudo, con una regla que gobierna todo lo demás: nada entra en
«cubierto» si no hay un control que lo sostenga.

### Cubierto habilita a saltar, así que se restringe por construcción

Un sujeto que aparece en `cubierto` le dice al revisor «no hace falta que
mires esto». Ese permiso es el más caro que existe en un arnés de
verificación, así que `AfirmacionCubierta` no tiene un constructor público:
la única entrada es la fábrica `desde`, y arma el objeto o devuelve nulo, sin
un tercer camino. Quien compone una corrida no puede ensamblar una afirmación
cubierta con cualquier afirmación y cualquier testigo — solo puede pedirle a
la fábrica que decida.

**Y eso es un residuo declarado, no fingido.** Que `desde` sea la única
entrada lo sostiene el código fuente, no una prueba de este repositorio: desde
afuera del paquete no hay manera de comprobar que no exista otro constructor
público, porque Dart no tiene reflexión sin una biblioteca que `core` tiene
prohibida. Una prueba que afirmara vigilar eso no podría fallar por lo que
dice mirar, así que no se escribe ninguna — es exactamente el guardia que no
se puede poner rojo del que habla el resto de este documento, y se prefiere
declararlo a fingir un control que no puede mirar.

### Un control que encontró algo no cubre ninguno de sus sujetos, y está medido

`AfirmacionCubierta.desde` niega la afirmación con **tres** condiciones —tres
`if`, tres ramas de código—: el desenlace no es `Executed`, el desenlace trae
**algún diagnóstico**, o el testigo no incluye al sujeto pedido. Y el hallazgo
se rechaza por completo —no solo el sujeto del diagnóstico— porque está medido
que el veredicto es global al paso y que un diagnóstico no tiene relación
validada con un sujeto del testigo: no se sabe cuál lo originó.

Hay una cuarta comprobación, y **no está en la fábrica**: el testigo tiene que
cubrir al sujeto vale también para la reconstrucción desde un documento, así
que es un invariante del tipo y vive en el cuerpo de su constructor. Desde
`desde` no puede dispararse —ahí la misma condición devuelve nulo, que es lo
que la derivación necesita—; desde `AfirmacionCubierta.fromJson` sí, y ahí
estaba el agujero que encontró una revisión: un documento con el sujeto
cambiado por uno que el testigo no nombra se deserializaba sin chistar.
`fromJson` **revalida lo comprobable y declara el resto**: la pertenencia del
sujeto al testigo está entera en el documento, y la correspondencia entre la
afirmación, el id y el control que los declara no, porque un documento no
lleva el control.

**La segunda condición decía «el veredicto es rojo», y así se escapaba un
hallazgo entero de la superficie.** `Executed.verdict` solo mira los
diagnósticos que bloquean, así que un paso que reportó un informativo salía
**verde** y sus sujetos quedaban cubiertos: `estado: verde · cubierto: 1 ·
criterio: 0` para una corrida donde el arnés sí había encontrado algo. Es
alcanzable desde una corrida real —un informativo del analizador se normaliza
a la severidad que solo reporta—, y la superficie le decía al revisor que podía
saltear ese sujeto. Lo cerró la revisión final de la rama, extendiendo la regla
que ya estaba en vez de agregar una tercera rama: **cualquier** diagnóstico,
bloqueante o no, deja el paso sin cobertura y manda todos sus sujetos a
criterio con el motivo `hallazgo`. El argumento es el mismo que ya sostenía el
rechazo del rojo y no depende de la severidad: con un informativo tampoco se
sabe cuál sujeto lo originó, y dejar un sujeto cubierto **y** en criterio sería
contradictorio para quien está decidiendo si mirarlo.

El chequeo del veredicto **desapareció en vez de acumularse**, porque el nuevo
lo subsume: `rojo` exige un diagnóstico que bloquea —y eso es un diagnóstico—,
y `noConcluyente` exige un testigo sin sujetos, que la tercera condición ya
rechaza. Dejarlo habría sido una condición incapaz de decidir nada: otro
guardia que no se puede poner rojo.

### Qué ata la firma de `desde`, y qué no

Este documento decía que `desde` hacía imposible combinar un control con el
testigo de otro, y **era falso**: una revisión lo rompió en tres líneas,
pasándole el control de un paso junto al desenlace de otro. Lo que la firma sí
garantiza es que la afirmación y el id salen **del control que se le pasa**, y
el testigo **del desenlace que se le pasa**: quien llama no puede sustituir
ninguno de los dos por el de otro objeto. Lo que no garantiza es que ese
control y ese desenlace sean de un mismo paso, porque son dos parámetros
independientes.

**No se cierra en la firma a propósito.** Atarlos pediría que el desenlace
supiera qué control lo produjo, y ADR-019 decidió lo contrario: el desenlace no
lleva el id del paso. Quien empareja control con desenlace es
`derivarSuperficie`, y ahí sí se comprueba contra el registro de la corrida:
lee el desenlace por el id del paso registrado, exige que el mapa de controles
tenga ese id y que el control declare ese mismo id, y lanza si alguna de las
dos falla —las dos comprobaciones tienen su prueba—. La procedencia depende de
que el llamador sea correcto, y eso queda **declarado** en vez de prometido
como si lo sostuviera el tipo: es el mismo criterio con el que esta rebanada ya
declara el residuo de `desde` como única entrada.

### Y un candidato alterado tampoco

Una alteración del candidato no dice cuál de los dos árboles vio cada control
—el que se fijó o el que quedó después—, así que ningún sujeto se puede dar
por cubierto aunque la cascada haya corrido entera y en verde. `derivarSuperficie`
decide esto **antes** de mirar la cascada: con alteraciones, todo lo que la
cascada haya afirmado queda como criterio, nunca como cobertura. Es el mismo
argumento que el control con hallazgos, aplicado al árbol en vez de al paso.

**Pero decidir la cobertura antes no es dejar de leer el resto.** Ese camino
devolvía temprano, sin procesar los desenlaces ni la partición del alcance: con
una alteración, una corrida donde además se rompió el instrumento, había un
sujeto ajeno al stack y otro que no se pudo mirar salía con un único motivo
—`candidatoAlterado`— y los otros tres hechos desaparecían. Hoy vacía
`cubierto`, fija el estado en no concluyente y **sigue**: los fallos, las
omisiones, los ajenos y los no observables son hechos independientes de la
alteración, y un revisor que no los ve no sabe que están.

Y **la alteración se nombra aunque el entorno se haya caído antes**. Ese camino
devuelve temprano —sin entorno no hay cascada de la cual derivar nada— y durante
un tiempo no leyó las alteraciones en absoluto: la superficie salía diciendo
solo que el entorno no se pudo derivar, y el hecho más alarmante que una corrida
puede producir desaparecía. Pasó inadvertido porque ese camino ya publicaba
`cubierto` vacío, así que nada se estaba autorizando de más — pero **vaciar
«cubierto» y no nombrar el hecho son cosas distintas**, y la segunda deja a un
revisor sin saber que el árbol cambió.

### El control declara su afirmación, y su límite

`Verifier` expone `afirmacion`, no un registro aparte: lo que un control
demuestra cuando ejecuta limpio lo declara el propio control, en el puerto.
`Afirmacion` exige un límite —`noDemuestra`— tan obligatorio como lo que sí
demuestra, y ninguno de sus tres campos acepta blanco. Sin ese límite, una
afirmación le diría al revisor que se saltee algo sin decirle qué queda sin
verificar, que es el peor fallo que este repositorio ya se cuidó de nombrar en
otro lado.

### Tres entradas, no una

`derivarSuperficie` no deriva solo de la cascada: toma el desenlace del
entorno, las alteraciones del candidato y el resultado de la cascada —que
puede faltar—, porque los dos primeros son hechos que la cascada no conoce y
que igual vuelven la corrida no concluyente. Derivar solo de la cascada
publicaba «cubierto» sobre un árbol alterado, el peor fallo que ADR-016
nombra.

La derivación **también lee la partición del alcance** —`cascada.alcance`—, no
solo los desenlaces por paso. Una revisión encontró que sin eso un sujeto ajeno
al stack quedaba invisible para el revisor: ni cubierto ni en criterio, que se
lee como «nada que mirar» sobre algo que sí se pidió. Y un sujeto no observable
mezclado con uno verde hacía reventar el invariante de `SuperficieDeVerificacion`
—no verde, cubierto no vacío, criterio vacío—, porque los desenlaces
`Skipped` y `Unobservable` solo aparecen cuando **ningún** sujeto es
utilizable: en cuanto hay uno solo utilizable, todos los pasos ejecutan y
ningún desenlace nombra a los sujetos ajenos o no observables que quedaron
afuera. Leer la partición directamente es lo único que los vuelve a nombrar.

### Invalidar la cobertura nunca justifica perder una señal

Es la regla que gobierna la derivación entera, y se escribió cuatro veces
porque cuatro veces se había aplicado a un camino en vez de a la regla: **vaciar
`cubierto` y no nombrar el hecho son cosas distintas**. `requiereCriterio` es la
mitad que existe para nombrar todo lo que un humano SÍ tiene que mirar, así que
un hecho que la derivación pudo ver no se descarta porque otro haya salido
primero. Lo que un camino decide es qué se vacía, no qué se nombra.

- **Un hallazgo sin cobertura sigue siendo un hallazgo.** Las entradas de
  `hallazgo` se emitían recorriendo los sujetos del testigo, así que un control
  con diagnósticos y sin ningún sujeto certificado no emitía ninguna. No es un
  caso de laboratorio: el formateador sobre un archivo que no parsea informa
  que no miró ningún archivo y reporta los errores de parseo, y la superficie
  publicaba el residuo y la obligación abierta **sin decir en ningún lado que
  el control había encontrado errores**. Hoy emite una entrada **sin sujeto**,
  con el control y cuántos diagnósticos hubo, diciendo que no se pudieron
  atribuir. Sin conceder cobertura, obviamente.
- **Una cascada que existe con el registro vacío no es una cascada nula.**
  `Cascada([]).correr(…)` observa el alcance, no registra ningún paso y sale con
  la causa `sinVerificadores`. La derivación contemplaba `cascada == null` y no
  esto: los bucles por paso no tienen sobre qué iterar y el libro de
  obligaciones está vacío porque no hay control que las contraiga, así que el
  revisor recibía el estado no concluyente **sin su explicación**. Hoy se nombra
  que nadie verificó ese alcance, y las observaciones de ese mismo alcance
  —ajenos, no observables— se siguen nombrando igual.

### Lo que esta rebanada NO hace

- **No hay `ship`.** Nada arma la solicitud que un humano aprueba; esta
  rebanada produce el material que esa composición futura necesitaría.
- **No hay forja.** El artefacto no se publica en ningún lado — se deriva y
  queda en memoria de quien lo pidió.
- **No hay composición.** `ArtefactoDeRevision` es un tipo con su fábrica
  validante y nada más: nadie lo arma todavía a partir de una corrida real de
  `shipflow verify`. Es un tipo sin productor, y eso va declarado en vez de
  quedar como un hueco sin nombrar.
- **`derivarSuperficie` no tiene llamador.** Sale con su derivación completa y
  probada motivo por motivo, y **cero invocaciones fuera de sus pruebas**:
  ningún comando la corre, así que ninguna corrida de `shipflow verify` produce
  hoy una superficie. Lo que arriba se describe en presente —«toma el desenlace
  del entorno, las alteraciones y el resultado de la cascada»— es lo que la
  función hace cuando se la llama, no algo que esté pasando en una corrida. El
  llamador llega con la etapa que la use, y es la misma que necesita el
  artefacto.
- **`Verifier.afirmacion` no lo lee ningún camino productivo.** El miembro está
  en el puerto y los dos pasos reales lo declaran, pero el único que lo lee es
  `AfirmacionCubierta.desde`, y a ese solo lo llama `derivarSuperficie`. Un
  puerto que crece un miembro que nadie consume se lee como capacidad; queda
  escrito que todavía no lo es.

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
`Verifier` ni siquiera recibe los sujetos ajenos —le llega un
`VerificationScope`, que solo tiene lo utilizable y su conteo—, así que
estructuralmente no tiene sobre qué declararse incompetente.

> **Esta frase fue falsa durante un arreglo, y así se encontró el quinto falso
> verde.** Para que el árbol se observara una sola vez por corrida, `run` pasó
> a recibir la `ScopeObservation` entera: la lectura se arregló y el
> *estructuralmente* de arriba dejó de ser cierto sin que nadie tocara el
> texto. Con la observación completa a mano, un paso que escriba `requested`
> donde quería `usable()` certifica un ajeno, y el libro de obligaciones —que
> solo mira lo que FALTA— lo daba por bueno: alcance esperado `[lib]`, testigo
> `[lib, README.md]`, verde. Lo encontró un review, reproducido.
>
> Se cerró por las dos vías, porque una sola no alcanza. `VerificationScope`
> hace que el ajeno no llegue, y `ResultadoDeCascada` rechaza un testigo que
> certifique u omita fuera del alcance esperado del paso —lo segundo atrapa al
> que invente un sujeto, que el tipo estrecho no puede impedir—.

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

El primero, `C3 · cubrir la mitad sin explicar el resto no da verde`, vive en
`packages/cli/test/verify_test.dart`, grupo «los ataques que antes
funcionaban» —la suite de la cascada tiene el mismo caso con otro nombre:
`un paso que cubre un subconjunto SIN explicar el resto no da verde`, en su
grupo «el libro de obligaciones»—. Los otros dos sí viven en
`packages/orchestration/test/cascada_test.dart`: `un alcance esperado más
CHICO que lo utilizable no se deja construir`, en el grupo «el invariante del
alcance esperado», y `un Skipped no puede declarar ajeno a un sujeto que la
observación no dio como tal — antes daba VERDE`, en el grupo «el desenlace no
puede contradecir a la observación».

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

## La forja y el aislamiento de la credencial

Le da a `ship` —que todavía no existe— dos cosas que necesita antes de poder
publicar algo: un desenlace tipado para lo que le pasa a un pull request, y la
garantía de que el token que lo abre no se filtra por ningún subproceso que
este repositorio lance en el camino.

### El token sale del entorno en un solo sitio, y por tipo

`EntornoDelProceso` (`packages/core/lib/src/entorno.dart`) captura el mapa del
proceso una sola vez, en la raíz de composición, y expone `paraHijos`: un
derivado que nunca lleva las claves de `clavesDeCredencial`. Antes de esta
rebanada cada costura que lanzaba un subproceso tenía que acordarse de excluir
el token por su cuenta —una lista negra repetida en cada lanzador—; ahora
`RepositorioGit` (en `vcs`) y `EmpujeAislado` (en `forge`) reciben
`EntornoDelProceso` en vez de un `Map` crudo, así que lo que baja hacia
`entornoSaneado(...)` ya pasó por `paraHijos` antes de que el lanzamiento
exista. El candidato de `vcs` no tiene un campo propio de ese tipo —guarda un
`RepositorioGit` y llega al entorno saneado a través suyo—, así que la
garantía le alcanza indirecta, no como tercer receptor directo. **El tipo es
el control**, no una convención que cada lector tiene que recordar.

Eso alcanza también al único lanzamiento que `subprocesos-con-entorno-saneado`
exceptúa: `_identidadComoEntorno`, en `RepositorioGit`, corre `git config --get`
con el entorno del padre sin sanear —porque necesita ver `XDG_CONFIG_HOME` y
`GIT_CONFIG_GLOBAL`, que la lista blanca no lleva a propósito—. Antes de esta
rebanada esa excepción se sostenía porque no había nada secreto en el entorno
que ver; ahora que sí lo hay, la excepción sigue admitiendo un único
lanzamiento sin sanear en esa biblioteca —el arnés lo cuenta y un segundo es
rojo—, pero el entero que recibe ya es el que entregó `EntornoDelProceso`, así
que tampoco puede traer el token: la garantía la sostiene el tipo, no una
revisión manual de cada excepción.

### El push no le entrega el token a ningún programa del usuario

`EmpujeAislado` (`packages/forge/lib/src/empuje.dart`) lanza su propio
`git push` con dos `-c`: `core.hooksPath` apuntado a un directorio temporal
vacío —que frena todos los ganchos del usuario— y `credential.helper=`, que
resetea la cadena de helpers **entera**, no solo la que este repositorio
configuró. Medido: sin el segundo, el helper del usuario corre igual —dos
veces— y ve el entorno completo, aunque `core.hooksPath` ya esté puesto; los
dos mecanismos gobiernan superficies distintas y hace falta vaciar las dos. La
credencial viaja en el `userinfo` de la URL de destino, de un solo uso, nunca
en el entorno del proceso.

**El `push` produce un desenlace o se muere en el intento: no se cuelga.**
`Process.run` sin límite espera a que el hijo salga, y `git push` puede no
salir nunca —un remoto que acepta la conexión y deja de contestar, un `git`
trabado—: ese flujo no producía **ningún** desenlace, que es lo contrario del
invariante de que el desenlace se declara. Ahora el lanzamiento es
`Process.start` con un presupuesto de **dos minutos**, y son cuatro cosas y no
una: se drenan `stdout` y `stderr` desde el arranque —un hijo que llena la
tubería se bloquea escribiendo, y entonces el presupuesto se dispararía por un
cuelgue que causamos nosotros—, al vencer se manda `SIGKILL` y se espera la
muerte **del proceso que lanzamos** —que no queda huérfano, y hay una prueba
que lo comprueba consultando su PID; lo que ese proceso haya lanzado a su vez
sobrevive, y está declarado más abajo entre los residuos—, y el desenlace es
`PushUnknown`: al interrumpirlo se pierde quien sabía cómo terminó, y el
packfile puede haber llegado entero.

El drenaje **posterior** a la salida también tiene presupuesto, y al vencer
**suelta la tubería en vez de abandonarla**. La distinción no es de estilo y
está medida: `Future.timeout` abandona el futuro pero **no cancela la
suscripción**, así que con un `join()` el descriptor queda abierto y
escuchado, y un proceso con una suscripción viva no termina —`shipflow` fija
`exitCode` y vuelve de `main` a propósito, en vez de llamar a `exit`—. Con un
programa que deja un nieto durmiendo 20 s con la tubería heredada y un
presupuesto de 300 ms: **el desenlace se computa a los 322 ms en las dos
formas**, pero el proceso termina a los **20,2 s** abandonando el futuro y a
los **0,8 s** cancelando la suscripción. En producción ese nieto es el
ayudante de transporte de `git` sobre una conexión muerta, o sea sin cota. Lo
que se pierde al soltar es el final del texto con el que se clasifica la
causa, que degrada a `desconocida` —un reintento de más— y nunca a una
publicación que se lea como completa; el texto ya leído se conserva.

Se espera **un solo** flujo, `stderr`, que es el único que alguien lee: la
causa sale de ahí. `stdout` se drena mientras el proceso corre —para que no se
bloquee escribiendo— y se suelta sin esperarlo cuando termina, así que no
agrega una tercera espera por un texto que nadie mira. Y el `stdin` del hijo
se cierra tras el lanzamiento, que es lo que `Process.run` hacía solo: sin
eso, un `git` que leyera de ahí dejaba de fallar al instante y pasaba a
colgarse hasta agotar el presupuesto.

Dos
minutos, y no treinta segundos como los pedidos de la API, porque un `push` no
es un pedido y una respuesta sino una negociación más la subida de un
packfile; y no más, porque el presupuesto de la corrida entera se mide en
minutos.

**Y no poder lanzar `git` es un fallo con nombre, no un efecto remoto
desconocido.** Si `Process.start` no consigue el proceso, no hubo nada capaz de
hablar con el remoto: el desenlace es `PushFailed` y no `PushUnknown`, que
mandaba a buscar allá un efecto que no pudo ocurrir. Y la causa es
`noSePudoLanzar`, no `desconocida`: ese `catch` sigue sin mirar la excepción
—`ProcessException.arguments` lleva la URL con la credencial adentro y su
`toString()` la interpola verbatim—, pero **no leer la excepción no es no
saber**: qué rama corrió es información propia del código, no del texto de la
excepción, así que nombrar el hecho no arriesga un byte del secreto. Decirle
«no se pudo determinar la causa» a alguien que no tiene `git` en el `PATH` es
falso y no deja nada que mirar. Es reintentable, a diferencia de
`revisionInvalida`: un `fork` que falló por recursos puede andar en el próximo
intento.

**Y los dos canales que llevan la credencial exigen `https`, validado.** El
`userinfo` del `git push` y el `Authorization: Bearer` del cliente de la API
salen los dos de una URL que produce la raíz de composición —que no existe
todavía—, y con `http://` el token viaja en claro por los dos.
`esCanalSeguroParaLaCredencial` (`packages/forge/lib/src/empuje.dart`) lo
rechaza **antes** de adjuntar nada, con un desenlace cerrado —`PushFailed` con
causa `configuracionInsegura`, que no es reintentable y no nombra la URL
rechazada— y no con una excepción que se escape del puerto. La causa es propia
y no `autenticacion` a propósito: decir «la credencial no fue aceptada» sobre
un token que nunca salió del proceso le reporta al usuario un problema de su
token cuando el problema es de la configuración. **Excepción decidida y
declarada:** `http` sobre loopback (`127.0.0.0/8`, `::1`, `localhost`) se
acepta —no sale de la máquina, y exigirle TLS obligaría a cada suite que
levanta un `HttpServer` local a montar un certificado propio, con lo que el
control terminaría probándose contra un montaje que no es el de producción.

### Ningún redirect se lleva la credencial, y el SDK no alcanzaba

Los dos pedidos a la API salían con `followRedirects` en su valor por omisión
—`true`—, así que un `3xx` lo seguía el cliente por su cuenta, con el
`Authorization` puesto y hacia el destino que eligiera el `Location`. Una
revisión anterior dio ese camino por seguro porque la biblioteca de entrada y
salida no copia el `authorization` cuando el redirect cambia de esquema, host o
puerto. **Eso es incompleto, y la diferencia es exactamente el agujero:**
`_HttpClient.shouldCopyHeaderOnRedirect`, en `lib/_http/http_impl.dart` del SDK
de Dart 3.12.0, copia **todos** los encabezados cuando `_isSubdomain(destino,
origen)` da verdadero, y esa función acepta cualquier host que **termine en `.`
más el host del origen**. Reproducido con la API servida en `http://localhost` y un
redirect hacia `http://sub.localhost`, con el mismo esquema y el mismo puerto.
El código fue `302` para el `GET` y `303` para el `POST` —el único que el SDK
sigue para ese método—, y el segundo destino recibió
`Authorization: Bearer <secreto>` en los dos.

Ahora `followRedirects` se apaga **en la misma función que adjunta la
credencial y antes de adjuntarla**, que es la única forma de que no exista un
pedido autenticado y seguidor a la vez; ponerlo en cada sitio de llamada sería
una disciplina que el próximo pedido puede olvidar. El `3xx` se trata como
respuesta fallida: en la búsqueda cae en «no es 200», o sea búsqueda
incompleta, que no autoriza a crear; en la creación tiene rama propia y es
`PullRequestUnknown`, porque un `303 See Other` es la forma documentada de
contestar «lo creé, mirá allá» y decir `failed` haría que el reintento abriera
un segundo pull request. Tampoco se sigue a mano: se podría, validando esquema,
host y puerto exactos, pero un redirect dentro del mismo origen no agrega nada
que esta API necesite —sus dos URLs salen de `baseDeLaApi`— y cada camino que
reintenta con la credencial adjunta es un camino más donde revalidar. La
comparación de origen que sí existe —la del encabezado `Link` de la
paginación— es por igualdad de los tres componentes, o sea que un **subdominio
no es el mismo origen**: es justo donde la regla del SDK se queda corta.

### El desenlace de publicar es una jerarquía sellada, no dos enums que se puedan combinar mal

`PublicationOutcome` (`packages/core/lib/src/publicacion.dart`) reemplaza lo
que hubieran sido dos enums independientes —uno para el `push`, otro para el
pull request— porque ese par admite el producto cartesiano: `push: failed,
pullRequest: succeeded` no significa nada, y `succeeded` a secas no
distinguía un PR abierto de uno fusionado o de uno cerrado. Son **siete
variantes**: `PullRequestOpen`, `PullRequestMerged` (utilizables),
`PullRequestClosed`, `PushFailed`, `PushUnknown`, `PullRequestFailed` y
`PullRequestUnknown` (no utilizables). `retryable`, `deliveryStatus` y
`nextAction` no son campos: se derivan de la variante y, en las que fallan, de
`CausaDePublicacion`. `safeReason` nunca copia la excepción externa —que puede
traer el secreto adentro—, porque sale de esa causa cerrada.

`unknown` no es un lujo: sin distinguir «falló» de «no sé si llegó», una
respuesta perdida se reporta como `failed` y un reintento crea un segundo PR.
La búsqueda idempotente de `SalidaDePrDeGitHub` —por revisión, rama base y el
marcador estable que `cuerpo.dart` también usa para renderizar— es lo que le
permite a un reintento después de `unknown` encontrar el PR que sí se llegó a
crear, en vez de abrir otro. **Mientras el reintento traiga el mismo `runId`:**
el marcador lo lleva adentro, así que un reintento con un `runId` nuevo no
encuentra el PR de la corrida anterior y abre uno segundo. Quien componga el
reintento tiene que reusar el `runId` de la corrida que quedó en `unknown` —es
de la rebanada de `ship`— y esa atadura hoy no la sostiene ningún control.

### Una revisión que no es un OID no llega a ser un refspec

`EmpujeAislado` arma `<revisión>:refs/heads/<rama>` y se lo pasa a `git push`.
Con la revisión vacía eso queda `:refs/heads/<rama>`, que es la forma
documentada de **eliminar** esa rama del remoto: una solicitud mal compuesta no
publicaba de más, borraba. `PullRequestRequest` validaba la relación de la
revisión con el árbol y no la revisión misma, así que `revision: ''` se
construía sin una queja.

Ahora lo exigen **las dos fronteras**, y no es una duplicación: `esOidCompleto`
(`packages/core/lib/src/publicacion.dart`) es un invariante de construcción en
el dominio —el constructor lanza— y una precondición de ejecución en el
adapter —`empujar` devuelve `PushFailed` con causa `revisionInvalida`, un
desenlace cerrado y no una excepción, **antes de lanzar ningún proceso**—. La
frontera del proceso no puede confiar en que su llamador validó: `empujar` es
público y recibe la revisión como parámetro suelto.

Los dos largos están **medidos, no supuestos**, con `git rev-parse HEAD` sobre
repositorios recién creados con git 2.50.1: **40** caracteres hexadecimales con
`--object-format=sha1`, **64** con `--object-format=sha256`. Las dos familias
se aceptan porque el repositorio puede ser de cualquiera de las dos, y también
las mayúsculas: medido con `git cat-file -t`, git resuelve el mismo objeto, así
que rechazarlas sería afirmar que un OID válido no lo es.

**Y aceptar dos escrituras no es dejarlas circular: la revisión se canonicaliza
a minúsculas en la frontera del dominio.** El defecto está reproducido: con la
solicitud trayendo el OID en mayúsculas y el pull request que ya existía
teniéndolo en minúsculas, la búsqueda idempotente —que comparaba literal contra
el `sha` de la forja— no lo encontraba y salía a crear un SEGUNDO pull request,
que es lo único que esa búsqueda existe para impedir. `PullRequestRequest`
guarda la forma canónica, así que las tres cosas que se derivan de la revisión
—la comparación con lo que devuelve la forja, el marcador estable del cuerpo y
el refspec del push— usan **una sola** representación. El `sha` que llega en la
respuesta es un dato ajeno y se lee a esa misma forma antes de comparar: que la
forja de hoy lo mande en minúsculas es su costumbre, no un contrato que este
cliente pueda exigir.

### La búsqueda idempotente mira todas las páginas, y lee el código antes que el cuerpo

Dos defectos que se sostenían el uno al otro. **Uno:** la búsqueda no miraba el
código de estado y le pasaba cualquier cuerpo a `jsonDecode(...) as
List<Object?>`. Un `401` de la forja trae un objeto, el cast fallaba, y el
`catch` exterior lo convertía en `PullRequestFailed(red)` —«la red falló» sobre
una credencial rechazada—; y como la corrida se detenía ahí, la clasificación
correcta del `401` del POST era prácticamente inalcanzable: estaba escrita y no
la ejercía ninguna corrida. Ahora el código se clasifica **antes** de decodificar
—`401` es `autenticacion`, `403` es `permisos`, `422` es `rechazoDeLaForja`— y
por el **mismo** clasificador que usa la creación, así que la coherencia entre
los dos pedidos dejó de ser una promesa de dos `switch` parecidos.

**Dos:** la búsqueda hacía **una sola** petición. La forja pagina esa operación
—30 por omisión, 100 como máximo— y entrega el resto por el encabezado `Link`.
Con el pull request coincidente en la segunda página, el cliente no la pedía y
seguía hasta el POST: creaba un segundo pull request, que es exactamente lo que
la búsqueda existe para impedir. Ahora pide `per_page=100` y sigue
`rel="next"` hasta encontrar o agotar, con el presupuesto de red y la
clasificación aplicados en **cada** página. Subir `per_page` no habría
alcanzado: corre el borde, no lo cierra.

Y el recorrido tiene un **tope de diez páginas, declarado con su motivo**: el
final lo decide lo que conteste el otro lado, y un `Link` que cicle haría girar
el bucle para siempre —el cuelgue que el presupuesto por pedido no cubre,
porque cada pedido contesta a tiempo—. Agotar el tope no significa «hay más de
mil pull requests para esta misma rama origen y esta misma rama base»:
significa que las páginas no se terminan, o sea que la búsqueda quedó
incompleta, y por eso el desenlace es un fallo y no «no encontré nada» —seguir
hasta la creación con la búsqueda incompleta es abrir el segundo pull request a
ciegas—. Lo mismo vale para un `Link` que apunte fuera del origen configurado:
no se sigue, porque cada página se pide con el `Authorization` puesto y el
destino lo habría elegido la respuesta y no la configuración.

### Ningún dato de la corrida puede enterrar la advertencia obligatoria

`cuerpoDeGitHub` interpolaba directo adentro del Markdown la intención, el
plan, los detalles, los sujetos y los identificadores. Reproducido con
`intent: '<!--'`: la intención abría un comentario HTML, **la advertencia y las
dos secciones obligatorias quedaban adentro**, y el comentario recién cerraba
al llegar al marcador final. O sea que un dato de la corrida enterraba
exactamente lo que ADR-016 y la decisión 7 de ADR-022 dicen que no se puede
enterrar, y el pull request se leía como si no hubiera nada que mirar.

El arreglo no son reemplazos sueltos sino **un render por contexto**, y ninguna
interpolación cruda: la neutralización es una sola —los caracteres que son
sintaxis (`&`, `<`, `>`, el acento grave y la tilde) pasan a entidades, que
GitHub decodifica al mostrar, así que el revisor lee el dato tal como vino—, y
lo que cambia es el envoltorio. Un texto de **bloque** conserva sus renglones y
se le escapa lo que abre bloque al principio de cada uno, para que un dato no
fabrique un `## Qué quedó cubierto` que nadie escribió. Un texto **dentro de un
ítem de lista** junta sus renglones en uno, porque un renglón nuevo termina el
ítem y deja al dato al mismo nivel que las secciones. Un **identificador** va
entre `<code>` y no entre acentos graves: adentro de un tramo de código las
entidades no se decodifican, y en CommonMark el HTML crudo tiene precedencia
sobre ese tramo, así que un `<!--` en un identificador y un `-->` en otro
formarían un comentario que se traga el detalle entre los dos.

**No hay canal de Markdown confiable, y el plan también se escapa.** Declararlo
por campo sería una propiedad de un `String` sostenida por prosa; el día que un
plan quiera sus viñetas, lo que tiene que declararlo es un tipo que se
construya donde alguien pueda responder por el contenido. Precio: un plan
escrito en Markdown se lee como texto plano.

Lo que la suite mide no es que el texto salga escapado —eso lo cumple cualquier
escape— sino que **la advertencia y las dos secciones se sigan leyendo**, una
vez cada una, fuera de todo comentario y de toda cerca: once campos por ocho
valores hostiles (`<!--`, `-->`, cercas de acentos y de tildes, un encabezado
que falsifica una sección, una advertencia falsificada, saltos de línea,
listas), más un control negativo que exige que el dato hostil se siga leyendo
entero.

**Y el título se trunca por runas, no por unidades UTF-16.** `String.length` y
`substring` cuentan unidades, y un emoji ocupa dos: cortar en 256 podía dejar
media pareja sustituta, que al codificarse a UTF-8 se vuelve `�` — un carácter
que la intención no tenía. No bloqueaba nada —la intención completa va en el
cuerpo—, pero era el render mostrando algo que no es el dato. **Residuo
declarado:** por runas y no por grafemas, así que un emoji compuesto —una
familia con `ZWJ`, una bandera— puede partirse en sus piezas; nunca en media
pareja. Cortar por grafemas pediría una dependencia externa, y `forge` no tiene
ninguna fuera del SDK.

### El PR no puede afirmar verificación sobre un árbol que los controles no vieron

`PullRequestRequest` exige, en su constructor, que el árbol del commit al que
apunta la rama sea el mismo que `draft.artefacto.candidato.contentRevision` —el
contenido que la superficie de verificación certificó—. `incompleto` y
`titulo` son derivados de `draft.artefacto.superficie.estado`, no campos
asignables: con dos campos independientes se puede construir `artefacto:
noConcluyente, incompleto: false`, y el título omitiría la advertencia
obligatoria de ADR-016. El render de la sintaxis de GitHub —la alerta
`> [!WARNING]`, el límite de 256 caracteres del título, el comentario HTML del
marcador— vive en `packages/forge/lib/src/cuerpo.dart`, y en ningún paquete que
otro adapter pudiera importar: lo instala `forja-en-su-adapter`.

### Residuos declarados

Veinticinco hechos que esta rebanada deja escritos porque son límites reales,
no trabajo pendiente con fecha:

- **La clasificación de la causa de un `push` fallido mira el texto del
  `stderr` de nuestro propio hijo.** Es un universo acotado por construcción
  —el mensaje lo escribe `git`, no un tercero—, y lo que el clasificador no
  reconoce cae en `desconocida`, que es reintentable: el precio de errar es un
  reintento de más, nunca una publicación que se lea como completa. **Lo que
  ese texto deja en memoria es solo la marca de qué señales pasaron**, y esas
  señales se buscan por trozo con un arrastre del largo de la más larga menos
  uno: las agujas son ASCII, así que pasar a minúsculas por trozo en vez de
  sobre la cadena entera no cambia ninguna, pero es una diferencia declarada y
  no una equivalencia que se dé por sentada.
- **`/proc/<pid>/cmdline` deja ver el argv de nuestro propio `git`** —y con él,
  la credencial en la URL— en Linux. Es limitación de ambiente, no un fallo
  propio: a diferencia de entregarle el token a un programa que el usuario
  eligió y que nosotros ejecutamos —lo que `core.hooksPath` y
  `credential.helper=` existen para impedir—, esto es el propio proceso que
  lanzamos, visible por un mecanismo del sistema operativo que no está bajo
  nuestro control.
- **El segundo criterio de `forja-en-su-adapter` es textual**: caza el nombre
  o el host de la forja como texto fuera de `packages/forge/`, y eso caza una
  regresión **literal** —alguien pegó `github.com` o `GitHub` donde no debía—,
  no una promesa equivalente escrita con otras palabras. Una mención que
  evitara esas palabras exactas no la vería.
- **La atadura entre la revisión del pull request y el árbol que vieron los
  controles es una invariante entre dos parámetros, no una verdad sobre
  git.** `core` no tiene entrada ni salida, así que el constructor de
  `PullRequestRequest` exige que el árbol que el llamador afirma sea el que
  vieron los controles, pero no puede abrir el commit para comprobarlo por su
  cuenta. Quien componga `revision` y `arbolDeLaRevision` a partir de un
  repositorio real tiene que hacer que las dos nazcan de la misma operación
  de git, y eso es trabajo de la rebanada de `ship`, no de esta.
- **La fase de conexión del `POST` no tiene prueba automatizada**, aislada de
  la del `GET`. Las dos URLs de `SalidaDePrDeGitHub` salen del mismo
  `baseDeLaApi`, y no se puede apuntar solo una a un host muerto sin cambiar
  la forma de la configuración. Se verificó a mano, contra una dirección no
  ruteable, que el `connectionTimeout` también cubre esa fase; no hay un test
  en el árbol que lo repita.
- **`CredentialSource` salió de `sin_implementacion` con una real
  —`FuenteDeEntorno`— y una falsa —`FuenteDeCredencialFalsa`— pero sin suite de
  contrato propia.** La pregunta de si le hace falta una quedó abierta:
  `FuenteDeEntorno` rechaza con `ArgumentError` una clave que
  `clavesDeCredencial` no declaró, y `FuenteDeCredencialFalsa`, configurada
  con un mapa directo, no tiene ningún equivalente. Si esa cláusula es del
  contrato del puerto o es propia de leer de un entorno de proceso real es lo
  que falta decidir antes de poder escribir esa suite.
- **El campo `"espera": "pasa"` de `violaciones_extra`, en la regla
  `forja-en-su-adapter`, es la primera vez que el JSON declarativo del arnés
  expresa un control negativo** —un caso que tiene que pasar, no fallar—.
  Antes de esta rebanada esa forma solo la tenían los casos escritos a mano en
  Python; acá cubre el fix de `_rangosDeComentarios` que hace que un comentario
  al final del archivo no se lea como código.
- **La excepción de loopback del canal de la credencial se acepta por el
  TEXTO del host, no por la dirección a la que resuelve.** `localhost` pasa
  porque se llama así; un `/etc/hosts` que lo apunte a una máquina remota haría
  viajar el token en claro y `esCanalSeguroParaLaCredencial` no lo vería.
  Resolverlo ahí significaría hacer DNS dentro de una validación sincrónica, y
  el resultado seguiría sin ser el que use el `git` que se lanza después, que
  resuelve por su cuenta al conectarse: sería una segunda resolución, no la
  misma.
- **`PushUnknown` y `PullRequestUnknown` admiten la causa
  `configuracionInsegura`, y esa combinación diría «no sé si llegó» sobre una
  credencial que nunca salió del proceso.** Hoy no la produce ningún sitio —los
  dos rechazos son `PushFailed`— y el tipo no la impide: `causa` es un getter
  de `PublicacionConCausa`, así que **toda** causa cabe en **toda** variante con
  causa. Es la misma forma que ya admitía `permisos` —un `PushUnknown` por
  permisos tampoco significa nada—, o sea un hueco previo un poco más ancho, no
  uno nuevo. Cerrarlo pide partir el enum por variante, que es un cambio de
  dominio y no de esta rebanada.
- **El ida y vuelta por JSON de `configuracionInsegura` no lo fija ninguna
  prueba.** Viaja por `name`/`byName` como cualquier otro valor del enum, así
  que funciona por construcción y no por cobertura: si alguien cambiara esa
  serialización a índices, lo cazaría la prueba «un enum viaja por nombre, no
  por índice» de `core`, que no nombra este valor en particular.
- **El peor caso del `push` es el presupuesto DOS veces, y son exactamente
  dos.** `Future.timeout` arranca su reloj cuando se lo invoca, así que las
  esperas en serie se suman: la del código de salida y la del drenaje de
  `stderr`. No hay una tercera porque `stdout` no se espera —se suelta—, que
  es la razón por la que este número dice dos y no tres. Es el mismo valor en
  las dos a propósito —es la misma pregunta, «¿esto termina?», en dos momentos
  del mismo lanzamiento— y no un segundo número que ajustar por su cuenta.
- **El presupuesto del `push` mide tiempo TOTAL del proceso, no progreso.**
  Una subida grande pero sana que pase de dos minutos se corta igual, y el
  desenlace es `PushUnknown`. Cortar por falta de progreso pediría leer el
  avance desde la salida de `git`, que es texto de progreso sin contrato — y
  de ese texto este repositorio solo deriva una causa cerrada.
- **El `SIGKILL` del vencimiento alcanza al hijo, no a sus nietos.** `git`
  lanza `git-remote-https`, y matar al proceso que lanzamos no mata lo que él
  haya lanzado: un nieto puede sobrevivir y mantener abierta la tubería. Por
  eso el camino del vencimiento espera la muerte del hijo y **no** el cierre
  de los flujos —esperar el cierre sería poner el cuelgue de vuelta un renglón
  más abajo—. Matar el grupo entero pide poner al hijo en su propio grupo de
  procesos al lanzarlo, que es un cambio de mecanismo y no un arreglo de este.
- **Un `403` de la forja también aparece por límite de tasa, y se clasifica
  como `permisos`.** Es lo que ya hacía la creación, y la coherencia entre los
  dos pedidos es lo que el clasificador único garantiza; el precio es que un
  límite de tasa se reporta como no reintentable. Separarlos pide mirar los
  encabezados de límite de tasa, que es un control nuevo.
- **El recorrido de páginas tiene un tope de diez, y agotarlo se reporta como
  fallo.** Diez páginas de a cien son mil pull requests para la misma rama
  origen y la misma rama base, que un repositorio real no alcanza: agotar el
  tope significa que las páginas no se terminan —un `Link` que cicla—, no que
  haya demasiados. El tope existe porque el presupuesto POR PEDIDO no cubre un
  bucle en el que cada pedido contesta a tiempo.
- **Perder el drenaje pierde parte de la clasificación.** Si el drenaje
  posterior a la salida se agota, se conserva el texto que ya había llegado y
  se pierde el resto; si lo perdido era la aguja, la causa cae en
  `desconocida`, que es reintentable. Es el precio elegido: un reintento de
  más antes que un cuelgue sin desenlace.
- **Lo que suelta los sockets del cliente de la API es una sola palabra:
  el `force: true` del `close` de `open`.** Todos los `.timeout(...)` de ese
  archivo abandonan lo que esperaban —un futuro abandonado no cancela la
  lectura ni cierra el socket—, así que con un extremo que manda encabezados y
  no cierra el cuerpo, `open` devuelve a tiempo y el proceso queda vivo con el
  socket abierto. Medido: con `force: true` el proceso termina en 0,5 s; con
  `close()` a secas seguía vivo a los 400 s. Se eligió un mecanismo único y
  declarado antes que cancelar sitio por sitio, porque cancelar suscripciones
  no cubre la fase de PEDIDO —ahí no hay flujo que cancelar— ni el grupo de
  conexiones. Lo pincha «el proceso TERMINA aunque la forja deje el cuerpo a
  medias».
- **Los dos `soltar()` de la rama del vencimiento del `push` no los sostiene
  ninguna prueba.** El fixture que deja un nieto vivo sale con 0 —ejercita el
  camino posterior a la salida— y el fixture del vencimiento muere por señal,
  con lo que sus tuberías cierran solas: borrar esas dos líneas queda verde.
  Pincharlas pide un hijo que se cuelgue Y deje un nieto con la tubería, un
  fixture que todavía no existe.
- **`forge` tiene superficie de comando y ninguna regla la vigila.** Su
  `bin/` es hoy el segundo ejecutable del repositorio fuera de la raíz de
  composición, y compone y empuja de verdad; que sea solo un instrumento de
  medición lo dice su doc comment y nada más — que es la clase de declaración
  sin control que este arnés existe para reemplazar. Ninguna de las catorce
  reglas mira quién puede tener `bin/`, así que al próximo que agregue uno no
  lo caza nada.
- **Que el proceso termine no lo sostiene una prueba de la suite, sino un
  proceso aparte.** Una suite no puede afirmar sobre su propio fin: corre
  hasta que terminan todas las pruebas. Por eso
  el programa `ayuda_fin_del_proceso` de `packages/forge/bin/` hace UN
  `empujar` y vuelve de `main`, y la prueba mide cuánto tarda ESE proceso en
  terminar. Vive en `bin/` y no en `test/` porque en `test/` sería un huérfano
  para el grafo; la suite lo BUSCA por su nombre en vez de escribir su ruta, y
  lo invoca directamente en vez de correrlo como ejecutable del paquete —eso
  último precompila un `snapshot` dentro del `.dart_tool` del checkout
  compartido, que es exactamente lo que `probar_reglas.py` vigila—. Lo que esa
  medición no distingue es POR QUÉ terminó: afirma el efecto observable —el
  proceso termina con un nieto vivo del otro lado de la tubería— y no que la
  suscripción se haya cancelado, que es el mecanismo. Un mecanismo distinto
  con el mismo efecto la pasaría igual.
- **La causa `revisionInvalida` usa `corregirConfiguracion` como acción
  siguiente, y quien tiene que corregir es el código que compuso la
  solicitud**, no una opción que el usuario haya configurado. Lo que las dos
  comparten —y es lo que esa acción promete— es que el mismo intento vuelve a
  fallar idéntico hasta que alguien cambie lo que se le pasa. Partir la acción
  por origen del defecto es un cambio de dominio.
- **`capas.py` no compara el árbol de paquetes que describe la sección
  `## Estructura` de este README contra `packages/` real.** Es una enumeración
  que dice enumerar y que nadie contrasta: hoy está al día —incluye `forge`—,
  pero nada además de una revisión humana lo sostiene.

- **El `runId` viaja crudo adentro del comentario HTML del marcador estable.**
  Un `runId` con `-->` cerraría ese comentario antes de tiempo y lo que
  escribiera después se renderizaría. El marcador es la **última** línea del
  cuerpo, así que no puede enterrar nada de lo que está arriba —que es lo que
  el render seguro protege—, pero sí agregar texto al final. Sanearlo cambia la
  forma del marcador, y el marcador es la clave de la búsqueda idempotente: el
  render y la búsqueda tienen que seguir produciendo la misma cadena, así que
  es un cambio de la clave y no un escape más.
- **El título se trunca por runas, no por grafemas.** Un emoji compuesto puede
  quedar partido en las piezas que lo componen. Lo que ya no puede quedar es
  media pareja sustituta, que es lo que la forja recibía como `�`.
- **El plan se renderiza como texto plano.** No existe hoy un tipo que declare
  «esto es Markdown que su autor escribió a propósito», y declararlo por campo
  sería sostener con prosa una propiedad de un `String`. Mientras no exista ese
  tipo, un plan con viñetas se lee con sus viñetas literales.

### Lo que esta rebanada NO hace

Queda para la rebanada de `ship`, y está declarado para que nadie lo lea como
olvido:

- **Nadie llama a `PullRequestSink.open` todavía.** La composición vive en las
  pruebas de contrato; `ship` es quien la va a hacer productiva.
- **`--retry-publication` no existe.** El desenlace ya sabe decir
  `retryable`; el comando que lo consume es de la rebanada siguiente.
- **`ShipOutcome`, `EstadoPublicable` y `CausaDeNoIntento` no se construyen
  acá.** Son §12 y §13 de la propuesta.
- **El código de salida `6` no se emite.** `packages/cli/lib/src/salida.dart`
  no se toca en esta rebanada.
- **La raíz de composición todavía no arma un `EntornoDelProceso` real y lo
  pasa hacia abajo.** Las tres costuras no comparten un único mecanismo acá,
  y hace falta decirlo por separado: `RepositorioGit._padre` y
  `EjecutorDelSistema._padre` (`packages/plugin_dart/lib/src/ejecutor.dart`)
  tienen, cada uno, el respaldo `_entornoDelPadre ?? EntornoDelProceso(Platform.environment)`
  —el parámetro es opcional por eso—, pero el respaldo se ejerce distinto en
  cada uno: `EjecutorDelSistema` sí tiene un llamador real que no inyecta,
  `cascadaPorDefecto` (`packages/cli/lib/src/verify.dart`), que construye
  `EjecutorDelSistema()` así y es el mismo `shipflow verify` que este README
  muestra al principio; `RepositorioGit` todavía no tiene ninguno en
  producción —hoy solo se construye desde pruebas—, porque quien lo compondría
  ahí es `ship`, que no existe. `EmpujeAislado.entornoDelPadre`, en
  `forge`, no tiene respaldo ninguno —es `required` y no nulable—, porque no
  tiene ningún llamador que no inyecte: ahí olvidarlo no es un valor por
  defecto silencioso, es un error de compilación. Lo que las tres comparten,
  y lo que cierra el agujero que esta rebanada vino a cerrar, no es el
  respaldo —que dos tienen y una no— sino el **tipo**: ninguna de las tres
  acepta un `Map<String, String>` crudo, así que ningún llamador, inyecte o
  no, puede colarles el entorno del padre sin pasar por `paraHijos`. Quien
  componga `ship` va a capturar el entorno real una vez, en la raíz, e
  inyectarlo en las tres, en vez de dejar que alguna caiga en su respaldo.

## Qué prometen estas fases y todavía no cumplen

Declararlo es obligación de cada fase, y viene de una lección concreta: una
superficie incompleta que se muestra vacía se lee como *"no había nada"*.

| Falta | Cuándo |
|---|---|
| **18 de los 28 puertos siguen sin implementación.** Está declarado puerto por puerto en `arquitectura.json`, y verificado en los dos sentidos: uno nuevo sin declarar falla, y una declaración que quedó vieja también | **fase 2**, rebanadas siguientes |
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
  forge           el adapter de la forja: push aislado, cliente de GitHub · solo ve a core
  cli             comandos y composition root
tool/
  checks/         capas.py · probar_reglas.py
  analisis/      lo que necesita el árbol sintáctico · fuera del workspace
```

Todas las flechas de dependencia apuntan hacia `core`, y `cli` es el único al
que la arquitectura le permite ver los plugins y los adapters.

**Permitido no es declarado.** `arquitectura.json` le permite ver también `vcs`,
`rules` y `agents`; su `pubspec.yaml` declara solo lo que hoy se importa. Las dos
frases que nombraban a `agents` de ejemplo —esta y la del barril de `cli`—
quedaron falsas el mismo día que se quitó esa dependencia. Un ejemplo elegido de
lo permitido envejece con cualquier limpieza de lo usado, y eso no lo cubre
ningún check de los que hay.
