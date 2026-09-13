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

import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _comun import ancla, ancla_multiple, exige_unica  # noqa: E402

# **Los sabotajes corren sobre una COPIA PRIVADA, nunca sobre el checkout
# compartido.** Esta bandera la pone el proceso externo cuando ya hizo la copia;
# sin ella, `main` copia y se rehace a sí mismo adentro.
EN_COPIA = "--en-copia"

# Por dónde el proceso externo le dice al interno de dónde salió la copia. No es
# comodidad: es lo que le permite al interno NEGARSE a sabotear si resulta que
# está parado sobre el original. Ver `main`.
ORIGEN = "ARNES_ORIGEN"

# Lo que NO se copia: el historial —que la copia no necesita y pesa—, los
# artefactos de build y los snapshots, que se regeneran. `.dart_tool` SÍ se
# copia: sus rutas a los miembros del workspace son relativas, así que en la
# copia resuelven a la copia, y eso evita un `pub get` por corrida. Es el mismo
# hecho medido que hace funcionar el candidato.
SIN_COPIAR = (".git", "build", "*.dill")

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


def huella_del_arbol(raiz: Path, *, con_generados: bool) -> str:
    """Huella del contenido de un árbol. **Bytes, no `git status`.**

    `estado_git` preguntaba a git, así que solo veía lo versionado y necesitaba
    un `.git` que la copia no tiene. Esto compara contenido, y sirve para las
    dos preguntas distintas que hay que hacerse:

    - **afuera**, que el checkout compartido no haya cambiado en absoluto, y ahí
      `.dart_tool` SÍ cuenta: nada nuestro corre pub sobre el original;
    - **adentro**, que los sabotajes no dejen residuo, y ahí `.dart_tool` NO
      puede contar, porque `package_config.json` lleva una fecha de generación y
      los casos que corren `pub get` la cambian sin que eso sea residuo.

    **Cada entrada va con su tipo, su modo y las longitudes por delante.** La
    primera versión concatenaba ruta y contenido con un `\0` en medio, y eso no
    es una representación inequívoca: un árbol con `a=«b»` y `c=«d»` entregaba al
    hash exactamente los mismos bytes que uno con `a=«bc\0d»`. No era una
    colisión de SHA-256 — eran dos árboles distintos con la misma entrada. Lo
    encontró una revisión, y `huella_ambigua` lo comprueba en cada corrida.

    El modo tampoco viajaba, así que cambiar el bit ejecutable de un archivo no
    movía la huella. Un arnés que promete «el original no cambió en absoluto»
    tiene que ver eso.
    """
    h = hashlib.sha256()
    ignorados = {".git", "build"} | (set() if con_generados else {".dart_tool"})
    for ruta in sorted(raiz.rglob("*")):
        rel = ruta.relative_to(raiz)
        if set(rel.parts) & ignorados or rel.suffix == ".dill":
            continue
        if ruta.is_symlink():
            tipo, carga, modo = b"L", os.readlink(ruta).encode("utf-8"), 0
        elif ruta.is_dir():
            tipo, carga, modo = b"D", b"", 0
        else:
            tipo, carga = b"F", ruta.read_bytes()
            modo = ruta.stat().st_mode & 0o777
        nombre = str(rel).encode("utf-8")
        h.update(tipo + b"\0")
        h.update(f"{modo:o}".encode("ascii") + b"\0")
        h.update(f"{len(nombre)}".encode("ascii") + b"\0" + nombre)
        h.update(f"{len(carga)}".encode("ascii") + b"\0" + carga)
    return h.hexdigest()


def huella_ambigua() -> list[str]:
    """Que la huella distinga lo que dice distinguir. **Se comprueba siempre.**

    No hay dónde poner una prueba unitaria de este archivo, y dejar la propiedad
    sin comprobar sería la misma clase de confianza que el arnés persigue: la
    huella es lo único que sostiene la afirmación de que el checkout compartido
    no cambió. Si deja de distinguir, esa afirmación pasa a ser una frase.

    Los dos casos son los que fallaron: la separación entre registros, y el modo.
    """
    problemas: list[str] = []
    base = Path(tempfile.mkdtemp(prefix="arnes-huella-"))
    try:
        a, b = base / "a", base / "b"
        a.mkdir()
        b.mkdir()
        (a / "a").write_bytes(b"b")
        (a / "c").write_bytes(b"d")
        (b / "a").write_bytes(b"bc\0d")
        if huella_del_arbol(a, con_generados=True) == huella_del_arbol(
                b, con_generados=True):
            problemas.append(
                "la huella no separa los registros: un árbol con dos archivos "
                "y otro con uno solo dan la misma.\n      Sin longitudes por "
                "delante, «no cambió en absoluto» no es una afirmación "
                "comprobable.")
        c = base / "c"
        c.mkdir()
        archivo = c / "x"
        archivo.write_bytes(b"1")
        antes = huella_del_arbol(c, con_generados=True)
        archivo.chmod(0o755)
        if huella_del_arbol(c, con_generados=True) == antes:
            problemas.append(
                "la huella no ve el modo: cambiar el bit ejecutable de un "
                "archivo no la mueve.")
    finally:
        shutil.rmtree(base, ignore_errors=True)
    return problemas


