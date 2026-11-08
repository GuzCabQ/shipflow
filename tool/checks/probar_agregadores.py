#!/usr/bin/env python3
"""Prueba que el conjunto de los sabotajes y la compuerta SEPAN FALLAR.

Los dos deciden el merge sin sabotear nada: juntan resultados de otros jobs.
Un agregador que acepta lo que no debe deja verde una corrida incompleta, así
que cada borde que rechazan se prueba con entradas construidas, y también lo
que tienen que aceptar —un agregador que rechaza todo «pasa» estas pruebas
por la razón equivocada—.

    python3 tool/checks/probar_agregadores.py

Los reintentos son el borde fino. Un grupo que no se reintentó aporta su
manifiesto anterior; uno que se reintentó y no publicó el suyo tiene que
fallar aunque el anterior siga en la corrida.
"""
from __future__ import annotations

import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import sabotajes_en_grupos as g  # noqa: E402
from compuerta import BLOQUEANTES, errores as errores_de_compuerta  # noqa: E402

N = 4
CASOS = [{"nombre": f"caso {i:02d}", "archivos": {f"a/{i}.txt": f"{i}\n"},
          **({"espera": "pasa"} if i % 5 == 0 else {})} for i in range(1, 12)]
NOMBRES = [c["nombre"] for c in CASOS]
ESPERADO = {"repositorio": "dueno/shipflow", "commit": "c" * 40, "arbol": "a" * 40,
            "inventario": g.huella_inventario(CASOS), "run_id": "42"}


def manifiesto(k: int, intento: int = 1, **cambios) -> dict:
    """El manifiesto correcto del grupo `k`, con `cambios` encima."""
    elegidos = g.asignados(NOMBRES, k, N)
    por_nombre = {c["nombre"]: c for c in CASOS}
    m = {"tipo": g.TIPO, "version": g.VERSION, **ESPERADO,
         "sdk": g.SDK_BLOQUEANTE, "canario": False, "grupo": k, "grupos": N,
         "intento": intento, "job": "sabotajes", "asignados": elegidos,
         "resultados": {x: {"estado": g.estado_esperado(por_nombre[x])}
                        for x in elegidos},
         "problemas": [], "arbol_limpio": True, "_ruta": f"g{k}-i{intento}"}
    m.update(cambios)
    return m


def todos(intento: int = 1) -> list[dict]:
    return [manifiesto(k, intento) for k in range(1, N + 1)]


def conjunto(manifiestos: list[dict], intentos: dict[int, int] | None = None,
             esperado: dict | None = None) -> list[str]:
    return g.verificar_conjunto(CASOS, manifiestos, N,
                                intentos or {k: 1 for k in range(1, N + 1)},
                                esperado or ESPERADO)


def jobs(*intentos_por_grupo: list[int], total: int | None = None) -> dict:
    """Cada grupo con los intentos en que CORRIÓ: cada uno con sus propias horas."""
    lista = [{"name": g.NOMBRE_DEL_JOB.format(k=k, n=N), "run_attempt": a,
              "started_at": f"2026-11-07T0{a}:00:0{k}Z",
              "completed_at": f"2026-11-07T0{a}:05:0{k}Z", "conclusion": "success"}
             for k, intentos in enumerate(intentos_por_grupo, 1) for a in intentos]
    return {"total_count": len(lista) if total is None else total, "jobs": lista}


def con_copias(base: dict, intento: int) -> dict:
    """Lo que devuelve la API tras «reintentar los fallidos»: cada job que NO se
    reintentó reaparece en el intento nuevo con otro id y `run_attempt` nuevo,
    pero con las horas del intento en que corrió."""
    lista = list(base["jobs"])
    reintentados = {j["name"] for j in lista if j["run_attempt"] == intento}
    for j in [j for j in base["jobs"] if j["run_attempt"] == intento - 1]:
        if j["name"] not in reintentados:
            lista.append({**j, "run_attempt": intento})
    return {"total_count": len(lista), "jobs": lista}


def _quitar(m: dict, campo: str) -> dict:
    m = copy.deepcopy(m)
    m["asignados"] = [x for x in m["asignados"] if x != campo]
    return m


CASOS_DE_PRUEBA: list[tuple[str, object, str | None]] = []


def caso(nombre: str, fallos: list[str], debe: str | None) -> None:
    """`debe=None`: se espera aceptación; si no, un fallo que lo mencione."""
    CASOS_DE_PRUEBA.append((nombre, fallos, debe))


# --- el conjunto ------------------------------------------------------------
caso("los cuatro grupos completos se aceptan", conjunto(todos()), None)
caso("un grupo sin manifiesto", conjunto([m for m in todos() if m["grupo"] != 3]),
     "no hay manifiesto suyo")
caso("dos manifiestos del mismo grupo e intento",
     conjunto(todos() + [manifiesto(2)]), "dos manifiestos")
for campo, valor in (("run_id", "7"), ("commit", "d" * 40), ("arbol", "b" * 40),
                     ("inventario", "0" * 64), ("repositorio", "otro/repo")):
    caso(f"un manifiesto de otro {campo}",
         conjunto([manifiesto(1, **{campo: valor})] + todos()[1:]), f"`{campo}`")
