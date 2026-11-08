#!/usr/bin/env python3
"""Los sabotajes repartidos en grupos, y la comprobación que los vuelve a juntar.

**Por qué en grupos.** Uno detrás de otro, los casos ocupan casi todo el
límite de tiempo de un job. Repartidos en `GRUPOS` jobs paralelos, cada uno en
su runner y en su copia privada, la espera baja sin quitar ningún caso. Nunca
dos grupos sabotean el mismo árbol.

**Por qué una comprobación conjunta.** Un grupo que pasa solo prueba su
porción. Que el inventario entero se ejecutó —sin un caso de menos, de más ni
repetido, sobre el mismo árbol, con el SDK bloqueante y en esta corrida— solo
se puede afirmar juntando los manifiestos. Eso hace `verificar_conjunto`, que
reconstruye el inventario y la asignación por su cuenta: no le cree a ningún
grupo lo que dice que le tocaba.

**Reintentos.** Reintentar solo los jobs fallidos conserva el `run_id` y sube
el intento, y los artefactos de intentos anteriores siguen en la corrida. Un
grupo que no se reintentó aporta, válidamente, el manifiesto del intento en el
que corrió. Pero «el mayor intento disponible» no alcanza: un grupo que SÍ se
reintentó y no publicó su manifiesto dejaría ver el anterior, que habla de
otra ejecución. Por eso el intento que se exige por grupo sale de la API de
jobs de la corrida —en qué intento corrió por última vez ese job—, no de los
artefactos.

**Y la API no lo dice directamente.** Al reintentar los fallidos, cada job que
no se reintentó reaparece en el intento nuevo con otro id y ese `run_attempt`,
pero con las horas de cuando corrió. Una entrada con las mismas horas y el
mismo resultado que una anterior es una copia, y el grupo corrió en el intento
de la primera.

Este módulo es puro: no lee el entorno ni lanza procesos. Lo usan
`probar_reglas.py` y `probar_agregadores.py`.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from ejecucion_nativa import EJECUCION_NATIVA

GRUPOS = 4
SDK_BLOQUEANTE = EJECUCION_NATIVA["sdk"]
TIPO = "shipflow.sabotajes.grupo"
VERSION = 1

# El nombre del job de cada grupo, tal como lo reporta la API de Actions. El
# workflow lo escribe con `${{ matrix.grupo }}`; `organizacion_ci.py` lo fija.
NOMBRE_DEL_JOB = "sabotajes · grupo {k}/{n}"

# Lo que cada manifiesto tiene que compartir con la corrida que lo junta.
PROCEDENCIA = ("repositorio", "commit", "arbol", "inventario", "run_id")


def asignados(nombres: list[str], k: int, n: int) -> list[str]:
    """Los casos del grupo `k` de `n`: round-robin sobre el orden canónico.

    Los casos duran parecido, así que el reparto por turnos ya equilibra los
    grupos. Uno por duraciones necesitaría un registro de tiempos que
    envejece.
    """
    if not 1 <= k <= n:
        raise ValueError(f"grupo {k} fuera de 1..{n}")
    return [nombre for i, nombre in enumerate(nombres) if i % n == k - 1]


def huella_inventario(casos: list[dict]) -> str:
    """Huella del inventario: qué se sabotea, qué se espera y por qué motivo.

    Entra el contenido de cada archivo que el caso escribe, no solo su ruta:
    dos grupos que construyeran el mismo caso con otro contenido no estarían
    probando lo mismo. No entra ninguna ruta absoluta, así que la copia
    privada de un grupo y el checkout del conjunto dan la misma huella.
    """
    filas = []
    for c in casos:
        filas.append({
            "nombre": c["nombre"],
            "espera": c.get("espera", "falla"),
            "menciona": c.get("menciona"),
            "banderas": sorted(k for k in ("regenerar_huella", "pub_get",
                                           "regenerar_grafo", "probar_grafo",
                                           "es_ciego") if c.get(k)),
            "archivos": {ruta: (None if contenido is None else
                                hashlib.sha256(contenido.encode("utf-8")).hexdigest())
                         for ruta, contenido in sorted(c["archivos"].items())},
        })
    crudo = json.dumps(filas, ensure_ascii=False, sort_keys=True)
    return hashlib.sha256(crudo.encode("utf-8")).hexdigest()


def estado_esperado(caso: dict) -> str:
    return "detectado" if caso.get("espera", "falla") == "falla" else "excluido"


def leer_manifiestos(directorio: Path) -> tuple[list[dict], list[str]]:
    """Cada `*.json` bajo `directorio`, con su ruta; los ilegibles, como fallo."""
    manifiestos, fallos = [], []
    for ruta in sorted(directorio.rglob("*.json")) if directorio.exists() else []:
        try:
            m = json.loads(ruta.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            fallos.append(f"«{ruta.name}» no se puede leer como manifiesto: {e}")
            continue
        if isinstance(m, dict):
            m["_ruta"] = str(ruta.relative_to(directorio))
            manifiestos.append(m)
        else:
            fallos.append(f"«{ruta.name}» no es un objeto JSON.")
    return manifiestos, fallos


def ultimos_intentos(jobs: object, n: int) -> tuple[dict[int, int], list[str]]:
    """En qué intento corrió por última vez el job de cada grupo.

    `jobs` es la respuesta de `/actions/runs/{id}/jobs?filter=all`, que trae
    los jobs de TODOS los intentos con su `run_attempt`: una página, o la lista
    de páginas de `gh api --paginate --slurp`. Cada intento repite todos los
    jobs de la corrida, así que unos pocos reintentos superan una página. Una
    respuesta a medias se rechaza: sin todos los jobs no se sabe qué se
    reintentó.
    """
    jobs, fallos = _unir_paginas(jobs)
    if jobs is None:
        return {}, fallos
    lista = jobs["jobs"]
    if jobs.get("total_count") != len(lista):
        fallos.append(f"la API informó {jobs.get('total_count')} jobs y llegaron "
                      f"{len(lista)}. Una página faltante podría esconder un "
                      f"reintento.")
    intentos: dict[int, int] = {}
    for k in range(1, n + 1):
        nombre = NOMBRE_DEL_JOB.format(k=k, n=n)
        vistos = [j for j in lista if isinstance(j, dict) and j.get("name") == nombre]
        if not vistos or not all(isinstance(j.get("run_attempt"), int) for j in vistos):
            fallos.append(f"no encontré el job «{nombre}» en la corrida, con su "
                          f"intento. Un grupo que no corrió no se puede dar "
                          f"por verificado.")
            continue
        intentos[k] = _intento_en_que_corrio(vistos)
    return intentos, fallos


def _unir_paginas(respuesta: object) -> tuple[dict | None, list[str]]:
    """Las páginas como una sola respuesta: todas declaran el mismo total y
    ningún job aparece en dos."""
    paginas = respuesta if isinstance(respuesta, list) else [respuesta]
    if not paginas or not all(isinstance(p, dict) and isinstance(p.get("jobs"), list)
                              for p in paginas):
        return None, ["la lista de jobs de la corrida no tiene la forma esperada; "
                      "sin ella no se sabe qué grupo se reintentó."]
    totales = {p.get("total_count") for p in paginas}
    if len(totales) != 1:
        return None, [f"las páginas de jobs no coinciden en el total ({sorted(map(str, totales))}): "
                      f"la corrida cambió mientras se leía, o se mezclaron respuestas."]
    lista = [j for p in paginas for j in p["jobs"]]
    ids = [j.get("id") for j in lista if isinstance(j, dict) and j.get("id") is not None]
    repetidos = sorted({i for i in ids if ids.count(i) > 1})
    if repetidos:
        return None, [f"el job {repetidos[0]} aparece dos veces entre las páginas: no se "
                      f"puede saber cuál de las dos lecturas vale."]
    return {"total_count": totales.pop(), "jobs": lista}, []


def _intento_en_que_corrio(vistos: list[dict]) -> int:
    """El intento de la entrada más reciente, salvo que sea una copia: entonces
    el de la primera entrada con sus mismas horas y su mismo resultado."""
    ultimo = max(vistos, key=lambda j: j["run_attempt"])
    huella = (ultimo.get("started_at"), ultimo.get("completed_at"),
              ultimo.get("conclusion"))
    return min(j["run_attempt"] for j in vistos
               if (j.get("started_at"), j.get("completed_at"), j.get("conclusion")) == huella)


def verificar_conjunto(casos: list[dict], manifiestos: list[dict], n: int,
                       intentos: dict[int, int], esperado: dict
                       ) -> list[str]:
    """Todo lo que impide afirmar que el inventario entero se ejecutó.

    `esperado` trae la procedencia de esta corrida: repositorio, commit,
    árbol git, huella del inventario —calculada por quien llama, sobre su
    propio checkout— y `run_id`.
    """
    fallos = []
    validos: dict[tuple[int, int], dict] = {}
    for m in manifiestos:
        motivo = _ajeno(m, n, esperado)
        if motivo:
            fallos.append(f"«{m.get('_ruta')}» no sirve como evidencia: {motivo}.")
            continue
        clave = (m["grupo"], m["intento"])
        if clave in validos:
            fallos.append(f"hay dos manifiestos del grupo {clave[0]} en el intento "
                          f"{clave[1]}. Uno de los dos sobra, y no se puede "
                          f"elegir cuál habla de la ejecución real.")
            continue
        validos[clave] = m

    nombres = [c["nombre"] for c in casos]
    por_nombre = {c["nombre"]: c for c in casos}
    cubiertos: list[str] = []
    for k in range(1, n + 1):
        if k not in intentos:
            continue
        m = validos.get((k, intentos[k]))
        if m is None:
            previos = sorted(i for (g, i) in validos if g == k)
            fallos.append(
                f"el grupo {k} corrió por última vez en el intento {intentos[k]} "
                f"y no hay manifiesto suyo de ese intento"
                + (f"; los de los intentos {previos} hablan de OTRA ejecución y "
                   f"no lo reemplazan" if previos else "")
                + ".")
            continue
        fallos.extend(_porcion(m, k, asignados(nombres, k, n), por_nombre))
        cubiertos.extend(m.get("asignados") or [])
    faltan = [x for x in nombres if x not in cubiertos]
    if faltan and not fallos:
        fallos.append(f"{len(faltan)} casos del inventario no los ejecutó ningún "
                      f"grupo; el primero es «{faltan[0]}».")
    return fallos


def _ajeno(m: dict, n: int, esperado: dict) -> str | None:
    """Por qué un manifiesto no es evidencia de esta corrida, o None."""
    if m.get("tipo") != TIPO or m.get("version") != VERSION:
        return f"declara tipo {m.get('tipo')!r} versión {m.get('version')!r}"
    for campo in PROCEDENCIA:
        if m.get(campo) != esperado.get(campo):
            return (f"su `{campo}` es {m.get(campo)!r} y el de esta corrida es "
                    f"{esperado.get(campo)!r}")
    if m.get("sdk") != SDK_BLOQUEANTE or m.get("canario") is not False:
        return (f"corrió con el SDK {m.get('sdk')!r} (canario={m.get('canario')!r}); "
                f"solo el SDK bloqueante «{SDK_BLOQUEANTE}» decide el merge")
    if m.get("grupos") != n:
        return f"se repartió en {m.get('grupos')!r} grupos y esta corrida en {n}"
    if not isinstance(m.get("grupo"), int) or not 1 <= m["grupo"] <= n:
        return f"declara el grupo {m.get('grupo')!r}, fuera de 1..{n}"
    if not isinstance(m.get("intento"), int):
        return f"declara el intento {m.get('intento')!r}"
    return None


def _porcion(m: dict, k: int, esperados: list[str],
             por_nombre: dict[str, dict]) -> list[str]:
    """Que el grupo ejecutó exactamente lo suyo, y cada caso por su motivo."""
    fallos = []
    hechos = list(m.get("asignados") or [])
    if hechos != esperados:
        omitidos = [x for x in esperados if x not in hechos]
        ajenos = [x for x in hechos if x not in esperados]
        repetidos = sorted({x for x in hechos if hechos.count(x) > 1})
        fallos.append(
            f"el grupo {k} no ejecutó exactamente lo que le tocaba: "
            f"{len(omitidos)} omitidos, {len(ajenos)} ajenos, "
            f"{len(repetidos)} repetidos"
            + (f"; primer omitido «{omitidos[0]}»" if omitidos else "")
            + (f"; primer ajeno «{ajenos[0]}»" if ajenos else "") + ".")
    resultados = m.get("resultados") or {}
    for nombre in esperados:
        r = resultados.get(nombre)
        if not isinstance(r, dict):
            fallos.append(f"el grupo {k} no informa el resultado de «{nombre}».")
            continue
        if r.get("estado") != estado_esperado(por_nombre[nombre]):
            fallos.append(f"«{nombre}» quedó «{r.get('estado')}» en el grupo {k} y "
                          f"tenía que quedar «{estado_esperado(por_nombre[nombre])}»"
                          + (f": {r['detalle']}" if r.get("detalle") else "") + ".")
    if m.get("problemas"):
        fallos.append(f"el grupo {k} informó problemas: {m['problemas'][0]}")
    if m.get("arbol_limpio") is not True:
        fallos.append(f"el grupo {k} no dejó su árbol limpio y en verde, o cambió "
                      f"el checkout original.")
    return fallos


def resumen(casos: list[dict]) -> str:
    falla = sum(1 for c in casos if c.get("espera", "falla") == "falla")
    ciegos = sum(1 for c in casos if c.get("es_ciego"))
    return (f"{falla} sabotajes detectados, de los cuales {ciegos} son casos "
            f"CIEGOS, y {len(casos) - falla} exclusiones honradas")
