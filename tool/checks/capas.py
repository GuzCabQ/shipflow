#!/usr/bin/env python3
"""La regla de capas, convertida en check.

Corre desde el commit 0 sobre paquetes vacíos, que es el único momento en que
instalar reglas de frontera cuesta cero: sobre veinte mil líneas producirían
miles de violaciones y terminarían desactivadas.

    python3 tool/checks/capas.py

Sale 1 si algo falla. No modifica archivos. Las reglas viven en
arquitectura.json, cada una con su `id`, su `alcance` y su violación canónica.

PRECONDICIÓN: `dart pub get` tiene que haber corrido. El grafo de dependencias
no se parsea a mano — se le pide a pub, que es quien lo resuelve. Si no está
disponible, este check FALLA: no mirar no es lo mismo que no encontrar nada.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
PAQUETES = RAIZ / "packages"
ARQ = RAIZ / "arquitectura.json"
REGLAS = json.loads(ARQ.read_text(encoding="utf-8"))["reglas"]
HUELLA = Path(__file__).parent / "arquitectura.huella"

# Las reglas que arquitectura.json DEBE seguir declarando, con los campos sin
# los cuales no se pueden aplicar.
OBLIGATORIAS = {
    "deps-hacia-core": ("enunciado", "origen", "tipo", "alcance", "permitidas"),
    "nucleo-sin-externas": ("enunciado", "origen", "tipo", "alcance", "paquetes",
                            "origenes_permitidos"),
    "agente-en-agents": ("enunciado", "origen", "tipo", "alternativa", "alcance",
                         "cadenas", "solo_en"),
    "lenguaje-en-plugin-dart": ("enunciado", "origen", "tipo", "alternativa", "alcance",
                                "cadenas", "solo_en"),
    "sin-api-de-modelo": ("enunciado", "origen", "tipo", "alternativa", "alcance",
                          "cadenas"),
}

# El `tipo` decide qué función aplica la regla. Cambiarlo la saltea sin borrarla.
TIPOS = {
    "deps-hacia-core": "flechas_internas",
    "nucleo-sin-externas": "origen_de_dependencias",
    "agente-en-agents": "cadenas_acotadas",
    "lenguaje-en-plugin-dart": "cadenas_acotadas",
    "sin-api-de-modelo": "cadenas_acotadas",
}

# Valores que NO derivan: vienen de un ADR o de docs/03 y cambiarlos es cambiar
# la arquitectura. La violación canónica prueba que el instrumento dispara; esto
# prueba que la política no se reescribió. Son modos de fallo distintos: ensanchar
# `solo_en` deja el canario disparando y desprotege todo lo demás.
EXT = [".dart", ".yaml", ".yml", ".json", ".sh", ".bash", ".md"]
VALORES_FIJOS = {
    "agente-en-agents": {"solo_en": ["agents", "cli"]},          # ADR-009
    "lenguaje-en-plugin-dart": {"solo_en": ["plugin_dart", "cli"]},  # docs/03 §2
    "sin-api-de-modelo": {"solo_en": []},                        # ADR-009: ninguno
    "nucleo-sin-externas": {"paquetes": ["core"], "origenes_permitidos": ["root"]},
    # El mapa de flechas ES la arquitectura de docs/03 §1.
    "deps-hacia-core": {"permitidas": {
        "core": [], "orchestration": ["core"], "vcs": ["core"], "rules": ["core"],
        "agents": ["core"], "plugin_dart": ["core"], "plugin_fake": ["core"],
        "cli": ["core", "orchestration", "vcs", "rules", "agents", "plugin_dart",
                "plugin_fake"]}},
}
# El alcance de las reglas de cadenas no deriva: vaciarlo las neutraliza sin
# tocar ningun otro campo.
VALORES_FIJOS_ALCANCE = {rid: {"extensiones": EXT}
                         for rid in ("agente-en-agents", "lenguaje-en-plugin-dart",
                                     "sin-api-de-modelo")}

# `no_cuenta` exime un TOKEN dentro de un contexto, y es el campo más peligroso
# del registro: una entrada de más neutraliza la regla sin vaciar nada. Por eso
# está fijado en dos sentidos — qué regla puede tenerlo, y con qué regexes
# exactos. Una regla que no figure acá y lo declare, falla.
# El MECANISMO de ceguera de cada regla, fijado. Es el campo que más
# fácilmente se vuelve inofensivo: basta cambiar `como` por algo que no ciegue
# nada para que el caso pase siempre y no pruebe nada. Igual que `tipo`.
# Los COMANDOS que CI tiene que ejecutar. Es política pura: no deriva de nada,
# y por eso está acá y no en el workflow, que es justamente lo que se vigila.
#
# Nada verificaba esto. `_check_delegadas` comprueba que CI invoque a los
# APLICADORES DELEGADOS —porque una regla lo declara—, pero `capas.py`,
# `probar_reglas.py`, los tests, el analizador y el formateo no los declaraba
# nadie: borrar cualquiera de esos pasos del workflow no lo notaba nada, y
# desde que CI bloquea merges eso es la compuerta abriéndose sola.
#
# Es F33 aplicado al ejecutor: registrado en ningún lado y ejecutado igual, o
# —peor— dejado de ejecutar sin que nadie se entere.
PASOS_OBLIGATORIOS = {
    # etiqueta: (comando EXACTO, working-directory esperado)
    "el parser de yaml": ('python3 -m pip install --quiet "pyyaml==6.0.3"', None),
    "la regla de capas": ("python3 tool/checks/capas.py", None),
    "que los checks sepan fallar": ("python3 tool/checks/probar_reglas.py", None),
    "serialización, opacidad y puertos": ("dart run bin/check.dart", "tool/analisis"),
    "el grafo interno": ("dart run bin/grafo.dart", "tool/analisis"),
    "las pruebas de core": ("dart test packages/core", None),
    "el analizador estático": ("dart analyze --fatal-infos", None),
    "el formato": ("dart format --set-exit-if-changed .", None),
}

# El job puede declararse `continue-on-error` SOLO con esta expresión, que es
# el canario de la matriz: la pata `stable` avisa y no bloquea, por ADR-013.
# Un `true` pelado convertiría el job entero en decorativo.
CANARIO_DECLARADO = "${{ matrix.canario }}"

CIEGO_FIJO = {
    "deps-hacia-core": "grafo_indisponible",
    "nucleo-sin-externas": "grafo_indisponible",
    "agente-en-agents": "alcance_inexistente",
    "lenguaje-en-plugin-dart": "alcance_inexistente",
    "sin-api-de-modelo": "alcance_inexistente",
    "serializacion-sin-perdida": "archivo_ilegible",
    "opacidad-declarada": "archivo_ilegible",
    "puertos-sin-implementacion": "archivo_ilegible",
    "grafo-derivado": "archivo_ilegible",
    "colecciones-inmutables": "archivo_ilegible",
}

NO_CUENTA_FIJO = {
    "lenguaje-en-plugin-dart": [
        (r"^\s*(?:import|export|part)\b", r"""\.dart(?=['"])"""),
        (r"^\s*(?:import|export|part)\b",
         r"""(?<=['"])dart(?=:(?:async|collection|convert|core|math|typed_data)\b)"""),
    ],
}

