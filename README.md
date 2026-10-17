# 🛡️ shipflow

> Un arnés de verificación de arquitectura para proyectos Dart: reglas declaradas
> en un solo lugar, aplicadas por dos motores, y una suite que comprueba que esas
> reglas **saben ponerse rojas**.

## 📖 Tabla de contenidos

- [Contexto](#-contexto)
- [Estado](#-estado)
- [Instalación](#️-instalación)
- [Uso](#-uso)
- [Gobierno](#-gobierno)
- [Mantenedores](#-mantenedores)
- [Contribución](#-contribución)

## 🧠 Contexto

Un check que nunca se disparó es indistinguible de uno roto. Y una ausencia de
resultados se lee igual que «no había nada que objetar».

Sobre esas dos ideas está construido este repositorio. Las reglas de arquitectura
viven en un registro único y diffeable; dos motores las aplican —uno lee texto,
otro necesita el árbol sintáctico—; y una suite de sabotajes inyecta violaciones
sintéticas en cada corrida para comprobar que cada control **todavía detecta lo
que dice detectar**, incluido el caso donde se le quita la vista.

Qué corre exactamente, qué regla impide qué, y quién aplica cada una está en
**[`GOBIERNO.md`](GOBIERNO.md)**, y lo verifica el propio arnés contra el registro
y contra el workflow.

## 🚦 Estado

**El producto está vacío, a propósito.** Los paquetes existen con su nombre y sin
API: son reservas declaradas, no código pendiente.

El arnés sí está completo y verde. Fue desacoplado del producto anterior antes de
retirarlo, para que pudiera seguir verificando sobre un árbol vacío sin que haya
que inventar código que lo satisfaga.

Las preguntas de diseño sin responder y los puntos ciegos conocidos del arnés
están en **[`HUECOS.md`](HUECOS.md)**, con su procedencia.

## ⚙️ Instalación

Requisitos:

```bash
# Dart SDK 3.11 o superior
# Python 3.11 o superior, con pyyaml
dart --version
python3 -c "import yaml; print(yaml.__version__)"
```

Resolver dependencias — es precondición de los checks, porque el grafo de paquetes
se le pide a `pub` y no se parsea a mano:

```bash
dart pub get
(cd tool/analisis && dart pub get)
```

## 🚀 Uso

Los checks, **en serie**:

```bash
python3 tool/checks/capas.py
(cd tool/analisis && dart run bin/check.dart)
(cd tool/analisis && dart run bin/grafo.dart)
python3 tool/checks/probar_recuperacion.py
python3 tool/checks/probar_reglas.py
```

No se paralelizan los dos últimos: comparten un archivo de estado, y correrlos a
la vez es una carrera cuyo fallo no se parece a su causa.

Y el resto de la compuerta:

```bash
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed packages tool
```

`--output=none` porque una compuerta verifica y no muta.

## ⚖️ Gobierno

Las reglas se declaran en `arquitectura.json`; los símbolos concretos que cada una
gobierna, en `inventario.json`. Los dos llevan huella propia: cambiar uno sin
regenerar su huella pone el check en rojo, de modo que tocar la arquitectura es un
acto visible y revisable.

Todo el detalle está en [`GOBIERNO.md`](GOBIERNO.md).

## 👥 Mantenedores

- [@GuzCabQ](https://github.com/GuzCabQ)

## 🤝 Contribución

Los PRs son bienvenidos. Antes de abrir uno, leé [`GOBIERNO.md`](GOBIERNO.md):
describe qué corre, qué regla impide qué, y por qué agregar una regla implica
agregar también la violación canónica que demuestra que sabe dispararse.
