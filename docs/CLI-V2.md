# Contrato público del CLI V2 · contexto inicial persistente

V2 permite **inicializar una vez** un proyecto Dart o Flutter, recuperar ese
contexto al volver, saber si sigue vigente y actualizarlo o recuperar una
operación interrumpida de forma explícita. Conserva el reconocimiento de V1
([`CLI-V1.md`](CLI-V1.md)) y el contrato de V0 ([`CLI-V0.md`](CLI-V0.md)).
Guardar el contexto no certifica la salud del proyecto ni convierte lo
observado en reglas.

## Comandos

| Invocación | Qué hace |
|---|---|
| `shipflow init --dry-run [--json] [--report-budget=…]` | Inspecciona sin escribir, preguntar, lanzar procesos ni usar la red (V1). |
| `shipflow init [--sharing=share\|local] [--json] [--report-budget=…]` | Primera incorporación; si ya hay contexto, lo comprueba y no cambia observaciones. |
| `shipflow init --refresh [--sharing=share\|local] [--json] [--report-budget=…]` | Reemplaza el contexto por lo observado ahora, si es elegible; conserva su identidad. |
| `shipflow init --recover [--json] [--report-budget=…]` | Termina o deshace sólo una operación propia interrumpida. |
| `shipflow doctor [--json] [--report-budget=…]` | Consulta el contexto guardado y explica la siguiente acción. Sólo lee. |

Las opciones repetidas, los valores desconocidos, las acciones combinadas
(`--dry-run`, `--refresh`, `--recover`), `--sharing` con `--dry-run`,
`--recover` o la ayuda, y los argumentos posicionales son uso inválido (`64`)
antes de inspeccionar. No hay `--force` ni `--yes`. `--json` nunca pregunta.

Cada invocación vuelve a ejecutar el reconocimiento acotado de V1 y lo compara
con lo guardado: así no pasa por alto un paquete nuevo, uno eliminado o un
enlace nuevo. No analiza código ni ejecuta herramientas del proyecto.

## Archivos

Todo vive bajo `shipflow/`, en la carpeta desde la que se ejecuta:

| Ruta | Contenido |
|---|---|
| `shipflow/project.json` | El contexto inicial portable: el único documento autoritativo. |
| `shipflow/.gitignore` | Exactamente `/local/` y un comentario: sólo excluye el estado operativo. |
| `shipflow/local/settings.json` | La elección de conservación de **esta copia**. |
| `shipflow/local/transaction.json` | Una operación en curso; desaparece al terminar. |
| `shipflow/local/previous.json` | La versión anterior, para recuperar una interrupción. |
| `shipflow/local/staging/`, `shipflow/local/locks/` | Preparación y coordinación breve. |

`project.json` no lleva rutas absolutas, Git ni efectos: se puede copiar o
clonar a otra ubicación y `doctor` lo vuelve a leer y a comprobar allí, sin la
configuración local. Su `projectId` es un UUID opaco. No se busca un contexto en
carpetas superiores: desde una subcarpeta de un proyecto inicializado, init pide
operar desde su raíz.

Una carpeta `shipflow` con contenido de otra herramienta no se oculta ni se
sobrescribe: el reconocimiento la inspecciona como cualquier otra y init informa
que está ocupada (`65`). Un contexto dañado o de una versión futura se conserva:
no hay migración ni reinicio automático.

## Elegir cómo conservarlo

En una terminal, la primera incorporación con Git pregunta:

```text
  1) Compartir con el proyecto — recomendado
     Se prepara para conservarlo junto al proyecto y compartirlo. Todavía tienes que incluirlo cuando guardes los cambios del proyecto: elegirlo no significa que ya se compartió.
  2) Mantenerlo sólo aquí
     Queda disponible en esta copia, no se incluye al compartir cambios y necesitas un respaldo para recuperarlo si pierdes la copia o cambias de equipo.
  ?) Detalle técnico    q) Cancelar
Elige 1, 2, ? o q:
```

Enter vacío no elige. `q` o el cierre de la entrada cancelan antes de escribir
(`130`). Con `--json` o sin terminal no se pregunta: init termina con `65`
`choice_required` y propone `--sharing=share` o `--sharing=local`. La elección
queda guardada y no se vuelve a preguntar.

- **share** deja `project.json` y `.gitignore` listos para versionar.
  Shipflow **no** ejecuta `git add`, `commit` ni `push`. Si una regla de ignore
  ajena los alcanza, la elección no se aplica y se informa la regla.
- **local** agrega un bloque propio y delimitado al exclude local de Git
  (resuelto con `git rev-parse --git-path info/exclude`), y comprueba que
  excluye de verdad antes de hacer visible el contexto. Preserva las reglas
  ajenas, byte a byte. No quita del índice un archivo ya seguido: en ese caso
  termina con `65` `already_tracked`. En copias de trabajo vinculadas, ese
  exclude es común: la regla alcanza la misma ruta en las otras copias del
  repositorio en el equipo, y un cambio hecho desde otra copia se informa sin
  alternarlo.
- Volver de local a share retira sólo el bloque propio intacto.

Sin Git o fuera de un repositorio, init guarda igual el contexto con la elección
pendiente y avisa que Shipflow no lo versiona ni lo comparte. Cuando Git
aparece, init vuelve a pedir la elección. Un Git que falla (repositorio dañado,
dueño dudoso, plazo vencido) no se toma por ausencia.