fallos: list[str] = []


def paquetes() -> list[str]:
    return sorted(p.name for p in PAQUETES.iterdir() if (p / "pubspec.yaml").exists())


def grafo() -> tuple[dict[str, dict], str]:
    """El grafo resuelto, tal como lo reporta pub. Se deriva, no se mantiene."""
    try:
        r = subprocess.run(["dart", "pub", "deps", "--json"],
                           cwd=RAIZ, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.TimeoutExpired) as e:
        fallos.append(f"no se pudo ejecutar `dart pub deps --json`: {e}")
        return {}, ""
    if r.returncode != 0:
        detalle = (r.stderr or r.stdout).strip().splitlines()
        fallos.append("`dart pub deps --json` falló. Corré `dart pub get` primero.\n      "
                      + (detalle[-1] if detalle else "sin detalle"))
        return {}, ""
    try:
        d = json.loads(r.stdout)
        return {p["name"]: p for p in d.get("packages", [])}, d.get("root", "")
    except json.JSONDecodeError as e:
        fallos.append(f"`dart pub deps --json` no devolvió JSON válido: {e}")
        return {}, ""


# --- meta · el registro sigue siendo aplicable --------------------------

def check_meta() -> None:
    existentes = paquetes()
    for rid, campos in OBLIGATORIAS.items():
        regla = REGLAS.get(rid)
        if regla is None:
            fallos.append(f"arquitectura.json: falta la regla «{rid}». "
                          f"Un control que desaparece sin ruido es F33.")
            continue
        for campo in campos:
            if campo not in regla:
                fallos.append(f"arquitectura.json: «{rid}» no declara «{campo}»")
            elif not regla[campo] and campo not in ("solo_en",):
                fallos.append(f"arquitectura.json: «{rid}» tiene «{campo}» vacío")
        if regla.get("tipo") != TIPOS[rid]:
            fallos.append(f"arquitectura.json: «{rid}» tiene tipo «{regla.get('tipo')}»; "
                          f"se esperaba «{TIPOS[rid]}». Cambiarlo la saltea sin borrarla.")
        if not regla.get("violacion_canonica"):
            fallos.append(f"arquitectura.json: «{rid}» no declara violación canónica. "
                          f"Una regla que no puede ponerse roja no está probada.")
    for rid, fijos in VALORES_FIJOS.items():
        for campo, esperado in fijos.items():
            actual = REGLAS.get(rid, {}).get(campo)
            if actual != esperado:
                fallos.append(f"arquitectura.json: «{rid}.{campo}» = {actual}; "
                              f"el valor fijado es {esperado}. Viene de {REGLAS.get(rid, {}).get('origen', '?')}.")
    for rid, fijos in VALORES_FIJOS_ALCANCE.items():
        for campo, esperado in fijos.items():
            actual = REGLAS.get(rid, {}).get("alcance", {}).get(campo)
            if actual != esperado:
                fallos.append(f"arquitectura.json: «{rid}.alcance.{campo}» = {actual}; "
                              f"el valor fijado es {esperado}. Vaciarlo neutraliza la regla.")
    for rid, regla in REGLAS.items():
        alcance = regla.get("alcance")
        if not isinstance(alcance, dict):
            continue
        for nombre, grupo in alcance.get("excluir", {}).items():
            if not isinstance(grupo, dict):
                continue
            invasores = sorted(set(grupo["que"]).intersection(existentes))
            if invasores:
                fallos.append(f"arquitectura.json: la exclusión «{rid}.{nombre}» nombra "
                              f"paquetes enteros {invasores}. Una exclusión acota QUÉ ARCHIVOS "
                              f"se miran, no exime paquetes: para eso está `solo_en`.")
    _check_no_cuenta()
    _check_casos_ciegos()
    _check_ci_ejecuta()
    _check_readme()
    _check_huella()
    _check_delegadas()
    for rid, regla in REGLAS.items():
        for pkg in list(regla.get("solo_en", [])) + list(regla.get("paquetes", [])):
            if pkg not in existentes:
                fallos.append(f"arquitectura.json: «{rid}» nombra «{pkg}», que no existe")


