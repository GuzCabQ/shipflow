# Contrato público del CLI V3 · levantamiento de referencias del código

`shipflow assess` observa las referencias que el código Dart y Flutter declara
entre sus archivos —`import`, `export`, `part` y `part of`— y guarda un
levantamiento con su evidencia, su cobertura y sus límites en
`shipflow/assessment.json`. Consultarlo después comprueba si sigue
correspondiendo al código de ahora sin volver a analizarlo.

Un levantamiento **no certifica la salud del proyecto**: no ejecuta pruebas, no
analiza llamadas ni el uso en tiempo de ejecución, no resuelve el SDK ni el
`package_config` del proyecto y no convierte una referencia en una regla de
arquitectura. Shipflow no ejecuta `git add`, `commit` ni `push`.

## Comandos

| Invocación | Efecto |
|---|---|
| `shipflow assess [--json] [--report-budget=standard\|extended]` | Observa y publica una revisión nueva. Nunca pregunta. |
| `shipflow assess --show [--json] [--report-budget=…]` | Muestra la revisión vigente y comprueba su vigencia. No analiza ni escribe. |
| `shipflow assess --show --previous [--json] [--report-budget=…]` | Muestra la revisión anterior como historia; no la certifica vigente. |
| `shipflow assess --recover [--json] [--report-budget=…]` | Termina o deshace una publicación propia interrumpida. |
| `shipflow assess --help [--json]` | Ayuda, sin mirar el proyecto. |

Una opción repetida, un argumento posicional, un valor desconocido,
`--previous` sin `--show`, `--show` con `--recover` o la ayuda con opciones de
operación terminan con **64** antes de leer nada.

## Antes de observar

`assess` reutiliza el contexto V2 de `shipflow/project.json`, que no modifica:

- tiene que existir, validar y estar vigente; si no, remite a `shipflow init`
  o `shipflow init --refresh` (65);
- la elección de conservación tiene que estar aplicada; si hay un repositorio
  Git y falta, remite a `shipflow init --sharing=share|local` (65). Sin Git,
  la elección pendiente permite guardar en esta copia, y se avisa;
- una operación de `init` sin terminar remite a `shipflow init --recover`, y
  una publicación de `assess` sin terminar a `shipflow assess --recover` (75).

## Qué se observa

- **Universo.** Los archivos `.dart` regulares bajo las unidades del contexto
  citado, cada uno una vez, con su unidad dueña: la de raíz más profunda. Se
  incluyen pruebas y generados presentes; ninguno se declara editable.
- **Exclusiones.** `.git`, `.dart_tool`, `build`, `.symlinks`, `Pods` y
  `node_modules` en cualquier profundidad, las omisiones del contexto citado y
  `shipflow/`. Quedan registradas con su motivo. `.gitignore` no oculta código.
- **Nunca** se siguen enlaces ni se abren dispositivos o FIFO, ni se sale de
  la raíz para resolver.
- **Directivas.** Con el parser de `package:analyzer` 14.1.0 en modo
  sintáctico: comentarios y textos no cuentan. Un archivo con cualquier
  diagnóstico del parser, o con UTF-8 inválido, no aporta referencias y queda
  como fallido: nunca como «sin referencias».
- **Condicionales.** Se conservan la base (`fallback`) y cada rama
  (`conditional`) con su condición en forma segura: una variable con puntos
  o su comparación con `"true"` o `"false"`. Cualquier otro valor comparado
  puede ser un dato privado del código: esa rama queda `unknown`, sin el
  valor.

| Referencia | Resolución |
|---|---|
| Ruta relativa | Local si llega léxicamente a un archivo incluido de la raíz; si sale de la raíz, está excluido, falta o no se pudo leer, sin resolver con su motivo. |
| `package:` del propio paquete | Local, sólo hacia el `lib` de su unidad, si su nombre es único. |
| `package:` de otro paquete local | Local sólo a través de una dependencia local corroborada por el contexto citado; nunca por la coincidencia de nombre de un vecino. |
| Otro `package:` o `dart:` | Externa: se nombra, sin comprobar que exista. |
| `part of` con URI | Adjunta la parte a su biblioteca (`source_attachment`). |
| `part of` con nombre, otro esquema o un literal inseguro | Sin resolver con su motivo; el literal rechazado no se guarda. |

Las dependencias declaradas en los manifiestos y las fuentes candidatas del
contexto se conservan como **vínculos** aparte: una declaración no prueba uso
y una referencia observada no la convierte en norma.

## Archivos

| Ruta | Contenido |
|---|---|
| `shipflow/assessment.json` | Portable: la revisión vigente y la anterior, completas, con sus testigos. |
| `shipflow/local/assessment-transaction.json` | Local: el journal de una publicación en curso. |
| `shipflow/local/assessment-staging/<operationId>/candidate.json` | Local y temporal: el candidato sellado. |
| `shipflow/local/locks/context.lock` | El mismo lock de `init`, `refresh` y `recover`. |

`assessment.json` sigue la elección de V2: con `share` queda listo para
versionarse; con `local` lo excluye la misma regla que a `shipflow/`.

**Retención.** Se conservan la revisión vigente y la anterior. Publicar una
tercera informa `retiredRevision`: las más antiguas requieren Git o un
respaldo. Repetir `assess` sin cambios no escribe ni cambia fechas.

## Vigencia

Cada revisión sella sus insumos: la huella de los bytes exactos de
`shipflow/project.json`, el listado de cada directorio, los manifiestos y
marcadores del reconocimiento —incluidos los nuevos— y cada fuente leída. No
usa `HEAD`, así que funciona sin Git y detecta archivos nuevos, sin seguir,
modificados y borrados.

