# 🛡️ shipflow

> Un arnés supervisor para producir cambios de software verificables, trazables
> y recuperables. Hoy ofrece un CLI Dart que reconoce proyectos Dart y Flutter
> sin modificarlos, y un arnés de arquitectura cuyas reglas **saben ponerse
> rojas**.

## 📖 Tabla de contenidos

- [Contexto](#-contexto)
- [Estado](#-estado)
- [Instalación](#️-instalación)
- [Uso del ejecutable](#-uso-del-ejecutable)
- [Herramientas de construcción](#-herramientas-de-construcción)
- [Gobierno](#-gobierno)
- [Mantenedores](#-mantenedores)
- [Contribución](#-contribución)

## 🧠 Contexto

Un check que nunca se disparó es indistinguible de uno roto. Y una ausencia de
resultados se lee igual que «no había nada que objetar».

Sobre esas dos ideas está construido este repositorio: el producto informa lo que
no pudo comprobar en vez de callarlo, y el arnés demuestra que sus controles
fallan cuando deben. Las reglas de arquitectura
viven en un registro único y diffeable; dos motores las aplican —uno lee texto,
otro necesita el árbol sintáctico—; y una suite de sabotajes inyecta violaciones
sintéticas en cada corrida para comprobar que cada control **todavía detecta lo
que dice detectar**, incluido el caso donde se le quita la vista.

Qué corre exactamente, qué regla impide qué, y quién aplica cada una está en
**[`GOBIERNO.md`](GOBIERNO.md)**, y lo verifica el propio arnés contra el registro
y contra el workflow.

## 🚦 Estado

El ejecutable tiene dos superficies:

- **V0**, identidad y distribución: ayuda, versión y respuestas JSON. Contrato en
  [`docs/CLI-V0.md`](docs/CLI-V0.md).
- **V1**, `shipflow init --dry-run`: reconoce la tecnología, los paquetes, los
  conflictos y las limitaciones de un proyecto Dart o Flutter **sin modificarlo
  ni guardar nada**. Contrato en [`docs/CLI-V1.md`](docs/CLI-V1.md).

Shipflow todavía no inicializa proyectos, no persiste estado, no ejecuta agentes
y no implementa `doctor`, `analyze`, `plan`, `implement`, `verify`, `review` ni
`ship`. Los paquetes sin uso en V1 (`agents`, `forge`, `orchestration`, `rules`)
son reservas declaradas.

Las preguntas de diseño sin responder y los puntos ciegos conocidos del arnés
están en **[`HUECOS.md`](HUECOS.md)**, con su procedencia.

## ⚙️ Instalación

Todavía no hay descargas publicadas: el ejecutable se construye desde el código.
Construirlo requiere el SDK de Dart; usar el binario resultante, no.

```bash
dart pub get --enforce-lockfile
mkdir -p build
dart run packages/cli/tool/build_release.dart \
  --version 0.1.0-dev.1 \
  --output build/release-0.1.0-dev.1
```

La build compila, ejecuta el artefacto en el host y genera `SHA256SUMS`. Verificá
el checksum, copiá el artefacto de tu plataforma a un directorio de tu `PATH` con
el nombre `shipflow` y comprobá `shipflow --version`. Verificar la instalación no
inicializa ningún proyecto.

## 🚀 Uso del ejecutable

Desde la carpeta de un proyecto Dart o Flutter:

```bash
shipflow init --dry-run                           # resumen legible
shipflow init --dry-run --json                    # el reporte completo, una línea JSON
shipflow init --dry-run --report-budget=extended  # admite un reporte mayor
```

El resumen dice qué se reconoció, qué impide continuar, qué no se comprobó
(compilación, tests, SDK instalado) y que no se modificó ni guardó nada. El JSON
conserva todo el detalle. Si un proyecto es demasiado grande para el perfil
normal, Shipflow lo dice y sugiere `--report-budget=extended`; no publica un
inventario parcial. Estados, códigos de salida, perfiles, límites y la garantía
frente a cambios concurrentes están en [`docs/CLI-V1.md`](docs/CLI-V1.md).

## 🧰 Herramientas de construcción

Esto es para mantener el repositorio, no para usar Shipflow. Requisitos: Dart
SDK 3.11 o superior y Python 3.11 o superior con `pyyaml`. Resolver dependencias
es precondición de los checks, porque el grafo de paquetes se le pide a `pub`:

```bash
dart pub get --enforce-lockfile
(cd tool/analisis && dart pub get --enforce-lockfile)
dart test packages/core packages/vcs packages/plugin_dart packages/cli
```

Los checks, **en serie**:

```bash
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart)
(cd tool/analisis && dart run bin/grafo.dart)
python3 tool/checks/probar_recuperacion.py
python3 tool/checks/probar_reglas.py
```

No se paralelizan los dos últimos: comparten un archivo de estado, y correrlos a
la vez es una carrera cuyo fallo no se parece a su causa.

Y el resto de la compuerta:

```bash
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed packages tool
```

`--output=none` porque una compuerta verifica y no muta.

## ⚖️ Gobierno

Las reglas se declaran en `arquitectura.json`; los símbolos concretos que cada una
gobierna, en `inventario.json`. Los dos llevan huella propia: cambiar uno sin
regenerar su huella pone el check en rojo, de modo que tocar la arquitectura es un
acto visible y revisable.

Todo el detalle está en [`GOBIERNO.md`](GOBIERNO.md).

## 👥 Mantenedores

- [@GuzCabQ](https://github.com/GuzCabQ)

## 🤝 Contribución

Los PRs son bienvenidos. Antes de abrir uno, leé [`GOBIERNO.md`](GOBIERNO.md):
describe qué corre, qué regla impide qué, y por qué agregar una regla implica
agregar también la violación canónica que demuestra que sabe dispararse.
