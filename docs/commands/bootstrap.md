# `shipflow bootstrap` · base de decisiones del proyecto

`shipflow bootstrap` guarda en `shipflow/basis.json` las decisiones que una
persona acepta para el proyecto, las fuentes que las sustentan y lo que falta
aclarar, con toda su historia. Se consulta después por ámbito, sin volver a
preguntar lo ya aceptado.

La base **no interpreta el código ni certifica que se cumpla**. No usa
modelos de IA, no deduce reglas de documentos ni de commits y no ejecuta
`git add`, `commit` ni `push`. La autoridad es **local y declarada**: Shipflow
no autentica quién acepta. Una fuente sin cambios no demuestra que la decisión
sea correcta, y una base vacía no significa que el proyecto no tenga reglas.

## Comandos

| Invocación | Efecto |
|---|---|
| `shipflow bootstrap [--json]` | En una terminal, la guía interactiva. Sin terminal o con `--json`, no pregunta: responde `choice_required` (65) sin escribir nada. |
| `shipflow bootstrap --input <archivo.json\|->` | Prepara un borrador desde una propuesta JSON (`-` lee la entrada estándar). **No acepta.** |
| `shipflow bootstrap --show [--scope <ruta> \| --history \| --draft]` | Consulta la base aceptada, su historia o el borrador. No escribe. |
| `shipflow bootstrap --accept <huella>` | Acepta exactamente el borrador con esa huella. |
| `shipflow bootstrap --discard <huella>` | Descarta exactamente ese borrador. |
| `shipflow bootstrap --recover` | Termina o aborta una publicación interrumpida. |
| `shipflow bootstrap --help [--json]` | Ayuda, sin mirar el proyecto. |

Todas aceptan `--json` y `--report-budget=standard|extended`. Una opción
repetida o desconocida, un argumento posicional, dos operaciones,
`--scope`/`--history`/`--draft` sin `--show` o juntas, un `--scope` que no es
`.` ni una ruta relativa segura, o una huella que no es `sha256:` y 64
hexadecimales terminan con **64** antes de leer nada.

## Antes de operar

`bootstrap` requiere el contexto de `shipflow init` (`shipflow/project.json`)
válido; si falta remite a `init` (65, `context_required`). Una operación de
`init` o de `assess` sin terminar bloquea con **75** (`recovery_required`) y
`bootstrap` no la recupera: la remite a su propio `--recover`.

## Qué se guarda

Tres tipos de registro, cada uno con un ID estable y versiones 1, 2, 3…:

- **Regla**: título, ámbito, enunciado, motivo y clase (`obligation`,
  `prohibition` o `preference`). Una prohibición activa necesita alternativa
  y política de excepción. Su ciclo de vida es `proposed`, `active`,
  `replaced` (con la regla que la reemplaza) o `retired`. Se sustenta en una
  declaración humana o en versiones exactas de fuentes.
- **Fuente**: un documento local (`.md`, `.txt`, `.rst`) o una referencia
  externa `https://` que nunca se descarga. Registrarla **no adopta** su
  contenido como reglas.
- **Pendiente**: una pregunta, su motivo y cuándo volver a mirarla. Un
  pendiente puede ser la **revisión de una decisión**: queda ligado a la
  versión exacta de la regla que revisa, con un responsable que puede quedar
  por definir. Ese vínculo no cambia aunque la regla cambie después.

El ámbito es `project` (todo el proyecto), prefijos de ruta relativos
(`lib/pagos`, que incluye `lib/pagos/x` pero no `lib/pagosx`) o `unknown`.
Una regla activa no puede tener ámbito desconocido. El actor declara su propio
ámbito y sólo puede cambiar registros dentro de él.

## Preparar, revisar y aceptar

Preparar valida la propuesta completa —forma, referencias, vínculos de
revisión y autoridad—, lee las fuentes citadas y guarda un borrador en
`shipflow/local/basis-draft.json` con su **huella**. La respuesta muestra
**cada cambio que hará aceptarlo** —crea, revisa, retira, reemplaza o
resuelve, con el ID y las versiones de cada registro, también lo que deja
de estar vigente—, el estado resultante y las acciones exactas.
`--show --draft` y la guía al retomar muestran lo mismo:

