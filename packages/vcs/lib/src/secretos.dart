/// Detección de secretos en un cambio. **Agnóstica del lenguaje**, por eso
/// vive acá y no en el plugin del stack: una credencial filtrada no es una
/// pregunta sobre ningún lenguaje ni sobre ningún ecosistema.
///
/// Esta frase nombraba dos ecosistemas como ejemplo y la regla de cadenas la
/// rechazó. Tenía razón, y es el mismo caso que ya corrigió `ArtifactPolicy`:
/// decía «esto no es una pregunta sobre X» y al escribirlo, `vcs` conocía X.
///
/// `docs/11` la asigna a `vcs` y lo explica: *«decir "el plugin abarca
/// desarrollo" llevaría a meter la detección de secretos adentro»*.
///
/// **Bloquea, y esa decisión no estaba tomada en el corpus.** No hay ADR, ni
/// delta, ni invariante; no figura en la tabla de severidades de `docs/08` ni
/// entre los seis deltas que ADR-013 reconcilió. La única pista era que el
/// plan la ubica en la superficie «Requiere criterio», que por ADR-012 es la
/// de MIRAR. Se decidió bloquear porque un secreto commiteado no se
/// des-commitea: queda en el historial, y reportarlo después no es un control
/// sino una crónica. Es el mismo argumento por el que nuestro propio check de
/// anonimato mira el historial y no el árbol.
///
/// Cumple INV-8 —solo bloquea lo que sabe decir qué hacer—: la alternativa la
/// escribe el propio corpus en `P-07` y `L-09`, *«leé de `env` vía provider de
/// configuración»*.
library;

/// Un secreto encontrado. **Nunca lleva el secreto.**
///
/// Es la misma exigencia que INV-5 le hace a las credenciales del arnés —*«un
/// `Credential` nunca se serializa ni aparece en traza, log o mensaje de
/// error»*— aplicada a las del usuario. Un detector que para avisarte de una
/// filtración te la escribe en un log la filtra otra vez, y en un lugar que
/// nadie está mirando.
class Secreto {
  /// Dónde. La ruta tal como la nombra `git`.
  final String archivo;

  /// La línea **del archivo nuevo**, contada desde el encabezado del hunk.
  final int linea;

  /// Qué se reconoció. Es el nombre del patrón, no lo que coincidió.
  final String queEs;

  /// Qué hacer. Un control que bloquea sin alternativa no se instala (INV-8).
  final String queHacer;

  const Secreto({
    required this.archivo,
    required this.linea,
    required this.queEs,
    required this.queHacer,
  });

  @override
  String toString() => '$archivo:$linea · $queEs';
}

/// Un patrón reconocible, con su nombre y su alternativa.
class _Patron {
  final String nombre;
  final RegExp expresion;
  final String queHacer;
  const _Patron(this.nombre, this.expresion, this.queHacer);
}

/// Se lanza cuando el detector **no puede mirar** una línea que debería poder
/// mirar. No es un hallazgo: es la ausencia de uno, que es peor.
///
/// Un archivo que `git` declara binario no llega acá — está declarado fuera de
/// alcance. Esto es para el otro caso: texto que no se puede leer. «No
/// encontré nada» y «no pude mirar» no se pueden confundir (ADR-011).
class DiffIlegible implements Exception {
  final String motivo;
  const DiffIlegible(this.motivo);

  @override
  String toString() => 'DiffIlegible: $motivo';
}

/// Lee el diff de un cambio y devuelve los secretos que reconoce.
///
/// **No es exhaustivo, y eso va escrito y no disimulado.** Reconoce formas con
/// estructura —encabezados de clave privada, prefijos de token de proveedores
/// conocidos— y asignaciones a nombres que declaran su contenido. Una cadena
/// que no tenga ninguna de esas dos cosas pasa. El límite es del método, no de
/// la lista: un secreto sin forma reconocible es indistinguible de cualquier
/// otra cadena, y prometer lo contrario sería el falso verde que este arnés
/// existe para cazar.
///
/// **Lo que `git` declara binario no llega acá, y no hace falta saltarlo.**
/// Hubo una rama que lo hacía y una mutación la encontró muerta: sin
/// `--binary`, `git diff` no emite ninguna línea de contenido para un binario,
/// solo *«Binary files … differ»*. Una defensa que no puede fallar se lee como
/// protección y no protege nada — es la misma línea muerta que este proyecto ya
/// borró dos veces. La premisa queda comprobada en la suite en vez de asumida.
///
/// Que un binario no se revise es entonces un límite del formato del diff, no
/// una decisión del detector, y va declarado igual. Declararlo **por corrida**
/// —qué se omitió y por qué, que es lo que pide el corolario 5 de ADR-011—
/// necesita el artefacto de revisión, que llega con `ship`.
class DetectorDeSecretos {
  static const _leeDeEnv =
      'Sacala del código y leela de `env` vía provider de configuración.';

