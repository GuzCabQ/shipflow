#!/usr/bin/env python3
"""Valida que `packages/` quedo EXACTAMENTE en el esqueleto normativo.

**ESTO ES UNA SONDA DE MIGRACION, NO UNA REGLA DE CI.**

El esqueleto exacto es una condicion de TRANSICION, no una invariante. Si estas
comprobaciones se instalaran en `capas.py` como regla permanente, el primer acto
de la reconstruccion —agregar una API real, declarar una dependencia legitima,
escribir la primera prueba— pondria CI en rojo y bloquearia el proyecto en su
estado vacio.

Un guardia que no sabe soltar es tan daniño como uno que no sabe disparar. Es el
fallo espejo de todo lo que el desacople persiguio: no una defensa que se vuelve
ciega, sino una que nunca deja crecer.

Por eso este archivo vive en `tool/migracion/`, NO esta en `PASOS_OBLIGATORIOS`,
NO lo invoca `checks.yml`, y se conserva como herramienta historica. Lo que
determina si un control bloquea el futuro no es que el archivo exista: es que CI
lo ejecute obligatoriamente.

Uso:
    python3 tool/migracion/validar_esqueleto.py            # valida el arbol
    python3 tool/migracion/validar_esqueleto.py --sabotajes  # se prueba a si misma
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]

PUBSPEC = """name: {p}
description: "Paquete reservado. Sin API todavia."
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.11.0

