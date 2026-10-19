# Contrato público del CLI V1 · `shipflow init --dry-run`

V1 agrega un comando: reconocer un proyecto Dart o Flutter existente **sin
modificarlo** y entregar una ficha de ingreso. Shipflow mira la carpeta actual y
explica qué es el proyecto, cómo se relacionan sus paquetes, qué entorno
declara, qué fuentes de contexto hay, qué no recorrió, qué impide continuar y
qué se puede hacer después. Conserva todo el contrato de V0
([`CLI-V0.md`](CLI-V0.md)).

## Qué hace y qué no hace

`shipflow init --dry-run`:

- lee los manifiestos `pubspec.yaml` y los marcadores `.fvmrc` y
  `flutter-version.txt` de la carpeta actual;
- informa la tecnología candidata (Dart o Flutter), los paquetes, las
  relaciones locales que declaran, su descripción y su entorno declarado, con
  la evidencia de cada afirmación;
- consulta sólo los **metadatos** de un catálogo fijo de fuentes candidatas
  (documentación, instrucciones, configuración de análisis, tareas y CI);
- informa los árboles que no recorrió y la regla que lo decidió;
- deriva la vista humana y la JSON del mismo reporte, sin una segunda
  inspección y sin modelos de IA.

No hace, y no afirma haber hecho:

- no modifica, crea ni borra archivos del proyecto;
- **no guarda el reporte** ni crea un expediente: el reporte existe sólo en esa
  ejecución (la terminal puede conservar su propio historial);
- no abre el contenido de las fuentes candidatas: un README, un Makefile o un
  workflow «encontrado» no se leyó ni se contrastó, y nada de lo que diga se
  ejecuta ni se interpreta;
- no ejecuta herramientas, compilaciones ni tests del proyecto, no ejecuta Pub
  ni lee `.dart_tool/package_config.json`, no comprueba su arquitectura ni que
  sus recursos existan, no usa red y no consulta el SDK instalado;
- no aplica la inicialización: una propuesta «elegible» es una propuesta sin
  aplicar;
- no diagnostica la salud del proyecto ni es un inventario global: «sin
  contradicciones entre las declaraciones examinadas» describe esta ficha, no
  la calidad del código, y puede haber paquetes no referenciados dentro de lo
  que no se recorrió.

## Instalación y primer uso

Todavía no hay descargas publicadas. El binario se construye desde el código con
la build oficial (requiere el SDK de Dart **sólo para construirlo**):

```bash
dart pub get --enforce-lockfile
mkdir -p build
dart run packages/cli/tool/build_release.dart \
  --version 0.1.0-dev.1 \
  --output build/release-0.1.0-dev.1
```

La build compila, ejecuta el artefacto en el host y genera `SHA256SUMS`. Verifica
el checksum, copia el artefacto de tu plataforma a un directorio de tu `PATH`
con el nombre `shipflow` y comprueba `shipflow --version`. El binario es
autocontenido: usarlo no requiere Dart ni Flutter instalados. Verificar la
instalación no inicializa ningún proyecto.

Primer uso, desde la carpeta del proyecto. Una app Flutter con un catálogo que
depende de ella:

```bash
cd mi-app
shipflow init --dry-run
```

```text
Shipflow · reconocimiento del proyecto
Identidad reconocida dentro del alcance indicado
Carpeta: /proyectos/mi-app

Identidad
  Tecnología: Flutter
  mi_app se describe como «Aplicación de pedidos» · pubspec.yaml

Unidades y relaciones
  Paquetes observados: 2
    mi_app · .
    catalogo · catalogo
  Relaciones declaradas: 1
    catalogo → . · dependencia local «mi_app» · corroborada

Entorno declarado
  Restricción declarada del SDK de Dart: ^3.12.0 · catalogo/pubspec.yaml
  Restricción declarada del SDK de Dart: ^3.12.0 · pubspec.yaml
  Sin contradicciones entre las declaraciones examinadas.
  Son declaraciones del proyecto: no se comprobó qué SDK está instalado.

Fuentes candidatas (no se abrió ni contrastó su contenido)
  README.md · documentación · archivo encontrado
  Otras 15 rutas del catálogo no existen.

Cobertura
  No se recorrieron, por reglas de alcance:
    directorio temporal (1): ios/Flutter/ephemeral
    recurso declarado (1): assets/images
  Puede haber paquetes no referenciados dentro de lo omitido: esta ficha no es un inventario global.

Resultado
  No se detectaron conflictos ni límites en este reconocimiento.
  La propuesta es elegible, pero no se aplicó.
  No se comprobó si el proyecto compila, si sus pruebas pasan, si respeta su arquitectura, si sus recursos existen ni si el SDK está instalado.
  No se modificó el proyecto. Shipflow no guardó este reporte ni creó un expediente.
  La inspección terminó. Esta versión sólo entrega esta ficha: no aplica la inicialización ni inicia tareas.

Para repetir la inspección con detalle estructurado:
  shipflow init --dry-run --json
```

