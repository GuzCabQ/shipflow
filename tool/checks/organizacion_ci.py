#!/usr/bin/env python3
"""La organización del workflow, convertida en check.

**Repartir el trabajo en jobs abre formas nuevas de que el merge deje de
estar protegido sin que ningún comando cambie.** Las ramas protegidas exigen un
solo contexto, y lo que no esté detrás de él no bloquea: un job agregado sin
pasar por la compuerta, el canario colado en ella, un grupo de sabotajes
quitado de la matriz, el conjunto o la compuerta omitidos cuando algo falla,
un paso obligatorio que solo sobrevive en el canario, o una concurrencia que
cancela la corrida de un commit de integración. Cada una deja el archivo
plausible y la compuerta abierta.

Lo corre `capas.py`. Cada invariante tiene su validador, que devuelve sus
fallos sin mirar los de los demás.
"""
from __future__ import annotations

from compuerta import BLOQUEANTES
from sabotajes_en_grupos import GRUPOS, NOMBRE_DEL_JOB, SDK_BLOQUEANTE

# El contexto que exigen `develop` y `production`. La protección vive en
# GitHub, fuera de lo que este check ve: si este nombre cambia acá, hay que
# cambiarlo allá en el mismo movimiento, o las ramas quedan tapiadas.
CONTEXTO_REQUERIDO = f"reglas de arquitectura · Dart {SDK_BLOQUEANTE}"
COMPUERTA = "compuerta"
CANARIOS = ("canario-estatico-pruebas", "canario-sabotajes")
SDK_CANARIO = "stable"
SIEMPRE = "${{ always() }}"

RAMAS_DE_INTEGRACION = ["develop", "production"]
GRUPO_DE_CONCURRENCIA = (
    "${{ github.workflow }}-${{ github.event_name == 'pull_request' && "
    "format('pr-{0}', github.event.pull_request.number) || "
    "format('run-{0}', github.run_id) }}")
CANCELAR_EN_CURSO = "${{ github.event_name == 'pull_request' }}"

COMANDO_GRUPO = ('python3 tool/checks/probar_reglas.py --grupo '
                 '${{ matrix.grupo }}/' + str(GRUPOS)
                 + ' --resultado "$RUNNER_TEMP/sabotajes.json"')
COMANDO_JOBS = ('gh api "repos/${{ github.repository }}/actions/runs/'
                '${{ github.run_id }}/jobs?filter=all&per_page=100" > '
                '"$RUNNER_TEMP/jobs.json"')
COMANDO_CONJUNTO = ('python3 tool/checks/probar_reglas.py --conjunto '
                    '"$RUNNER_TEMP/manifiestos" --grupos ' + str(GRUPOS)
                    + ' --jobs "$RUNNER_TEMP/jobs.json"')
COMANDO_COMPUERTA = "python3 tool/checks/compuerta.py"
COMANDO_SECUENCIAL = "python3 tool/checks/probar_reglas.py"
ARTEFACTO = "sabotajes-g${{ matrix.grupo }}-i${{ github.run_attempt }}"
SUBIDA = {"name": ARTEFACTO, "path": "${{ runner.temp }}/sabotajes.json",
          "if-no-files-found": "error"}
BAJADA = {"pattern": "sabotajes-g*-i*", "path": "${{ runner.temp }}/manifiestos"}


def errores_de_organizacion(doc: dict) -> list[str]:
    """Todo lo que deja al merge sin la protección que el workflow declara."""
    jobs = {n: j for n, j in (doc.get("jobs") or {}).items() if isinstance(j, dict)}
    return [
        *_disparadores(doc),
        *_concurrencia(doc),
        *_jobs_declarados(jobs),
        *_compuerta(jobs),
        *_bloqueantes(jobs),
        *_sabotajes(jobs.get("sabotajes")),
        *_conjunto(jobs.get("sabotajes-conjunto")),
        *_canarios(jobs),
    ]


# --- EXTRACCIÓN -------------------------------------------------------------

def _pasos(job: dict | None) -> list[dict]:
    return [p for p in ((job or {}).get("steps") or []) if isinstance(p, dict)]


def _corridos(job: dict | None) -> set[tuple[str, object, object]]:
    """Cada comando con su directorio y su condición: los tres deciden qué corre."""
    return {(str(p.get("run", "")).strip(), p.get("working-directory"), p.get("if"))
            for p in _pasos(job) if "run" in p}


def _necesita(job: dict) -> list[str]:
    n = job.get("needs") or []
    return [n] if isinstance(n, str) else [str(x) for x in n]


def _sdks(job: dict) -> list[str]:
    return [str((p.get("with") or {}).get("sdk")) for p in _pasos(job)
            if "setup-dart" in str(p.get("uses", ""))]


def _usa(job: dict | None, accion: str) -> list[dict]:
    return [p for p in _pasos(job) if f"actions/{accion}@" in str(p.get("uses", ""))]


# --- VALIDADORES, UNO POR INVARIANTE ----------------------------------------