```text
Borrador preparado: todavía no está aceptado.
Huella: sha256:7bf49109…
…
Cambios de este borrador (sólo se aplican al aceptar su huella):
• Retira «Contratos públicos» (regla) · ID 4f1c… · versión 1 → 2
  Deja de estar vigente; sigue en la historia.
…
Siguientes pasos:
  shipflow bootstrap --show --draft
  shipflow bootstrap --accept sha256:7bf49109…
  shipflow bootstrap --discard sha256:7bf49109…
```

Aceptar exige esa huella y, ya bajo el lock, vuelve a leer el borrador:
uno descartado, revisado o aceptado entre medio no se publica. Si la base,
el contexto o una fuente citada cambiaron
desde la preparación, no se publica (**75**, `base_changed` o
`source_changed`) y el borrador se conserva: hay que prepararlo y revisarlo
de nuevo. Aceptar dos veces el mismo borrador responde `already_applied` sin
crear otra revisión. Hay un solo borrador activo; otro se rechaza con
`draft_conflict`.

Si la base cambió desde que se preparó el borrador (por ejemplo, llegó otra
con `git pull`), `--show --draft` y `--accept` responden `base_changed` y
ofrecen descartarlo; nunca lo presentan aplicado a la base nueva.

## La guía

En una terminal, `shipflow bootstrap` explica para qué sirve la base y ofrece
añadir una decisión, señalar una fuente o anotar un asunto por aclarar. Si ya
hay una base, también revisar o retirar una decisión vigente y resolver un
pendiente, sin volver a preguntar lo aceptado. Al incorporar o revisar una
decisión ofrece registrar su revisión pendiente, con responsable opcional.
Pregunta una sola vez quién acepta, con qué responsabilidad y sobre qué
ámbito decide; si algo no se puede preparar, permite quitar lo último añadido
y conservar lo demás. Sin contexto inicial no pregunta nada y remite a
`init`.

Prepara con el mismo servicio que `--input` y muestra el resumen. Sólo
escribir **«aceptar»** acepta; «borrador» lo conserva sin aceptar y
«descartar» lo descarta. Enter vacío no elige, y cerrar la entrada cancela
(**130**) conservando el último borrador guardado. La guía no toma ningún
lock mientras espera respuestas.

## Propuesta JSON (`--input`)

Una propuesta es un objeto con `schemaVersion` 1, `type`
`shipflow.basis.input`, el `projectId` de `shipflow/project.json`,
`expectedBasisDigest` (el `digest` de `basis.json` sobre el que se propone, o
`null` si todavía no hay base), `actor` (`label`, `role`, `authority`
`local_declared` y su `scope`), `reason` y `changes`. Cada cambio lleva una
`key` única en la propuesta, `targetId` y `expectedVersion` (`null` para un
registro nuevo; el ID y la versión vigente para revisar uno) y el `payload`
completo de la versión nueva. Dentro de la misma propuesta, `new:<key>` cita
un registro nuevo. Una fuente local se propone con `contentDigest: null` y
`observation: "unverified"`: la huella la registra el preparado al leerla.

```json
{
  "schemaVersion": 1,
  "type": "shipflow.basis.input",
  "projectId": "<projectId de shipflow/project.json>",
  "expectedBasisDigest": null,
  "actor": {"label": "Ana", "role": "mantenimiento",
            "authority": "local_declared",
            "scope": {"kind": "project", "paths": []}},
  "reason": "Primera base.",
  "changes": [
    {"key": "doc", "targetId": null, "expectedVersion": null,
     "payload": {"kind": "source", "title": "Política de contratos",
                 "scope": {"kind": "project", "paths": []},
                 "lifecycle": "active", "sourceType": "local",
                 "locator": "docs/politica.md",
                 "purpose": "Referencia de compatibilidad.",
                 "contentDigest": null, "observation": "unverified"}},
    {"key": "contratos", "targetId": null, "expectedVersion": null,
     "payload": {"kind": "rule", "title": "Contratos públicos",
                 "scope": {"kind": "paths", "paths": ["lib/api"]},
                 "lifecycle": "active", "replacementRef": null,
                 "statement": "Los cambios de contrato requieren revisión.",
                 "reason": "Preservar compatibilidad.",
                 "ruleClass": "obligation", "alternative": null,
                 "exceptionPolicy": "requires_authority",
                 "support": "source_supported",
                 "sourceRefs": [{"ref": "new:doc", "version": 1}],
                 "evidenceLevel": "declared"}},
    {"key": "consumidores", "targetId": null, "expectedVersion": null,
     "payload": {"kind": "pending", "title": "Consumidores",
                 "scope": {"kind": "paths", "paths": ["lib/api"]},
                 "status": "open",
                 "question": "¿Qué consumidores externos hay que consultar?",
                 "reason": "No hay registro todavía.",
                 "revisitWhen": "Al integrar el segundo consumidor.",
                 "sourceRefs": [], "resolution": null,
                 "decisionReview": {"ref": "new:contratos", "version": 1,
                                    "reviewer": null}}}
  ]
}
```