Si una dependencia requiere un paquete dentro de un árbol omitido, la ficha no
lo completa y lo dice:

```text
Reconocimiento no concluyente
Carpeta: /proyectos/mi-app
Hay 1 causa que impide continuar; se detalla en «Resultado».
…
Resultado
  Qué impide continuar:
    required_path_excluded (1):
      - la dependencia local «dependencies.modulo: assets/images/modulo» apunta dentro de «assets/images», omitido por las reglas de alcance; queda sin corroborar y bloquea la propuesta. Puedes inspeccionar esa ruta por separado. · pubspec.yaml
  La propuesta no puede aplicarse: hay limitaciones bloqueantes.
```

## Gramática

```text
shipflow init --dry-run [--json] [--report-budget=standard|extended]
shipflow init --help [--json]
```

- `init` debe ser el primer argumento; no hay argumento de ruta: se inspecciona
  la carpeta actual.
- `init` sin `--dry-run` es uso inválido (`64`) y explica el comando válido.
- `--report-budget` se acepta sólo después de `init`, junto con `--dry-run`, una
  vez y con la forma exacta `--report-budget=standard` o
  `--report-budget=extended`. Un valor vacío, desconocido, numérico o con
  mayúsculas, la forma separada (`--report-budget extended`), la repetición
  (aunque sea idéntica), el uso fuera de `init` o junto con la ayuda son uso
  inválido (`64`), antes de inspeccionar nada.
- Omitirlo equivale a `standard`. La elección vale sólo para esa invocación: no
  hay configuración, variable de entorno ni ampliación automática.

## Vista humana

Después del encabezado y la carpeta (y su alias, si corresponde), una línea
anuncia cuántas causas impiden continuar, si las hay. Siguen seis bloques:

1. **Identidad**: tecnología y la descripción declarada de cada paquete, con su
   fuente.
2. **Unidades y relaciones**: los paquetes y cada relación local con su origen,
   destino y estado (`corroborada` o `sin resolver`).
3. **Entorno declarado**: cada declaración de SDK o versión con su fuente, si
   las declaraciones examinadas se contradicen, y que no se comprobó el SDK
   instalado.
4. **Fuentes candidatas**: las encontradas, con su tipo; las ausentes sólo se
   cuentan.
5. **Cobertura**: los árboles que no se recorrieron, agrupados por regla.
6. **Resultado**: primero lo que impide continuar, después las advertencias que
   no bloquean; la propuesta, lo que no se comprobó, que nada se guardó, la
   acción disponible y cómo obtener el JSON.

Un reporte compacto o una carpeta inválida no tienen inventario: sólo muestran
el resultado.

| Estado | Encabezado | Acción que se sugiere |
|---|---|---|
| `recognized` | Identidad reconocida dentro del alcance indicado | La inspección terminó; esta versión sólo entrega la ficha. |
| `ambiguous` | Reconocimiento no concluyente | Revisar las fuentes en contradicción, o las causas; si una depende del alcance de esta versión, esta versión no puede resolverla. |
| `unsupported` | Proyecto no soportado | Esta versión reconoce Dart y Flutter por sus manifiestos y marcadores. |
| `invalid_root` | No se pudo inspeccionar la carpeta | Comprobar que la carpeta exista y que se pueda leer. |

- Las causas y advertencias se agrupan por su código, con la cuenta real y
  hasta cinco filas por grupo; se muestran hasta 10 grupos de cada clase. Una
  limitación nunca se presenta como conflicto, y una omisión nunca oculta una
  causa que bloquea.
- Se muestran hasta 20 paquetes, 20 relaciones, 20 declaraciones de entorno o
  descripción y 20 fuentes encontradas; lo demás se cuenta («Hay N …
  adicionales; consulta la salida JSON.»). Estos cortes son de la vista: no
  cambian evidencia, elegibilidad ni presupuesto.