def _check_readme() -> None:
    """La tabla de reglas del README se DERIVA del registro, no se mantiene.

    Un review encontró que la tabla documentaba ocho reglas cuando había nueve,
    seguía nombrando un directorio renombrado, y presentaba como pendiente algo
    ya construido. Nada lo detectaba: `cifras.py` deriva cantidades, pero vive
    en el otro repositorio y mira otro corpus.

    Una tabla de reglas desactualizada es peor que no tenerla: dice qué
    gobierna el repositorio, y quien la lea va a creerle.
    """
    doc = RAIZ / "README.md"
    if not doc.exists():
        fallos.append("falta README.md, que es donde se declara qué gobierna "
                      "este repositorio.")
        return
    texto = doc.read_text(encoding="utf-8")
    filas = dict(re.findall(r"^\| `([a-z][a-z-]+)` \|.*\| `([^`]+)` \|$",
                            texto, re.M))
    if not filas:
        fallos.append("no encontré la tabla de reglas en README.md. Cero filas "
                      "se lee igual que una tabla al día.")
        return
    for rid in sorted(set(REGLAS) - set(filas)):
        fallos.append(f"README.md: la regla «{rid}» gobierna este repositorio y "
                      f"no está en la tabla. Quien lea el README no se entera "
                      f"de que existe.")
    for rid in sorted(set(filas) - set(REGLAS)):
        fallos.append(f"README.md: la tabla declara «{rid}», que ya no está en "
                      f"arquitectura.json. Una fila vieja describe un control "
                      f"que no corre.")
    for rid, aplicador in sorted(filas.items()):
        esperado = REGLAS.get(rid, {}).get("aplicada_por", "capas.py")
        if aplicador != esperado:
            fallos.append(f"README.md: dice que «{rid}» la aplica «{aplicador}»; "
                          f"el registro dice «{esperado}».")
    # Rutas del repositorio nombradas en el README que ya no existen. Es lo que
    # dejó vivo el nombre `tool/serializacion` después de renombrarlo.
    for ruta in sorted(set(re.findall(r"`((?:tool|packages)/[A-Za-z0-9_./-]+)`", texto))):
        if not (RAIZ / ruta.rstrip("/")).exists():
            fallos.append(f"README.md nombra «{ruta}», que no existe en el "
                          f"árbol. Una ruta muerta en la documentación manda a "
                          f"quien la siga a un lugar que no está.")