Un pendiente se resuelve con `status: "resolved"` y `resolution`
`disposition:<texto>` o `rule:<id>@<versión>` de una regla ya aceptada. Una
regla reemplazada lleva `lifecycle: "replaced"` y `replacementRef` con la
regla que la reemplaza. Cualquier campo desconocido o ausente es inválido
(65).

## Consultar

Consultar exige el contexto de `init` y que la base y el borrador sean de
este proyecto: una base copiada de otro (otro `projectId`) no se presenta
como aplicable (65, `invalid_reference`), y `doctor` la informa como
inválida.

`--show` devuelve las reglas vigentes, las fuentes que citan (en la versión
citada, aunque su ámbito sea otro) y los pendientes abiertos. Con
`--scope <ruta>` incluye lo global, lo de ámbito desconocido y los prefijos
que se solapan con la ruta; `excludedCount` cuenta sólo lo excluido por
ámbito. Las revisiones abiertas de una regla seleccionada se incluyen siempre,
y la versión que revisan aparece aparte en `reviewTargets` («Decisión a la
que corresponde esta revisión»): no es la regla vigente, y sus soportes no se
vuelven a comprobar.

Cada fuente citada se vuelve a leer: `current` si conserva su huella, `stale`
si cambió, `unverified` si es externa, no se pudo leer o se registró sin
huella (no había con qué compararla), `excluded` si su ruta o su contenido
parecen credenciales. Una regla sólo se acepta sustentada en fuentes
observadas `current` al preparar. Una fuente `stale` **no borra** la regla:
la regla sigue visible con su soporte sin verificar.

`--history` devuelve todas las revisiones en orden, con cada cambio y la
versión exacta que cita cada revisión; no vuelve a comprobar soportes.
`--draft` muestra el borrador como estado no aceptado.

## Archivos

| Archivo | Contenido |
|---|---|
| `shipflow/basis.json` | La base aceptada: eventos encadenados por huella desde la revisión 1. Se conserva junto a `project.json` según la elección de `init --sharing`. |
| `shipflow/local/basis-draft.json` | El borrador activo de esta copia. |
| `shipflow/local/basis-transaction.json` | Una publicación en curso; desaparece al terminar. |
| `shipflow/local/basis-staging/` | El candidato de esa publicación. |

Con `--sharing=local`, una base ya seguida por Git bloquea el cambio de
elección (`already_tracked`) sin quitarla del índice ni tocar el archivo.

## Publicación y recuperación

Bajo el lock compartido con `init` y `assess`: se escribe el candidato en
staging, se publica el journal con las huellas de los bytes antes y después,
se revalidan base, contexto y fuentes, y sólo entonces se reemplaza
`basis.json` con un rename comparado con su huella anterior. Si algo falla
después del rename, la respuesta conserva `published: true`.

Ni `--recover` ni `--discard` comparan una base que no se pudo leer con
la anterior: sin leerla, conservan todo e informan el fallo. `--discard`
sólo aborta una publicación cuyo journal es de este proyecto, sin otra
transacción activa y con su candidato exacto.

`--recover` con la base ya en su versión nueva sólo limpia. Con la base en
la versión anterior revalida las precondiciones y publica, o aborta con
**75** (`recovery_preconditions_changed`) conservando todo y ofreciendo
`--discard`. Una base que no es ninguna de las dos, o un journal ilegible, es
un conflicto que se conserva. Responde `no_changes` sólo si comprobó que
no queda nada: un estado que no pudo inspeccionar o con restos ajenos es un
conflicto (75).

## Cotas

| Cota | standard | extended |
|---|---:|---:|
| `basis.json` completo | 4 MiB | 16 MiB |
| Propuesta, borrador o journal | 1 MiB | 4 MiB |
| Registros actuales | 1.024 | 4.096 |
| Eventos | 8.192 | 32.768 |
| Cambios por propuesta | 64 | 256 |
| Bytes por fuente | 1 MiB | 4 MiB |
| Fuentes por operación | 64 | 256 |
| Bytes de fuentes por operación | 16 MiB | 64 MiB |
| Respuesta | 8 MiB | 32 MiB |

