#!/usr/bin/env python3
"""Los sabotajes de la organización del workflow, que corre `probar_reglas.py`.

Cada uno deja el archivo plausible —los comandos siguen escritos— y abre la
compuerta por otro lado: un grupo fuera de la matriz, el conjunto o la
compuerta omitidos cuando algo falla, el canario decidiendo el merge, un paso
obligatorio que solo sobrevive en el canario, una concurrencia que reemplaza
la corrida de un commit de integración. Los ve `organizacion_ci.py`, salvo
los que tocan un comando, que los ve la comparación exacta de
`PASOS_OBLIGATORIOS`.
"""
from __future__ import annotations

from _comun import ancla

_COMPUERTA_NEEDS = ("    needs: [estatico, pruebas, sabotajes, sabotajes-conjunto, "
                    "formato, nativo]\n")
_SETUP_DART = ("        uses: dart-lang/setup-dart@"
               "6afc89df92d6eb3834022f73cd65adc8cdfcb92d # v1\n"
               "        with:\n")


def casos_ci(ci: str, ci_rel: str) -> list[dict]:
    """Cada sabotaje como `probar_reglas.py` los espera."""
    casos: list[dict] = []

    def caso(nombre: str, viejo: str, nuevo: str, menciona: str) -> None:
        casos.append({"nombre": f"ci-org · {nombre}",
                      "archivos": {ci_rel: ancla(ci, viejo, nuevo, que=nombre)},
                      "menciona": menciona})

    # --- los grupos de sabotajes y su conjunto ---
    caso("un grupo de sabotajes fuera de la matriz",
         "        grupo: [1, 2, 3, 4]\n", "        grupo: [1, 2, 3]\n",
         "los grupos de sabotajes son")
    caso("un grupo de más en la matriz",
         "        grupo: [1, 2, 3, 4]\n", "        grupo: [1, 2, 3, 4, 5]\n",
         "los grupos de sabotajes son")
    caso("un grupo que termina verde sin publicar su manifiesto",
         "          if-no-files-found: error\n", "          if-no-files-found: warn\n",
         "el manifiesto del grupo no se publica")
    caso("un grupo de sabotajes que no bloquea",
         "    name: sabotajes · grupo ${{ matrix.grupo }}/4\n",
         "    name: sabotajes · grupo ${{ matrix.grupo }}/4\n"
         "    continue-on-error: true\n",
         "el bloqueante «sabotajes» declara `continue-on-error`")
    caso("el conjunto sin if: always()",
         "    needs: [sabotajes]\n    if: ${{ always() }}\n",
         "    needs: [sabotajes]\n",
         "conjunto omitido")
    caso("el conjunto sin leer en qué intento corrió cada grupo",
         '      - name: los intentos de cada grupo\n'
         '        env:\n          GH_TOKEN: ${{ github.token }}\n'
         '        run: gh api "repos/${{ github.repository }}/actions/runs/'
         '${{ github.run_id }}/jobs?filter=all&per_page=100" > '
         '"$RUNNER_TEMP/jobs.json"\n\n', "",
         "no lee en qué intento corrió cada grupo")
    inicio = ci.index("  # LOS GRUPOS, JUNTADOS.")
    fin = ci.index("  # EL FORMATO, EN SU PROPIO JOB.")
    casos.append({"nombre": "ci-org · el conjunto borrado",
                  "archivos": {ci_rel: ci[:inicio] + ci[fin:]},
                  "menciona": "falta el job «sabotajes-conjunto»"})

    # --- la compuerta ---
    caso("la compuerta sin uno de sus bloqueantes",
         _COMPUERTA_NEEDS, _COMPUERTA_NEEDS.replace(", formato", ""),
         "la compuerta espera")
    caso("la compuerta esperando al canario",
         _COMPUERTA_NEEDS, _COMPUERTA_NEEDS.replace("nativo]", "nativo, canario-sabotajes]"),
         "depende del canario")
    caso("la compuerta sin if: always()",
         _COMPUERTA_NEEDS + "    if: ${{ always() }}\n", _COMPUERTA_NEEDS,
         "compuerta omitida")
    caso("la compuerta con continue-on-error",
         _COMPUERTA_NEEDS + "    if: ${{ always() }}\n",
         _COMPUERTA_NEEDS + "    if: ${{ always() }}\n    continue-on-error: true\n",
         "la compuerta declara `continue-on-error`")
    caso("la compuerta con otro nombre",
         "    name: reglas de arquitectura · Dart 3.12.0\n", "    name: compuerta\n",
         "nombre protegido")
    caso("el nombre protegido en un job que no es la compuerta",
         "    name: análisis estático · Dart 3.12.0\n",
         "    name: reglas de arquitectura · Dart 3.12.0\n",
         "también lleva el nombre protegido")
    caso("la compuerta sin el resultado de los jobs",
         "        env:\n          NECESITA: ${{ toJSON(needs) }}\n", "",
         "no le pasa `toJSON(needs)`")
    casos.append({"nombre": "ci-org · un job que la compuerta no espera",
                  "archivos": {ci_rel: ci.rstrip("\n") + "\n\n  extra:\n"
                               "    runs-on: ubuntu-latest\n    steps:\n"
                               "      - run: echo extra\n"},
                  "menciona": "no está entre los jobs declarados"})

    # --- lo bloqueante y el canario ---
    caso("un paso obligatorio que solo sobrevive en el canario",
         "      - name: analyze\n        run: dart analyze --fatal-infos\n", "",
         "ya no ejecuta el analizador estático")
    caso("un bloqueante con el SDK del canario",
         "      # significan nada» (docs/09 §3).\n"
         "      - name: dart · SDK bloqueante\n" + _SETUP_DART + '          sdk: "3.12.0"\n',
         "      # significan nada» (docs/09 §3).\n"
         "      - name: dart · SDK bloqueante\n" + _SETUP_DART + "          sdk: stable\n",
         "el bloqueante «estatico» instala el SDK")
    caso("el canario sin un comando del camino bloqueante",
         "      - name: canario · analyze\n        run: dart analyze --fatal-infos\n", "",
         "el canario no corre «dart analyze --fatal-infos»")
    caso("el canario sin los sabotajes en secuencia",
         "      - name: canario · los checks saben fallar, en secuencia\n"
         "        run: python3 tool/checks/probar_reglas.py\n", "",
         "el canario no corre «python3 tool/checks/probar_reglas.py»")
    caso("el canario bloqueando",
         "    name: canario · sabotajes · Dart stable\n    runs-on: ubuntu-latest\n"
         "    timeout-minutes: 20\n    continue-on-error: true\n",
         "    name: canario · sabotajes · Dart stable\n    runs-on: ubuntu-latest\n"
         "    timeout-minutes: 20\n",
         "no declara `continue-on-error: true`")
    caso("el canario con el SDK bloqueante",
         "      - name: dart stable · canario de sabotajes\n" + _SETUP_DART
         + "          sdk: stable\n",
         "      - name: dart stable · canario de sabotajes\n" + _SETUP_DART
         + '          sdk: "3.12.0"\n',
         "un canario con el SDK bloqueante")

    # --- disparadores y concurrencia ---
    caso("sin validar los PR",
         "  pull_request:\n", "",
         "los disparadores del workflow son")
    caso("push en cualquier rama",
         "  push:\n    branches: [develop, production]\n", "  push:\n",
         "los disparadores del workflow son")
    caso("concurrencia agrupada por rama",
         "  group: ${{ github.workflow }}-${{ github.event_name == 'pull_request' && "
         "format('pr-{0}', github.event.pull_request.number) || "
         "format('run-{0}', github.run_id) }}\n",
         "  group: ${{ github.workflow }}-${{ github.ref }}\n",
         "la concurrencia del workflow es")
    caso("cancelar en curso también fuera de un PR",
         "  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n",
         "  cancel-in-progress: true\n",
         "la concurrencia del workflow es")
    return casos
