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


def literal_de_lista(texto: str, apertura: str, *, que: str) -> tuple[int, int]:
    """Los índices del literal de lista que abre en [apertura], `[` y `]` incluidos.

    **El cierre se busca por profundidad de corchetes, no por un literal.** La
    llamada que esto lee ganó un segundo argumento —`Cascada([...], observador:
    obs)`— así que ya no cierra con `]);`, y los dos archivos que la leían
    quedaron apuntando a una forma que no existe. Contar profundidad encuentra
    el `]` que hace juego sea cual sea lo que venga después.

    **No entiende Dart**: cuenta caracteres. Un `[` o un `]` dentro de una
    cadena o un comentario, antes del cierre real, la confunde igual que a
    cualquier expresión regular. No es silencioso —el llamador comprueba que lo
    que quedó adentro tenga sentido— pero tampoco es correcto con cualquier
    entrada, y va escrito.
    """
    desde = texto.find(apertura)
    if desde < 0:
        raise AnclaPerdida(
            f"no encontré «{apertura}» para leer {que}. El ancla se perdió: "
            f"reapuntala a la forma nueva. Un ancla que no encuentra nada no "
            f"comprueba nada, y se lee igual que una que comprobó y salió bien.")
    profundidad, i = 0, desde + apertura.index("[")
    while i < len(texto):
        if texto[i] == "[":
            profundidad += 1
        elif texto[i] == "]":
            profundidad -= 1
            if profundidad == 0:
                return desde, i + 1
        i += 1
    raise AnclaPerdida(
        f"el literal de lista de {que} no cierra: no encontré el `]` que hace "
        f"juego con «{apertura}».")
