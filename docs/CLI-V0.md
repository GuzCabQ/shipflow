# Contrato público del CLI V0

V0 establece la identidad ejecutable y distribuible de Shipflow. Su superficie
pública se limita a ayuda, versión y respuestas JSON. No activa todavía ninguna
etapa del ciclo de desarrollo.

> **Relación con V1.** Este documento conserva el contrato de V0. V1 lo extiende
> con `shipflow init --dry-run`, descrito en [`CLI-V1.md`](CLI-V1.md): la ayuda
> raíz agrega la línea de uso de `init` y una sección «Comandos», y `init` deja
> de ser un argumento inesperado. Ayuda, versión, errores de uso, códigos y la
> forma de sus respuestas JSON se conservan tal como se describen aquí, con
> `schemaVersion: 1`; sólo la respuesta de `init --dry-run` tiene su propia
> versión.

## Plataformas verificadas

| Plataforma | Estado |
|---|---|
| Linux x64 | El artefacto se compila y ejecuta en CI sobre Ubuntu 24.04. |
| macOS ARM64 | El artefacto se compila y ejecuta en CI sobre macOS 14. |

macOS x64, Linux ARM64 y Windows no están declarados como soportados en V0.

## Gramática

```text
shipflow
shipflow [-h | --help] [--json]
shipflow --version [--json]
```

- Sin argumentos se muestra la ayuda.
- `--json` sin otra acción devuelve la ayuda estructurada.
- `-h` y `--help` representan la misma acción.
- Repetir opciones, combinar ayuda con versión, usar argumentos posicionales o
  enviar opciones desconocidas produce un error de uso.
- El token exacto `--json` selecciona el protocolo estructurado incluso cuando
  otro argumento es inválido.
- No se aceptan abreviaturas, asignaciones como `--json=true` ni capacidades
  documentadas para versiones futuras.

## Salida humana

La ayuda exacta de V0 era la siguiente; en V1 incluye además `init` (ver la
nota del inicio):

```text
Shipflow supervisa cambios de software verificables y recuperables.

Uso:
  shipflow [--help] [--json]
  shipflow --version [--json]

Opciones:
  -h, --help  Muestra esta ayuda.
  --version   Muestra la versión del ejecutable.
  --json      Emite una única respuesta JSON.
```

La versión utiliza esta forma:

```text
shipflow <semver>
```

Un error de uso se escribe en `stderr`:

```text
shipflow: <motivo concreto>
Usa 'shipflow --help'.
```

Los argumentos reflejados se escapan y acotan para impedir que una entrada
hostil inyecte líneas o produzca una salida sin límite.

## Salida JSON

Cada respuesta controlada ocupa exactamente una línea UTF-8 en `stdout` y deja
`stderr` vacío.

Ayuda (en V0; en V1 agrega `init` a `usage` y una lista `commands`):

```json
{"schemaVersion":1,"type":"help","name":"shipflow","usage":["shipflow [--help] [--json]","shipflow --version [--json]"],"options":[{"flags":["-h","--help"],"description":"Muestra esta ayuda."},{"flags":["--version"],"description":"Muestra la versión del ejecutable."},{"flags":["--json"],"description":"Emite una única respuesta JSON."}],"exitCode":0}
```

Versión:

```json
{"schemaVersion":1,"type":"version","name":"shipflow","version":"<semver>","exitCode":0}
```

Error de uso:

```json
{"schemaVersion":1,"type":"error","code":"invalid_usage","message":"<motivo concreto>","exitCode":64}
```

## Códigos y canales

| Código | Significado | Canal humano |
|---:|---|---|
| `0` | Ayuda o versión emitida correctamente | `stdout` |
| `64` | Uso inválido | `stderr` |
| `70` | No pudo completarse una operación interna o de salida | `stderr` |

En modo JSON, las respuestas controladas usan `stdout` aunque el código sea
distinto de cero. Si el canal requerido falla, el proceso termina con `70` y no
afirma haber entregado una respuesta JSON válida.

## Efectos y límites

El ejecutable público V0:

- funciona dentro o fuera de un repositorio Git;
- no requiere red;
- no crea, modifica ni elimina archivos;
- no lee `.sdlc/`, credenciales ni configuración de proyecto;
- no lanza subprocesos ni registra telemetría;
- no cambia su respuesta por TTY, locale, rama o directorio actual.

Esto describe la ayuda, la versión y los errores de uso. En V1, `init --dry-run`
sí lee el directorio actual para reconocerlo, sin escribir en él.

Estas restricciones no describen el tooling interno de build y promoción, que
sí compila procesos y administra exclusivamente las rutas que recibe de forma
explícita.

## Distribución V0

La build oficial recibe una SemVer explícita, ejecuta el binario recién
compilado y genera `SHA256SUMS`. Instalación, actualización y desinstalación son
operaciones manuales externas al ejecutable.

V0 no incluye `shipflow update`, selección de versión por proyecto, launcher
mediante `.sdlc/version`, publicación en `pub.dev`, firma, notarización ni un
package manager.