Además: textos cortos 512 bytes, motivos y localizadores 4 KiB, enunciados
16 KiB y profundidad JSON 32. Cada operación tiene una sola cuenta de
lectura de fuentes: cada ruta se lee a lo sumo una vez y todas sus fases
cobran de la misma cota. Lo que queda sin leer al agotarla hace la
consulta no concluyente (`budget_exceeded`, 65). Aceptar lee las fuentes
una sola vez antes de publicar: con el journal escrito y bajo el lock, y
esa misma lectura comprueba los soportes y se presenta. Si esa
revalidación no cabe, no se publica (`budget_exceeded`) y el borrador se
conserva. Las rutas protegidas
(`.git`, `.ssh`, `.aws`, `.env`, `shipflow/local`) se reconocen sin
distinguir mayúsculas. Los bytes de la base se cuentan sobre el archivo
en disco, legible con sangría, que ocupa más que su forma canónica. El
borrador contiene la propuesta y los cambios preparados, así que una
propuesta debe ocupar bastante menos que la cota del borrador. Preparar ya
comprueba que la base resultante cabría: un borrador que no se podría
aceptar con ese perfil no se ofrece. Las cotas son independientes: una base puede
llegar a sus bytes antes que a sus eventos. Lo que no cabe se rechaza
(`budget_exceeded`) sin recortar historia. Una respuesta que no cabe se
entrega no concluyente (`selection.complete: false`), sin registros, nunca
como un conjunto truncado que parezca completo. Si lo que no cabe son los
cambios de un borrador, se dice cuántos son y, en vez de ofrecer
aceptarlo, se ofrece revisarlo con `--report-budget=extended`. La guía
aplica la misma regla al preparar y al retomar: muestra la respuesta
acotada y sólo deja conservar o descartar un borrador cuyos cambios no
pudo mostrar.

## Códigos de salida

| Código | Cuándo |
|---|---|
| 0 | Base consultada o guardada, recuperación terminada o nada que cambiar. |
| 64 / 66 | Uso inválido / entrada o raíz que no se puede leer. |
| 65 | Formato, huella, historia, autoridad o referencia inválidos; base ausente; cota; borrador preparado sin aceptar; falta elegir operación. |
| 70 / 74 | Error inesperado / fallo de lectura o escritura propia. |
| 75 | Otra operación publicando, borrador en conflicto, base, contexto o fuente cambiados, o recuperación pendiente. |
| 130 | La guía se canceló: nada se aceptó. |

## JSON

Una línea: `schemaVersion` 1, `type` `bootstrap`, `operation`, `exitCode`,
`outcome`, `storageIntegrity` (base, borrador y journal por separado),
`basisDigest`, `draftDigest`, `published`, `changedFiles`,
`normativeCoverage` (`not_established` o `declared_partial`), `selected`,
`reviewTargets`, `proposedChanges`, `pending`, `sourceStatus`, `actor`, `reason`, `history`,
`selection`, `diagnostics` y `nextActions`. Cada acción trae `command`,
`arguments` literales, `purpose` y `effect`; mostrarla no la ejecuta.
`--json` nunca mezcla preguntas con la respuesta.

`proposedChanges` lista, sólo en la respuesta de un borrador sin aceptar
(`--input` con `operation=prepare` y `outcome=draft_prepared`, y `--show
--draft` con `outcome=shown`), cada versión exacta que guarda el borrador
con su efecto: `{"change": "create|revise|retire|replace|resolve",
"version": {…}}`. El efecto se deriva de la versión —la versión 1 crea; un
retiro, un reemplazo o una resolución se reconocen por su estado— y una
respuesta que declare otro, o que los lleve en cualquier otra operación o
resultado —`already_applied` incluido—, es inválida. `history` lleva sólo
aceptaciones ya registradas.

`init` y `doctor` informan la integridad de la base y de su transacción en
dos checks propios de su respuesta.

## Plataformas

macOS ARM64 y Linux x64, con el mismo almacenamiento anclado de `init`. La
recuperación cubre la muerte del proceso con el sistema de archivos
funcionando, no la pérdida física del disco.