## Git consultado

Sólo `git --version`, `rev-parse`, `ls-files` y `check-ignore` sobre las rutas
propias, sin shell, con argumentos en lista y un entorno saneado (sin variables
`GIT_*`, sin preguntas ni locks opcionales, sin `fsmonitor`). El ejecutable es
el primero de las entradas absolutas del `PATH` que no estén dentro del
proyecto. Cada proceso tiene 5 s y 1 MiB de salida; una operación, 12 procesos y
20 s. No hay escrituras de índice, hooks ni red.

## Vigencia

| `freshness` | Significa |
|---|---|
| `current` | Lo observado ahora coincide con lo guardado, dentro de su cobertura. |
| `stale` | Difiere: `init --refresh` lo actualiza; init y doctor no lo reemplazan. |
| `unverified` | No se pudo comparar: reconocimiento inelegible, otro contrato o el perfil no alcanza. |
| `not_applicable` | No hay un contexto que comparar. |

`current` no dice que el proyecto compile ni que su arquitectura sea válida, y
el texto de un README no se lee: cambiarlo no afecta la vigencia. El perfil
`--report-budget` vale sólo para esa invocación: un contexto guardado con
`extended` que no cabe en el perfil normal da `unverified` y propone
`--report-budget=extended`.

## Publicación y recuperación

Cada publicación toma un lock breve por recurso, sin esperar: si otro proceso
de Shipflow lo tiene, termina con `75`; el lock se libera cuando su dueño
termina, y nunca se borra para apropiárselo. Antes de escribir vuelve a
comprobar las huellas de lo que leyó y las fuentes; si cambiaron, `75`
`concurrent_change`. Después escribe el registro de la operación, prepara los
archivos, aplica el exclude si corresponde, y publica la configuración, la copia
anterior y el contexto, cada uno con archivo temporal, `fsync` y renombrado
sobre la versión esperada. Ningún destino se trunca ni se abre siguiendo un
enlace.

Si el proceso se interrumpe, init y doctor lo informan (`75`) y
`init --recover` compara los bytes de cada destino con las huellas registradas:
termina lo preparado, lo deshace si las fuentes cambiaron (`65`) o, si un
archivo ya no es ni la versión anterior ni la preparada, lo conserva y pide una
decisión manual (`75` `recovery_conflict`). Un resto anterior al primer registro
no se adopta por su nombre: init y `--recover` responden `65`
`bootstrap_unverified` y piden mover esa carpeta como respaldo.

La garantía cubre la interrupción del proceso y errores de entrada y salida con
un sistema de archivos funcional. No cubre la pérdida física del disco, un
corte de energía ni a quien edita los archivos saltándose la coordinación.

## Códigos de salida

| Código | Resultado |
|---|---|
| `0` | Inicializado, actualizado, recuperado o sin cambios; doctor con contexto vigente, aunque falte Git o la elección. |
| `64` | Uso inválido. |
| `65` | Contexto ausente, desactualizado, incompatible o inelegible; elección requerida o imposible. |
| `66` | Raíz inválida. |
| `70` | Fallo inesperado, sin traza ni rutas. |
| `74` | Un error de entrada y salida impidió la operación; se informa lo que alcanzó a hacer. |
| `75` | Otra operación en curso, un cambio concurrente o una recuperación pendiente o conflictiva. |
| `130` | Cancelado antes de escribir. |

## JSON

`init`, `--refresh`, `--recover` y `doctor` responden una línea con
`schemaVersion: 3`, `command`, `operation`, `outcome`, `exitCode`,
`contextState`, `freshness`, `sharing`, `checks` (los seis del catálogo, cada uno
`passed`, `failed` o `not_checked`), `diagnostics`, `context` (lo guardado, o
`null`), `effects` y `nextActions`. `effects` distingue archivos creados,
reemplazados y eliminados, carpetas creadas, procesos y si se modificó el
exclude; la red es siempre `0`. Si la respuesta no cabe en 4 MiB, sale una
versión compacta sin `context` que conserva el resultado, los efectos y las
acciones. Ayuda, versión y uso inválido conservan `schemaVersion: 1`.

`init --dry-run` pasa a `schemaVersion: 3`, con `command: "init"`,
`operation: "dry_run"` y la omisión `tool_state` de `shipflow`; ver
[`CLI-V1.md`](CLI-V1.md).

## Ejemplo

`doctor` sobre una copia de un proyecto Flutter de dos paquetes ya inicializada
con `--sharing=share` (salida real, con la carpeta abreviada):

```text
Shipflow · contexto del proyecto
Contexto disponible
Carpeta: …/freya

Contexto guardado: shipflow/project.json
  2 paquetes: freya, componentes_freya
  Descripción: «A new Flutter project.»
  Coincide con lo observado ahora, dentro de la misma cobertura.

Conservación: listo para versionarlo con el proyecto; todavía tienes que incluirlo al guardar los cambios.

Cambios en disco:
  No se modificó ningún archivo.

No se comprobó si el proyecto compila, si sus pruebas pasan, si respeta su arquitectura ni si el SDK está instalado.

Para el detalle estructurado: shipflow doctor --json
```
