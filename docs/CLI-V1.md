# Contrato público del CLI V1 · `shipflow init --dry-run`

V1 agrega un comando: reconocer un proyecto Dart o Flutter existente **sin
modificarlo**. Shipflow mira la carpeta actual, identifica la tecnología y los
paquetes, y explica qué encontró, qué impide continuar, qué no comprobó y qué se
puede hacer después. Conserva todo el contrato de V0 ([`CLI-V0.md`](CLI-V0.md)).

## Qué hace y qué no hace

`shipflow init --dry-run`:

- lee los manifiestos `pubspec.yaml` y los marcadores `.fvmrc` y
  `flutter-version.txt` de la carpeta actual;
- informa la tecnología candidata (Dart o Flutter), los paquetes observados, las
  evidencias que lo sostienen, los conflictos y las limitaciones;
- deriva la vista humana y la JSON del mismo reporte, sin una segunda
  inspección y sin modelos de IA.

No hace, y no afirma haber hecho:

- no modifica, crea ni borra archivos del proyecto;
- **no guarda el reporte** ni crea un expediente: el reporte existe sólo en esa
  ejecución (la terminal puede conservar su propio historial);
- no ejecuta herramientas, compilaciones ni tests del proyecto, no usa red y no
  consulta el SDK instalado;
- no aplica la inicialización: una propuesta «elegible» es una propuesta sin
  aplicar;
- no diagnostica la salud del proyecto: «no se detectaron conflictos ni límites»
  describe este reconocimiento, no la calidad del código.

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

Primer uso, desde la carpeta del proyecto:

```bash
cd mi-app
shipflow init --dry-run
```