- Cada conflicto lista sus fuentes con su valor. Shipflow no elige una versión.
- No se imprimen IDs de evidencia, hashes ni nombres internos de plugins: están
  en el JSON.
- Cada valor ocupa una línea: se escapan controles, saltos de línea y controles
  bidireccionales, y se corta en 240 runes visibles con `…`. Un texto del
  proyecto, como una descripción, se muestra entre comillas y nunca se usa
  como instrucción.

## Estados y códigos

| Código | Significado |
|---:|---|
| `0` | `recognized`: un candidato inequívoco, con unidades, sin conflictos ni limitaciones bloqueantes |
| `65` | `ambiguous` o `unsupported` |
| `66` | `invalid_root`: la carpeta no existe o no se puede leer |
| `64` | uso inválido |
| `70` | fallo interno inesperado: mensaje genérico, sin traza ni rutas |

Omisiones, fuentes candidatas y advertencias no bloquean por sí solas. El
reporte va a `stdout` en ambos formatos y `stderr` queda vacío.

## JSON

Una línea UTF-8 con **`schemaVersion: 2`**, `type: "init_dry_run"` y, en este
orden, `status`, `requestedRoot`, `resolvedRoot`, `repository`,
`recognitionScope`, `candidates`, `units`, `evidence`, `conflicts`,
`limitations`, `relations`, `contextSources`, `omissions`, `proposal`,
`effects` y `exitCode`. Los campos opcionales se escriben como `null` y las
listas vacías, como `[]`.

Sólo esta respuesta cambia de versión: ayuda, versión y errores de uso
conservan `schemaVersion: 1`. Un consumidor que sólo admite la versión 1 debe
rechazar la 2 en vez de leerla en silencio; V1 no importa reportes guardados.

- `recognitionScope` es siempre `"declared_project_recognition"`: lo que el
  proyecto declara y se observó, no un inventario global.
- Cada evidencia agrega `role` (`identity`, `environment`, `description`,
  `relation`, `resource`) y `label`, cómo nombrarla ante una persona; `kind`
  sigue siendo opaco.
- `relations`: `id` (`r0001`…), `kind` (`local_dependency` o
  `workspace_member`), `fromPath`, `declaredName`, `targetPath`,
  `targetUnitId`, `status` (`corroborated` o `unresolved`) y `evidenceIds`.
- `contextSources`: `scopePath`, `path`, `kind` (`documentation`,
  `instructions`, `analysis_configuration`, `task_configuration`,
  `ci_configuration`), `entityType` (`file`, `directory`, `link`, `special`,
  `missing`, `unavailable`), `reason` (`observed`, `not_found`,
  `access_failed`, `ancestor_link`, `excluded`) y `contentStatus`, siempre
  `"not_inspected"`. No tienen huella: no se leyó nada.
- `omissions`: `path`, `rule` (`baseline_exclusion`, `temporary_directory`,
  `declared_resource`) y `evidenceIds`, la declaración que justifica la regla.

Ninguna cadena extraída del proyecto pasa de 4096 bytes UTF-8: si la supera, se
conserva un adelanto con `…` y se agrega la limitación bloqueante
`observed_value_truncated`; el adelanto se muestra pero nunca se interpreta.
Una descripción que no cabe se omite entera con una advertencia.

Códigos de limitación que pueden aparecer: `symlink_not_followed`,
`subtree_unreadable`, `scan_limit_reached`, `source_too_large`,
`source_unreadable`, `source_changed_during_scan`, `invalid_manifest`,
`invalid_toolchain_marker`, `invalid_constraint`,
`path_dependency_outside_root`, `path_dependency_unresolved`,
`required_path_excluded`, `required_manifest_missing`,
`unsupported_local_reference`, `observed_value_truncated` y
`report_limit_reached`, que bloquean; `optional_description_unavailable` y
`unsupported_resource_declaration`, que sólo advierten; y `root_not_found`,
`root_not_directory` y `root_inaccessible` para `invalid_root`. Códigos de
conflicto: `toolchain_versions_disagree`, `toolchain_outside_constraint`,
`flutter_constraints_disjoint`, `sdk_constraints_disjoint`,
`duplicate_package_name` y `local_dependency_name_mismatch`.

## Perfiles del reporte

El reporte derivado se acota antes de construirse. Cada perfil fija tres
máximos inclusivos, que se eligen juntos:

| Máximo | `standard` (omisión) | `extended` |
|---|---:|---:|
| Elementos del reporte (filas y referencias a evidencia) | 16.384 | 18.432 |
| Texto del reporte (UTF-8) | 1.048.576 bytes | 1.835.008 bytes |
| Respuesta JSON completa | 2.097.152 bytes | 2.359.296 bytes |

