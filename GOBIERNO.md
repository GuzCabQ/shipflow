# Gobierno de este repositorio

**Qué es este documento.** Lo que gobierna a shipflow: qué corre, qué reglas lo
hacen cumplir y quién aplica cada una. **Lo verifica `capas.py`**, que compara lo
escrito acá contra `arquitectura.json` y contra el workflow de CI, y se pone rojo
si divergen.

**Por qué no está en el README.** Un README es para quien llega; esto es para
quien mantiene. Tienen audiencia, cadencia y motivo de cambio distintos, y
mientras compartieron archivo el que empujaba era el verificador: el README pasó
de 93 líneas en la fase 0 a 4.565. La invariante —que la declaración dirigida a
humanos no se desvíe de lo que la máquina hace cumplir— no cambió; cambió el
archivo que la lleva.

---

## Qué corre

```
dart pub get                                  # PRECONDICIÓN: el grafo se le pide a pub
python3 tool/checks/capas.py                  # las reglas que se leen del texto
(cd tool/analisis && dart pub get \
   && dart run bin/check.dart      # serialización, opacidad, puertos, colecciones
   && dart run bin/grafo.dart)     # el grafo: derivado == commiteado
python3 tool/checks/probar_reglas.py          # y la prueba de que saben fallar
python3 tool/checks/probar_recuperacion.py    # y de que se recupera de una corrida muerta
dart test packages/core            # si y solo si tiene test/**/*_test.dart
dart test packages/orchestration   # si y solo si tiene test/**/*_test.dart
dart test packages/vcs             # si y solo si tiene test/**/*_test.dart
dart test packages/rules           # si y solo si tiene test/**/*_test.dart
dart test packages/agents          # si y solo si tiene test/**/*_test.dart
dart test packages/plugin_dart     # si y solo si tiene test/**/*_test.dart
dart test packages/plugin_fake     # si y solo si tiene test/**/*_test.dart
dart test packages/forge           # si y solo si tiene test/**/*_test.dart
dart test packages/cli             # si y solo si tiene test/**/*_test.dart
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed packages tool
(cd fixtures/app-minima/dominio && dart test)  # el fixture se verifica solo
(cd fixtures/app-minima/app && flutter test)
```

**Los 19 pasos obligatorios los verifica `capas.py` contra el workflow**, comando
por comando: un paso borrado de CI, o neutralizado con un `continue-on-error`,
pone el check en rojo.

**Diez son fijos; los otros nueve se DERIVAN del `workspace:`** —uno por miembro—
y son CONDICIONALES: cada uno corre si y solo si su paquete tiene al menos un
`test/**/*_test.dart`. Sin la condición, un paquete sin pruebas hace salir a
`dart test` con 79 —«No tests ran»— y el job queda rojo por no haber nada que
correr.

La lista se deriva y no se escribe porque escrita a mano ya se había separado:
`rules`, `agents` y `plugin_fake` no tenían el suyo, así que una prueba agregada
en esos paquetes no habría corrido nunca y nada lo habría dicho. Y para esos nueve el meta-check no prohíbe la condición: exige **la
condición exacta prevista para ese paquete**, carácter por carácter. Un pin, no
un permiso.

**Las reglas viven en [`arquitectura.json`](arquitectura.json)**, en un solo
lugar y diffeable, aunque las apliquen dos motores distintos. Tocarlo es cambiar
la arquitectura y se revisa como tal.

| `id` de la regla | Qué impide | Aplica |
|---|---|---|
| `deps-hacia-core` | Que una flecha **interna** apunte a otro lado que no sea `core` | `capas.py` |
| `nucleo-sin-externas` | Que `core` gane una dependencia **de cualquier origen**, incluidas las de desarrollo | `capas.py` |
| `nucleo-sin-entrada-salida` | Que `core` toque el mundo directamente en vez de pedirlo por un puerto | `capas.py` |
| `dependencias-declaradas-se-usan` | Que un pubspec declare una flecha interna que ninguna línea importa | `capas.py` |
| `subprocesos-con-entorno-saneado` | Que un subproceso **herede** el entorno del padre —el token de la forja, un `GIT_*` del shell— en vez de recibir la lista blanca | `tool/analisis` |
| `agente-en-agents` | Que `claude`/`codex`/`gemini` salgan de `agents/` | `capas.py` |
| `lenguaje-en-plugin-dart` | Que `dart`/`flutter`/`pubspec` salgan de `plugin_dart/` | `capas.py` |
| `sin-api-de-modelo` | Que **cualquier** paquete llame a una API de modelo | `capas.py` |
| `serializacion-sin-perdida` | Que un campo de `core` no viaje, o vuelva vacío | `tool/analisis` |
| `opacidad-declarada` | Que «no serializa» sea indistinguible de «se olvidaron» | `tool/analisis` |
| `puertos-sin-implementacion` | Que una superficie de puertos vacía se lea como un sistema que hace esas cosas | `tool/analisis` |
| `colecciones-inmutables` | Que un invariante se pueda romper **después** de construir el objeto, mutando la lista que se le pasó | `tool/analisis` |
| `grafo-derivado` | Que el mapa del repositorio quede desactualizado, o que un archivo no lo alcance nadie | `tool/analisis` |
| `forja-en-su-adapter` | Que el nombre de la forja, su host o un `HttpClient` salgan de `packages/forge/` | `tool/analisis` |

