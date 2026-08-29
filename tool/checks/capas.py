#!/usr/bin/env python3
"""La regla de capas, convertida en check.

Tres controles, todos de la fase 0 del plan. Corren desde el commit 0 sobre
paquetes vacíos, que es el único momento en que instalarlos cuesta cero: sobre
veinte mil líneas producirían miles de violaciones y se desactivarían.

    python3 tool/checks/capas.py

Sale 1 si algo falla. No modifica archivos. La regla vive en arquitectura.json.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
REGLA = json.loads((RAIZ / "arquitectura.json").read_text(encoding="utf-8"))
PAQUETES = RAIZ / "packages"

fallos: list[str] = []


def paquetes() -> list[Path]:
    return sorted(p for p in PAQUETES.iterdir() if (p / "pubspec.yaml").exists())


def dependencias(pubspec: Path) -> dict[str, str]:
    """Lee el bloque `dependencies:` de un pubspec sin depender de PyYAML.

    Devuelve {nombre: origen}, donde origen es 'path' o 'externa'. Falla ruidosa
    si el archivo no tiene la forma esperada: un parseo silencioso que devuelve
    vacío daría verde por no haber mirado, que es la clase 1 del catálogo.
    """
    deps: dict[str, str] = {}
    lineas = pubspec.read_text(encoding="utf-8").splitlines()
    try:
        i = lineas.index("dependencies:")
    except ValueError:
        return deps
    actual = None
    for l in lineas[i + 1:]:
        if l and not l.startswith(" "):
            break
        m = re.match(r"^  ([a-z_][a-z0-9_]*):\s*(\S.*)?$", l)
        if m:
            actual = m.group(1)
            deps[actual] = "externa" if m.group(2) else "path"
        elif actual and re.match(r"^    path:", l):
            deps[actual] = "path"
    return deps


# --- 1 · cadenas acotadas a su adapter -----------------------------------

def check_cadenas() -> None:
    for reglita in REGLA["cadenas_acotadas"]:
        permitidos = set(reglita["solo_en"])
        patron = re.compile(r"\b(" + "|".join(reglita["cadenas"]) + r")\b", re.I)
        for pkg in paquetes():
            if pkg.name in permitidos:
                continue
            for fuente in sorted(pkg.rglob("*.dart")):
                for n, l in enumerate(fuente.read_text(encoding="utf-8").splitlines(), 1):
                    m = patron.search(l)
                    if m:
                        fallos.append(
                            f"{fuente.relative_to(RAIZ)}:{n}: «{m.group(0)}» fuera de "
                            f"{sorted(permitidos)} — {reglita['regla']}.\n"
                            f"      → {reglita['alternativa']}"
                        )


# --- 2 · dependencias declaradas dentro de lo permitido ------------------

def check_dependencias() -> None:
    permitidas = REGLA["dependencias_permitidas"]
    for pkg in paquetes():
        if pkg.name not in permitidas:
            fallos.append(f"packages/{pkg.name}: no está declarado en arquitectura.json")
            continue
        ok = set(permitidas[pkg.name])
        for dep, origen in dependencias(pkg / "pubspec.yaml").items():
            if dep not in ok:
                fallos.append(
                    f"packages/{pkg.name}/pubspec.yaml: depende de «{dep}», que no está "
                    f"permitido. Permitidas: {sorted(ok) or 'ninguna'}"
                )
            del origen


# --- 3 · core no tiene dependencias externas -----------------------------

def check_nucleo_limpio() -> None:
    for nombre in REGLA["sin_dependencias_externas"]:
        pubspec = PAQUETES / nombre / "pubspec.yaml"
        if not pubspec.exists():
            fallos.append(f"packages/{nombre}: declarado sin dependencias externas y no existe")
            continue
        for dep, origen in dependencias(pubspec).items():
            if origen == "externa":
                fallos.append(
                    f"packages/{nombre}/pubspec.yaml: dependencia externa «{dep}». "
                    f"{nombre} no tiene dependencias externas. Ninguna."
                )


# --- 4 · meta-check: las reglas registradas siguen registradas ------------

# Los orígenes que arquitectura.json DEBE seguir cubriendo. Sin esto, vaciar el
# archivo deja el check en verde con menos reglas y nadie se entera: es F33
# —cuatro de nueve reglas no corrieron y nada lo dijo— en nuestro propio arnés.
# Quitar un origen de acá es un cambio de arquitectura, y se revisa como tal.
ORIGENES_OBLIGATORIOS = {"ADR-009", "docs/03 §2"}


def check_meta() -> None:
    declarados = " · ".join(r["regla"] for r in REGLA["cadenas_acotadas"])
    for origen in sorted(ORIGENES_OBLIGATORIOS):
        if origen not in declarados:
            fallos.append(
                f"arquitectura.json: ya no declara ninguna regla de «{origen}». "
                f"Un control que desaparece sin ruido es F33."
            )
    for reglita in REGLA["cadenas_acotadas"]:
        if not reglita.get("cadenas"):
            fallos.append(f"arquitectura.json: la regla «{reglita['regla']}» quedó sin cadenas")
        if not reglita.get("alternativa"):
            fallos.append(
                f"arquitectura.json: la regla «{reglita['regla']}» no declara alternativa. "
                f"Ninguna regla prohibitiva se instala sin su «hacé esto» (ADR-017, INV-11)."
            )
        for pkg in reglita["solo_en"]:
            if not (PAQUETES / pkg).exists():
                fallos.append(f"arquitectura.json: «{reglita['regla']}» permite «{pkg}», que no existe")


CHECKS = [
    ("reglas registradas presentes", check_meta),
    ("cadenas acotadas a su adapter", check_cadenas),
    ("dependencias entre paquetes", check_dependencias),
    ("núcleo sin dependencias externas", check_nucleo_limpio),
]


def main() -> int:
    for nombre, fn in CHECKS:
        antes = len(fallos)
        fn()
        print(f"  {nombre:<36} {'ok' if len(fallos) == antes else f'{len(fallos) - antes} fallo(s)'}")
    if fallos:
        print("\ncapas: FALLA\n")
        for f in fallos:
            print(f"  {f}")
        return 1
    print(f"\ncapas: ok — {len(paquetes())} paquetes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