Cuenta cada fila de cada lista —relaciones, fuentes candidatas y omisiones
incluidas—, cada referencia a evidencia y los bytes de cada texto retenido,
también los valores de enumeración y las etiquetas. El tamaño JSON se comprueba
también al pedir la vista humana, para que el formato no cambie el resultado.
No son reservas de memoria ni un límite del proceso entero.

Si se alcanza un máximo, Shipflow **no publica un inventario parcial**: devuelve
`ambiguous` (`65`) con las raíces y el contexto Git, todas las listas vacías,
una sola limitación bloqueante `report_limit_reached` y la propuesta no
elegible. El mensaje nombra la dimensión y el perfil:

```text
El reconocimiento alcanzó el límite de texto del reporte del perfil normal; no se publica un inventario parcial.
Puedes repetir con shipflow init --dry-run --report-budget=extended. El perfil ampliado puede consumir más recursos.
```

En `extended`, en cambio: «Se alcanzó el máximo disponible en esta versión.
Inspecciona una raíz tecnológica más acotada; esto cambia el alcance de la
inspección.» No hay un perfil ilimitado. La línea de detalle conserva el perfil
activo (`shipflow init --dry-run --json --report-budget=extended`) y vuelve a
inspeccionar.

**Coste observado** (macOS ARM64, mediciones, no garantías): proyectos reales
de 2 a 131 paquetes tardaron 0,02–0,34 s con unos 19–22 MB de memoria
residente y cupieron en `standard`; con la ficha completa, una app Flutter de
dos paquetes tardó unos 0,06 s y 20 MB. Un caso sintético de 513 paquetes
excedió el texto de `standard` y cupo en `extended`. Un caso patológico de ocho
manifiestos de 250 KB se detiene en ambos perfiles con un reporte compacto.

## Límites de lectura

Independientes del perfil; ampliar el reporte no amplía la inspección:

- 100.000 entradas, profundidad 32, 4.096 manifiestos, 262.144 bytes por
  manifiesto, 4.096 bytes por marcador y 16.777.216 bytes de fuentes en total;
  cada consulta de una fuente candidata consume una entrada, aunque falte;
- no se siguen enlaces simbólicos.

Alcanzar uno de estos límites produce una limitación bloqueante y **conserva**
lo ya observado: el resultado es no concluyente, pero no se descarta.

## Alcance del recorrido

Cada directorio se lee en orden y su manifiesto se analiza **antes** de
descender, una sola vez: así se sabe qué excluye antes de entrar. No se
recorren, y quedan como omisiones:

- en cualquier lugar, `.git`, `.dart_tool`, `build`, `.symlinks`, `Pods` y
  `node_modules`;
- en un paquete cuyo propio manifiesto declara la dependencia del SDK Flutter,
  su `ios/Flutter/ephemeral` exacto y cada directorio literal que declare en
  `flutter.assets` dentro de `assets/` (con `/` final, `./` inicial admitido).

Un árbol excluido se omite aunque sea un enlace, sin seguirlo ni enumerar su
destino. Fuera de esas reglas, un enlace bloquea: una carpeta con el mismo
nombre en otra ruta, o un `assets` sin declarar, no obtiene excepción. Un
manifiesto inválido, inestable, enlazado, sin nombre o con una limitación que
bloquea no concede exclusiones. Una entrada
de archivo en `flutter.assets` no excluye su carpeta; `flutter.fonts` no se
interpreta; una forma no soportada (absoluta, con `..`, patrones, URI,
separadores invertidos, fuera de `assets/`) se advierte y no excluye nada.

Las exclusiones son reglas de alcance: no prueban que lo de adentro sea
generado, seguro o irrelevante.

## Fuentes candidatas

En la carpeta y en la raíz de cada paquete se consultan, sólo por metadatos y
sin seguir enlaces: `README.md`, `analysis_options.yaml`, `Makefile`,
`.gitlab-ci.yml`, `docs/`, `.github/workflows/`, `AGENTS.md` y `CLAUDE.md`. El
catálogo es fijo; no hay búsqueda por contenido.

- Un archivo opcional del catálogo que es un enlace se informa como enlace y no
  bloquea la ficha.
- Un directorio real con uno de esos nombres se recorre como cualquier otro: si
  `docs/` o `.github/` no se pueden listar o son enlaces, siguen bloqueando la
  cobertura.
