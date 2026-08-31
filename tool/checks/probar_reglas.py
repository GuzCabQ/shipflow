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

3. CASO CIEGO · a cada verificador se le quita el canal por el que observa, y
   se comprueba que se ponga ROJO. Es el simétrico de la violación canónica y
   la mitad que faltaba: aquella prueba que el check detecta un EXCESO —algo
   que no debería estar—; esta, que detecta una OMISIÓN —que no pudo mirar—.

   ADR-011 corolario 5 lo llama «el sesgo natural de todo verificador», y su
   invariante ejecutable pedía exactamente esto desde el 25/08. Estuvo escrito
   y sin instalar, que es la enfermedad que este proyecto combate.

4. Y controles NEGATIVOS: que las exclusiones declaradas excluyan de verdad.

    python3 tool/checks/probar_reglas.py

Corre los DOS motores —`capas.py` y `tool/analisis`— contra cada
sabotaje, porque las reglas viven en un solo registro y el sabotaje no sabe
cuál de los dos tiene que atraparlo. Que una regla la aplique otro motor no la
exime de tener que poder ponerse roja.
"""
from __future__ import annotations

import json
import re
import signal
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
CHECK = RAIZ / "tool" / "checks" / "capas.py"
ANALISIS = RAIZ / "tool" / "analisis"
# Diario de escritura anticipada. Se escribe ANTES de tocar el árbol y se borra
# después de restaurarlo, así que su existencia significa exactamente una cosa:
# hay un sabotaje aplicado y sin revertir.
#
# El `finally` cubre las excepciones; no cubre que a este proceso lo maten. Ya
# pasó: una corrida terminada desde afuera dejó `arquitectura.json` saboteado y
# un canario suelto en el árbol, y hubo que limpiarlo a mano. Con el diario, la
# corrida siguiente lo DICE y falla; deshacerlo es un acto explícito,
# `--recuperar`. Ver `recuperar()` para por qué no se repara solo.
DIARIO = RAIZ / "tool" / "checks" / ".sabotaje-en-curso.json"
ARQ_REL = "arquitectura.json"
CI_REL = ".github/workflows/checks.yml"
ARQ = RAIZ / ARQ_REL
HUELLA_REL = "tool/checks/arquitectura.huella"
REGLAS = json.loads(ARQ.read_text(encoding="utf-8"))["reglas"]


def arq_con(mutar) -> str:
    a = json.loads(ARQ.read_text(encoding="utf-8"))
    mutar(a["reglas"])
    return json.dumps(a, ensure_ascii=False, indent=2) + "\n"


# Violaciones canónicas ADICIONALES que el registro TIENE que declarar.
#
# `REGLAS[rid].get("violaciones_extra", [])` hace que borrar la entrada del
# JSON se lea como «esta regla no tiene extras»: el canario que sostiene un
# arreglo desaparece y el arnés sigue en verde con un sabotaje menos. Lo
# comprobó un review borrándolo — 86 sabotajes, exit 0 — contra un README que
# afirmaba que el arreglo no se podía deshacer en silencio.
#
# Esta lista es el piso. Borrarla es editar el arnés, que es el mismo acto que
# borrar un check entero; no un campo que se va en un diff de JSON.
EXTRAS_OBLIGATORIAS: dict[str, set[str]] = {
    "puertos-sin-implementacion": {
        "implementado a traves de una base abstracta",
        "homonima en el ORIGEN de la resolucion",
        "dos puertos homonimos con la MISMA herencia",
    },
}


def inventario_incompleto() -> list[str]:
    """Extras declaradas en el registro contra las que el arnés exige."""
    faltantes = []
    for rid, nombres in EXTRAS_OBLIGATORIAS.items():
        if rid not in REGLAS:
            faltantes.append(
                f"«{rid}» tiene violaciones canónicas obligatorias y ya no está "
                f"en el registro.")
            continue
        declaradas = {e["nombre"] for e in REGLAS[rid].get("violaciones_extra", [])}
        for n in sorted(nombres - declaradas):
            faltantes.append(
                f"«{rid}» tiene que declarar la violación canónica «{n}» y no "
                f"está en arquitectura.json. Sin ella, el arreglo que sostiene "
                f"se puede deshacer sin que nada falle.")
    return faltantes


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


BASURA = ")))esto no parsea de ninguna manera(((\n"


def casos_ciegos() -> list[dict]:
    """Uno por regla, DERIVADO del registro. Si una regla no lo declara no se
    saltea: `capas.py` la rechaza, y acá el conteo tampoco cuadraría."""
    c: list[dict] = []
    for rid, regla in REGLAS.items():
        ciego = regla.get("caso_ciego")
        if not ciego:
            continue
        como = ciego.get("como")
        caso = {
            "nombre": f"{rid} · CIEGO · {como}",
            "menciona": ciego.get("debe_mencionar"),
            "es_ciego": True,
        }
        if como == "alcance_inexistente":
            caso["archivos"] = {ARQ_REL: arq_con(
                lambda r, _rid=rid: r[_rid]["alcance"].update(raiz="no-existe"))}
            # Sin esto la huella caza la mutación y tapa lo que se quiere probar.
            caso["regenerar_huella"] = True
        elif como == "grafo_indisponible":
            caso["archivos"] = {"pubspec.yaml": "name: shipflow\n  :::esto no es yaml\n"}
            caso["pub_get"] = True
        elif como == "archivo_ilegible":
            # Se rompe un archivo QUE YA EXISTE Y YA ES ALCANZABLE. Agregar uno
            # nuevo no serviría: quedaría huérfano y el rojo vendría de Q5, no
            # de la ceguera — y rojo por la razón equivocada no prueba nada.
            objetivo = ("packages/core/test/regla_test.dart"
                        if rid == "grafo-derivado"
                        else "packages/core/lib/src/valores.dart")
            caso["archivos"] = {objetivo: BASURA}
            caso["probar_grafo"] = rid == "grafo-derivado"
        else:
            caso["archivos"] = {}
            caso["mecanismo_desconocido"] = como
        c.append(caso)
    return c


def casos() -> list[dict]:
    c: list[dict] = []
    for rid in REGLAS:
        base = canonica(rid)
        # Una regla que aplica el motor del grafo necesita ese motor encendido.
        del_grafo = REGLAS[rid].get("tipo") == "grafo_derivado"
        c.append({
            "nombre": f"{rid} · violación canónica",
            "archivos": dict(base["archivos"]),
            "pub_get": base["pub_get"],
            "menciona": REGLAS[rid]["violacion_canonica"]["debe_mencionar"],
            "probar_grafo": del_grafo,
        })
        # Violaciones canónicas ADICIONALES. Una regla puede tener más de una
        # forma de romperse, y la segunda suele aparecer cuando el check falla
        # en verde por un camino que nadie había mirado. Sin registrarla, el
        # arreglo se puede deshacer sin que nada lo note: el arreglo tampoco es
        # un invariante hasta que algo lo sostiene.
        for extra in REGLAS[rid].get("violaciones_extra", []):
            archivos = dict(extra["archivos"])
            declarar = extra.get("declarar_sin_implementacion")
            caso = {
                "nombre": f"{rid} · {extra['nombre']}",
                "archivos": archivos,
                "pub_get": extra.get("requiere_pub_get", False),
                "menciona": extra["debe_mencionar"],
                "probar_grafo": del_grafo,
            }
            if declarar is not None:
                # El sabotaje necesita que el registro AFIRME que el puerto no
                # tiene implementación, para que el check tenga que
                # contradecirlo. Sin esto el puerto sería un huérfano sin
                # declarar y el check fallaría por el otro motivo — en rojo,
                # pero por la razón equivocada, que es un falso detectado.
                caso["archivos"] = {
                    ARQ_REL: arq_con(
                        lambda r, d=declarar, i=rid: r[i]["sin_implementacion"]
                        .update({d: "canario del sabotaje"})),
                    **archivos,
                }
                caso["regenerar_huella"] = True
            c.append(caso)

        for etiqueta, mutar in neutralizaciones(rid):
            c.append({
                "nombre": f"{rid} · {etiqueta}",
                "archivos": {ARQ_REL: arq_con(mutar), **base["archivos"]},
                "pub_get": base["pub_get"],
                "probar_grafo": del_grafo,
                # Se regenera la huella a propósito: sin esto la huella cazaría
                # toda mutación del JSON y los controles puntuales quedarían sin
                # probar, tapados por ella. Cada uno tiene que valerse solo.
                "regenerar_huella": True,
            })

    # Y el otro modo de fallo del grafo: no un archivo nuevo, sino el grafo
    # commiteado retocado a mano. Son distintos: uno es olvidarse de
    # regenerar, el otro es editar lo que se deriva.
    c.append({
        "nombre": "grafo · grafo commiteado editado a mano",
        "archivos": {"grafo.jsonl": (RAIZ / "grafo.jsonl").read_text(encoding="utf-8")
                     .replace('"saltos":0', '"saltos":9', 1)},
        "menciona": "grafo",
        "probar_grafo": True,
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

    # Que CI siga ejecutando lo que dice ejecutar. Tres modos de fallo, y son
    # distintos: uno borra el paso, otro lo deja corriendo sin que detenga
    # nada, y el tercero se lleva el workflow entero.
    ci = (RAIZ / CI_REL).read_text(encoding="utf-8")
    i = ci.index("      - name: los checks saben fallar")
    j = ci.index("      - name: pruebas de core")
    c.append({
        "nombre": "ci · un paso obligatorio borrado del workflow",
        "archivos": {CI_REL: ci[:i] + ci[j:]},
        "menciona": "ya no ejecuta",
    })
    c.append({
        "nombre": "ci · un paso obligatorio con continue-on-error",
        "archivos": {CI_REL: ci.replace(
            "        run: python3 tool/checks/probar_reglas.py",
            "        run: python3 tool/checks/probar_reglas.py\n"
            "        continue-on-error: true")},
        "menciona": "continue-on-error",
    })
    c.append({
        "nombre": "ci · el workflow vaciado",
        "archivos": {CI_REL: "# vacío\n"},
        "menciona": "NI UN paso",
    })
    # Un paso puede estar presente y no gobernar nada. Estas cuatro formas
    # dejan el comando escrito en el archivo y la compuerta abierta, y las
    # cuatro pasaban cuando la comprobación era por subcadena.
    for etiqueta, viejo, nuevo, menciona in [
        ("envuelto en echo",
         "        run: python3 tool/checks/probar_reglas.py",
         '        run: echo "python3 tool/checks/probar_reglas.py"',
         "exactamente"),
        ("con «|| true» al final",
         "        run: dart test packages/core",
         "        run: dart test packages/core || true",
         "exactamente"),
        ("el job entero con continue-on-error",
         "    continue-on-error: ${{ matrix.canario }}",
         "    continue-on-error: true",
         "compuerta queda abierta"),
        # Estas dos dejan el comando EXACTO en el archivo y aun así no
        # gobiernan nada: GitHub omite el paso o deja de bloquear con él.
        # Comparar el comando no alcanzaba; hay que mirar sus atributos.
        ("omitido con «if: false»",
         "        run: python3 tool/checks/probar_reglas.py",
         "        run: python3 tool/checks/probar_reglas.py\n        if: false",
         "condición"),
        ("con «continue-on-error: ${{ true }}»",
         "        run: python3 tool/checks/probar_reglas.py",
         "        run: python3 tool/checks/probar_reglas.py\n"
         "        continue-on-error: ${{ true }}",
         "no detiene nada"),
        ("corriendo desde otro directorio",
         "        run: dart run bin/check.dart\n        working-directory: tool/analisis",
         "        run: dart run bin/check.dart",
         "exactamente"),
    ]:
        assert ci.count(viejo) == 1, f"ancla del caso «{etiqueta}» no encontrada"
        c.append({
            "nombre": f"ci · un paso obligatorio {etiqueta}",
            "archivos": {CI_REL: ci.replace(viejo, nuevo)},
            "menciona": menciona,
        })

    # Que el README siga describiendo lo que gobierna de verdad. Es lo que
    # envejeció en silencio y encontró un review, no un check.
    readme = (RAIZ / "README.md").read_text(encoding="utf-8")
    filas = [l for l in readme.splitlines()
             if re.match(r"^\| `grafo-derivado` \|.*\| `[^`]+` \|$", l)]
    assert len(filas) == 1, f"filas de la tabla encontradas: {len(filas)}"
    c.append({
        "nombre": "readme · una regla que gobierna y no está en la tabla",
        "archivos": {"README.md": readme.replace(filas[0] + "\n", "")},
        "menciona": "no está en la tabla",
    })
    c.append({
        "nombre": "readme · una ruta del repositorio que ya no existe",
        "archivos": {"README.md": readme.replace("`tool/analisis`",
                                                 "`tool/serializacion`", 1)},
        "menciona": "no existe en el",
    })
    # La toolchain: dos formas de que el verde deje de significar lo que dice.
    # No hay fallo visible en ninguna — hay un instrumento sustituido.
    flutter_paso = ("      - name: flutter\n"
                    "        uses: subosito/flutter-action@"
                    "1a449444c387b1966244ae4d4f8c696479add0b2 # v2\n"
                    "        with:\n          flutter-version: 3.44.0")
    assert ci.count(flutter_paso) == 1, "ancla del paso de flutter no encontrada"
    c.append({
        "nombre": "ci · dos toolchains de Dart en el mismo job",
        "archivos": {CI_REL: ci.replace(
            "      - name: analyze\n        run: dart analyze --fatal-infos",
            flutter_paso + "\n\n      - name: analyze\n"
            "        run: dart analyze --fatal-infos", 1)},
        "menciona": "instala Dart Y Flutter",
    })
    c.append({
        "nombre": "ci · Flutter en un canal flotante como compuerta",
        "archivos": {CI_REL: ci.replace("          flutter-version: 3.44.0",
                                        "          channel: stable", 1)},
        "menciona": "no es una versión exacta",
    })
    # El control negativo de la exención de canario se retiró CON la exención.
    # Existía para probar que «flotante prohibido salvo en canario» no era
    # «prohibido siempre» — y hoy es prohibido siempre, a propósito: no existe
    # ningún canario de Flutter, y la exención estaba escrita para un caso
    # hipotético. Un control negativo que defiende una exención que ya no está
    # es peor que no tenerlo: la haría parecer viva.
    c.append({
        "nombre": "ci · Flutter flotante tampoco vale con pinta de canario",
        "archivos": {CI_REL: ci
                     .replace("          flutter-version: 3.44.0",
                              "          flutter-version: stable", 1)
                     .replace("    name: el fixture se verifica a sí mismo\n"
                              "    runs-on: ubuntu-latest",
                              "    name: el fixture se verifica a sí mismo\n"
                              "    runs-on: ubuntu-latest\n"
                              "    continue-on-error: ${{ matrix.canario }}", 1)},
        "menciona": "no es una versión exacta",
    })
    # El número se DERIVA del README, no se cablea: cablearlo hacía que este
    # caso dejara de sabotear nada en cuanto la cantidad real cambiara — un
    # sabotaje que no sabotea es un caso que pasa por no hacer nada.
    m_pasos = re.search(r"[Ll]os (\d+) pasos obligatorios", readme)
    assert m_pasos, "no encontré la cantidad de pasos en el README"
    c.append({
        "nombre": "readme · una cantidad en prosa que envejeció",
        "archivos": {"README.md": readme.replace(
            m_pasos.group(0),
            m_pasos.group(0).replace(m_pasos.group(1),
                                     str(int(m_pasos.group(1)) - 3)), 1)},
        "menciona": "pasos obligatorios",
    })

    # El nombre viejo sobrevivió dentro de un bloque de código, colgando de
    # `tool/` y sin ser una ruta completa: no había ruta que verificar.
    c.append({
        "nombre": "readme · un nombre retirado, sin forma de ruta",
        "archivos": {"README.md": readme.replace("  analisis/", "  serializacion/", 1)},
        "menciona": "nombre retirado",
    })

    # La canónica de `colecciones-inmutables` usa el constructor anónimo. El
    # nombrado era el punto ciego: la regla cubría una FORMA DE ESCRIBIR el
    # constructor y no el invariante.
    c.append({
        "nombre": "colecciones-inmutables · alias por constructor con nombre",
        "archivos": {"packages/core/lib/src/_canario_nombrado.dart":
                     "class CanarioNombrado {\n"
                     "  final List<String> items;\n"
                     "  CanarioNombrado.desde(this.items);\n"
                     "  Map<String, Object?> toJson() => {'items': items};\n"
                     "  factory CanarioNombrado.fromJson(Map<String, Object?> json) =>\n"
                     "      CanarioNombrado.desde(\n"
                     "          List<String>.from(json['items']! as List<Object?>));\n"
                     "}\n"},
        "menciona": "por referencia",
    })

    # Y la mitad que faltaba: a cada verificador se le quita la vista.
    c += casos_ciegos()
    return c


def compilar() -> dict[str, list[str]]:
    """Compila los verificadores Dart a snapshot, UNA vez.

    Cada caso los invoca de nuevo, y `dart run` paga ~2,6 s de arranque de VM
    cada vez: sobre cincuenta y cinco casos son más de cuatro minutos de nada.
    Un snapshot arranca en 0,2 s.

    El `.dill` va en `bin/`, no en un temporal, porque los dos verificadores
    encuentran la raíz del repositorio subiendo desde `Platform.script`.
    """
    ordenes: dict[str, list[str]] = {}
    for binario in ("check", "grafo"):
        dill = ANALISIS / "bin" / f"{binario}.dill"
        r = subprocess.run(
            ["dart", "compile", "kernel", f"bin/{binario}.dart", "-o", f"bin/{binario}.dill"],
            cwd=ANALISIS, capture_output=True, text=True, timeout=300)
        ordenes[binario] = (["dart", str(dill)] if r.returncode == 0 and dill.exists()
                            else ["dart", "run", f"bin/{binario}.dart"])
    return ordenes


ORDENES: dict[str, list[str]] = {}


def corre_check(con_grafo: bool = True) -> tuple[int, str]:
    """Los motores, sumados. Un sabotaje se considera detectado si CUALQUIERA
    de ellos lo ve: las reglas son del registro, no del verificador.

    `con_grafo=False` apaga el del grafo, y no es comodidad. Todo archivo que
    un sabotaje inyecta es, por construcción, un archivo que nadie importa —
    es decir, un huérfano—, así que el control Q5 dispararía en TODOS los casos
    y taparía al control que cada uno apunta. Es el mismo enmascaramiento que
    ya había provocado la huella. El grafo se prueba en sus dos casos propios,
    donde es lo único que puede fallar."""
    salida, peor = "", 0
    r = subprocess.run([sys.executable, str(CHECK)], capture_output=True, text=True)
    salida += r.stdout + r.stderr
    peor = max(peor, r.returncode)
    for binario in ("check", *(("grafo",) if con_grafo else ())):
        d = subprocess.run(ORDENES.get(binario, ["dart", "run", f"bin/{binario}.dart"]),
                           cwd=ANALISIS, capture_output=True, text=True, timeout=300)
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
    # El diario se escribe ANTES de la primera modificación. Si el proceso
    # muere en cualquier punto de lo que sigue, la corrida siguiente sabe qué
    # deshacer.
    DIARIO.write_text(json.dumps(previo, ensure_ascii=False), encoding="utf-8")
    for ruta, contenido in archivos.items():
        p = RAIZ / ruta
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(contenido, encoding="utf-8")
    return previo


def anotar(previo: dict[str, str | None], ruta: str) -> None:
    """Agrega un archivo al conjunto a restaurar Y REESCRIBE EL DIARIO.

    Sin esto quedaba un hueco: la huella se agregaba a `previo` después de que
    el diario ya estaba escrito, así que una muerte entre medio la dejaba
    modificada y sin registrar. Un diario que no se actualiza cuando cambia lo
    que hay que deshacer es un diario que miente sobre su alcance.
    """
    p = RAIZ / ruta
    previo[ruta] = p.read_text(encoding="utf-8") if p.exists() else None
    DIARIO.write_text(json.dumps(previo, ensure_ascii=False), encoding="utf-8")


def restaurar(previo: dict[str, str | None]) -> None:
    _restaurar(previo)
    DIARIO.unlink(missing_ok=True)


def _restaurar(previo: dict[str, str | None]) -> None:
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
    if caso.get("mecanismo_desconocido"):
        return (f"declara el mecanismo de ceguera «{caso['mecanismo_desconocido']}», "
                f"que este arnés no sabe aplicar. Un caso que no se puede montar "
                f"no es un caso que pasó: es uno que no se probó.")
    espera_falla = caso.get("espera", "falla") == "falla"
    if espera_falla and codigo == 0:
        if caso.get("es_ciego"):
            return ("el check pasó en VERDE con su canal de observación "
                    "inutilizado. No miró nada y lo llamó aprobación — es la "
                    "clase 1 exacta, y ADR-011 dice que eso es fallo.")
        return "el check pasó en verde. La regla quedó sin efecto y nadie se enteró."
    if espera_falla and caso.get("menciona") and caso["menciona"] not in salida:
        return f"falló, pero no por esto — no menciona «{caso['menciona']}»."
    if not espera_falla and codigo != 0:
        return "el check falló, pero esto debería estar EXCLUIDO por declaración."
    return None


def recuperar(reparar: bool) -> bool:
    """Informa qué dejó a medias una corrida que no terminó. Devuelve si hay algo.

    **No repara sola, y eso es la decisión.** El diseño ya falla ruidosamente
    ante un árbol tocado —«el árbol ya está en rojo antes de sabotear»— y esa
    negativa ES el control. Reparar en silencio pisaría con contenido viejo
    cualquier cosa editada después del corte, y escondería lo que había que
    mostrar; ADR-015 dice lo mismo de un hallazgo: no se corrige solo ni se
    reporta en silencio.

    Lo que faltaba no era reparar: era **saber qué reparar**. Averiguarlo a
    mano costó tiempo real cuando pasó.

    `--recuperar` lo deshace, y es explícito a propósito — mismo patrón que
    `cifras.py --fix`, que tampoco corrige sin que se lo pidan. Y a diferencia
    de `git checkout`, devuelve los archivos a su contenido PREVIO AL SABOTAJE,
    no al último commit: no se pierde trabajo sin commitear.
    """
    for b in ("check", "grafo"):
        (ANALISIS / "bin" / f"{b}.dill").unlink(missing_ok=True)
    if not DIARIO.exists():
        return False
    previo = json.loads(DIARIO.read_text(encoding="utf-8"))
    if reparar:
        _restaurar(previo)
        DIARIO.unlink(missing_ok=True)
        print(f"recuperado: {len(previo)} archivo(s) devueltos a su contenido "
              f"previo al sabotaje.\n")
        for ruta in sorted(previo):
            print(f"  {ruta}")
        return False
    print("Una corrida anterior no terminó y dejó el árbol saboteado.\n")
    for ruta in sorted(previo):
        print(f"  {ruta}")
    print("\nEstos archivos NO dicen la verdad sobre el proyecto: tienen un "
          "sabotaje aplicado y sin\nrevertir. Corré `probar_reglas.py "
          "--recuperar` para devolverlos a su contenido\nprevio — no a lo "
          "commiteado, así que no se pierde trabajo sin commitear.")
    return True


def _al_recibir_senal(_num, _frame):
    """SIGINT y SIGTERM: acá el proceso todavía es dueño del árbol, así que
    deshacer es correcto y no pisa nada de nadie. SIGKILL no se puede atrapar,
    y para ese caso está el diario más `--recuperar`."""
    recuperar(reparar=True)
    sys.exit(130)


def main() -> int:
    global ORDENES
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, _al_recibir_senal)
    if recuperar(reparar="--recuperar" in sys.argv):
        return 1
    if "--recuperar" in sys.argv:
        return 0
    ORDENES = compilar()
    codigo, salida = corre_check()
    if codigo != 0:
        print("El árbol ya está en rojo antes de sabotear. Arreglá eso primero:\n")
        print(salida)
        return 1
    faltantes = inventario_incompleto()
    if faltantes:
        print("El inventario de sabotajes está incompleto:\n")
        for f in faltantes:
            print(f"  {f}")
        return 1

    git_antes = estado_git()
    print("  árbol limpio\n")

    problemas: list[str] = []
    lista = casos()
    for caso in lista:
        previo = aplicar(caso["archivos"])
        try:
            if caso.get("regenerar_huella"):
                anotar(previo, HUELLA_REL)
                subprocess.run([sys.executable, str(CHECK), "--huella"], capture_output=True)
            if caso.get("pub_get"):
                pub_get()
            codigo, salida = corre_check(con_grafo=bool(caso.get("probar_grafo")))
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
    for b in ("check", "grafo"):
        (ANALISIS / "bin" / f"{b}.dill").unlink(missing_ok=True)
    ciegos = sum(1 for c in lista if c.get("es_ciego"))
    if ciegos != len(REGLAS):
        problemas.append(
            f"hay {ciegos} casos ciegos para {len(REGLAS)} reglas. Toda regla "
            f"declara cómo se la deja sin vista; si falta uno, ese control nunca "
            f"se probó a oscuras y nadie lo nota.")
    if problemas:
        print("\nprobar_reglas: FALLA\n")
        for p in problemas:
            print(f"  {p}")
        return 1
    positivos = sum(1 for c in lista if c.get("espera", "falla") == "falla")
    print(f"\nprobar_reglas: ok — {positivos} sabotajes detectados sobre {len(REGLAS)} reglas, "
          f"de los cuales {ciegos} son casos CIEGOS —uno por regla—, "
          f"y {len(lista) - positivos} exclusiones honradas.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