def _disparadores(doc: dict) -> list[str]:
    # PyYAML lee la clave `on` como el booleano True: es YAML 1.1.
    on = doc.get("on", doc.get(True))
    esperado = {"push": {"branches": RAMAS_DE_INTEGRACION},
                "pull_request": None, "workflow_dispatch": None}
    normal = ({k: (v or None) for k, v in on.items()} if isinstance(on, dict) else on)
    if normal == esperado:
        return []
    return [f"los disparadores del workflow son {normal!r} y tienen que ser "
            f"{esperado!r}: cada PR, el push a las ramas de integración y la vía "
            f"manual. Sin `pull_request` un PR no se valida; con push a cualquier "
            f"rama, cada cambio de un PR corre dos veces."]


def _concurrencia(doc: dict) -> list[str]:
    c = doc.get("concurrency")
    esperada = {"group": GRUPO_DE_CONCURRENCIA, "cancel-in-progress": CANCELAR_EN_CURSO}
    if c == esperada:
        return []
    return [f"la concurrencia del workflow es {c!r}. Tiene que agrupar por PR —y "
            f"cancelar solo ahí— y por `run_id` todo lo demás: agrupada por rama, "
            f"una corrida nueva cancela a la PENDIENTE de un commit de integración "
            f"aunque `cancel-in-progress` sea falso."]


def _jobs_declarados(jobs: dict) -> list[str]:
    esperados = {*BLOQUEANTES, COMPUERTA, *CANARIOS}
    fallos = []
    for extra in sorted(set(jobs) - esperados):
        fallos.append(f"el job «{extra}» no está entre los jobs declarados: ni lo "
                      f"espera la compuerta ni es del canario, así que su rojo no "
                      f"bloquearía nada. Va en `BLOQUEANTES` o no va.")
    for falta in sorted(esperados - set(jobs)):
        fallos.append(f"falta el job «{falta}» entre los jobs declarados.")
    return fallos


def _compuerta(jobs: dict) -> list[str]:
    job = jobs.get(COMPUERTA)
    if job is None:
        return []
    fallos = []
    if job.get("name") != CONTEXTO_REQUERIDO:
        fallos.append(f"la compuerta se llama «{job.get('name')}» y el nombre "
                      f"protegido es «{CONTEXTO_REQUERIDO}»: con otro nombre, las "
                      f"ramas esperan un contexto que nadie reporta.")
    for nombre, otro in jobs.items():
        if nombre != COMPUERTA and otro.get("name") == CONTEXTO_REQUERIDO:
            fallos.append(f"el job «{nombre}» también lleva el nombre protegido: "
                          f"su verde satisfaría a las ramas sin pasar por la "
                          f"compuerta.")
    if sorted(_necesita(job)) != sorted(BLOQUEANTES):
        fallos.append(f"la compuerta espera {sorted(_necesita(job))} y tiene que "
                      f"esperar exactamente {sorted(BLOQUEANTES)}: lo que no espere "
                      f"no bloquea, y si espera al canario, un canario lento o rojo "
                      f"decide el merge.")
    if job.get("if") != SIEMPRE:
        fallos.append(f"la compuerta lleva `if: {job.get('if')!r}` y no "
                      f"`{SIEMPRE}`: con un bloqueante rojo quedaría compuerta "
                      f"omitida, y una omitida no reporta rojo.")
    if job.get("continue-on-error") not in (None, False):
        fallos.append("la compuerta declara `continue-on-error`: su rojo dejaría "
                      "de bloquear.")
    paso = [p for p in _pasos(job) if str(p.get("run", "")).strip() == COMANDO_COMPUERTA]
    if len(paso) != 1 or (paso[0].get("env") or {}).get("NECESITA") != "${{ toJSON(needs) }}":
        fallos.append("la compuerta no le pasa `toJSON(needs)` a compuerta.py: sin "
                      "el resultado de cada job, decide a ciegas.")
    return fallos


def _bloqueantes(jobs: dict) -> list[str]:
    fallos = []
    for nombre in (*BLOQUEANTES, COMPUERTA):
        job = jobs.get(nombre)
        if job is None:
            continue
        if job.get("continue-on-error") not in (None, False):
            fallos.append(f"el bloqueante «{nombre}» declara `continue-on-error`: "
                          f"su rojo no detendría el merge.")
        if nombre not in ("sabotajes-conjunto", COMPUERTA) and "if" in job:
            fallos.append(f"el bloqueante «{nombre}» lleva `if: {job['if']!r}`: un "
                          f"job omitido no verifica nada y no reporta rojo.")
        if nombre not in ("sabotajes", "nativo") and "strategy" in job:
            fallos.append(f"el bloqueante «{nombre}» declara una matriz: una pata "
                          f"con otro SDK pasaría a decidir el merge.")
        if nombre != COMPUERTA and set(_sdks(job)) != {SDK_BLOQUEANTE}:
            fallos.append(f"el bloqueante «{nombre}» instala el SDK {_sdks(job)}; lo "
                          f"bloqueante se verifica con «{SDK_BLOQUEANTE}».")
        for dep in _necesita(job):
            if dep in CANARIOS:
                fallos.append(f"el bloqueante «{nombre}» depende del canario "
                              f"«{dep}»: un canario lento lo retendría.")
    return fallos


