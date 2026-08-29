#!/usr/bin/env python3
"""Prueba que los checks de capas SEPAN FALLAR.

    «Un check que nunca falló no está probado.»
    — criterio de salida de la fase 0

Un guardia que existe y nunca se disparó es indistinguible de uno roto: es el
fallo F40 del catálogo, y la clase 1 entera —el instrumento en verde sobre algo
que no midió—. Así que cada control se rompe a propósito y se verifica que el
check se entere.

Se sabotea **cada regla por separado**, no el registro entero: borrar todo es el
caso fácil, y el que ocurre de verdad es que se caiga una sola sin que nadie lo
note. También hay dos controles NEGATIVOS: verifican que las exclusiones
declaradas efectivamente excluyan, y no sean un agujero accidental.

Corre en CI junto al check, no una sola vez a mano: si mañana alguien neutraliza
`capas.py`, esto se pone rojo.

    python3 tool/checks/probar_capas.py
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
CHECK = RAIZ / "tool" / "checks" / "capas.py"
ARQ = RAIZ / "arquitectura.json"

CORE = """name: core
description: "sabotaje"
publish_to: none
version: 0.1.0

environment:
  sdk: ^3.6.0

resolution: workspace
"""


def sin_regla(rid: str) -> str:
    a = json.loads(ARQ.read_text(encoding="utf-8"))
    a["reglas"].pop(rid)
    return json.dumps(a, ensure_ascii=False, indent=2) + "\n"


def sin_campo(rid: str, campo: str) -> str:
    a = json.loads(ARQ.read_text(encoding="utf-8"))
    a["reglas"][rid].pop(campo)
    return json.dumps(a, ensure_ascii=False, indent=2) + "\n"


def permitiendo(rid: str, paquete: str, dep: str) -> str:
    a = json.loads(ARQ.read_text(encoding="utf-8"))
    a["reglas"][rid]["permitidas"][paquete] = [dep]
    return json.dumps(a, ensure_ascii=False, indent=2) + "\n"


def sabotajes() -> list[dict]:
    s: list[dict] = []

    # Cada regla, borrada por separado. El meta-check tiene que notar la falta.
    for rid in ("deps-hacia-core", "nucleo-sin-externas",
                "agente-en-agents", "lenguaje-en-plugin-dart"):
        s.append({
            "nombre": f"regla «{rid}» borrada, sola",
            "archivos": {"arquitectura.json": sin_regla(rid)},
            "menciona": rid,
        })

    # Y una regla a la que se le quita un campo sin el cual no se puede aplicar.
    s.append({
        "nombre": "regla sin su «alternativa» (INV-11)",
        "archivos": {"arquitectura.json": sin_campo("agente-en-agents", "alternativa")},
        "menciona": "alternativa",
    })

    # Formas de YAML que el parser viejo no entendía y devolvían cero deps.
    s.append({
        "nombre": "dep externa en flow mapping",
        "archivos": {"packages/core/pubspec.yaml": CORE + "\ndependencies: {lints: ^5.0.0}\n"},
        "pub_get": True,
        "menciona": "lints",
    })
    s.append({
        "nombre": "dep externa tras un comentario inline",
        "archivos": {"packages/core/pubspec.yaml":
                     CORE + "\ndependencies: # deps del paquete\n  lints: ^5.0.0\n"},
        "pub_get": True,
        "menciona": "lints",
    })

    # El caso combinado: el nombre está permitido, así que deps-hacia-core pasa.
    # Solo lo caza nucleo-sin-externas, mirando el ORIGEN. Es la prueba de que
    # los dos controles son independientes y no se tapan entre sí.
    s.append({
        "nombre": "dep externa con nombre ya permitido",
        "archivos": {
            "arquitectura.json": permitiendo("deps-hacia-core", "core", "lints"),
            "packages/core/pubspec.yaml": CORE + "\ndependencies:\n  lints: ^5.0.0\n",
        },
        "pub_get": True,
        "menciona": "origen",
    })

    # Cadenas fuera de su adapter, en los formatos que el check antes no miraba.
    s.append({
        "nombre": "cadena de agente en un .yaml",
        "archivos": {"packages/orchestration/lib/agentes.yaml": "agente: claude\n"},
        "menciona": "claude",
    })
    s.append({
        "nombre": "cadena de agente en un .sh",
        "archivos": {"packages/orchestration/lib/lanzar.sh": "#!/bin/sh\ngemini -p x\n"},
        "menciona": "gemini",
    })
    s.append({
        "nombre": "cadena de lenguaje en un .md",
        "archivos": {"packages/rules/lib/notas.md": "Corre `flutter test` acá.\n"},
        "menciona": "flutter",
    })

    # NEGATIVOS: las exclusiones declaradas tienen que excluir de verdad.
    s.append({
        "nombre": "capa C proyectada: AGENTS.md queda fuera",
        "archivos": {"packages/orchestration/AGENTS.md": "Usá claude y flutter.\n"},
        "espera": "pasa",
    })
    s.append({
        "nombre": "artefacto de build: .dart_tool queda fuera",
        "archivos": {"packages/rules/.dart_tool/cache.json": '{"cli": "claude"}\n'},
        "espera": "pasa",
    })
    return s


def corre_check() -> tuple[int, str]:
    r = subprocess.run([sys.executable, str(CHECK)], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def pub_get() -> None:
    subprocess.run(["dart", "pub", "get"], cwd=RAIZ, capture_output=True, timeout=180)


def estado_git() -> str | None:
    """Huella del árbol de trabajo.

    No exige que esté LIMPIO —esto tiene que poder correrse mientras se
    desarrolla, que es justo cuando hay cambios sin commitear— sino que no
    CAMBIE. Lo que se busca es residuo del sabotaje, no pulcritud del repo.
    """
    r = subprocess.run(["git", "status", "--porcelain"], cwd=RAIZ,
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def aplicar(archivos: dict[str, str]) -> dict[str, str | None]:
    previo: dict[str, str | None] = {}
    for ruta, contenido in archivos.items():
        p = RAIZ / ruta
        previo[ruta] = p.read_text(encoding="utf-8") if p.exists() else None
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(contenido, encoding="utf-8")
    return previo


def restaurar(previo: dict[str, str | None]) -> None:
    for ruta, contenido in previo.items():
        p = RAIZ / ruta
        if contenido is None:
            p.unlink(missing_ok=True)
            for padre in p.parents:
                if padre == RAIZ:
                    break
                if padre.is_dir() and not any(padre.iterdir()):
                    padre.rmdir()
        else:
            p.write_text(contenido, encoding="utf-8")


def main() -> int:
    codigo, salida = corre_check()
    if codigo != 0:
        print("El árbol ya está en rojo antes de sabotear. Arreglá eso primero:\n")
        print(salida)
        return 1
    git_antes = estado_git()
    print("  árbol limpio                                    ok\n")

    problemas: list[str] = []
    casos = sabotajes()
    for caso in casos:
        nombre = caso["nombre"]
        espera_falla = caso.get("espera", "falla") == "falla"
        previo = aplicar(caso["archivos"])
        try:
            if caso.get("pub_get"):
                pub_get()
            codigo, salida = corre_check()
            if espera_falla and codigo == 0:
                problemas.append(f"{nombre}: el check pasó en verde. NO detecta esta violación.")
            elif espera_falla and caso["menciona"] not in salida:
                problemas.append(
                    f"{nombre}: falló, pero no por esto — no menciona «{caso['menciona']}»."
                )
            elif not espera_falla and codigo != 0:
                problemas.append(
                    f"{nombre}: el check falló, pero esto debería estar EXCLUIDO.\n"
                    f"      La exclusión declarada en arquitectura.json no se está honrando."
                )
            else:
                print(f"  {nombre:<46} {'detectado' if espera_falla else 'excluido, como se declaró'}")
        finally:
            restaurar(previo)
            if caso.get("pub_get"):
                pub_get()

    codigo, _ = corre_check()
    if codigo != 0:
        problemas.append("el árbol quedó en rojo tras restaurar")
    git_despues = estado_git()
    if git_antes is None or git_despues is None:
        print("  (sin git: no se pudo verificar que no quedara residuo)")
    elif git_antes != git_despues:
        nuevos = sorted(set(git_despues.splitlines()) - set(git_antes.splitlines()))
        problemas.append(
            "los sabotajes dejaron residuo en el árbol:\n      "
            + "\n      ".join(nuevos or ["(diferencia sin detalle)"])
        )

    if problemas:
        print("\nprobar_capas: FALLA\n")
        for p in problemas:
            print(f"  {p}")
        return 1
    positivos = sum(1 for c in casos if c.get("espera", "falla") == "falla")
    print(f"\nprobar_capas: ok — {positivos} violaciones detectadas, "
          f"{len(casos) - positivos} exclusiones honradas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
