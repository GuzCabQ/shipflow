# Huecos abiertos

Preguntas de diseño sin responder y puntos ciegos conocidos del arnés. **No es una
hoja de ruta del producto**: eso vive en el corpus de diseño, en otro repositorio.
Acá va lo que sobrevive al reinicio porque no depende del código que se retiró.

Cada entrada lleva **de dónde salió**. Un hueco sin procedencia se vuelve folklore.

---

## 1 · ¿De quién es la validación de claves: del puerto o de leer un entorno?

**Fuente:** la declaración de `CredentialStore` en `inventario.json`, rescatada
antes de vaciarlo durante el reinicio del 2026-09-21.

Está escrito así, y se conserva literal porque la precisión es el valor:

> fase de `init` · el puerto se partio en la rebanada de la forja: `CredentialSource`, que solo lee, salio de esta lista con UNA implementacion real —`FuenteDeEntorno` en cli— y, desde la tarea de los fakes de la forja, UNA falsa —`FuenteDeCredencialFalsa` en plugin_fake—. No hay suite de contrato que las corra a las dos contra las mismas preguntas, y eso queda escrito y no disimulado: hoy la falsa solo se usa como colaborador de la suite de `PullRequestSink` —para construir `SalidaDePrDeGitHub` sin credenciales reales—, no como sujeto comparado contra la real. Escribir esa suite tendria que decidir primero algo que hoy no esta decidido: `FuenteDeEntorno` rechaza con `ArgumentError` una clave que `clavesDeCredencial` no declaro —esa validacion vive en `EntornoDelProceso`, no en el puerto— y `FuenteDeCredencialFalsa`, configurada con un mapa directo, no tiene ningun equivalente; sirve cualquier clave que se le dio. Si esa clausula es del contrato de `CredentialSource` o es propia de leer de un entorno de proceso es la pregunta que falta responder antes de poder escribir la suite, asi que el hueco es de esa decision, no solo de tiempo. `CredentialStore` agrega escritura y borrado, y sigue sin implementacion porque no hay almacenamiento real: una clase que leyera y lanzara en `write`/`delete` seria una capacidad declarada que no existe

**Por qué se rescata:** no es hoja de ruta. Es una decisión de diseño que hay que
tomar antes de poder escribir una suite de contrato, y el hueco es de esa decisión,
no de tiempo. Sobrevive al vaciado porque la pregunta no depende del código que la
motivó.

---

## 2 · El arnés está partido en dos repositorios, y se puede instalar a medias

**Fuente:** el README anterior, sección «Qué prometen estas fases y todavía no
cumplen».

Los checks de este repositorio cubren la arquitectura del código. Los que verifican
el corpus de diseño viven en `../sdlc-agentico/`, con su propio CI. **Tener uno
solo en verde no significa que el arnés esté completo.**

Lo único que cruza los dos es `estados.py`, que compara el inventario del arnés
contra las reglas instaladas acá. Si los repositorios dejan de estar uno al lado
del otro, **falla** — no poder mirar no es «no disponible». La única evasión es
`--sin-repo-de-codigo`, que hay que escribir a mano y que imprime que no miró.

---

## 3 · Puntos ciegos del arnés, encontrados al reiniciarlo

Los cuatro salieron de **ejecutar** el reinicio, no de leerlo. Ninguno lo detectó
una revisión del plan.

### 3.1 · No hay ejecutor local de expresiones de CI

`capas.py` inspecciona el workflow con un parser de YAML, estáticamente. Nada acá
evalúa una expresión del proveedor de CI. Por eso, que un paso condicional corra o
se omita **según corresponda** se verificó con sondas remotas de una sola vez, y su
evidencia quedó archivada fuera del repositorio.

Construir ese ejecutor sería un cambio de arquitectura mayor y no se justifica
todavía. Lo que no se puede es fingir que esos controles corren en cada corrida.

### 3.2 · El check de rutas del gobierno solo mira dos prefijos

`_readme_rutas` en `tool/checks/capas.py` usa un patrón que solo gobierna rutas
bajo `tool/` y `packages/`. Un documento de gobierno que enlace un archivo
inexistente **fuera** de esos prefijos pasa en verde.

Ampliar su alcance cambiaría una regla de gobierno y merece su propia decisión.

### 3.3 · El arnés verifica la prosa que gobierna, no la prosa que explica

`capas.py` compara `GOBIERNO.md` contra el registro y contra el workflow. **No
mira los comentarios de su propio código.**

Se encontró al retirar el material de prueba: la compuerta pasó en verde dejando
dos comentarios que seguían describiéndolo como algo vivo. Apareció porque la
evidencia de la compuerta incluye una búsqueda por texto, no porque una regla lo
exigiera.

### 3.4 · Un paquete que gana pruebas gana su dependencia de desarrollo

La política de pruebas dice **cuándo** corre el paso de un paquete. No dice que ese
paquete también tenga que declarar el framework de pruebas, y el analizador sí lo
exige: `depend_on_referenced_packages` no supone una resolución compartida.

El caso difícil ya está resuelto en el árbol, con alcance acotado y motivo escrito:
`core` no puede declarar **ninguna** dependencia sin violar `nucleo-sin-externas`,
así que apaga ese lint solo en su directorio de pruebas. Los demás paquetes toman
el camino normal.

Se encontró agregando una prueba a un paquete que no tenía ninguna, durante las
sondas remotas del reinicio.

### 3.5 · El verificador fija la ruta de un símbolo del producto

`check.dart` tiene escrito `_origenDelSaneador = 'package:core/src/entorno.dart'`
y compara la **identidad** de lo que se invoca contra esa ruta exacta. La
comparación por identidad es correcta y costó un hallazgo: sin ella, una función
homónima que devuelva el entorno del padre intacto pasaba en verde.

Lo que quedó acoplado es **dónde** tiene que vivir ese símbolo. La separación entre
la política y el inventario de símbolos movió las tres rutas enumeradas, y esta no
estaba entre ellas: sigue escrita en el verificador.

**Consecuencia:** el producto nuevo queda obligado a poner el saneador en esa ruta,
o a cambiar el verificador. Es una decisión de diseño predecidida por un lugar que
no debería decidirla.

**Cómo se encontró:** al vaciar el producto, el canario que prueba esta regla dejó
de resolver el símbolo y el verificador reportó «no es el de core» —cierto, y otro
control— en vez del defecto que el caso declara. Se resolvió haciendo que el canario
traiga su propio saneador **en esa misma ruta**, que funciona pero no retira el
acople.