caso("un manifiesto del SDK canario",
     conjunto([manifiesto(1, sdk="3.99.0", canario=True)] + todos()[1:]), "SDK")
caso("un manifiesto con canario y el SDK bloqueante",
     conjunto([manifiesto(1, canario=True)] + todos()[1:]), "SDK")
caso("un manifiesto repartido en otra cantidad de grupos",
     conjunto([manifiesto(1, grupos=3)] + todos()[1:]), "grupos y esta corrida")
caso("un manifiesto de otro tipo",
     conjunto([manifiesto(1, tipo="otro")] + todos()[1:]), "declara tipo")
caso("un caso omitido",
     conjunto([_quitar(manifiesto(2), g.asignados(NOMBRES, 2, N)[0])] + todos()[:1]
              + todos()[2:]), "omitidos")
caso("un caso ajeno",
     conjunto([manifiesto(1, asignados=g.asignados(NOMBRES, 1, N) + [NOMBRES[1]])]
              + todos()[1:]), "1 ajenos")
caso("un caso repetido",
     conjunto([manifiesto(1, asignados=g.asignados(NOMBRES, 1, N)
                          + g.asignados(NOMBRES, 1, N)[:1])] + todos()[1:]),
     "1 repetidos")
_m = manifiesto(1)
_m["resultados"][_m["asignados"][0]] = {"estado": "problema", "detalle": "otro motivo"}
caso("un sabotaje que falló por otro motivo", conjunto([_m] + todos()[1:]),
     "tenía que quedar «detectado»")
_m = manifiesto(1)
_m["resultados"][NOMBRES[4]] = {"estado": "detectado"}
caso("una exclusión que se puso roja", conjunto([_m] + todos()[1:]),
     "tenía que quedar «excluido»")
_m = manifiesto(2)
del _m["resultados"][_m["asignados"][0]]
caso("un caso sin resultado", conjunto(todos()[:1] + [_m] + todos()[2:]),
     "no informa el resultado")
caso("un grupo que dejó residuo",
     conjunto([manifiesto(1, arbol_limpio=False)] + todos()[1:]), "árbol limpio")
caso("un grupo que informó problemas",
     conjunto([manifiesto(1, problemas=["algo"])] + todos()[1:]), "informó problemas")
caso("ningún manifiesto", conjunto([]), "no hay manifiesto suyo")

# --- los reintentos ---------------------------------------------------------
caso("reintento parcial válido: los grupos no reintentados aportan su manifiesto anterior",
     conjunto(todos() + [manifiesto(2, intento=2)], {1: 1, 2: 2, 3: 1, 4: 1}), None)
caso("un grupo reintentado sin manifiesto falla aunque esté el anterior",
     conjunto(todos(), {1: 1, 2: 1, 3: 2, 4: 1}), "OTRA ejecución")
caso("un grupo reintentado sin manifiesto y sin artefactos anteriores",
     conjunto([m for m in todos() if m["grupo"] != 3], {1: 1, 2: 1, 3: 2, 4: 1}),
     "intento 2")
caso("el manifiesto anterior, verde, no tapa al reintentado, rojo",
     conjunto(todos() + [manifiesto(2, intento=2, problemas=["roto"])],
              {1: 1, 2: 2, 3: 1, 4: 1}), "informó problemas")
_intentos, _f = g.ultimos_intentos(jobs([1], [1, 2], [1], [1]), N)
caso("los intentos salen del último job de cada grupo",
     [] if (_intentos, _f) == ({1: 1, 2: 2, 3: 1, 4: 1}, []) else [f"{_intentos} {_f}"],
     None)
_intentos, _f = g.ultimos_intentos(con_copias(jobs([1], [1, 2], [1], [1]), 2), N)
caso("una copia de un job no reintentado no cuenta como haber corrido otra vez",
     [] if (_intentos, _f) == ({1: 1, 2: 2, 3: 1, 4: 1}, []) else [f"{_intentos} {_f}"],
     None)
_intentos, _f = g.ultimos_intentos(
    con_copias(con_copias(jobs([1], [1, 2], [1, 3], [1]), 2), 3), N)
caso("las copias se siguen hasta el intento en que el grupo corrió de verdad",
     [] if (_intentos, _f) == ({1: 1, 2: 2, 3: 3, 4: 1}, []) else [f"{_intentos} {_f}"],
     None)
_intentos, _ = g.ultimos_intentos(con_copias(jobs([1], [1], [1, 2], [1]), 2), N)
caso("con copias en la lista, un grupo reintentado de verdad sin manifiesto falla",
     conjunto(todos(), _intentos), "OTRA ejecución")
caso("con copias en la lista, los no reintentados aportan su manifiesto anterior",
     conjunto(todos() + [manifiesto(3, intento=2)], _intentos), None)


