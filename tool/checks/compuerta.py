#!/usr/bin/env python3
"""La compuerta requerida: verde solo si TODO lo bloqueante terminó en verde.

**Las ramas protegidas exigen UN contexto**, «reglas de arquitectura · Dart
3.12.0», y la protección vive en GitHub, fuera de lo que el arnés ve. Mientras
todo corría en un job, ese contexto cubría análisis, pruebas y sabotajes. Al
repartir el trabajo en jobs paralelos, cada uno nuevo quedaría fuera de la
protección: un sabotaje rojo en otro job no bloquearía nada. Este job lleva el
nombre protegido y depende de todos los bloqueantes.

**`if: always()` y la comprobación explícita, los dos.** Sin `always()`, un
bloqueante rojo deja a la compuerta OMITIDA, y una compuerta omitida no reporta
rojo. Con `always()` corre siempre, así que tiene que decidir ella: cualquier
resultado que no sea `success` —falla, cancelación, omisión, ausencia— es rojo.

    NECESITA='${{ toJSON(needs) }}' python3 tool/checks/compuerta.py

La lista de IDs se fija acá y `organizacion_ci.py` exige que el `needs:` del
workflow sea exactamente esta: un job agregado sin pasar por la compuerta, o el
canario colado en ella, ponen `capas.py` en rojo.
"""
from __future__ import annotations

import json
import os
import sys

# Los jobs que bloquean el merge. El canario no está, y es a propósito: avisa
# sin detener, y si la compuerta lo esperara, un canario lento la retendría.
BLOQUEANTES = ("estatico", "pruebas", "sabotajes", "sabotajes-conjunto",
               "formato", "nativo")


def errores(necesita: object) -> list[str]:
    """Lo que impide a la compuerta ponerse verde; vacío si nada lo impide."""
    if not isinstance(necesita, dict):
        return [f"no recibí el resultado de los jobs como un objeto sino como "
                f"{type(necesita).__name__}: sin saber qué terminó, no hay verde."]
    fallos = []
    for job in BLOQUEANTES:
        if job not in necesita:
            fallos.append(f"«{job}» no está entre los resultados que recibí. Un "
                          f"bloqueante sin resultado no es un bloqueante en verde.")
            continue
        resultado = (necesita[job] or {}).get("result") if isinstance(
            necesita[job], dict) else None
        if resultado != "success":
            fallos.append(f"«{job}» terminó en «{resultado}». Solo `success` "
                          f"deja pasar: una cancelación o una omisión no "
                          f"verificaron nada.")
    for extra in sorted(set(necesita) - set(BLOQUEANTES)):
        fallos.append(f"«{extra}» llegó a la compuerta y no es un bloqueante "
                      f"declarado. Si es el canario, su resultado no puede "
                      f"decidir el merge; si es nuevo, va en `BLOQUEANTES`.")
    return fallos


def main() -> int:
    crudo = os.environ.get("NECESITA")
    if crudo is None:
        print("compuerta: FALLA\n\n  falta NECESITA: sin el resultado de los "
              "jobs no hay nada que afirmar.")
        return 1
    try:
        necesita = json.loads(crudo)
    except json.JSONDecodeError as e:
        print(f"compuerta: FALLA\n\n  NECESITA no es JSON: {e}")
        return 1
    fallos = errores(necesita)
    if fallos:
        print("compuerta: FALLA\n")
        for f in fallos:
            print(f"  {f}")
        return 1
    print(f"compuerta: ok — {', '.join(BLOQUEANTES)} en verde.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