def _check_ci_ejecuta() -> None:
    """CI sigue invocando cada paso obligatorio, y ninguno está neutralizado.

    Un paso borrado del workflow no lo detectaba nada. Desde que las ramas
    están protegidas y el merge depende de este workflow, borrar un paso es
    abrir la compuerta sin tocar ninguna regla.

    NO SE PARSEA A MANO. El workflow se le pide a un parser de YAML, por la
    misma razón por la que el grafo de dependencias se le pide a pub: un
    parser casero devuelve cero pasos ante una sintaxis que no reconoce, y
    cero pasos se lee igual que «están todos». Si el parser no está
    disponible, esto FALLA — no mirar no es lo mismo que no encontrar nada.
    """
    ci = RAIZ / ".github" / "workflows" / "checks.yml"
    if not ci.exists():
        fallos.append("falta .github/workflows/checks.yml. Sin workflow no hay "
                      "compuerta, y las ramas protegidas exigen un check que "
                      "nadie produce.")
        return
    try:
        import yaml
    except ImportError:
        fallos.append("no pude importar `yaml` para leer el workflow. Sin parser "
                      "no puedo saber qué pasos corren, y suponer que corren "
                      "todos es exactamente el falso verde que este check evita. "
                      "Instalalo: `pip install pyyaml`.")
        return
    try:
        doc = yaml.safe_load(ci.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as e:
        fallos.append(f"no pude leer checks.yml como YAML: {e}")
        return

    pasos = []
    for nombre_job, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        coe = job.get("continue-on-error")
        if coe not in (None, False, CANARIO_DECLARADO):
            fallos.append(
                f"el job «{nombre_job}» declara `continue-on-error: {coe!r}`. "
                f"Todos sus pasos corren, se ven en rojo, y el job no falla: "
                f"la compuerta queda abierta sin tocar ni un check. La única "
                f"forma permitida es «{CANARIO_DECLARADO}», que es el canario "
                f"declarado de la matriz.")
        for paso in (job.get("steps") or []):
            if isinstance(paso, dict):
                pasos.append(paso)
    if not pasos:
        fallos.append("leí el workflow y no encontré NI UN paso. Cero pasos se "
                      "lee igual que todos los pasos presentes.")
        return
    # Comparación EXACTA, no por subcadena. Un check que solo exige que el
    # comando aparezca MENCIONADO acepta `echo "dart test"` y
    # `dart test || true`: los dos contienen el texto y ninguno gobierna el
    # resultado del job. Lo encontró un review, y es el mismo criterio que
    # `VALORES_FIJOS`: lo que no deriva, se fija.
    for etiqueta, (comando, wd) in PASOS_OBLIGATORIOS.items():
        encontrados = [p for p in pasos
                       if str(p.get("run", "")).strip() == comando
                       and p.get("working-directory") == wd]
        if not encontrados:
            parecidos = [str(p.get("run", "")).strip() for p in pasos
                         if comando.split()[-1] in str(p.get("run", ""))]
            detalle = (f"\n      hay pasos que lo MENCIONAN sin ejecutarlo así: "
                       f"{parecidos}" if parecidos else "")
            fallos.append(
                f"CI ya no ejecuta {etiqueta} exactamente como «{comando}»"
                + (f" en «{wd}»" if wd else "")
                + f". Un comando envuelto —`echo`, `|| true`, otro directorio— "
                  f"aparece en el archivo y no gobierna el resultado del job."
                + detalle)
            continue
        for p in encontrados:
            if p.get("continue-on-error") is True:
                fallos.append(
                    f"CI ejecuta {etiqueta} con `continue-on-error: true`. Corre, "
                    f"se ve en rojo, y no detiene nada — es severidad `reporta` "
                    f"disfrazada de `bloquea`. Si es deliberado, va como canario "
                    f"declarado en la matriz, no acá.")


def _check_casos_ciegos() -> None:
    """TODA regla declara cómo se la deja ciega. Sin excepción.

    Es el invariante ejecutable de ADR-011, que estuvo escrito y sin instalar:
    «para cada paso registrado existe un caso donde el paso NO PUEDE ejecutarse
    y el resultado es no concluyente, nunca verde».

    La `violacion_canonica` prueba que el check detecta un EXCESO —algo que no
    debería estar—. Nada probaba que detecte una OMISIÓN —que no pudo mirar—, y
    ese es el sesgo natural de todo verificador (corolario 5). Las dos hacen
    falta: son modos de fallo distintos y ninguno implica al otro.
    """
    for rid in sorted(set(REGLAS) | set(CIEGO_FIJO)):
        regla = REGLAS.get(rid)
        if regla is None:
            fallos.append(f"arquitectura.json: falta la regla «{rid}», que tiene "
                          f"mecanismo de ceguera fijado. Desapareció sin ruido.")
            continue
        ciego = regla.get("caso_ciego")
        if not ciego:
            fallos.append(
                f"arquitectura.json: «{rid}» no declara `caso_ciego`. Sin él, "
                f"nadie probó nunca qué hace este control cuando NO PUEDE MIRAR, "
                f"y su silencio es indistinguible de su aprobación (ADR-011 §5).")
            continue
        for campo in ("que", "como", "por_que_ciega", "debe_mencionar"):
            if not ciego.get(campo):
                fallos.append(f"arquitectura.json: el `caso_ciego` de «{rid}» no "
                              f"declara «{campo}».")
        esperado = CIEGO_FIJO.get(rid)
        if esperado is None:
            fallos.append(f"arquitectura.json: «{rid}» declara `caso_ciego` y su "
                          f"mecanismo no está fijado en capas.py. Un mecanismo sin "
                          f"fijar se puede cambiar por uno que no ciegue nada.")
        elif ciego.get("como") != esperado:
            fallos.append(f"arquitectura.json: el `caso_ciego` de «{rid}» usa "
                          f"«{ciego.get('como')}»; el mecanismo fijado es «{esperado}». "
                          f"Cambiarlo deja el caso pasando siempre.")


def _check_no_cuenta() -> None:
    """Ninguna exencion de token que no este fijada acá, y ninguna regla ajena
    que se la agregue. Vaciar un alcance se ve; agregarle una exencion no."""
    for rid, regla in REGLAS.items():
        alcance = regla.get("alcance")
        declarado = alcance.get("no_cuenta", []) if isinstance(alcance, dict) else []
        esperado = NO_CUENTA_FIJO.get(rid, [])
        actual = [(e.get("donde"), e.get("token")) for e in declarado]
        if actual != esperado:
            fallos.append(
                f"arquitectura.json: «{rid}.alcance.no_cuenta» no es el fijado.\n"
                f"      declarado: {actual}\n"
                f"      fijado:    {esperado}\n"
                f"      Una exencion de token neutraliza la regla sin vaciar ningun campo.")
        for e in declarado:
            for campo in ("que", "donde", "token", "por_que", "quien_lo_cubre"):
                if not e.get(campo):
                    fallos.append(f"arquitectura.json: una exencion de «{rid}» no declara "
                                  f"«{campo}». Una ausencia sin motivo es una ausencia silenciosa.")


def _check_delegadas() -> None:
    """Una regla que capas.py no aplica solo es legitima si declara QUIEN la
    aplica, ese aplicador existe, y CI lo invoca. Sin las tres cosas es F33:
    registrada y no ejecutada."""
    ci = RAIZ / ".github" / "workflows" / "checks.yml"
    texto = ci.read_text(encoding="utf-8") if ci.exists() else ""
    for rid in sorted(set(REGLAS) - set(OBLIGATORIAS)):
        aplicador = REGLAS[rid].get("aplicada_por")
        if not aplicador:
            fallos.append(f"arquitectura.json: «{rid}» no la aplica capas.py y no declara "
                          f"`aplicada_por`. Una regla escrita y no ejecutada es la "
                          f"enfermedad que este proyecto combate.")
            continue
        if not (RAIZ / aplicador).exists():
            fallos.append(f"arquitectura.json: «{rid}» delega en «{aplicador}», que no existe.")
        elif aplicador not in texto:
            fallos.append(f"arquitectura.json: «{rid}» delega en «{aplicador}», que CI no invoca. "
                          f"Registrada y no ejecutada es exactamente F33.")


# --- flechas internas · por NOMBRE, solo dentro del workspace -----------

def huella_actual() -> str:
    """Huella de la política completa. Mismo criterio que el grafo interno:
    se deriva del contenido y se compara contra lo commiteado."""
    canon = json.dumps(REGLAS, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()


def _check_huella() -> None:
    """Respaldo para todo lo que no está pinneado campo por campo.

    LÍMITE DECLARADO: esto vuelve imposible degradar la política en silencio,
    no vuelve imposible degradarla. Quien edite `arquitectura.json` y esta
    huella junto cambia la arquitectura de forma visible y revisable — que es
    exactamente lo que se busca. Contra eso no hay check: hay revisión.
    """
    if not HUELLA.exists():
        fallos.append("falta tool/checks/arquitectura.huella. Generala con `capas.py --huella`.")
        return
    esperada = HUELLA.read_text(encoding="utf-8").strip()
    if huella_actual() != esperada:
        fallos.append(
            "arquitectura.json cambió y su huella no.\n"
            f"      commiteada: {esperada}\n"
            f"      actual:     {huella_actual()}\n"
            "      Si el cambio es deliberado, regenerala con `capas.py --huella` "
            "y que se revise en el mismo commit.")


def check_flechas(g: dict[str, dict], raiz_ws: str) -> None:
    """Los miembros salen del grafo de pub, NO del listado de `packages/`.

    Antes se derivaban del directorio, y un miembro declarado en `workspace:`
    fuera de `packages/` quedaba sin gobierno: no aparecia en el bucle y su
    ausencia se leia igual que «no encontre nada». Es el corolario 5 de ADR-011
    aplicado al propio check.
    """
    regla = REGLAS["deps-hacia-core"]
    permitidas = regla["permitidas"]
    internos = {n for n, d in g.items() if d.get("source") == "root"} - {raiz_ws}
    for huerfano in sorted(set(paquetes()) - internos):
        fallos.append(f"packages/{huerfano}: pub no lo reporta como miembro. "
                      f"¿Falta en `workspace:`? Un paquete fuera del grafo no lo mira nadie.")
    for nombre in sorted(internos):
        if nombre not in permitidas:
            fallos.append(f"«{nombre}»: es miembro del workspace y no está en «deps-hacia-core». "
                          f"Declaralo o sacalo de `workspace:`.")
            continue
        ok = set(permitidas[nombre])
        for dep in g[nombre].get("directDependencies", []):
            if dep in internos and dep not in ok:
                fallos.append(
                    f"packages/{nombre}: depende de «{dep}», que no está permitido.\n"
                    f"      permitidas: {sorted(ok) or 'ninguna'} — {regla['enunciado']}")


# --- origen de dependencias · independiente de la anterior --------------

def check_origenes(g: dict[str, dict]) -> None:
    regla = REGLAS["nucleo-sin-externas"]
    permitidos = set(regla["origenes_permitidos"])
    for nombre in regla["paquetes"]:
        if nombre not in g:
            fallos.append(f"packages/{nombre}: pub no lo reporta en el grafo")
            continue
        # Las DOS claves. pub las reporta por separado, y mirar solo la
        # primera dejaba entrar cualquier externa por `dev_dependencies:`.
        # El enunciado dice «ninguna», no «ninguna de produccion».
        for clave in ("directDependencies", "devDependencies"):
            for dep in g[nombre].get(clave, []):
                origen = g.get(dep, {}).get("source", "desconocido")
                if origen not in permitidos:
                    que = "dependencia" if clave == "directDependencies" else "dependencia de desarrollo"
                    fallos.append(f"packages/{nombre}: {que} «{dep}» de origen «{origen}». "
                                  f"{regla['enunciado']}")


# --- cadenas acotadas a su adapter --------------------------------------

def check_cadenas() -> None:
    for rid, regla in REGLAS.items():
        if TIPOS.get(rid) == "cadenas_acotadas" and regla.get("tipo") == "cadenas_acotadas":
            _cadenas_de(rid, regla)


MIRADOS: dict[str, int] = {}


def _cadenas_de(rid: str, regla: dict) -> None:
    alcance = regla["alcance"]
    extensiones = set(alcance["extensiones"])
    permitidos = set(regla["solo_en"])
    patron = re.compile("(" + "|".join(re.escape(c) for c in regla["cadenas"]) + ")", re.I)
    excluidos = {n for grupo in alcance.get("excluir", {}).values()
                 if isinstance(grupo, dict) for n in grupo["que"]}
    # Exenciones de TOKEN: borran solo el token exento, no la línea. Así
    # `import 'paquete_vigilado/algo.dart'` sigue disparando por el nombre del
    # paquete aunque el sufijo esté exento. Borrar la línea entera sería la
    # exención tragándose lo que la regla existe para ver.
    exenciones = [(re.compile(e["donde"]), re.compile(e["token"]))
                  for e in alcance.get("no_cuenta", [])]
    raiz = RAIZ / alcance["raiz"]
    mirados = 0
    for archivo in sorted(raiz.rglob("*")):
        if not archivo.is_file() or archivo.suffix not in extensiones:
            continue
        rel = archivo.relative_to(raiz)
        if not rel.parts or rel.parts[0] in permitidos or excluidos.intersection(rel.parts):
            continue
        mirados += 1
        for n, linea in enumerate(archivo.read_text(encoding="utf-8").splitlines(), 1):
            mirada = linea
            for donde, token in exenciones:
                if donde.search(linea):
                    mirada = token.sub("", mirada)
            m = patron.search(mirada)
            if m:
                fallos.append(f"{archivo.relative_to(RAIZ)}:{n}: «{m.group(0)}» fuera de "
                              f"{sorted(permitidos) or 'todo paquete'} — {regla['enunciado']}\n"
                              f"      → {regla['alternativa']}")
    MIRADOS[rid] = mirados
    if mirados == 0:
        # ADR-011: la ausencia de evidencia es fallo, no aprobación. Cero
        # archivos inspeccionados no es «no encontré nada»: es «no miré».
        fallos.append(
            f"«{rid}»: recorrió «{alcance['raiz']}» y no inspeccionó NI UN archivo, "
            f"así que pasó sin mirar. Verde acá es indistinguible de verde sobre "
            f"un árbol limpio. Revisá `alcance.raiz` y `alcance.extensiones`.")


def _paso(nombre, fn, *args) -> None:
    antes = len(fallos)
    fn(*args)
    print(f"  {nombre:<38} {'ok' if len(fallos) == antes else f'{len(fallos) - antes} fallo(s)'}")


def main() -> int:
    if "--huella" in sys.argv:
        HUELLA.write_text(huella_actual() + "\n", encoding="utf-8")
        print(f"huella escrita: {huella_actual()}")
        return 0
    _paso("registro aplicable", check_meta)
    g, raiz_ws = grafo()
    if g:
        _paso("flechas entre paquetes internos", check_flechas, g, raiz_ws)
        _paso("núcleo sin dependencias externas", check_origenes, g)
    else:
        print(f"  {'grafo de dependencias':<38} NO DISPONIBLE")
    _paso("cadenas acotadas a su adapter", check_cadenas)

    if fallos:
        print("\ncapas: FALLA\n")
        for f in fallos:
            print(f"  {f}")
        return 1
    detalle = ", ".join(f"{k}: {v}" for k, v in sorted(MIRADOS.items()))
    print(f"\ncapas: ok — {len(paquetes())} paquetes, {len(OBLIGATORIAS)} reglas aplicadas.\n"
          f"       archivos inspeccionados por regla de cadenas → {detalle}\n"
          f"       pasos obligatorios verificados en CI → {len(PASOS_OBLIGATORIOS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
