#!/usr/bin/env python3
"""La regla de capas, convertida en check.

Corre desde el commit 0 sobre paquetes vacíos, que es el único momento en que
instalar reglas de frontera cuesta cero: sobre veinte mil líneas producirían
miles de violaciones y terminarían desactivadas.

    python3 tool/checks/capas.py

Sale 1 si algo falla. No modifica archivos. Las reglas viven en
arquitectura.json, cada una con su `id` estable y su `alcance` declarado.

PRECONDICIÓN: `dart pub get` tiene que haber corrido. El grafo de dependencias
no se parsea a mano — se le pide a pub, que es quien lo resuelve. Si no está
disponible, este check FALLA: no mirar no es lo mismo que no encontrar nada.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
PAQUETES = RAIZ / "packages"
REGLAS = json.loads((RAIZ / "arquitectura.json").read_text(encoding="utf-8"))["reglas"]

# Los cuatro controles que arquitectura.json DEBE seguir declarando, con los
# campos sin los cuales no se pueden aplicar. Quitar uno de acá es un cambio de
# arquitectura y se revisa como tal; quitarlo solo del JSON, sin esto, dejaba el
# árbol verde con menos reglas: es F33 en nuestro propio arnés.
OBLIGATORIAS = {
    "deps-hacia-core": ("enunciado", "origen", "alcance", "permitidas"),
    "nucleo-sin-externas": ("enunciado", "origen", "alcance", "paquetes", "origenes_permitidos"),
    "agente-en-agents": ("enunciado", "origen", "alternativa", "alcance", "cadenas", "solo_en"),
    "lenguaje-en-plugin-dart": ("enunciado", "origen", "alternativa", "alcance", "cadenas", "solo_en"),
}

fallos: list[str] = []


def paquetes() -> list[str]:
    return sorted(p.name for p in PAQUETES.iterdir() if (p / "pubspec.yaml").exists())


def grafo() -> dict[str, dict]:
    """El grafo resuelto, tal como lo reporta pub.

    Se deriva, no se mantiene. Reemplaza al parser de pubspec que teníamos, que
    solo reconocía una forma textual: `dependencies: {http: ^1.0.0}` o un
    comentario en la misma línea le devolvían cero dependencias y el check
    pasaba en verde sin haber mirado.
    """
    try:
        r = subprocess.run(
            ["dart", "pub", "deps", "--json"],
            cwd=RAIZ, capture_output=True, text=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        fallos.append(f"no se pudo ejecutar `dart pub deps --json`: {e}")
        return {}
    if r.returncode != 0:
        detalle = (r.stderr or r.stdout).strip().splitlines()
        fallos.append(
            "`dart pub deps --json` falló. Corré `dart pub get` primero.\n"
            "      " + (detalle[-1] if detalle else "sin detalle")
        )
        return {}
    try:
        datos = json.loads(r.stdout)
    except json.JSONDecodeError as e:
        fallos.append(f"`dart pub deps --json` no devolvió JSON válido: {e}")
        return {}
    return {p["name"]: p for p in datos.get("packages", [])}


# --- meta · las reglas registradas siguen registradas --------------------

def check_meta() -> None:
    existentes = paquetes()
    for rid, campos in OBLIGATORIAS.items():
        regla = REGLAS.get(rid)
        if regla is None:
            fallos.append(
                f"arquitectura.json: falta la regla «{rid}». "
                f"Un control que desaparece sin ruido es F33."
            )
            continue
        for campo in campos:
            if not regla.get(campo):
                fallos.append(f"arquitectura.json: «{rid}» no declara «{campo}»")
    sobrantes = sorted(set(REGLAS) - set(OBLIGATORIAS))
    if sobrantes:
        fallos.append(
            f"arquitectura.json declara reglas que capas.py no aplica: {sobrantes}. "
            f"Una regla escrita y no ejecutada es la enfermedad que este proyecto combate."
        )
    for rid, regla in REGLAS.items():
        for pkg in list(regla.get("solo_en", [])) + list(regla.get("paquetes", [])):
            if pkg not in existentes:
                fallos.append(f"arquitectura.json: «{rid}» nombra el paquete «{pkg}», que no existe")


# --- deps-hacia-core · por NOMBRE ---------------------------------------

def check_dependencias(g: dict[str, dict]) -> None:
    regla = REGLAS["deps-hacia-core"]
    permitidas = regla["permitidas"]
    for nombre in paquetes():
        if nombre not in permitidas:
            fallos.append(f"packages/{nombre}: no está en «deps-hacia-core». Declaralo o borralo.")
            continue
        if nombre not in g:
            fallos.append(f"packages/{nombre}: pub no lo reporta en el grafo. ¿Falta en `workspace:`?")
            continue
        ok = set(permitidas[nombre])
        for dep in g[nombre].get("dependencies", []):
            if dep not in ok:
                fallos.append(
                    f"packages/{nombre}: depende de «{dep}», que no está permitido.\n"
                    f"      permitidas: {sorted(ok) or 'ninguna'} — {regla['enunciado']}"
                )


# --- nucleo-sin-externas · por ORIGEN, independiente de la anterior ------

def check_origenes(g: dict[str, dict]) -> None:
    regla = REGLAS["nucleo-sin-externas"]
    permitidos = set(regla["origenes_permitidos"])
    for nombre in regla["paquetes"]:
        if nombre not in g:
            fallos.append(f"packages/{nombre}: pub no lo reporta en el grafo")
            continue
        for dep in g[nombre].get("dependencies", []):
            origen = g.get(dep, {}).get("source", "desconocido")
            if origen not in permitidos:
                fallos.append(
                    f"packages/{nombre}: dependencia «{dep}» de origen «{origen}». "
                    f"{regla['enunciado']}"
                )


# --- cadenas acotadas a su adapter --------------------------------------

def check_cadenas() -> None:
    for regla in REGLAS.values():
        if regla.get("tipo") != "cadenas_acotadas":
            continue
        _cadenas_de(regla)


def _cadenas_de(regla: dict) -> None:
    alcance = regla["alcance"]
    extensiones = set(alcance["extensiones"])
    permitidos = set(regla["solo_en"])
    patron = re.compile(r"\b(" + "|".join(regla["cadenas"]) + r")\b", re.I)
    excluidos = {
        nombre
        for grupo in alcance.get("excluir", {}).values()
        if isinstance(grupo, dict)
        for nombre in grupo["que"]
    }
    raiz = RAIZ / alcance["raiz"]
    for archivo in sorted(raiz.rglob("*")):
        if not archivo.is_file() or archivo.suffix not in extensiones:
            continue
        rel = archivo.relative_to(raiz)
        if not rel.parts or rel.parts[0] in permitidos:
            continue
        if excluidos.intersection(rel.parts):
            continue
        for n, linea in enumerate(archivo.read_text(encoding="utf-8").splitlines(), 1):
            m = patron.search(linea)
            if m:
                fallos.append(
                    f"{archivo.relative_to(RAIZ)}:{n}: «{m.group(0)}» fuera de "
                    f"{sorted(permitidos)} — {regla['enunciado']}\n"
                    f"      → {regla['alternativa']}"
                )


def _paso(nombre, fn, *args) -> None:
    antes = len(fallos)
    fn(*args)
    estado = "ok" if len(fallos) == antes else f"{len(fallos) - antes} fallo(s)"
    print(f"  {nombre:<38} {estado}")


def main() -> int:
    _paso("reglas registradas presentes", check_meta)
    g = grafo()
    if g:
        _paso("dependencias entre paquetes", check_dependencias, g)
        _paso("núcleo sin dependencias externas", check_origenes, g)
    else:
        print(f"  {'grafo de dependencias':<38} NO DISPONIBLE")
    _paso("cadenas acotadas a su adapter", check_cadenas)

    if fallos:
        print("\ncapas: FALLA\n")
        for f in fallos:
            print(f"  {f}")
        return 1
    print(f"\ncapas: ok — {len(paquetes())} paquetes, {len(OBLIGATORIAS)} reglas aplicadas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