- Una fuente dentro de un árbol omitido se informa no disponible, sin entrar.

## Carpeta y alias

La autoridad de acceso es el directorio actual, resuelto a su ruta real. Si el
entorno trae `PWD` absoluto, sin NUL, de hasta 4096 bytes y que resuelve a esa
misma carpeta, se muestra como alias: `requestedRoot` conserva la ruta lógica y
`resolvedRoot` la real. Un `PWD` ausente, relativo o que apunta a otra carpeta
se ignora sin bloquear. `PWD` nunca cambia qué se lee ni rescata una carpeta
inválida.

## Relaciones locales

Cada dependencia `path:` de `dependencies`, `dev_dependencies` y
`dependency_overrides`, y cada miembro de `workspace`, es una relación. Sólo se
interpretan rutas literales: una vacía, con URI o con patrones es
`unsupported_local_reference`, y un miembro del workspace tiene que ser relativo
y descendiente: `.` y `./` no lo son. Una ruta o un miembro que no es texto
(`null`, un número) es `invalid_manifest`, y la relación se conserva sin
resolver. La ruta se recorre tramo a tramo sin seguir enlaces y se detiene en
la primera frontera: un enlace, la salida de la raíz, un árbol omitido o algo
que no es un directorio. No se mira nada más allá, así que el resultado no
depende del destino de un enlace ni de lo que haya fuera de la raíz.

Una relación queda **corroborada** sólo si su destino es un paquete observado
con manifiesto válido y nombre y, en una dependencia, con el mismo nombre que
declara. Eso prueba que la declaración corresponde a un paquete, no que se use,
compile ni resuelva sus dependencias. Si no, queda **sin resolver** y bloquea:

| Causa | Código |
|---|---|
| El trayecto sale de la raíz, aunque vuelva a entrar | `path_dependency_outside_root` |
| No se puede decidir: NUL, tramo sin permiso, un tramo debajo de un archivo, `..` tras un tramo inexistente | `path_dependency_unresolved` |
| Pasa por un enlace, roto o no, o usa una forma no soportada | `unsupported_local_reference` |
| La ruta o el miembro no es texto | `invalid_manifest` |
| Entra en un árbol omitido, aunque ese árbol sea un enlace | `required_path_excluded` |
| El destino no existe o no tiene un manifiesto con nombre | `required_manifest_missing` |
| El destino se llama distinto de lo declarado | conflicto `local_dependency_name_mismatch` |

Cada diagnóstico nombra la declaración, la causa, su efecto sobre la propuesta
y la alternativa disponible. Un árbol omitido no se reabre para completar la
relación: inspeccionar esa ruta por separado produce otra ficha, que no
completa la original.

## Garantía frente a cambios concurrentes

Shipflow fija la carpeta real al empezar, comprueba cada directorio y archivo
antes y después de usarlo, y descarta lo que cambió de tipo, se volvió un enlace
o salió de la carpeta (`source_changed_during_scan`, `symlink_not_followed`).
Estas comprobaciones **detectan y descartan**; no son atómicas. Si otro proceso
sustituye una ruta justo entre la comprobación y la apertura, puede ocurrir una
lectura fuera de la carpeta antes de descartarla. V1 no ofrece aislamiento ni
confidencialidad frente a un proceso que manipula deliberadamente las rutas
mientras se inspecciona; no se recomienda usarlo sobre árboles que controla un
tercero de forma concurrente.

## Límite conocido

Si el directorio actual fue borrado o no se puede acceder a él, el runtime de
Dart termina con código `255` y un mensaje en `stderr` antes de que Shipflow
arranque; en ese caso no se emite el reporte `invalid_root`.

## Cambios respecto del corte anterior de V1

- El JSON de `init --dry-run` pasa a `schemaVersion: 2`, con `recognitionScope`,
  `role` y `label` en cada evidencia, y las listas `relations`,
  `contextSources` y `omissions`.
- La vista humana es una ficha de seis bloques, con las causas agrupadas antes
  que las advertencias; el reconocimiento verde se anuncia como «Identidad
  reconocida dentro del alcance indicado».
- Un paquete Flutter ya no recorre su carpeta temporal de iOS ni sus
  directorios de assets declarados; antes, los enlaces que suelen contener
  bloqueaban la propuesta.
- Una dependencia local que antes quedaba «dentro» sin más comprobación ahora
  sólo es verde si su destino es un paquete observado con el mismo nombre.
