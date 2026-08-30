#!/usr/bin/env python3
"""Prueba que la recuperación del arnés SEPA HACER SU TRABAJO.

    python3 tool/checks/probar_recuperacion.py

`probar_reglas.py` sabotea el árbol y lo revierte. Cuando lo matan a mitad, el
diario es lo único que sabe qué quedó tocado — y esa recuperación **es un
control como cualquier otro**: puede romperse sin que ninguno de los ochenta y
pico de sabotajes lo note, porque todos corren en el camino feliz donde el
proceso termina.

Un guardia que existe y nunca se disparó es indistinguible de uno roto.

QUÉ SE PRUEBA, Y POR QUÉ CADA COSA
    1. Con el árbol limpio, no inventa una recuperación que nadie pidió.
    2. Con un diario presente, INFORMA Y FALLA. No repara solo: reparar en
       silencio pisaría con contenido viejo lo editado después del corte.
    3. Nombra cada archivo afectado. Averiguarlo a mano fue el costo real.
    4. `--recuperar` los devuelve a su contenido PREVIO AL SABOTAJE —no al
       último commit—, tanto el que existía como el que no.

El sujeto es sintético y se crea acá: esta prueba no toca ningún archivo del
proyecto, ni siquiera para restaurarlo.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
ARNES = Path(__file__).parent / "probar_reglas.py"
DIARIO = Path(__file__).parent / ".sabotaje-en-curso.json"

# Sujetos sintéticos: uno que YA EXISTÍA y se modifica, y uno que NO existía y
# se crea. Son los dos caminos que la restauración tiene que distinguir.
EXISTIA = RAIZ / "tool" / "checks" / "_sujeto_recuperacion.tmp"
NO_EXISTIA = RAIZ / "tool" / "checks" / "_sujeto_nuevo.tmp"
ORIGINAL = "contenido previo al sabotaje\n"

problemas: list[str] = []


def corre(*args: str) -> tuple[int, str]:
    r = subprocess.run([sys.executable, str(ARNES), *args],
                       capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout + r.stderr


def limpiar() -> None:
    for p in (EXISTIA, NO_EXISTIA, DIARIO):
        p.unlink(missing_ok=True)


def main() -> int:
    if DIARIO.exists():
        print("hay un sabotaje sin revertir. Corré `probar_reglas.py "
              "--recuperar` antes de probar la recuperación.")
        return 1
    limpiar()
    try:
        # --- 1 · sin diario, no inventa nada -----------------------------
        _, salida = corre("--recuperar")
        if "recuperado" in salida:
            problemas.append("con el árbol limpio dijo haber recuperado algo. "
                             "Una recuperación inventada es ruido que entrena "
                             "a ignorar el mensaje.")

        # --- montar una corrida interrumpida -----------------------------
        EXISTIA.write_text(ORIGINAL, encoding="utf-8")
        DIARIO.write_text(json.dumps({
            str(EXISTIA.relative_to(RAIZ)): ORIGINAL,
            str(NO_EXISTIA.relative_to(RAIZ)): None,
        }), encoding="utf-8")
        EXISTIA.write_text("SABOTEADO\n", encoding="utf-8")
        NO_EXISTIA.write_text("canario suelto\n", encoding="utf-8")

        # --- 2 y 3 · informa, falla, y dice cuáles -----------------------
        codigo, salida = corre()
        if codigo == 0:
            problemas.append("con un sabotaje sin revertir, el arnés pasó en "
                             "verde. El árbol dice algo falso sobre sí mismo y "
                             "la corrida no lo notó.")
        for p in (EXISTIA, NO_EXISTIA):
            if str(p.relative_to(RAIZ)) not in salida:
                problemas.append(f"no nombró «{p.relative_to(RAIZ)}». Informar "
                                 f"sin decir QUÉ obliga a averiguarlo a mano, "
                                 f"que es el costo que esto vino a evitar.")
        if EXISTIA.read_text(encoding="utf-8") != "SABOTEADO\n":
            problemas.append("reparó sin que se lo pidieran. Reparar en "
                             "silencio pisa lo editado después del corte.")

        # --- 4 · --recuperar devuelve los dos caminos --------------------
        codigo, salida = corre("--recuperar")
        if codigo != 0:
            problemas.append(f"`--recuperar` salió con {codigo}")
        if EXISTIA.read_text(encoding="utf-8") != ORIGINAL:
            problemas.append("no devolvió el archivo que YA EXISTÍA a su "
                             "contenido previo. `git checkout` lo habría "
                             "devuelto al último commit, que es otra cosa.")
        if NO_EXISTIA.exists():
            problemas.append("no borró el archivo que NO EXISTÍA antes del "
                             "sabotaje. Un canario suelto deja el árbol "
                             "diciendo algo que no es.")
        if DIARIO.exists():
            problemas.append("el diario sobrevivió a la recuperación. Si queda, "
                             "la corrida siguiente vuelve a fallar por algo ya "
                             "resuelto.")
    finally:
        limpiar()

    if problemas:
        print("probar_recuperacion: FALLA\n")
        for p in problemas:
            print(f"  {p}")
        return 1
    print("probar_recuperacion: ok — informa sin reparar, nombra los archivos, "
          "y `--recuperar`\n                      devuelve los dos caminos: el "
          "que existía y el que no.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
