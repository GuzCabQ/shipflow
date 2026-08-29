#!/usr/bin/env python3
"""Prueba que los checks de capas SEPAN FALLAR.

    «Un check que nunca falló no está probado.»
    — criterio de salida de la fase 0

Un guardia que existe y nunca se disparó es indistinguible de uno roto: es el
fallo F40 del catálogo, y la clase 1 entera —el instrumento en verde sobre algo
que no midió—. Así que cada control se rompe a propósito y se verifica que el
check se entere.

Corre en CI junto al check, no una sola vez a mano: si mañana alguien
neutraliza `capas.py`, esto se pone rojo.

    python3 tool/checks/probar_capas.py
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
CHECK = RAIZ / "tool" / "checks" / "capas.py"

# (nombre, archivo a tocar, contenido saboteado, fragmento que debe aparecer)
SABOTAJES = [
    (
        "cadena de agente fuera de agents/",
        "packages/orchestration/lib/orchestration.dart",
        "/// orchestration\nvoid lanzar() { print('claude -p'); }\n",
        "claude",
    ),
    (
        "cadena de lenguaje fuera de plugin_dart/",
        "packages/vcs/lib/vcs.dart",
        "/// vcs\nvoid resolver() { print('pubspec.lock'); }\n",
        "pubspec",
    ),
    (
        "dependencia no permitida entre paquetes",
        "packages/core/pubspec.yaml",
        'name: core\ndescription: "sabotaje"\npublish_to: none\nversion: 0.1.0\n\n'
        "environment:\n  sdk: ^3.6.0\n\nresolution: workspace\n\n"
        "dependencies:\n  vcs:\n    path: ../vcs\n",
        "no está permitido",
    ),
    (
        "dependencia externa en el núcleo",
        "packages/core/pubspec.yaml",
        'name: core\ndescription: "sabotaje"\npublish_to: none\nversion: 0.1.0\n\n'
        "environment:\n  sdk: ^3.6.0\n\nresolution: workspace\n\n"
        "dependencies:\n  http: ^1.0.0\n",
        "dependencia externa",
    ),
    (
        "regla borrada de arquitectura.json",
        "arquitectura.json",
        '{"dependencias_permitidas": {"core": [], "orchestration": ["core"], "vcs": ["core"],'
        ' "rules": ["core"], "agents": ["core"], "plugin_dart": ["core"],'
        ' "plugin_fake": ["core"], "cli": ["core"]},'
        ' "sin_dependencias_externas": ["core"], "cadenas_acotadas": []}',
        "F33",
    ),
]


def corre_check() -> tuple[int, str]:
    r = subprocess.run([sys.executable, str(CHECK)], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def main() -> int:
    codigo, salida = corre_check()
    if codigo != 0:
        print("El árbol ya está en rojo antes de sabotear. Arreglá eso primero:\n")
        print(salida)
        return 1
    print("  árbol limpio                          ok\n")

    problemas: list[str] = []
    for nombre, ruta, saboteado, esperado in SABOTAJES:
        archivo = RAIZ / ruta
        original = archivo.read_text(encoding="utf-8")
        try:
            archivo.write_text(saboteado, encoding="utf-8")
            codigo, salida = corre_check()
            if codigo == 0:
                problemas.append(f"{nombre}: el check pasó en verde. NO detecta esta violación.")
            elif esperado not in salida:
                problemas.append(
                    f"{nombre}: el check falló, pero no por esto — no menciona «{esperado}»."
                )
            else:
                print(f"  {nombre:<38} detectado")
        finally:
            archivo.write_text(original, encoding="utf-8")

    codigo, _ = corre_check()
    if codigo != 0:
        problemas.append("el árbol quedó sucio tras restaurar: revisá probar_capas.py")

    if problemas:
        print("\nprobar_capas: FALLA\n")
        for p in problemas:
            print(f"  {p}")
        return 1
    print(f"\nprobar_capas: ok — {len(SABOTAJES)} violaciones, {len(SABOTAJES)} detectadas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