def _sabotajes(job: dict | None) -> list[str]:
    if job is None:
        return []
    fallos = []
    nombre = NOMBRE_DEL_JOB.format(k="${{ matrix.grupo }}", n=GRUPOS)
    if job.get("name") != nombre:
        fallos.append(f"el job de sabotajes se llama «{job.get('name')}» y no "
                      f"«{nombre}»: el conjunto encuentra a cada grupo por ese "
                      f"nombre.")
    esperada = {"fail-fast": False, "matrix": {"grupo": list(range(1, GRUPOS + 1))}}
    if job.get("strategy") != esperada:
        fallos.append(f"los grupos de sabotajes son {job.get('strategy')!r} y "
                      f"tienen que ser {esperada!r}: un grupo de menos deja su "
                      f"porción sin correr, y uno de más corre casos que el "
                      f"conjunto no espera.")
    if COMANDO_GRUPO not in {r for r, _, _ in _corridos(job)}:
        fallos.append(f"el job de sabotajes no corre «{COMANDO_GRUPO}».")
    subida = _usa(job, "upload-artifact")
    if (len(subida) != 1 or subida[0].get("with") != SUBIDA
            or "if" in subida[0] or "continue-on-error" in subida[0]):
        fallos.append(f"el manifiesto del grupo no se publica como {SUBIDA!r}, sin "
                      f"condición: un grupo que termina sin manifiesto tiene que "
                      f"fallar, y el nombre lleva el intento.")
    return fallos


def _conjunto(job: dict | None) -> list[str]:
    if job is None:
        return []
    fallos = []
    if _necesita(job) != ["sabotajes"]:
        fallos.append(f"el conjunto espera {_necesita(job)} y tiene que esperar a "
                      f"«sabotajes».")
    if job.get("if") != SIEMPRE:
        fallos.append(f"el conjunto lleva `if: {job.get('if')!r}` y no `{SIEMPRE}`: "
                      f"con un grupo rojo quedaría conjunto omitido, sin decir qué "
                      f"falta.")
    if job.get("permissions") != {"contents": "read", "actions": "read"}:
        fallos.append(f"el conjunto declara los permisos {job.get('permissions')!r}; "
                      f"necesita leer la API de Actions y nada más.")
    bajada = _usa(job, "download-artifact")
    if len(bajada) != 1 or bajada[0].get("with") != BAJADA:
        fallos.append(f"el conjunto no baja los manifiestos como {BAJADA!r}.")
    jobs = [p for p in _pasos(job) if str(p.get("run", "")).strip() == COMANDO_JOBS]
    if len(jobs) != 1 or (jobs[0].get("env") or {}).get("GH_TOKEN") != "${{ github.token }}":
        fallos.append("el conjunto no lee en qué intento corrió cada grupo: sin "
                      "eso, un grupo reintentado sin manifiesto se taparía con el "
                      "de un intento anterior.")
    for p in _pasos(job):
        if "if" in p or p.get("continue-on-error") not in (None, False):
            fallos.append(f"el paso «{p.get('name')}» del conjunto es condicional o "
                          f"no bloquea.")
    return fallos


def _canarios(jobs: dict) -> list[str]:
    fallos = []
    for nombre in CANARIOS:
        job = jobs.get(nombre)
        if job is None:
            continue
        if job.get("continue-on-error") is not True:
            fallos.append(f"el canario «{nombre}» no declara `continue-on-error: "
                          f"true`: un canario rojo bloquearía el merge — ADR-013 "
                          f"dice que reporta, no detiene.")
        if set(_sdks(job)) != {SDK_CANARIO}:
            fallos.append(f"el canario «{nombre}» instala {_sdks(job)} y no "
                          f"«{SDK_CANARIO}»: un canario con el SDK bloqueante no "
                          f"avisa de nada.")
        for otro, j in jobs.items():
            if nombre in _necesita(j):
                fallos.append(f"«{otro}» depende del canario «{nombre}»: lo "
                              f"esperaría aunque no bloquee.")
    espejo = jobs.get("canario-estatico-pruebas")
    if espejo is not None:
        faltan = (_corridos(jobs.get("estatico")) | _corridos(jobs.get("pruebas"))) \
            - _corridos(espejo)
        for run, wd, cond in sorted(faltan, key=str):
            fallos.append(f"el canario no corre «{run}»"
                          + (f" en «{wd}»" if wd else "")
                          + (f" bajo «{cond}»" if cond else "")
                          + ": el canal estable dejaría de mirar eso.")
    secuencial = jobs.get("canario-sabotajes")
    if secuencial is not None and COMANDO_SECUENCIAL not in {
            r for r, _, c in _corridos(secuencial) if c is None}:
        fallos.append(f"el canario no corre «{COMANDO_SECUENCIAL}»: los sabotajes "
                      f"dejarían de probarse con el canal estable.")
    return fallos