Una regla que `capas.py` no aplica **tiene que declarar `aplicada_por`**, ese
aplicador tiene que existir, y CI tiene que invocarlo. Sin las tres cosas es
F33: registrada y no ejecutada. El propio check lo verifica —y de hecho fue lo
primero que hizo cuando se agregaron las tres reglas nuevas.

### Por qué siete de estas reglas necesitan otro motor

**Siete, y no son un bloque contiguo de la tabla:** las seis últimas más
`subprocesos-con-entorno-saneado`, que es la quinta fila. El registro es la
fuente —`aplicada_por: tool/analisis`—, no la posición en la tabla.

Lo único que las siete comparten es la razón: **ninguna se puede derivar
leyendo el archivo como texto plano.** Es la misma lección que ya pagó
`capas.py` con el grafo de dependencias: parsear a mano devuelve cero
resultados ante una sintaxis que el parser no reconoce, y cero se lee igual que
*"está todo bien"*. Su paquete está **fuera del `workspace:`** a propósito:
ninguna regla de capas debería tener que hacerle una excepción a su propio
verificador.

**Lo que mira cada una no es lo mismo, y agruparlas bajo «se derivan del árbol
sintáctico de `core`» era falso.** Medido sobre `tool/analisis`:

- `serializacion-sin-perdida`, `opacidad-declarada` y `colecciones-inmutables`
  — y solo estas tres — se derivan del árbol sintáctico de `packages/core/lib`.
- `puertos-sin-implementacion` saca los puertos de ahí, pero **quién los
  implementa lo busca en todos los paquetes**: una implementación que viviera
  solo en `core` no es la pregunta que responde.
- `subprocesos-con-entorno-saneado` mira `lib/` y `bin/` de cada paquete, y es
  la única que además **resuelve** la identidad de `Process` contra el SDK en
  vez de conformarse con el nombre.
- `forja-en-su-adapter` mira `lib/` y `bin/` de cada paquete **menos `forge`**,
  y de sus dos criterios solo el primero sale del árbol: el segundo es
  **textual** sobre el contenido del archivo, y lo único que le pide al parser
  es el stream de tokens con el que descarta los comentarios.
- `grafo-derivado` mira el repositorio entero, `.dart` **y `.md`**: los `.dart`
  por sus directivas en el árbol, pero las aristas de cita de los `.md` salen
  de la **prosa**, no de ningún árbol.

Los residuos de cada criterio están en
[`arquitectura.json`](arquitectura.json), no acá.

---

## Que los checks sepan fallar

Cada regla lleva una **violación canónica** —un caso sintético que TIENE que
detectar— y un **caso ciego**, que le quita la vista y comprueba que el check se
ponga rojo en vez de reportar «nada que objetar». `probar_reglas.py` los inyecta y
los revierte en cada corrida.

**El arnés aplica 154 sabotajes.** La cifra la deriva `cifra_de_sabotajes` en
`tool/checks/probar_reglas.py` contando los casos que esperan falla, y falla si
esta prosa no coincide. No se mantiene a mano: se escribe acá porque hay quien la
tiene que leer, y se verifica porque una cifra que nadie deriva envejece sola.

---

## Dónde viven los verificadores

```
tool/
  checks/        capas.py, probar_reglas.py, probar_recuperacion.py
  analisis/      check.dart, grafo.dart — los que necesitan el árbol sintáctico
```

`tool/analisis/` está **fuera del `workspace:`** a propósito: ninguna regla de
capas debería tener que hacerle una excepción a su propio verificador.

---

## Cardinalidades: qué puede y qué no puede afirmar este documento

`capas.py` **prohíbe** que este documento declare una cardinalidad que nada
derive. El motivo está pagado tres veces: una cifra en prosa que nadie deriva
envejece sola, y la anterior lo hizo —«cuatro de los veintitrés» cuando eran
otras— sin que nada lo viera.

**Lo que sí puede afirmarse:** los 19 pasos obligatorios, porque `capas.py` los
deriva de `PASOS_OBLIGATORIOS` y falla si la cifra no coincide.

**Lo que no puede afirmarse:** ninguna otra cantidad asociada a *puertos*,
*pasos*, *cascada*, *presupuesto* o *minutos*. La prosa se escribe en plural o
sin cardinal.

**Alcance del control.** Es léxico, no semántico: rechaza dígitos y las formas
cardinales enumeradas cuando aparecen en la **misma oración** que alguno de esos
conceptos.

**Lo que queda fuera, declarado.** Los artículos indefinidos no cuentan como
cardinal: en español son casi siempre artículo y no cantidad, y exigir que la
prosa los evite volvía este documento inescribible — medido, diez falsos
positivos contra uno. Tampoco cubre cuantificadores no cardinales como `ambos`,
`sendos`, `media docena` o `varios`, ni cantidades asociadas a conceptos fuera de
la lista. Todo eso es **riesgo residual conocido**, sujeto a revisión humana: un
regex no puede demostrar una garantía semántica, y prometerlo sería la misma clase
de falso verde que el resto de este arnés persigue.