def paginas(respuesta: dict, por_pagina: int = 100) -> list[dict]:
    """La forma de `gh api --paginate --slurp`: una lista de páginas, cada una
    con el total de la corrida y su porción de jobs."""
    lista = respuesta["jobs"]
    return [{"total_count": respuesta["total_count"], "jobs": lista[i:i + por_pagina]}
            for i in range(0, len(lista), por_pagina)]


def siete_intentos() -> dict:
    """Siete intentos de una corrida de 16 jobs: 112 entradas. El grupo 2 se
    reintenta en cada intento; los demás grupos y el resto de los jobs
    reaparecen como copias. El último intento del grupo 2 cae en la página 2."""
    lista = []
    for a in range(1, 8):
        for k in range(1, N + 1):
            corrio = 1 if k != 2 else a
            lista.append({"id": len(lista), "name": g.NOMBRE_DEL_JOB.format(k=k, n=N),
                          "run_attempt": a, "conclusion": "success",
                          "started_at": f"2026-11-07T0{corrio}:00:0{k}Z",
                          "completed_at": f"2026-11-07T0{corrio}:05:0{k}Z"})
        for x in range(12):
            lista.append({"id": len(lista), "name": f"otro {x}", "run_attempt": a,
                          "conclusion": "success", "started_at": "2026-11-07T01:00:00Z",
                          "completed_at": "2026-11-07T01:01:00Z"})
    return {"total_count": len(lista), "jobs": lista}


_todas = paginas(siete_intentos())
_intentos, _f = g.ultimos_intentos(_todas, N)
caso("más de 100 jobs en varias páginas, con el reintento en la segunda",
     [] if (len(_todas), _intentos, _f) == (2, {1: 1, 2: 7, 3: 1, 4: 1}, [])
     else [f"{len(_todas)} páginas {_intentos} {_f}"], None)
caso("más de 100 jobs con una página faltante",
     g.ultimos_intentos(_todas[:1], N)[1], "Una página faltante")
caso("páginas que no coinciden en el total de jobs",
     g.ultimos_intentos([_todas[0], {**_todas[1], "total_count": 113}], N)[1],
     "no coinciden en el total")
caso("un job repetido entre páginas",
     g.ultimos_intentos([_todas[0], {**_todas[1], "jobs": _todas[1]["jobs"][:-1]
                                    + _todas[0]["jobs"][:1]}], N)[1],
     "aparece dos veces")
caso("una página que no es un objeto",
     g.ultimos_intentos([_todas[0], "basura"], N)[1], "no tiene la forma esperada")
caso("un grupo ausente de la lista de jobs",
     g.ultimos_intentos(jobs([1], [1], [1]), N)[1], "no encontré el job")
caso("una lista de jobs paginada a medias",
     g.ultimos_intentos(jobs([1], [1], [1], [1], total=9), N)[1], "Una página faltante")
caso("una lista de jobs con otra forma", g.ultimos_intentos({"jobs": None}, N)[1],
     "no tiene la forma esperada")
caso("un job de grupo sin su intento",
     g.ultimos_intentos({"total_count": 4, "jobs": [
         {"name": g.NOMBRE_DEL_JOB.format(k=k, n=N)} for k in range(1, N + 1)]}, N)[1],
     "con su intento")

# --- la compuerta -----------------------------------------------------------
_verde = {j: {"result": "success"} for j in BLOQUEANTES}
caso("la compuerta con todo en verde", errores_de_compuerta(_verde), None)
for resultado in ("failure", "cancelled", "skipped", None):
    caso(f"la compuerta con un bloqueante en «{resultado}»",
         errores_de_compuerta({**_verde, "pruebas": {"result": resultado}}),
         f"terminó en «{resultado}»")
caso("la compuerta sin uno de sus bloqueantes",
     errores_de_compuerta({k: v for k, v in _verde.items() if k != "formato"}),
     "no está entre los resultados")
caso("la compuerta con el canario entre sus resultados",
     errores_de_compuerta({**_verde, "canario-sabotajes": {"result": "success"}}),
     "no es un bloqueante declarado")
caso("la compuerta sin resultados", errores_de_compuerta(None), "no recibí")
caso("la compuerta con un resultado sin forma",
     errores_de_compuerta({**_verde, "nativo": "success"}), "terminó en «None»")


def main() -> int:
    problemas = []
    for nombre, fallos, debe in CASOS_DE_PRUEBA:
        if debe is None and fallos:
            problemas.append(f"{nombre}: tenía que aceptarse y dio {fallos[0]!r}")
        elif debe is not None and not any(debe in f for f in fallos):
            problemas.append(f"{nombre}: tenía que fallar mencionando «{debe}» y dio "
                             f"{fallos[:1] or 'verde'}")
        else:
            print(f"  {nombre:<76} {'aceptado' if debe is None else 'rechazado'}")
    if problemas:
        print("\nprobar_agregadores: FALLA\n")
        for p in problemas:
            print(f"  {p}")
        return 1
    rechazos = sum(1 for _, _, d in CASOS_DE_PRUEBA if d is not None)
    print(f"\nprobar_agregadores: ok — {rechazos} rechazos por su motivo y "
          f"{len(CASOS_DE_PRUEBA) - rechazos} aceptaciones.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