def en_copia_privada(argumentos: list[str]) -> int:
    """Copia el árbol, corre el arnés adentro, y comprueba que el original no
    cambió.

    **El arnés escribía los sabotajes sobre el checkout compartido y restauraba
    después.** El diario cubría las interrupciones y no cubría la concurrencia:
    mientras una corrida tenía un sabotaje puesto, otro proceso commiteó — y el
    commit se llevó `aplicada_por: tool/inexistente`, un canario sintético
    versionado, y la huella del JSON saboteado. Un checkout limpio de ese commit
    fallaba `capas.py` con dos errores. Ningún control lo vio, porque todos miran
    el árbol de trabajo y ninguno mira lo commiteado.

    Copiar cuesta una décima de segundo y vuelve el problema imposible en vez de
    improbable: el original queda intocado por construcción, y además se
    comprueba. Lo segundo no es redundante — es lo que convierte «no lo tocamos»
    en un hecho medido.
    """
    antes = huella_del_arbol(RAIZ, con_generados=True)
    temporal = Path(tempfile.mkdtemp(prefix="arnes-copia-"))
    # `flush` porque el proceso interno escribe a la misma salida sin buffer:
    # sin esto, el aviso de la copia aparecía DESPUÉS del veredicto, que es
    # decir dónde corrió una vez que ya no importa.
    print(f"  copia privada en {temporal}\n", flush=True)
    try:
        destino = temporal / RAIZ.name
        shutil.copytree(RAIZ, destino,
                        ignore=shutil.ignore_patterns(*SIN_COPIAR),
                        symlinks=True)
        adentro = subprocess.run(
            [sys.executable,
             str(destino / "tool" / "checks" / "probar_reglas.py"),
             EN_COPIA, *argumentos],
            env={**os.environ, ORIGEN: str(RAIZ)})
        codigo = adentro.returncode
    finally:
        shutil.rmtree(temporal, ignore_errors=True)

    if huella_del_arbol(RAIZ, con_generados=True) != antes:
        print("\nprobar_reglas: FALLA\n")
        print("  el checkout COMPARTIDO cambió durante la corrida. Los sabotajes "
              "viven en una\n  copia privada, así que esto no puede venir del "
              "arnés: o alguien más lo editó,\n  o hay un camino que se escapó de "
              "la copia. Lo segundo es grave.")
        return 1
    return codigo


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
    "dependencias-declaradas-se-usan": {
        "una dependencia de desarrollo sin usar",
        "una dependencia de produccion que solo se usa en pruebas",
        "una dependencia de produccion usada solo desde integration_test",
        "un comentario que nombra el paquete no es evidencia de uso",
    },
    "subprocesos-con-entorno-saneado": {
        "sin environment, hereda todo",
        "entornoSaneado sin includeParentEnvironment false",
        "start y runSync tambien cuentan",
        "un part suma un lanzamiento a la biblioteca exceptuada",
    },
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
            # `setdefault`: una regla de cadenas puede no excluir NADA —y la
            # que mira solo core no excluye nada—, pero la neutralización tiene
            # que poder aplicarse igual. Asumir que el campo existe dejaba a la
            # regla nueva sin ese sabotaje, y la ausencia se leía como error del
            # arnés en vez de como un hueco.
            ("exclusión que traga paquetes",
             lambda r: r[rid]["alcance"].setdefault("excluir", {}).__setitem__(
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
                # **Se lee del JSON.** La primera vez quedó sin copiar acá: la
                # extra declaraba `regenerar_grafo` y el caso se montaba sin él,
                # así que `capas.py` leía el grafo commiteado, no veía el import
                # recién agregado, y el caso salía rojo por «no la importa en
                # ninguna directiva» — el mensaje de otro control. Un caso que
                # falla por la razón equivocada es un falso detectado, y el
                # `menciona` fue lo único que lo delató.
                "regenerar_grafo": extra.get("regenerar_grafo", False),
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
    #
    # El ancla se repite por diseño: `saltos` es un campo de TODO nodo derivado,
    # así que exigir unicidad sería exigir lo contrario de lo que el formato
    # garantiza. Lo que sí se prohíbe es cero — antes no: un `.replace` mudo
    # dejaba el caso probando el archivo sin tocar, y el arnés lo reportaba
    # como «la regla quedó sin efecto», acusando al control equivocado.
    c.append({
        "nombre": "grafo · grafo commiteado editado a mano",
        "archivos": {"grafo.jsonl": ancla_multiple(
            (RAIZ / "grafo.jsonl").read_text(encoding="utf-8"),
            '"saltos":0', '"saltos":9', que="un nodo del grafo derivado")},
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

    # La otra mitad de `deps-hacia-core`, simétrica a la de arriba: una
    # dependencia de DESARROLLO hacia un plugin, desde un paquete que
    # `excepciones_dev_dependencies` no declara. La regla ya leía
    # `directDependencies`; `devDependencies` viajaba por su propia clave del
    # grafo y no se miraba — la clave existía en arquitectura.json, con la
    # excepción real de `plugin_dart` documentada, y no la leía nadie. Contra
    # `orchestration`, que es a quien la prohibición de ver plugins más le
    # importa (docs/03 §2): no está en la lista de excepciones, así que esto
    # tiene que quedar rojo.
    c.append({
        "nombre": "deps-hacia-core · una dependencia de desarrollo hacia un plugin "
                  "sin excepción declarada",
        "archivos": {"packages/orchestration/pubspec.yaml":
                     "name: orchestration\ndescription: \"canario\"\npublish_to: none\n"
                     "version: 0.1.0\n\nenvironment:\n  sdk: ^3.6.0\n\n"
                     "resolution: workspace\n\ndependencies:\n  core:\n    path: ../core\n\n"
                     "dev_dependencies:\n  plugin_fake:\n    path: ../plugin_fake\n"},
        "pub_get": True,
        "menciona": "excepciones_dev_dependencies",
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
    #
    # Los dos anclajes del recorte pasan por `ancla`, que exige UNA ocurrencia
    # y dice qué buscaba. Antes eran `.index` pelados: la misma clase de
    # anclaje que estuvo roto 24 commits en el caso `Cascada([...])`, y cuyo
    # `ValueError` no decía ni qué se buscaba ni para qué.
    ci = (RAIZ / CI_REL).read_text(encoding="utf-8")
    _i = exige_unica(ci, "      - name: los checks saben fallar",
                     que="el step que se borra del workflow")
    _j = exige_unica(ci, "      - name: pruebas de core",
                     que="el step siguiente, que marca el corte")
    c.append({
        "nombre": "ci · un paso obligatorio borrado del workflow",
        "archivos": {CI_REL: ci[:_i] + ci[_j:]},
        "menciona": "ya no ejecuta",
    })
    c.append({
        "nombre": "ci · un paso obligatorio con continue-on-error",
        "archivos": {CI_REL: ancla(
            ci,
            "        run: python3 tool/checks/probar_reglas.py",
            "        run: python3 tool/checks/probar_reglas.py\n"
            "        continue-on-error: true",
            que="el step al que se le agrega continue-on-error")},
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
        c.append({
            "nombre": f"ci · un paso obligatorio {etiqueta}",
            "archivos": {CI_REL: ancla(ci, viejo, nuevo, que=etiqueta)},
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
        "archivos": {"README.md": ancla(readme, filas[0] + "\n", "",
                                        que="la fila de `grafo-derivado`")},
        "menciona": "no está en la tabla",
    })
    # `ancla_multiple`: el README nombra `tool/analisis` cinco veces, y eso es
    # correcto —es el directorio de los verificadores—. Alcanza con volver
    # muerta UNA, porque el check junta el conjunto de rutas nombradas. Lo
    # descubrió la guardia al instalarla: el `.replace(…, 1)` de antes suponía
    # unicidad sin decirlo, y nadie lo había comprobado.
    c.append({
        "nombre": "readme · una ruta del repositorio que ya no existe",
        "archivos": {"README.md": ancla_multiple(
            readme, "`tool/analisis`", "`tool/serializacion`",
            que="una de las menciones al directorio de verificadores")},
        "menciona": "no existe en el",
    })
    # La toolchain: dos formas de que el verde deje de significar lo que dice.
    # No hay fallo visible en ninguna — hay un instrumento sustituido.
    flutter_paso = ("      - name: flutter\n"
                    "        uses: subosito/flutter-action@"
                    "1a449444c387b1966244ae4d4f8c696479add0b2 # v2\n"
                    "        with:\n          flutter-version: 3.44.0")
    _analyze = "      - name: analyze\n        run: dart analyze --fatal-infos"
    c.append({
        "nombre": "ci · dos toolchains de Dart en el mismo job",
        "archivos": {CI_REL: ancla(
            ci, _analyze, flutter_paso + "\n\n" + _analyze,
            que="el step de analyze, antes del cual se inyecta Flutter")},
        "menciona": "instala Dart Y Flutter",
    })
    # Antes esta ancla estaba protegida DE REBOTE, porque `flutter_paso` la
    # contiene como substring. Era indirecto y no obvio releyendo el caso: si
    # `flutter_paso` cambiaba de formato sin cambiar la versión, la protección
    # se perdía sin que nada lo anunciara. Ahora tiene la suya.
    _version = "          flutter-version: 3.44.0"
    c.append({
        "nombre": "ci · Flutter en un canal flotante como compuerta",
        "archivos": {CI_REL: ancla(ci, _version, "          channel: stable",
                                   que="la versión fijada de Flutter")},
        "menciona": "no es una versión exacta",
    })
    # El control negativo de la exención de canario se retiró CON la exención.
    # Existía para probar que «flotante prohibido salvo en canario» no era
    # «prohibido siempre» — y hoy es prohibido siempre, a propósito: no existe
    # ningún canario de Flutter, y la exención estaba escrita para un caso
    # hipotético. Un control negativo que defiende una exención que ya no está
    # es peor que no tenerlo: la haría parecer viva.
    #
    # El segundo anclaje de este caso —el job del fixture— no tenía ninguna
    # guardia, ni directa ni indirecta: si ese nombre de job o esa línea de
    # `runs-on` cambiaban, el `.replace` no aplicaba y el caso quedaba probando
    # el archivo sin tocar. Silencioso, no un crash, que es el modo de fallo
    # peor de los dos.
    _job_fixture = ("    name: el fixture se verifica a sí mismo\n"
                    "    runs-on: ubuntu-latest")
    c.append({
        "nombre": "ci · Flutter flotante tampoco vale con pinta de canario",
        "archivos": {CI_REL: ancla(
            ancla(ci, _version, "          flutter-version: stable",
                  que="la versión de Flutter, vuelta flotante"),
            _job_fixture,
            _job_fixture + "\n    continue-on-error: ${{ matrix.canario }}",
            que="el job del fixture, al que se le da pinta de canario")},
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

    # Las tres formas de que la cantidad de puertos deje de significar lo que
    # dice. El check anterior derivaba UNA frase, así que el README podía
    # afirmar el inventario con otras palabras y envejecer sin ruido: tenía
    # tres afirmaciones y la derivación cubría una. Lo encontró un review, que
    # es la tercera vez que una cantidad en prosa se va sola.
    #
    # Los anclajes salen del README, no de una constante: cablear el número
    # hace que el caso deje de sabotear nada el día que la cantidad cambie, y
    # un sabotaje que no sabotea es un caso que pasa por no hacer nada.
    m_faltan = re.search(
        r"(\d+)(\s+de\s+los\s+)(\d+)(\s+puertos\s+siguen\s+sin\s+implementación)",
        readme)
    assert m_faltan, "no encontré la cantidad de puertos pendientes en el README"
    c.append({
        "nombre": "readme · la cantidad de puertos pendientes envejeció",
        "archivos": {"README.md": readme.replace(
            m_faltan.group(0),
            f"{int(m_faltan.group(1)) - 2}{m_faltan.group(2)}"
            f"{m_faltan.group(3)}{m_faltan.group(4)}", 1)},
        "menciona": "el registro declara",
    })

    m_hay = re.search(
        r"(\d+\s+de\s+los\s+)(\d+)(\s+puertos\s+ya\s+tienen\s+implementación\s+viva)",
        readme)
    assert m_hay, "no encontré la cantidad de puertos implementados en el README"
    # Escrita con letra: la cifra sigue estando y sigue siendo correcta HOY,
    # pero en una forma que nada deriva. Es exactamente cómo envejeció —
    # «cuatro de los veintitrés»— y por qué ningún check lo vio.
    c.append({
        "nombre": "readme · la cantidad de puertos, en una forma que nada deriva",
        "archivos": {"README.md": readme.replace(
            m_hay.group(0),
            f"{m_hay.group(1)}veinticuatro{m_hay.group(3)}", 1)},
        "menciona": "nada la deriva",
    })
    # Y el caso ciego de la derivación: que la frase derivada desaparezca. Un
    # patrón que no encuentra nada no comprueba nada, y se lee igual que uno
    # que comprobó y salió bien.
    c.append({
        "nombre": "readme · la frase derivada desaparece y nadie la extraña",
        "archivos": {"README.md": readme.replace(
            m_hay.group(0), "algunos puertos ya tienen implementación viva", 1)},
        "menciona": "ya no afirma",
    })

    # La cuarta cifra que el README afirma sobre sí mismo. Las tres anteriores
    # envejecieron solas; esta se deriva de `verify.dart`, y su sabotaje ataca
    # los DOS lados: que mienta la prosa, y que cambie la fuente sin que la
    # prosa se entere. Un solo caso probaría medio control.
    m_min = re.search(r"un default de \*\*(\d+) minutos\*\*", readme)
    assert m_min, "no encontré el presupuesto por paso en el README"
    c.append({
        "nombre": "readme · el presupuesto por paso, dicho de más",
        "archivos": {"README.md": readme.replace(
            m_min.group(0),
            m_min.group(0).replace(m_min.group(1),
                                   str(int(m_min.group(1)) + 4)), 1)},
        "menciona": "el presupuesto por paso da",
    })
    # La propagación por paso, que el sabotaje del default no cubría: un review
    # cambió UN paso a `presupuesto * 2` y el check quedó verde.
    #
    # **El cierre se busca por profundidad de corchetes, no por `]);` literal
    # — la MISMA técnica que ya usa `capas.py` para este mismo literal, y por
    # la misma razón.** `Cascada` ganó el parámetro `observador`, así que la
    # llamada cierra con `], observador: obs);`, no con `]);`. Este caso
    # buscaba el literal viejo y estuvo reventando con `ValueError: substring
    # not found` desde el commit que agregó ese parámetro — sin que nadie lo
    # notara, porque este archivo no corrió ni una vez en esos 24 commits. El
    # indentado tampoco se cablea (`\s+`, no seis espacios fijos): un
    # `dart format` que cambia la indentación de `verify.dart` no tiene por
    # qué avisarle a este patrón, y capas.py aprendió esa lección aparte.
    # La propagación por paso, que el sabotaje del default no cubría: un review
    # cambió UN paso a `presupuesto * 2` y el check quedó verde.
    #
    # **Ya no hace falta localizar el literal de la lista.** Se hacía contando
    # corchetes, y eso admitía un falso verde con un `]` dentro de un
    # comentario; la derivación se mudó al analizador y el sabotaje puede
    # atacar el texto directo. `ancla_multiple` porque hay una propagación por
    # paso y alcanza con romper una.
    verify_prop = (RAIZ / "packages/cli/lib/src/verify.dart").read_text(
        encoding="utf-8")
    c.append({
        "nombre": "cascada · un paso con un presupuesto distinto del resto",
        "archivos": {"packages/cli/lib/src/verify.dart": ancla_multiple(
            verify_prop, "presupuesto: presupuesto",
            "presupuesto: presupuesto * 2",
            que="la propagación del presupuesto a un paso")},
        "menciona": "como presupuesto y no el parámetro",
    })

    verify_rel = "packages/cli/lib/src/verify.dart"
    verify = (RAIZ / verify_rel).read_text(encoding="utf-8")
    m_src = re.search(r"const Duration\(minutes: (\d+)\)", verify)
    assert m_src, "no encontré el presupuesto en verify.dart"
    c.append({
        "nombre": "cascada · el presupuesto cambia y la prosa no se entera",
        "archivos": {verify_rel: verify.replace(
            m_src.group(0),
            m_src.group(0).replace(m_src.group(1),
                                   str(int(m_src.group(1)) + 4)), 1)},
        "menciona": "el presupuesto por paso da",
    })

    # El nombre viejo sobrevivió dentro de un bloque de código, colgando de
    # `tool/` y sin ser una ruta completa: no había ruta que verificar.
    #
    # Era frágil y silenciosa: si el árbol de ejemplo del README dejaba de tener
    # una línea `  analisis/` con esa indentación exacta, el `.replace` no
    # aplicaba y el caso no saboteaba nada, sin avisar. Ahora el ancla lo dice.
    c.append({
        "nombre": "readme · un nombre retirado, sin forma de ruta",
        "archivos": {"README.md": ancla(readme, "  analisis/", "  serializacion/",
                                        que="el árbol de estructura del README")},
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

    # La canónica de `opacidad-declarada` es una clase CONCRETA con un campo,
    # así que nunca ejerce la rama de las clases SELLADAS: `d.abstractKeyword`
    # queda `null` para una `sealed class`, y antes del arreglo eso la exímía
    # igual que a una interfaz de puerto sin datos propios que perder. Dos
    # clases de core —`StepOutcome` y `VerificationOutcome`— sobrevivían así:
    # ni serializaban ni estaban declaradas opacas. Sin este caso, la
    # distinción entre "abstracta" y "sellada" se puede deshacer en
    # `check.dart` sin que nada falle — se verificó a mano revirtiéndola.
    c.append({
        "nombre": "opacidad-declarada · clase sellada sin campos, sin serializar, "
                  "sin declarar opaca",
        "archivos": {"packages/core/lib/src/_canario_sellado.dart":
                     "sealed class CanarioSellado {\n"
                     "  const CanarioSellado();\n"
                     "}\n"},
        # **El `menciona` es lo que salva a este caso, no el código de salida.**
        # Una clase sellada sin miembros se lee además como un PUERTO, así que
        # este canario dispara de rebote la regla de puertos sin implementación.
        # Con el arreglo de selladas revertido, el verificador SIGUE saliendo
        # con error —por esa otra regla— y un caso que solo mirara el código de
        # salida daría falsa protección: parecería cuidar algo que dejó de
        # cuidar. Lo que desaparece al revertir es este texto, y por eso la
        # atribución se sostiene. Medido las dos veces, con y sin el arreglo.
        "menciona": "base de una jerarquía sellada",
    })

    # **El enmascaramiento, que ningún sabotaje cubría.** El arnés inyecta un
    # defecto por vez, así que la combinación donde uno tapa a otro no se
    # ejercitaba nunca. Y pasaba: `_check_readme` encadenaba seis `return`, y un
    # fallo cualquiera apagaba en silencio a los que venían después.
    #
    # Dos defectos independientes —uno en la PRIMERA sección y otro en la
    # ÚLTIMA— y se exige que aparezcan los dos. Con las secciones encadenadas,
    # el segundo desaparecía del informe mientras el código de salida seguía en
    # 1: no un falso verde, pero sí un problema escondido detrás de otro.
    #
    # **La versión anterior de este caso rompía la forma del presupuesto con un
    # espacio de más, y dejó de sabotear** cuando la derivación se mudó al árbol
    # sintáctico, donde los espacios no significan nada. Reapuntado a un defecto
    # que la primera sección sí ve.
    c.append({
        "nombre": "capas · un fallo no puede apagar a los que vienen después",
        "archivos": {
            "README.md": ancla_multiple(
                ancla(readme, filas[0] + "\n", "",
                      que="la fila de la tabla, que rompe la PRIMERA sección"),
                "  analisis/", "  serializacion/",
                que="el nombre retirado, que solo ve la ÚLTIMA sección"),
        },
        "menciona": ["no está en la tabla", "nombre retirado"],
    })

    # **Y que un control que revienta se reporte, en vez de llevarse a los
    # demás.** `check_meta` corría diez controles adentro de una sola llamada,
    # así que una excepción en el segundo dejaba sin ejecutar al de CI y al del
    # README: el resultado quedaba rojo y los defectos aparecían de a uno por
    # corrida. Lo encontró una revisión, con este mismo sabotaje — un campo del
    # registro con la forma estructural equivocada.
    #
    # **Hacen falta DOS defectos, y la primera versión de este caso tenía uno.**
    # Pedía que el diagnóstico dijera «la comprobación se rompió» y que
    # apareciera «cadenas acotadas a su adapter» — pero eso último es el nombre
    # de un paso que está FUERA del grupo que el sabotaje fusiona, así que
    # seguía apareciendo con los controles otra vez juntos y el caso pasaba.
    # Probaba menos de lo que decía probar, que es el defecto que este archivo
    # existe para no tener.
    #
    # Ahora el segundo defecto lo ve un control POSTERIOR al que revienta: si el
    # grupo se vuelve a fusionar, la excepción lo deja sin ejecutar y su
    # diagnóstico desaparece.
    c.append({
        "nombre": "capas · un control que revienta no apaga a los que siguen",
        "archivos": {
            ARQ_REL: arq_con(
                lambda r: r["lenguaje-en-plugin-dart"]["alcance"].update(
                    no_cuenta="esto no es una lista")),
            "README.md": ancla_multiple(
                readme, "  analisis/", "  serializacion/",
                que="el nombre retirado, que ve un control POSTERIOR"),
        },
        "regenerar_huella": True,
        "menciona": ["la comprobación se rompió", "nombre retirado"],
    })

    # **Las formas de elemento que la derivación no sabe contar.**
    #
    # `whereType<Expression>()` descartaba en silencio los `CollectionElement`
    # que no son expresiones. Una revisión lo reprodujo metiendo los pasos por
    # un spread: la cascada corría dos, el README declaraba uno, y el
    # verificador salía con cero. Las tres formas tienen su caso porque las tres
    # pueden aportar cualquier cantidad de pasos, y ninguna se puede contar sin
    # resolver — así que la derivación tiene que fallar cerrada, no saltearlas.
    _abre = "  return Cascada([\n    PasoDeFormato("
    _paso_extra = ("PasoDeFormato(\n        ejecutor: ejecutor, "
                   "directorio: directorio, presupuesto: presupuesto)")
    for _forma, _inyectado in (
        ("un spread", "    ...const [],\n"),
        ("un `if`", f"    if (false) {_paso_extra},\n"),
        ("un `for`", f"    for (final _ in const <int>[]) {_paso_extra},\n"),
    ):
        c.append({
            "nombre": f"cascada · la lista de pasos con {_forma}",
            "archivos": {verify_rel: ancla(
                verify, _abre,
                "  return Cascada([\n" + _inyectado + "    PasoDeFormato(",
                que=f"la apertura de la lista de pasos, donde entra {_forma}")},
            "menciona": "no sabe contar",
        })

    # Y que la cascada que se lee sea **la retornada**, no la primera que
    # aparezca. Reproducido: una rama condicional antes del `return` construye
    # una cascada de un paso, la retornada sigue teniendo dos, y todo queda
    # verde. Una llamada auxiliar o un closure pueden volverse la fuente
    # documental por accidente.
    c.append({
        "nombre": "cascada · una cascada auxiliar antes de la retornada",
        "archivos": {verify_rel: ancla(
            verify, "  return Cascada([",
            "  if (presupuesto.inMinutes == 0) {\n"
            "    return Cascada([\n"
            "      " + _paso_extra.replace("\n        ", "\n          ") + ",\n"
            "    ], observador: obs);\n"
            "  }\n"
            "  return Cascada([",
            que="el `return` de cascadaPorDefecto, antes del cual se inyecta otra")},
        "menciona": "hace falta uno solo",
    })

    # **Acá vivía el caso del ancla perdida, y se fue con su sujeto.** Protegía
    # un `.index("Cascada([")` que ya no existe: la derivación se mudó al árbol
    # sintáctico, donde un tipo explícito en el literal no cambia nada. Un caso
    # que no puede sabotear nada es peor que ninguno — se lee como protección.

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


# **Acá vivía `estado_git`, y se fue con su motivo.** Detectaba residuo
# preguntándole a `git status`, lo que traía dos límites: solo veía lo
# versionado —un canario en un directorio ignorado no aparecía— y necesitaba un
# `.git`, que la copia privada no tiene. `huella_del_arbol` compara contenido.


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
    menciona = caso.get("menciona")
    if espera_falla and menciona:
        # **Puede ser una lista, y ahí se exigen TODAS.** Un caso que inyecta
        # dos defectos para probar que los dos se reportan no se puede evaluar
        # con una sola cadena: bastaría que apareciera uno.
        faltan = [m for m in ([menciona] if isinstance(menciona, str) else menciona)
                  if m not in salida]
        if faltan:
            return ("falló, pero no por esto — no menciona "
                    + ", ".join(f"«{m}»" for m in faltan) + ".")
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


def cifra_de_sabotajes(lista: list[dict]) -> str | None:
    """La cantidad que el README afirma, contra la que hay de verdad.

    El README lleva la cuenta en prosa y nada la derivaba. Es la misma clase de
    cifra que ya envejeció tres veces del lado de los puertos, y esta encima la
    escribe el arnés al terminar: tenerla escrita a mano al lado de una que se
    calcula es pedir que se separen.

    Se cuentan solo los que ESPERAN FALLA, que es lo mismo que cuenta el
    resumen: los controles negativos —los que esperan verde— prueban que una
    regla no se pasó de larga, y llamarlos sabotajes inflaría el número con
    casos que no sabotean nada.

    **Este check no está atado al trinquete, y es a propósito.** Ponerlo en
    `capas.py` lo haría sabotéable, pero obligaría a `capas.py` a importar este
    archivo y a construir la lista de casos con el árbol ya mutado: cualquier
    sabotaje que tocara el README rompería la construcción, y el caso quedaría
    «detectado» por un motivo que no es el suyo. Un caso que pasa por la razón
    equivocada es peor que uno que falta.
    """
    esperados = sum(1 for c in lista if c.get("espera", "falla") == "falla")
    texto = (RAIZ / "README.md").read_text(encoding="utf-8")
    dichos = re.findall(r"\*\*El arnés aplica (\d+) sabotajes\.\*\*", texto)
    if len(dichos) != 1:
        return (f"el README tiene {len(dichos)} veces la frase que declara "
                f"cuántos sabotajes aplica el arnés, y tiene que tener una. "
                f"Cero es una cifra que nadie deriva; más de una son dos "
                f"cifras que se pueden separar.")
    if int(dichos[0]) != esperados:
        return (f"el README dice que el arnés aplica {dichos[0]} sabotajes y "
                f"son {esperados}.")
    return None


def main() -> int:
    global ORDENES
    for s in (signal.SIGINT, signal.SIGTERM):
        signal.signal(s, _al_recibir_senal)
    # **`--recuperar` opera sobre el árbol donde se lo invoca, no sobre una
    # copia.** Existe para deshacer lo que dejó una corrida vieja —de antes de
    # que los sabotajes vivieran en una copia—, y `probar_recuperacion.py` lo
    # ejercita sobre el árbol real. Mandarlo a una copia lo volvería un no-op
    # silencioso.
    if recuperar(reparar="--recuperar" in sys.argv):
        return 1
    if "--recuperar" in sys.argv:
        return 0

    # Y si todavía no estamos adentro de la copia, se hace y nos rehacemos ahí.
    if EN_COPIA not in sys.argv:
        return en_copia_privada([a for a in sys.argv[1:] if a != EN_COPIA])

    # **Y acá se NIEGA a sabotear el original.**
    #
    # Una revisión pidió una prueba que demostrara que el árbol compartido no
    # cambia. La huella que compara `en_copia_privada` antes y después ya lo mide
    # en cada corrida, pero tiene un hueco: si alguien saca el desvío a la copia,
    # la comprobación se va con él y nada queda mirando.
    #
    # Una negativa cierra eso mejor que una prueba. El proceso externo dice de
    # dónde salió la copia; si esa variable no está, o si apunta al árbol donde
    # estamos parados, este proceso no sabotea nada. Sacar el desvío no deja al
    # arnés escribiendo sobre el checkout compartido: lo deja **rojo**.
    origen = os.environ.get(ORIGEN)
    if origen is None or Path(origen).resolve() == RAIZ:
        print("Me niego a sabotear este árbol.\n")
        print(f"  Los sabotajes viven en una copia privada, y «{ORIGEN}» "
              f"{'no está puesta' if origen is None else 'apunta acá mismo'}.\n"
              f"  Si el desvío a la copia se sacó, esto es exactamente lo que "
              f"tenía que pasar:\n  el arnés no escribe sobre el checkout "
              f"compartido ni cuando se lo rompen.")
        return 1

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

    # La huella sostiene la afirmación de que el árbol no cambió, así que se
    # comprueba a sí misma antes de que nadie se apoye en ella.
    ambiguas = huella_ambigua()
    if ambiguas:
        print("La huella del árbol no distingue lo que dice distinguir:\n")
        for a in ambiguas:
            print(f"  {a}")
        return 1

    # **Residuo por CONTENIDO, no por `git status`.** La copia no tiene `.git`,
    # y además preguntarle a git solo veía lo versionado: un canario sintético
    # en un directorio ignorado no aparecía.
    huella_antes = huella_del_arbol(RAIZ, con_generados=False)
    print("  árbol limpio\n")

    problemas: list[str] = []
    lista = casos()
    desfasada = cifra_de_sabotajes(lista)
    if desfasada:
        print(f"La cuenta de sabotajes no cuadra: {desfasada}")
        return 1
    for caso in lista:
        previo = aplicar(caso["archivos"])
        try:
            if caso.get("regenerar_huella"):
                anotar(previo, HUELLA_REL)
                subprocess.run([sys.executable, str(CHECK), "--huella"], capture_output=True)
            if caso.get("pub_get"):
                pub_get()
            if caso.get("regenerar_grafo"):
                # Mismo motivo que la huella: sin esto, `capas.py` leería el
                # grafo COMMITEADO y no vería el import que el sabotaje acaba de
                # agregar — el caso saldría rojo por «no la importa en ninguna
                # directiva», que es el mensaje de OTRO control. Un caso que
                # falla por la razón equivocada es un falso detectado.
                #
                # **Va DESPUÉS de `pub get`, y el orden importa.** El grafo
                # resuelve `package:x/` con la configuración que escribe pub;
                # regenerarlo antes dejaba el import sin resolver y el caso salía
                # rojo por el mensaje equivocado. Se vio así la primera vez.
                anotar(previo, "grafo.jsonl")
                subprocess.run(["dart", "run", "bin/grafo.dart", "--escribir"],
                               cwd=ANALISIS, capture_output=True)
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
    if huella_del_arbol(RAIZ, con_generados=False) != huella_antes:
        problemas.append(
            "los sabotajes dejaron residuo: el contenido del árbol no volvió a "
            "ser el de antes.\n      Alguno no restauró lo que tocó, y el "
            "siguiente corrió sobre un árbol que no era el que dice.")

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
