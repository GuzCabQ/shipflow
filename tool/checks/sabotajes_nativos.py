#!/usr/bin/env python3
"""Los sabotajes del ejecutable nativo, que corre `probar_reglas.py`.

Dos familias, y las ve un control distinto cada una. Borrar un paso nativo
o volverlo decorativo cambia un comando, y eso lo ve la comparación exacta
de `PASOS_OBLIGATORIOS`. Recortar la matriz, fijar el runner u omitir el
job deja cada comando intacto y la plataforma sin ejecutar: eso solo lo ve
`ejecucion_nativa.py`.
"""
from __future__ import annotations

from _comun import ancla


def casos_nativos(ci: str, ci_rel: str) -> list[dict]:
    """Cada sabotaje como `probar_reglas.py` los espera: nombre, archivos y
    la frase que el check tiene que mencionar."""
    casos: list[dict] = []
    nativos = (
        ("dependencias exactas del lockfile", "dart pub get --enforce-lockfile"),
        ("pruebas del CLI en la plataforma nativa", "dart test packages/cli/test"),
        ("build oficial nativa",
         'dart run packages/cli/tool/build_release.dart --version 0.0.0-ci '
         '--output "$RUNNER_TEMP/shipflow-release"'),
        ("el artefacto de esta plataforma responde",
         'test "$("$RUNNER_TEMP/shipflow-release/shipflow-0.0.0-ci-'
         '${{ matrix.plataforma }}" --version)" = "shipflow 0.0.0-ci"'),
    )
    for paso, comando in nativos:
        casos.append({
            "nombre": f"nativo · «{paso}» borrado del workflow",
            "archivos": {ci_rel: ancla(
                ci, f"      - name: {paso}\n        run: {comando}\n", "",
                que=f"el paso nativo «{paso}»")},
            "menciona": "ya no ejecuta",
        })
        casos.append({
            "nombre": f"nativo · «{paso}» con «|| true»",
            "archivos": {ci_rel: ancla(
                ci, f"        run: {comando}\n",
                f"        run: {comando} || true\n",
                que=f"el comando nativo «{paso}»")},
            "menciona": "exactamente",
        })
    casos.append({
        "nombre": "nativo · la build oficial omitida con «if: false»",
        "archivos": {ci_rel: ancla(
            ci, f"        run: {nativos[2][1]}\n",
            f"        run: {nativos[2][1]}\n        if: false\n",
            que="la build oficial nativa")},
        "menciona": "condición",
    })
    casos.append({
        "nombre": "nativo · las pruebas nativas con continue-on-error",
        "archivos": {ci_rel: ancla(
            ci, f"        run: {nativos[1][1]}\n",
            f"        run: {nativos[1][1]}\n        continue-on-error: true\n",
            que="las pruebas nativas")},
        "menciona": "no detiene nada",
    })
    dart_nativo = ('      - name: dart, el SDK bloqueante\n'
                    '        uses: dart-lang/setup-dart@'
                    '6afc89df92d6eb3834022f73cd65adc8cdfcb92d # v1\n'
                    '        with:\n          sdk: "3.12.0"')
    for etiqueta, viejo, nuevo, menciona in (
        ("la pata de macOS fuera de la matriz",
         "          - runner: macos-14\n            plataforma: macos-arm64\n", "",
         "no está verificada"),
        ("un runner que no es el nativo de su plataforma",
         "          - runner: macos-14\n", "          - runner: macos-13\n",
         "no está verificada"),
        ("runs-on fijo en vez del runner de la matriz",
         "    runs-on: ${{ matrix.runner }}\n", "    runs-on: ubuntu-24.04\n",
         "queda decorativa"),
        ("un exclude que saca una pata",
         "        include:\n          - runner: ubuntu-24.04\n",
         "        exclude:\n          - runner: macos-14\n"
         "        include:\n          - runner: ubuntu-24.04\n",
         "solo puede declarar `include`"),
        ("el job entero omitido con «if: false»",
         "  nativo:\n    name: ejecutable nativo",
         "  nativo:\n    if: false\n    name: ejecutable nativo",
         "Un job omitido"),
        ("el job entero con continue-on-error",
         "    runs-on: ${{ matrix.runner }}\n",
         "    runs-on: ${{ matrix.runner }}\n    continue-on-error: true\n",
         "dejaría de bloquear"),
        ("el SDK en un canal flotante",
         dart_nativo, dart_nativo.replace('"3.12.0"', "stable"),
         "SDK bloqueante"),
        ("un paso nativo repartido en otro job",
         "        run: dart format --output=none --set-exit-if-changed packages tool\n",
         "        run: dart format --output=none --set-exit-if-changed packages tool\n"
         f"\n      - name: build fuera de su job\n        run: {nativos[2][1]}\n",
         "Tienen que vivir"),
    ):
        casos.append({
            "nombre": f"nativo · {etiqueta}",
            "archivos": {ci_rel: ancla(ci, viejo, nuevo, que=etiqueta)},
            "menciona": menciona,
        })
    return casos
