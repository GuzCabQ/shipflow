#!/usr/bin/env python3
"""Anclajes en texto, **con el fallo a la vista**.

Los dos checks anclan en literales: un nombre de step del workflow, una frase
del README, una llamada de Dart. Cuando un ancla se pierde hay dos formas de
fallar, y las dos estaban sueltas en el árbol:

- **`.index` sin guardia** revienta con `ValueError: substring not found`, sin
  decir qué se buscaba ni para qué. Pasó en `probar_reglas.py`: el ancla
  `Cascada([...])` quedó rota **veinticuatro commits** sin que nadie lo notara.
- **`.replace` sin guardia** es peor, porque no revienta: devuelve el texto sin
  tocar, el sabotaje no sabotea nada, y el arnés lo reporta como «la regla quedó
  sin efecto» — un diagnóstico que acusa al control equivocado.

Este módulo existe para que las dos formas dejen de ser posibles. Es un tercero
neutral a propósito: `probar_reglas.py` invoca a `capas.py` **como subproceso**
para que un sabotaje no pueda romper el arnés que lo aplica, así que importarse
entre ellos deshacía esa separación.
"""
from __future__ import annotations


class AnclaPerdida(Exception):
    """Un ancla dejó de existir, o dejó de ser única."""


def exige_unica(texto: str, trozo: str, *, que: str) -> int:
    """El índice de [trozo], **exigiendo que aparezca exactamente una vez**.

    Para los anclajes que solo localizan —un recorte entre dos posiciones— y no
    reemplazan nada.
    """
    n = texto.count(trozo)
    if n != 1:
        raise AnclaPerdida(
            f"el ancla de «{que}» aparece {n} veces y tiene que aparecer una.\n"
            f"      buscaba: {trozo!r}\n"
            f"      Si el texto cambió de forma, hay que reapuntar el ancla — no "
            f"borrarla: sin ella el caso deja de probar lo que dice probar.")
    return texto.index(trozo)


def ancla_multiple(texto: str, viejo: str, nuevo: str, *, que: str) -> str:
    """Reemplaza la PRIMERA ocurrencia, exigiendo que haya **al menos una**.

    Es para los anclajes que se repiten por diseño —un campo que todo nodo de
    un archivo derivado tiene—, donde exigir unicidad sería exigir lo contrario
    de lo que el formato garantiza. Lo que se sigue prohibiendo es cero: un
    reemplazo que no encuentra nada devuelve el texto intacto y deja un sabotaje
    que no sabotea.
    """
    if viejo not in texto:
        raise AnclaPerdida(
            f"el ancla de «{que}» no aparece ninguna vez.\n"
            f"      buscaba: {viejo!r}\n"
            f"      Sin ella el caso deja de probar lo que dice probar.")
    return texto.replace(viejo, nuevo, 1)


def ancla(texto: str, viejo: str, nuevo: str, *, que: str) -> str:
    """Reemplaza [viejo] por [nuevo] **exigiendo exactamente una ocurrencia**.

    No es paranoia sobre `.replace`: cero ocurrencias lo vuelve una operación
    muda, y dos lo vuelven ambiguo —se cambia la primera y la otra queda—.
    Las dos dejan un sabotaje que no sabotea.
    """
    exige_unica(texto, viejo, que=que)
    return texto.replace(viejo, nuevo, 1)


# **Acá vivía `literal_de_lista`, y se fue porque estaba mal.**
#
# Encontraba el `]` que hace juego con un `[` contando profundidad sobre el
# texto, comentarios y cadenas incluidos. Su propio comentario admitía que no
# entendía Dart y afirmaba que el llamador comprobaría que el recorte tuviera
# sentido. Una revisión lo reprodujo: con `// ]` antes del segundo paso, el
# recorte veía UNO donde había dos y ningún guardia disparaba.
#
# No se le agregó una guardia más: contar caracteres para leer sintaxis es la
# idea equivocada, y se pide al analizador, que es quien sabe. La derivación
# vive en `tool/analisis/bin/check.dart`, sobre el árbol sintáctico.