  /// Los patrones. **Cada uno lleva su nombre y su alternativa**, porque el
  /// mensaje de bloqueo no puede ser el hallazgo a secas.
  static final List<_Patron> _patrones = [
    _Patron(
      'una clave privada',
      RegExp(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----'),
      'Una clave privada no va al repositorio. Rotala: si estuvo en un '
          'archivo que se commiteó, hay que darla por comprometida.',
    ),
    _Patron('una clave de acceso de AWS', RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
        _leeDeEnv),
    _Patron('un token de GitHub', RegExp(r'\bgh[pousr]_[A-Za-z0-9]{36,}\b'),
        _leeDeEnv),
    _Patron('un token de Slack', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b'),
        _leeDeEnv),
    _Patron('una clave de API de Google', RegExp(r'\bAIza[0-9A-Za-z_\-]{35}\b'),
        _leeDeEnv),
    _Patron('una clave secreta de Stripe',
        RegExp(r'\bsk_live_[A-Za-z0-9]{16,}\b'), _leeDeEnv),
    // El único patrón que mira el NOMBRE en vez de la forma del valor. Es el
    // que más falsos positivos puede dar, así que exige un literal largo y
    // descarta los marcadores de posición, que son la mitad de los casos.
    _Patron(
      'una credencial asignada en el código',
      RegExp(
          r'''\b(?:password|passwd|secret|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|client[_-]?secret)\b\s*[:=]\s*(['"])(?![^'"]*(?:\$|\{\{|<|\.\.\.|YOUR|your|EXAMPLE|example|CHANGE|change|dummy|placeholder|xxxx|XXXX|TODO))[^'"]{12,}\1''',
          caseSensitive: false),
      _leeDeEnv,
    ),
  ];

  const DetectorDeSecretos();

  /// Los nombres de lo que sabe reconocer. **Existe para que la suite se
  /// derive de la tabla y no de una lista paralela**: un patrón nuevo sin
  /// caso de prueba deja la suite en rojo, en vez de entrar sin que nadie lo
  /// haya visto fallar.
  static List<String> get loQueReconoce =>
      _patrones.map((p) => p.nombre).toList(growable: false);

  /// Revisa **las líneas agregadas** de un diff unificado.
  ///
  /// Solo las agregadas: lo que se quita no lo introduce esta rebanada, y lo
  /// que queda igual ya estaba. La pregunta que `apply` tiene que contestar es
  /// *«¿este cambio introduce un secreto?»*, y el corpus concreta exactamente
  /// eso —`happy-path.md`: «escanea secretos **en el diff**»—. Lo «del repo»
  /// de `docs/11` es otra pregunta, con otro costo, y queda declarada.
  List<Secreto> revisar(String diff) {
    if (diff.isEmpty) return const [];
    final hallazgos = <Secreto>[];
    var archivo = '';
    var linea = 0;

    for (final l in diff.split('\n')) {
      if (l.startsWith('diff --git ')) {
        archivo = _rutaDeEncabezado(l);
        linea = 0;
        continue;
      }
      if (l.startsWith('@@')) {
        linea = _lineaDeHunk(l, archivo);
        continue;
      }
      if (!l.startsWith('+') || l.startsWith('+++')) continue;

      final contenido = l.substring(1);
      for (final p in _patrones) {
        if (p.expresion.hasMatch(contenido)) {
          hallazgos.add(Secreto(
              archivo: archivo,
              linea: linea,
              queEs: p.nombre,
              queHacer: p.queHacer));
          break; // Un hallazgo por línea: nombrar dos veces la misma línea no
          // agrega información y multiplica el ruido.
        }
      }
      linea++;
    }
    return hallazgos;
  }

  /// `diff --git a/x b/x` → `x`. Se toma **el lado b**, que es el archivo
  /// nuevo: en un renombrado, el lado a ya no existe.
  static String _rutaDeEncabezado(String l) {
    final b = l.indexOf(' b/');
    return b < 0 ? l : l.substring(b + 3);
  }

  /// `@@ -1,0 +12,3 @@` → `12`. **Si no se puede leer, lanza.**
  ///
  /// Sin el número de línea el hallazgo dice «hay un secreto en este archivo»
  /// sin decir dónde, y quien lo lea tiene que buscarlo a mano — o peor,
  /// devolver cero porque el encabezado no se entendió, que se lee igual que
  /// «no había nada».
  static int _lineaDeHunk(String l, String archivo) {
    final m = RegExp(r'^@@ -\S+ \+(\d+)').firstMatch(l);
    if (m == null) {
      throw DiffIlegible(
          'no entiendo el encabezado de hunk «$l» en «$archivo», así que no '
          'puedo decir en qué línea está lo que encuentre');
    }
    return int.parse(m.group(1)!);
  }
}
