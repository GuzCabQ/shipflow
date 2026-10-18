#!/usr/bin/env python3
"""El ejecutable nativo, convertido en check.

**Una plataforma soportada es una plataforma donde el binario CORRIÓ.**
Compilar para otra plataforma produce bytes, no evidencia. Por eso los pasos
nativos tienen que vivir en UN job cuya matriz sea exactamente estos runners,
cada uno con el nombre de release que su artefacto lleva. Que los pasos
existan en el workflow no alcanza: con la matriz recortada, el runner fijo o
el job omitido, el comando sigue escrito y la plataforma deja de ejecutarse.

Lo corre `capas.py`, que lee el workflow y le pasa los comandos exactos de
`PASOS_OBLIGATORIOS`. Acá primero se ubica el job y después cada invariante
tiene su validador, que devuelve sus fallos sin mirar los de los demás.
"""
from __future__ import annotations

EJECUCION_NATIVA = {
    "plataformas": {"ubuntu-24.04": "linux-x64", "macos-14": "macos-arm64"},
    "runs-on": "${{ matrix.runner }}",
    "sdk": "3.12.0",
    "pasos": ("las dependencias exactas del lockfile",
              "las pruebas del CLI en la plataforma nativa",
              "la build oficial nativa",
              "el artefacto de la plataforma responde"),
}


def errores_de_ejecucion_nativa(doc: dict, comandos: dict[str, str]) -> list[str]:
    """Los pasos nativos corren en su job, una vez por plataforma declarada.

    `comandos` va de la etiqueta de cada paso nativo a su comando exacto.
    """
    candidatos = _jobs_con_pasos_nativos(doc, set(comandos.values()))
    if len(candidatos) != 1:
        return [
            f"los pasos del ejecutable nativo aparecen en "
            f"{[n for n, _, _ in candidatos] or 'ningún'} job. Tienen que vivir "
            f"juntos en UN job con la matriz de plataformas declaradas; "
            f"repartidos, ninguno garantiza que el binario corrió donde dice."]
    nombre, job, corridos = candidatos[0]
    return [
        *_pasos_faltantes(nombre, corridos, comandos),
        *_condicion_del_job(nombre, job),
        *_runner_de_la_matriz(nombre, job),
        *_patas_de_la_matriz(nombre, _matriz(job)),
        *_sdk_bloqueante(nombre, job),
    ]


# --- EXTRACCIÓN -------------------------------------------------------------

def _jobs_con_pasos_nativos(doc: dict, comandos: set[str]
                            ) -> list[tuple[str, dict, set[str]]]:
    """Cada job que corre al menos un paso nativo, con todo lo que corre."""
    candidatos = []
    for nombre, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        corridos = {str(p.get("run", "")).strip() for p in _pasos(job)}
        if corridos & comandos:
            candidatos.append((nombre, job, corridos))
    return candidatos


def _pasos(job: dict) -> list[dict]:
    return [p for p in (job.get("steps") or []) if isinstance(p, dict)]


def _matriz(job: dict) -> dict:
    return (job.get("strategy") or {}).get("matrix") or {}


# --- VALIDADORES, UNO POR INVARIANTE ----------------------------------------

def _pasos_faltantes(nombre: str, corridos: set[str],
                     comandos: dict[str, str]) -> list[str]:
    return [f"el job «{nombre}» no ejecuta {etiqueta}: sin ese paso la "
            f"plataforma no queda atestiguada."
            for etiqueta, comando in comandos.items() if comando not in corridos]


def _condicion_del_job(nombre: str, job: dict) -> list[str]:
    fallos = []
    if "if" in job:
        fallos.append(f"el job «{nombre}» lleva la condición `if: {job['if']!r}`. "
                      f"Un job omitido deja cada plataforma sin ejecutar y el "
                      f"comando sigue escrito.")
    if job.get("continue-on-error") not in (None, False):
        fallos.append(f"el job «{nombre}» declara `continue-on-error`: una "
                      f"plataforma roja dejaría de bloquear.")
    return fallos


def _runner_de_la_matriz(nombre: str, job: dict) -> list[str]:
    if job.get("runs-on") == EJECUCION_NATIVA["runs-on"]:
        return []
    return [f"el job «{nombre}» corre en `runs-on: {job.get('runs-on')!r}` "
            f"y no en {EJECUCION_NATIVA['runs-on']}: la matriz de "
            f"plataformas queda decorativa."]


def _patas_de_la_matriz(nombre: str, matriz: dict) -> list[str]:
    fallos = []
    if set(matriz) != {"include"}:
        fallos.append(f"la matriz del job «{nombre}» declara {sorted(matriz)} y "
                      f"solo puede declarar `include`: un `exclude` o un eje "
                      f"más cambian qué plataformas corren.")
    patas = {str(p.get("runner")): str(p.get("plataforma"))
             for p in (matriz.get("include") or []) if isinstance(p, dict)}
    if patas != EJECUCION_NATIVA["plataformas"]:
        fallos.append(f"la matriz del job «{nombre}» ejecuta {patas} y las "
                      f"plataformas declaradas son {EJECUCION_NATIVA['plataformas']}. "
                      f"Una plataforma sin su runner nativo no está verificada.")
    return fallos


def _sdk_bloqueante(nombre: str, job: dict) -> list[str]:
    sdks = [str((p.get("with") or {}).get("sdk"))
            for p in _pasos(job) if "setup-dart" in str(p.get("uses", ""))]
    if sdks == [EJECUCION_NATIVA["sdk"]]:
        return []
    return [f"el job «{nombre}» instala el SDK {sdks}; el ejecutable "
            f"nativo se verifica con el SDK bloqueante "
            f"«{EJECUCION_NATIVA['sdk']}»."]