`--show` vuelve a sellar esos insumos sin el parser:

- un cambio demostrado es **stale** y nombra las primeras rutas afectadas;
- una entrada que no se pudo leer, o un inventario cortado por presupuesto,
  es **unverified**, nunca **current**;
- un inventario cortado ahora no cuenta como desaparición.

`--show --previous` no certifica vigencia, pero si la revisión anterior cita
el mismo `project.json` comprueba que le corresponda (65 si no); si cita
otro, avisa que ese vínculo no se volvió a comprobar. Un archivo propio que
no se puede acreditar, como un journal ilegible, se informa junto a la
evidencia (65), nunca como una consulta limpia.

Si el contexto citado cambió, el levantamiento sigue consultable como
obsoleto, sin reenlazarlo a las unidades nuevas. Con la misma huella, sus
unidades y vínculos tienen que corresponder exactamente al contexto: una
huella correcta no legitima un contenido ajeno.

Es consistencia comprobada mediante lecturas acotadas y revalidación, **no
una instantánea atómica del sistema de archivos** frente a escritores
externos que cambian algo y lo restauran entre dos lecturas.

## Cobertura y testigos

Cinco testigos con lo esperado, procesado, fallido y omitido:
`source_inventory`, `source_references`, `local_resolution`, `test_inventory`
y `context_candidates`. Lo esperado sale del inventario, nunca del detector.
La cobertura es **complete** sólo con un inventario completo y todos los
testigos completos; complete significa el universo explícito de directivas,
no que se comprenda el proyecto. Cero referencias sobre fuentes analizadas es
completo; un detector que no corrió no lo es.

## Comparación

Sólo entre dos revisiones completas, con inventarios completos, del mismo
contexto citado y el mismo contrato del productor: referencias nuevas,
repetidas y **no observadas ahora**. Esta última no prueba que algo ya no
exista ni retira nada. En cualquier otro caso la comparación es `null` y se
dice por qué.

## Publicación y recuperación

Bajo el lock compartido: se revalidan las precondiciones, se codifica y
vuelve a validar el candidato entero, se escribe en staging, se publica el
journal con las huellas antes y después del documento, se vuelven a sellar
las fuentes y sólo entonces se reemplaza el documento con un rename atómico
comparado con su huella anterior. Un cambio antes de ese punto cancela con
**75** y conserva lo anterior; también una fuente sellada que ya no se pudo
volver a leer, porque sin un cambio demostrado no equivale a confirmada.
Repetir `assess` sin cambios de snapshot también revalida antes de decir
**current**. Si algo falla después del rename, la respuesta conserva que se
guardó.

`assess --recover` limpia sin republicar si el documento ya tiene su versión
preparada; si conserva la anterior y el candidato es el preparado, vuelve a
leer el contexto bajo el lock y publica cuando el contexto y las fuentes se
confirman iguales, y aborta conservando lo anterior si no. Un journal o un
candidato de otro proyecto, o que no corresponde al contexto que cita, es un
conflicto (**75**) que se conserva. Un documento que no es ninguna de las dos versiones es un
conflicto (**75**) que no se toca. Sin journal, sólo retira un candidato
completo del mismo proyecto; nunca lo adopta. `init --recover` no recupera
publicaciones de assess: las remite a `assess --recover`, y dos operaciones
sin terminar son un conflicto.

## Cotas por ejecución

| Cota | standard | extended |
|---|---:|---:|
| Entradas enumeradas | 100.000 | 400.000 |
| Profundidad | 32 | 64 |
| Archivos fuente | 4.096 | 16.384 |
| Bytes por fuente | 2 MiB | 2 MiB |
| Bytes fuente totales | 32 MiB | 128 MiB |
| Referencias | 32.768 | 131.072 |
| Snapshot serializado | 16 MiB | 64 MiB |
| Observación o comprobación | 30 s | 120 s |
| Análisis de un archivo | 2 s | 8 s |

Superar un presupuesto de recorrido, conteo o tiempo deja cobertura parcial
con lo admitido; las referencias de un archivo se admiten enteras o ninguna.
Un snapshot que no cabe no se publica (65, `assessment_limit`); tampoco un
proyecto con más de 16.384 fuentes elegibles, que excede lo que el archivo
puede guardar en cualquier perfil.

## Códigos de salida

| Código | Cuándo |
|---|---|
| 0 | Guardado o vigente con cobertura completa; recuperación terminada; consulta histórica válida pedida expresamente. No significa proyecto sano. |
| 64 / 66 | Uso inválido / raíz que no se puede inspeccionar. |
| 65 | Preflight, integridad, levantamiento ausente, obsoleto o no comprobado, o cobertura parcial. Un resultado parcial **puede quedar guardado**: lo dice `effects`. |
| 70 / 74 | Error inesperado / fallo de lectura o escritura propia. |
| 75 | Otra operación publicando, cambio durante la operación o recuperación pendiente o en conflicto. |

## JSON

Una línea: `schemaVersion` 1, `kind` `shipflow.assessment-response`,
`command` `assess`, `operation` (`observe`, `show` o `recover`), `exitCode`,
`outcome`, `freshness`, `coverage`, el snapshot elegido completo o `null`,
`diagnostics`, `effects`, `nextActions`, `comparison` y `retiredRevision`.
Resultado, vigencia y cobertura son ejes independientes: `published` o un
código 0 no significan completo ni vigente. La vista humana resume el mismo
resultado y remite a `shipflow assess --show --json` para el detalle.

## Plataformas

macOS ARM64 y Linux x64, con el mismo almacenamiento anclado de V2. La
recuperación cubre la muerte del proceso con el sistema de archivos
funcionando, no la pérdida física del disco.