```text
Shipflow · reconocimiento del proyecto
Proyecto reconocido
Carpeta: /proyectos/mi-app
Tecnología: Flutter
Paquetes observados: 1
  mi_app · .

No se detectaron conflictos ni límites en este reconocimiento.
La propuesta es elegible, pero no se aplicó.
No se comprobó si el proyecto compila, si sus pruebas pasan o si el SDK está instalado.

No se modificó el proyecto. Shipflow no guardó este reporte ni creó un expediente.
La inspección terminó. Esta versión todavía no aplica la inicialización ni inicia tareas.
Para repetir la inspección con detalle estructurado:
  shipflow init --dry-run --json
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

En este orden: resultado, carpeta (y alias si corresponde), tecnología,
paquetes observados, conflictos y limitaciones, alcance, efectos, acción
disponible y cómo obtener el detalle JSON.

| Estado | Encabezado | Acción que se sugiere |
|---|---|---|
| `recognized` | Proyecto reconocido | La inspección terminó; esta versión no aplica la inicialización. |
| `ambiguous` | Reconocimiento no concluyente | Revisar las fuentes indicadas y repetir tras decidir la corrección; o revisar las limitaciones. |
| `unsupported` | Proyecto no soportado | Esta versión reconoce Dart y Flutter por sus manifiestos y marcadores. |
| `invalid_root` | No se pudo inspeccionar la carpeta | Comprobar que la carpeta exista y que se pueda leer. |

- Se muestran hasta 20 paquetes, 10 conflictos y 10 limitaciones; lo demás se
  cuenta («Hay N … adicionales; consulta la salida JSON.»). Si hay un bloqueo,
  se anuncia aunque quede fuera de las filas visibles.
- Cada conflicto lista sus fuentes con su valor. Shipflow no elige una versión.
- No se imprimen IDs de evidencia, hashes ni nombres internos de plugins: están
  en el JSON.
- Cada valor del proyecto ocupa una línea: se escapan controles, saltos de línea
  y controles bidireccionales, y se corta en 240 runes visibles con `…`.

## Estados y códigos

| Código | Significado |
|---:|---|
| `0` | `recognized`: un candidato inequívoco, sin conflictos ni bloqueos |
| `65` | `ambiguous` o `unsupported` |
| `66` | `invalid_root`: la carpeta no existe o no se puede leer |
| `64` | uso inválido |
| `70` | fallo interno inesperado: mensaje genérico, sin traza ni rutas |

El reporte va a `stdout` en ambos formatos y `stderr` queda vacío.

## JSON

Una línea UTF-8 con `schemaVersion: 1`, `type: "init_dry_run"` y, en este
orden, `status`, `requestedRoot`, `resolvedRoot`, `repository`, `candidates`,
`units`, `evidence`, `conflicts`, `limitations`, `proposal`, `effects` y
`exitCode`. Los campos opcionales se escriben como `null`. Ninguna cadena
extraída del proyecto pasa de 4096 bytes UTF-8: si la supera, se conserva un
adelanto con `…` y se agrega la limitación bloqueante
`observed_value_truncated`; el adelanto se muestra pero nunca se interpreta.

Códigos de limitación que pueden aparecer: `symlink_not_followed`,
`subtree_unreadable`, `scan_limit_reached`, `source_too_large`,
`source_unreadable`, `source_changed_during_scan`, `invalid_manifest`,
`invalid_toolchain_marker`, `invalid_constraint`,
`path_dependency_outside_root`, `path_dependency_unresolved`,
`observed_value_truncated` y `report_limit_reached` (además de
`root_not_found`, `root_not_directory` y `root_inaccessible` para
`invalid_root`).

## Perfiles del reporte

El reporte derivado se acota antes de construirse. Cada perfil fija tres
máximos inclusivos, que se eligen juntos:

| Máximo | `standard` (omisión) | `extended` |
|---|---:|---:|
| Elementos del reporte (filas y referencias a evidencia) | 16.384 | 18.432 |
| Texto del reporte (UTF-8) | 1.048.576 bytes | 1.835.008 bytes |
| Respuesta JSON completa | 2.097.152 bytes | 2.359.296 bytes |

El tamaño JSON se comprueba también al pedir la vista humana, para que el
formato no cambie el resultado. No son reservas de memoria ni un límite del
proceso entero.

Si se alcanza un máximo, Shipflow **no publica un inventario parcial**: devuelve
`ambiguous` (`65`) con las raíces y el contexto Git, sin candidatos, unidades,
evidencias ni conflictos, una sola limitación bloqueante `report_limit_reached`
y la propuesta no elegible. El mensaje nombra la dimensión y el perfil:

```text
El reconocimiento alcanzó el límite de texto del reporte del perfil normal; no se publica un inventario parcial.
Puedes repetir con shipflow init --dry-run --report-budget=extended. El perfil ampliado puede consumir más recursos.
```

En `extended`, en cambio: «Se alcanzó el máximo disponible en esta versión.
Inspecciona una raíz tecnológica más acotada; esto cambia el alcance de la
inspección.» No hay un perfil ilimitado. La línea de detalle conserva el perfil
activo (`shipflow init --dry-run --json --report-budget=extended`) y vuelve a
inspeccionar.

**Coste observado** (macOS ARM64, binario de esta versión; mediciones, no
garantías): proyectos reales de 2 a 131 paquetes tardaron 0,02–0,34 s con unos
19–22 MB de memoria residente y cupieron en `standard`. Un caso sintético de 513
paquetes excedió el texto de `standard` y cupo en `extended` (0,33 s, unos
70 MB, 1,83 MB de JSON). Un caso patológico de ocho manifiestos de 250 KB que
antes producía 34,5 MB de JSON ahora se detiene en ambos perfiles (unos 0,06 s,
unos 60 MB, 791 bytes de salida).

## Límites de lectura

Independientes del perfil; ampliar el reporte no amplía la inspección:

- 100.000 entradas, profundidad 32, 4.096 manifiestos, 262.144 bytes por
  manifiesto, 4.096 bytes por marcador y 16.777.216 bytes de fuentes en total;
- no se siguen enlaces simbólicos; se excluyen `.git`, `.dart_tool`, `build`,
  `.symlinks`, `Pods` y `node_modules`.

Alcanzar uno de estos límites produce una limitación bloqueante y **conserva**
lo ya observado: el resultado es no concluyente, pero no se descarta.

## Carpeta y alias

La autoridad de acceso es el directorio actual, resuelto a su ruta real. Si el
entorno trae `PWD` absoluto, sin NUL, de hasta 4096 bytes y que resuelve a esa
misma carpeta, se muestra como alias: `requestedRoot` conserva la ruta lógica y
`resolvedRoot` la real. Un `PWD` ausente, relativo o que apunta a otra carpeta
se ignora sin bloquear. `PWD` nunca cambia qué se lee ni rescata una carpeta
inválida.

## Dependencias locales

Las rutas `path:` de `dependencies`, `dev_dependencies` y
`dependency_overrides` se resuelven como lo haría el sistema, siguiendo cada
enlace antes del siguiente `..`. Ninguna se atraviesa.

- `path_dependency_outside_root`: el destino está demostradamente fuera de la
  carpeta.
- `path_dependency_unresolved`: no se pudo decidir (enlace roto, NUL, un tramo
  sin permiso, `..` después de un tramo inexistente).
- Una ruta inexistente bajo un prefijo interior queda dentro: pertenecer a la
  carpeta no significa que la dependencia exista ni que esté instalada.

Ambas limitaciones bloquean la propuesta y citan la dependencia que las causa.

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

## Cambios respecto del primer corte de V1

Este binario agrega `--report-budget`, el reporte `report_limit_reached`, el
alias por `PWD`, la limitación `path_dependency_unresolved` y la vista humana de
primer uso. Proyectos que antes producían un reporte enorme ahora devuelven el
reporte compacto. El JSON conserva `schemaVersion: 1` y su forma.
