/// El control de integridad del candidato: **se le pide a `git`**, igual que el
/// grafo de dependencias se le pide a pub.
///
/// Acá vive solo la LECTURA de lo que `git` contestó. La invocación está en el
/// candidato, que es quien tiene las costuras contra la herramienta: son
/// privadas a propósito, y abrirlas convertiría cualquier archivo futuro en un
/// segundo lugar donde se arman invocaciones.
part of 'repositorio.dart';

/// Lee la salida de `diff-index --raw -z`.
///
/// El formato, medido: dos puntos, modo viejo, modo nuevo, sha viejo, sha nuevo
/// y la letra, separados por espacios; después NUL, la ruta, y otro NUL.
/// **El sha nuevo siempre viene en ceros**, porque
/// `diff-index` no hashea el árbol de trabajo — y eso es lo que obliga a leer
/// los MODOS para distinguir un cambio de permisos de uno de contenido.
///
/// **Falla cerrado ante una letra que no sea `M`, `D` ni `T`**, y las que
/// quedan afuera no se adivinan: el manual de `git-diff-index(1)` enumera en
/// su sección de la salida cruda las ocho que el formato admite —`A`, `C`,
/// `D`, `M`, `R`, `T`, `U` y `X`—, y de ahí sale esta lista. De las cinco que
/// este parser no clasifica: con un índice recién leído del árbol no puede
/// aparecer una `A`; una `R` o una `C` solo aparecen con detección de
/// renombres o de copias, que no se pide; una `U` pide una entrada sin
/// fusionar, y el índice aislado del candidato se arma leyendo un árbol, no
/// fusionando nada; y una `X` la declara el propio manual como un error de la
/// herramienta. Si aparece cualquiera de ellas, `git` vio algo que este
/// control no previó, y descartarlo sería leer un hueco como un candidato
/// intacto.
///
/// **Ese dominio es el del índice AISLADO del candidato, y no se hereda.**
/// Quien compare el índice REAL de quien corre contra un árbol arbitrario
/// tiene otro conjunto alcanzable —`A` y `U` sí lo son ahí— y le toca
/// resolverlas antes de llegar acá: ver [RepositorioGit.rutasQueDifierenDelArbol].
///
/// [declaradas] son las rutas que el candidato **no materializó a propósito**
/// —enlaces absolutos, enlaces con `..`, destinos que no son UTF-8,
/// submódulos—. Para `git` están en el árbol y no en el disco, así que salen
/// como `D`; está medido. Sin restarlas, **todo candidato con un enlace
/// absoluto sería no concluyente para siempre**.
///
/// La resta es estrecha: una `D` sobre una declarada no cuenta, **cualquier
/// otra letra sobre ella sí**. Si un verificador escribió un archivo regular
/// donde el candidato dejó un hueco a sabiendas, eso es una `T`, y es una
/// alteración.
List<AlteracionDelCandidato> leerDiffRaw(
  List<int> bytes, {
  required Set<String> declaradas,
}) {
  final piezas = _CandidatoGit._partirNul(bytes);
  if (piezas.length.isOdd) {
    throw const PromesaIncumplida(
      'leer la salida de `diff-index --raw -z`',
      'un registro sin su ruta',
    );
  }
  final salida = <AlteracionDelCandidato>[];
  for (var i = 0; i < piezas.length; i += 2) {
    final campos = utf8.decode(piezas[i]).split(' ');
    if (campos.length != 5 || !campos.first.startsWith(':')) {
      throw PromesaIncumplida(
        'leer un registro de `diff-index --raw`',
        '«${utf8.decode(piezas[i])}», que no tiene la forma esperada',
      );
    }
    final modoViejo = campos[0].substring(1);
    final modoNuevo = campos[1];
    final letra = campos[4];
    final ruta = _CandidatoGit._comoRuta(piezas[i + 1]);

    final TipoDeAlteracion tipo;
    switch (letra) {
      case 'D':
        if (declaradas.contains(ruta)) continue;
        tipo = TipoDeAlteracion.borrada;
      case 'T':
        tipo = TipoDeAlteracion.cambioDeTipo;
      case 'M':
        tipo = modoViejo == modoNuevo
            ? TipoDeAlteracion.modificada
            : TipoDeAlteracion.cambioDeModo;
      default:
        throw PromesaIncumplida(
          'clasificar la alteración de «$ruta»',
          'la letra «$letra» de `diff-index`, que este control no previó',
        );
    }
    salida.add(AlteracionDelCandidato(ruta: ruta, tipo: tipo));
  }
  return salida;
}
