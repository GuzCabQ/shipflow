# `app-minima` — el fixture

**No es código del producto.** Es el **sujeto** sobre el que corre el arnés: un
proyecto de verdad, con toolchain de verdad, donde `verify` y `ship` tienen algo
que verificar y algo que empaquetar.

```
app/       depende de Flutter y del dominio, por ruta
dominio/   Dart puro, sin UI
```

Dos paquetes y no uno **a propósito**: con uno solo, `ProjectTopology` no
tendría ninguna flecha que reportar y se ejercería sobre el caso que no existe
en ningún proyecto real.

## Por qué tiene que ser real

`DiagnosticNormalizer` traduce **la salida del analizador**. Si esa salida la
invento yo, el normalizador queda escrito contra mi invención, pasa sus propias
pruebas, y falla el día que ve una salida verdadera.

Ya ocurrió mientras se armaba este fixture: el analizador real encontró dos
errores en el test de `app` que yo no había visto. Ese es exactamente el valor
que un fixture inventado no puede dar.

## Y por qué CI lo ejecuta en vez de solo leerlo

Un fixture commiteado es una **fotografía**. Sus archivos están ahí porque
alguien los copió, no porque el proyecto siga funcionando. CI corre sobre él
`pub get`, `analyze` y `test` con su propia toolchain: si dejó de compilar, es
rojo.

Es F36 del catálogo de fallos, literal: *«el fixture del spec "mínimo válido"
que nunca validó es un fixture que mentía sobre sí mismo»*.

## Qué NO es

- **No entra en el grafo interno.** El grafo mapea *nuestra* arquitectura;
  incluirlo mezclaría dos proyectos en el mismo mapa. Está declarado en
  `arquitectura.json` → `grafo-derivado.alcance.excluir.fixtures`.
- **No es miembro del `workspace:`** de la raíz, y no puede serlo en silencio:
  `deps-hacia-core` deriva los miembros del grafo de pub, así que uno nuevo sin
  declarar es rojo.
- **No es representativo de la escala.** Dos paquetes, cinco archivos. Un
  proyecto real tiene decenas de paquetes y ruido acumulado en el analizador.
  Eso es una observación de campo, no un fixture, y va en la fase 3.