resolution: workspace
"""

BARRIL = ("/// {p} — sin API todavia. La fase 0 instala los controles, "
          "no el producto.\nlibrary;\n")

fallos: list[str] = []


def miembros() -> list[str]:
    """Del `workspace:` de la raiz, con un parser. Nunca de un listado a mano."""
    import yaml
    doc = yaml.safe_load((RAIZ / "pubspec.yaml").read_text(encoding="utf-8"))
    return [str(x).rstrip("/").split("/")[-1] for x in (doc or {}).get("workspace", [])]


def _bytes_esperados(ms: list[str]) -> dict[str, str]:
    esperado: dict[str, str] = {}
    for p in ms:
        esperado[f"packages/{p}/pubspec.yaml"] = PUBSPEC.format(p=p)
        esperado[f"packages/{p}/lib/{p}.dart"] = BARRIL.format(p=p)
    return esperado


def check_contenido(ms: list[str]) -> None:
    """Pieza 2: bytes y estructura de los nueve manifiestos y los nueve barriles.

    Se comparan BYTES, no «que tenga las claves»: una `description` que nombre
    `CredentialStore` o `ChangeClass` predecide el diseño nuevo, y una dependencia
    externa residual —`path`, `yaml`— no la gobierna ninguna regla, porque
    `dependencias-declaradas-se-usan` solo mira las internas.
    """
    for rel, contenido in _bytes_esperados(ms).items():
        f = RAIZ / rel
        if not f.exists():
            fallos.append(f"{rel}: falta.")
            continue
        real = f.read_text(encoding="utf-8")
        if real != contenido:
            fallos.append(
                f"{rel}: no coincide con la plantilla del esqueleto.\n"
                f"      esperado ({len(contenido)} bytes) / real ({len(real)} bytes)")


def check_arbol_git(ms: list[str]) -> None:
    """Pieza 4: el arbol GIT candidato tiene exactamente los 18 versionados."""
    r = subprocess.run(["git", "ls-files", "packages"], cwd=RAIZ,
                       capture_output=True, text=True)
    reales = {l for l in r.stdout.split("\n") if l.strip()}
    esperados = set(_bytes_esperados(ms))
    for extra in sorted(reales - esperados):
        fallos.append(f"{extra}: versionado bajo packages/ y no es del esqueleto.")
    for falta in sorted(esperados - reales):
        fallos.append(f"{falta}: no esta versionado.")


def check_arbol_de_trabajo() -> None:
    """Pieza 3: ningun archivo FUENTE SIN VERSIONAR bajo `packages/`.

    **El universo importa, y la primera version de este check lo tenia mal.**
    Marcaba como sucio TODO lo que `git status` reportara, incluido lo que esta
    preparado y sin commitear — que es el estado legitimo cuando la sonda corre
    ANTES del commit, que es cuando tiene sentido correrla.

    Lo que se busca es otra cosa: un archivo fuente que nadie versiono y que pase
    inadvertido. Es la leccion del artefacto que se perdio durante el preflight —
    lo ignorado y lo no versionado son universos distintos y solo uno importa aca.

    `.dart_tool/` y `build/` los regenera `pub get` y estan en `.gitignore`:
    quedan FUERA por construccion, porque `git status` sin `--ignored` no los
    reporta. Las modificaciones sin preparar (`XY` con `Y` distinto de espacio)
    tambien se reportan: el arbol de trabajo tiene que coincidir con lo que se va
    a commitear.
    """
    r = subprocess.run(["git", "status", "--porcelain", "--", "packages"],
                       cwd=RAIZ, capture_output=True, text=True)
    for linea in r.stdout.split("\n"):
        if len(linea) < 3:
            continue
        indice, trabajo, ruta = linea[0], linea[1], linea[3:].strip()
        if indice == "?" and trabajo == "?":
            fallos.append(
                f"{ruta}: archivo fuente SIN VERSIONAR bajo packages/. Un archivo "
                f"que nadie versiono no entra al candidato y se pierde sin ruido.")
        elif trabajo != " ":
            fallos.append(
                f"{ruta}: modificado y sin preparar. El arbol de trabajo no "
                f"coincide con lo que se va a commitear.")


def sabotajes() -> int:
    """Pieza 5: los dos sabotajes de CONTENIDO. Se prueba a si misma.

    Una sonda que nunca se vio roja es indistinguible de una rota, y esta corre
    una sola vez: si no se prueba acá, no se prueba nunca.
    """
    ms = miembros()
    casos = [
        ("una dependencia externa residual en un manifiesto",
         f"packages/{ms[0]}/pubspec.yaml",
         PUBSPEC.format(p=ms[0]) + "\ndependencies:\n  path: ^1.9.0\n"),
        ("una declaracion residual en un barril",
         f"packages/{ms[0]}/lib/{ms[0]}.dart",
         BARRIL.format(p=ms[0]) + "\nclass Residuo {}\n"),
    ]
    global fallos
    malos = 0
    for nombre, rel, contenido in casos:
        f = RAIZ / rel
        previo = f.read_text(encoding="utf-8")
        f.write_text(contenido, encoding="utf-8")
        try:
            fallos = []
            check_contenido(ms)
            detectado = any(rel in x for x in fallos)
        finally:
            f.write_text(previo, encoding="utf-8")
        print(f"  {nombre:<52} {'detectado' if detectado else 'NO DETECTADO'}")
        malos += not detectado
    fallos = []
    return malos


def main() -> int:
    if "--sabotajes" in sys.argv:
        print("sonda de migracion · los sabotajes de contenido\n")
        malos = sabotajes()
        if malos:
            print(f"\nvalidar_esqueleto: FALLA — {malos} sabotaje(s) no detectado(s).")
            return 1
        print("\nvalidar_esqueleto: los sabotajes de contenido se detectan.")
        return 0

    ms = miembros()
    if not ms:
        print("validar_esqueleto: FALLA — el `workspace:` de la raiz no declara "
              "miembros. Sin eso no se sabe que esqueleto esperar.")
        return 1
    check_contenido(ms)
    check_arbol_git(ms)
    check_arbol_de_trabajo()
    if fallos:
        print("validar_esqueleto: FALLA\n")
        for f in fallos:
            print(f"  {f}")
        return 1
    n = len(_bytes_esperados(ms))
    print(f"validar_esqueleto: ok — {n} archivos, {len(ms)} paquetes al esqueleto "
          f"normativo; arbol git y arbol de trabajo coinciden.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
