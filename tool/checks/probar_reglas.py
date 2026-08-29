#!/usr/bin/env python3
"""Prueba que los checks de arquitectura SEPAN FALLAR.

    «Un check que nunca falló no está probado.»
    — criterio de salida de la fase 0

Dos familias de prueba, y la segunda es la que importa:

1. VIOLACIÓN CANÓNICA · cada regla declara en arquitectura.json un caso que
   tiene que detectar. Se inyecta y se revierte. Es sintética a propósito: eso
   la hace compatible con el ratchet —toda regla nueva está verde el día que se
   agrega— y de hecho es su precondición, porque «verde» no significa nada si
   la regla no puede ponerse roja.

2. NEUTRALIZACIÓN + CANÓNICA · se degrada la regla de todas las formas que
   conservan su `id`, y se comprueba que el check IGUAL falla con la canónica
   puesta. Es la diferencia entre «la regla existe» y «la regla dispara».

   Validar el schema de la política va siempre un paso atrás de quien la edita:
   una regla puede conservar id, tipo y todos sus campos no vacíos y no detectar
   nada — basta ensanchar `solo_en`, que hace la lista más LARGA. Por eso se
   verifica el comportamiento, no la forma.

3. Y controles NEGATIVOS: que las exclusiones declaradas excluyan de verdad.

    python3 tool/checks/probar_reglas.py

Corre los DOS verificadores —`capas.py` y `tool/serializacion`— contra cada
sabotaje, porque las reglas viven en un solo registro y el sabotaje no sabe
cuál de los dos tiene que atraparlo. Que una regla la aplique otro motor no la
exime de tener que poder ponerse roja.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
CHECK = RAIZ / "tool" / "checks" / "capas.py"
SERIALIZACION = RAIZ / "tool" / "serializacion"
ARQ_REL = "arquitectura.json"
ARQ = RAIZ / ARQ_REL
HUELLA_REL = "tool/checks/arquitectura.huella"
REGLAS = json.loads(ARQ.read_text(encoding="utf-8"))["reglas"]


def arq_con(mutar) -> str:
    a = json.loads(ARQ.read_text(encoding="utf-8"))
    mutar(a["reglas"])
    return json.dumps(a, ensure_ascii=False, indent=2) + "\n"


def canonica(rid: str) -> dict:
    v = REGLAS[rid]["violacion_canonica"]
    return {"archivos": {v["donde"]: v["contenido"]}, "pub_get": v.get("requiere_pub_get", False)}


def neutralizaciones(rid: str) -> list[tuple[str, object]]:
    """Formas de dejar la regla sin efecto CONSERVANDO su id."""
    tipo = REGLAS[rid]["tipo"]
    n: list[tuple[str, object]] = [
        ("regla borrada", lambda r: r.pop(rid)),
        ("tipo cambiado", lambda r: r[rid].update(tipo="desactivada")),
    ]
    if tipo == "cadenas_acotadas":
        n += [
            ("extensiones vaciadas", lambda r: r[rid]["alcance"].update(extensiones=[])),
            ("solo_en ampliado a todos",
             lambda r: r[rid].update(solo_en=sorted(p.name for p in (RAIZ / "packages").iterdir()))),
            ("exclusión que traga paquetes",
             lambda r: r[rid]["alcance"]["excluir"].__setitem__(
                 "artefactos_de_build",
                 {"que": sorted(p.name for p in (RAIZ / "packages").iterdir()),
                  "por_que": "x", "quien_lo_cubre": "x"})),
            # `no_cuenta` es el único campo que neutraliza la regla AGRANDANDO
            # el registro: la lista queda más larga y todos los campos llenos.
            # Vaciar se ve en un diff; agregar una exención se lee como trabajo.
            ("exención de token ampliada a todo",
             lambda r: r[rid]["alcance"].update(no_cuenta=[{
                 "que": "x", "donde": ".", "por_que": "x", "quien_lo_cubre": "x",
                 "token": "(" + "|".join(r[rid]["cadenas"]) + ")"}])),
        ]
    elif tipo == "flechas_internas":
        n.append(("permitidas ampliadas",
                  lambda r: r[rid]["permitidas"].update(
                      orchestration=sorted(p.name for p in (RAIZ / "packages").iterdir()))))
    elif tipo == "origen_de_dependencias":
        n += [
            ("paquetes vaciados", lambda r: r[rid].update(paquetes=[])),
            ("orígenes ampliados",
             lambda r: r[rid].update(origenes_permitidos=["root", "hosted", "git", "path", "sdk"])),
        ]
    elif tipo == "campos_derivados":
        # Saltear la regla declarando opaca la clase que la violaría. Es una
        # neutralización CRUZADA: no toca esta regla, toca la de al lado.
        n.append(("clase declarada opaca para saltearla",
                  lambda r: r["opacidad-declarada"]["opacos"].__setitem__(
                      "CanarioCampo", {"por_que": "x"})))
    elif tipo == "opacidad_declarada":
        n.append(("lista de opacos vaciada",
                  lambda r: r[rid].update(opacos={"_": "x"})))
    elif tipo == "huecos_declarados":
        n.append(("lista de huecos vaciada",
                  lambda r: r[rid].update(sin_implementacion={"_": "x"})))
    if REGLAS[rid].get("aplicada_por"):
        n.append(("aplicada_por apuntado a otro lado",
                  lambda r: r[rid].update(aplicada_por="tool/inexistente")))
    return n


def casos() -> list[dict]:
    c: list[dict] = []
    for rid in REGLAS:
        base = canonica(rid)
        c.append({
            "nombre": f"{rid} · violación canónica",
            "archivos": dict(base["archivos"]),
            "pub_get": base["pub_get"],
            "menciona": REGLAS[rid]["violacion_canonica"]["debe_mencionar"],
        })
        for etiqueta, mutar in neutralizaciones(rid):
            c.append({
                "nombre": f"{rid} · {etiqueta}",
                "archivos": {ARQ_REL: arq_con(mutar), **base["archivos"]},
                "pub_get": base["pub_get"],
                # Se regenera la huella a propósito: sin esto la huella cazaría
                # toda mutación del JSON y los controles puntuales quedarían sin
                # probar, tapados por ella. Cada uno tiene que valerse solo.
                "regenerar_huella": True,
            })

    # Y la huella, probada por separado: mutación del JSON SIN regenerarla.
    c.append({
        "nombre": "huella · política cambiada sin actualizar la huella",
        "archivos": {ARQ_REL: arq_con(
            lambda r: r["agente-en-agents"]["cadenas"].append("cursor"))},
        "menciona": "huella",
    })

    # La otra mitad de `nucleo-sin-externas`, que la canonica no cubre: la
    # canonica usa `dependencies:`, y `dev_dependencies:` viaja por otra clave
    # del grafo. Mirar una sola era una ausencia silenciosa.
    c.append({
        "nombre": "nucleo-sin-externas · una externa entrando por dev_dependencies",
        "archivos": {"packages/core/pubspec.yaml":
                     "name: core\ndescription: \"canario\"\npublish_to: none\n"
                     "version: 0.1.0\n\nenvironment:\n  sdk: ^3.6.0\n\n"
                     "resolution: workspace\n\ndev_dependencies:\n  lints: ^5.0.0\n"},
        "pub_get": True,
        "menciona": "desarrollo",
    })

    # NEGATIVOS: las exclusiones declaradas tienen que excluir de verdad.
    c.append({
        "nombre": "exclusión · AGENTS.md proyectado queda fuera",
        "archivos": {"packages/orchestration/AGENTS.md": "Usá claude y flutter.\n"},
        "espera": "pasa",
    })
    c.append({
        "nombre": "exclusión · .dart_tool queda fuera",
        "archivos": {"packages/rules/.dart_tool/cache.json": '{"cli": "claude"}\n'},
        "espera": "pasa",
    })

    # La exención de token, por sus DOS bordes. Sin el segundo caso sería
    # indistinguible de haber desactivado la regla en los archivos fuente.
    c.append({
        "nombre": "exención · el sufijo de un export legítimo queda fuera",
        "archivos": {"packages/core/lib/_canario_export.dart": "export 'src/x.dart';\n"},
        "espera": "pasa",
    })
    c.append({
        "nombre": "exención · el mismo sufijo FUERA de una directiva sigue rojo",
        "archivos": {
            "packages/core/lib/_canario_sufijo.dart":
                "bool esFuente(String p) => p.endsWith('.dart');\n"},
        "menciona": "dart",
    })
    c.append({
        "nombre": "exención · una biblioteca del SDK en la lista blanca queda fuera",
        "archivos": {"packages/core/lib/_canario_sdk.dart": "import 'dart:convert';\n"},
        "espera": "pasa",
    })
    c.append({
        "nombre": "exención · una biblioteca del SDK FUERA de la lista sigue roja",
        # core haciendo entrada/salida directa es justo lo que la regla existe
        # para ver: para eso está el puerto Workspace.
        "archivos": {"packages/core/lib/_canario_io.dart": "import 'dart:io';\n"},
        "menciona": "dart",
    })
    c.append({
        "nombre": "exención · un import de paquete vigilado sigue rojo",
        "archivos": {
            "packages/core/lib/_canario_import.dart":
                "import 'package:flutter/material.dart';\n"},
        "menciona": "flutter",
    })
    return c


def corre_check() -> tuple[int, str]:
    """Los dos motores, sumados. Un sabotaje se considera detectado si CUALQUIERA
    de los dos lo ve: las reglas son del registro, no del verificador."""
    salida, peor = "", 0
    r = subprocess.run([sys.executable, str(CHECK)], capture_output=True, text=True)
    salida += r.stdout + r.stderr
    peor = max(peor, r.returncode)
    d = subprocess.run(["dart", "run", "bin/check.dart"], cwd=SERIALIZACION,
                       capture_output=True, text=True, timeout=300)
    salida += d.stdout + d.stderr
    peor = max(peor, d.returncode)
    return peor, salida


def pub_get() -> None:
    subprocess.run(["dart", "pub", "get"], cwd=RAIZ, capture_output=True, timeout=180)


def estado_git() -> str | None:
    """Huella del árbol. No exige que esté LIMPIO —esto corre mientras se
    desarrolla— sino que no CAMBIE: busca residuo, no pulcritud."""
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
                if padre == RAIZ or not padre.is_dir() or any(padre.iterdir()):
                    break
                padre.rmdir()
        else:
            p.write_text(contenido, encoding="utf-8")


def evaluar(caso: dict, codigo: int, salida: str) -> str | None:
    espera_falla = caso.get("espera", "falla") == "falla"
    if espera_falla and codigo == 0:
        return "el check pasó en verde. La regla quedó sin efecto y nadie se enteró."
    if espera_falla and caso.get("menciona") and caso["menciona"] not in salida:
        return f"falló, pero no por esto — no menciona «{caso['menciona']}»."
    if not espera_falla and codigo != 0:
        return "el check falló, pero esto debería estar EXCLUIDO por declaración."
    return None


def main() -> int:
    codigo, salida = corre_check()
    if codigo != 0:
        print("El árbol ya está en rojo antes de sabotear. Arreglá eso primero:\n")
        print(salida)
        return 1
    git_antes = estado_git()
    print("  árbol limpio\n")

    problemas: list[str] = []
    lista = casos()
    for caso in lista:
        previo = aplicar(caso["archivos"])
        try:
            if caso.get("regenerar_huella"):
                previo[HUELLA_REL] = (RAIZ / HUELLA_REL).read_text(encoding="utf-8")
                subprocess.run([sys.executable, str(CHECK), "--huella"], capture_output=True)
            if caso.get("pub_get"):
                pub_get()
            codigo, salida = corre_check()
            problema = evaluar(caso, codigo, salida)
            if problema:
                problemas.append(f"{caso['nombre']}: {problema}")
            else:
                espera_falla = caso.get("espera", "falla") == "falla"
                print(f"  {caso['nombre']:<52} {'detectado' if espera_falla else 'excluido'}")
        finally:
            restaurar(previo)
            if caso.get("pub_get"):
                pub_get()

    codigo, _ = corre_check()
    if codigo != 0:
        problemas.append("el árbol quedó en rojo tras restaurar")
    git_despues = estado_git()
    if git_antes is None or git_despues is None:
        print("\n  (sin git: no se pudo verificar que no quedara residuo)")
    elif git_antes != git_despues:
        nuevos = sorted(set(git_despues.splitlines()) - set(git_antes.splitlines()))
        problemas.append("los sabotajes dejaron residuo:\n      " + "\n      ".join(nuevos))

    if problemas:
        print("\nprobar_reglas: FALLA\n")
        for p in problemas:
            print(f"  {p}")
        return 1
    positivos = sum(1 for c in lista if c.get("espera", "falla") == "falla")
    print(f"\nprobar_reglas: ok — {positivos} sabotajes detectados sobre {len(REGLAS)} reglas, "
          f"{len(lista) - positivos} exclusiones honradas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
