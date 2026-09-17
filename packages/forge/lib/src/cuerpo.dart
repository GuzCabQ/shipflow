/// El render del cuerpo y el título del pull request de GitHub.
///
/// **Por qué vive acá y no en un renderizador neutral.** Un componente
/// neutral decide la **estructura**; el adapter aplica la **sintaxis**. La
/// alerta `> [!WARNING]` y el comentario HTML del marcador son sintaxis de
/// GitHub — Markdown de otro proveedor no las entiende igual, algunos ni las
/// entienden — así que un componente que se dijera neutral y las produjera
/// tendría neutralidad falsa. Esta función vive en `forge`, el adapter, y en
/// ningún paquete que otro adapter pudiera importar.
///
/// **Por qué el orden de las secciones no es una elección de estilo.** ADR-016
/// nombra «cubierto» como el peor lugar para una traducción mala: habilita a
/// un revisor a **saltar**. Por eso la advertencia va antes de cualquier
/// sección que se lea como verde, y por eso ninguna sección resume o entierra
/// lo que requiere criterio — cada entrada sale completa, con su motivo y su
/// detalle, nunca como un conteo.
library;

import 'package:core/core.dart';

import 'github.dart' show marcadorEstable;

/// El límite de GitHub para el título de un pull request. Es conocimiento de
/// **este** proveedor — `core` no lo sabe, y no debería: `titulo` en
/// `PullRequestRequest` es texto sin límite de proveedor alguno.
const _longitudMaximaDelTitulo = 256;

/// El título, truncado al límite de GitHub **conservando el prefijo**.
///
/// Si hay que cortar, se corta la intención, nunca la advertencia: un título
/// que perdiera `PullRequestRequest.prefijoIncompleto` por el corte le diría
/// a un revisor que la corrida salió verde cuando no fue así.
String tituloDeGitHub(PullRequestRequest solicitud) {
  final titulo = solicitud.titulo;
  if (titulo.length <= _longitudMaximaDelTitulo) return titulo;

  final prefijo = solicitud.incompleto
      ? PullRequestRequest.prefijoIncompleto
      : '';
  final intencion = titulo.substring(prefijo.length);
  final maximoParaLaIntencion = _longitudMaximaDelTitulo - prefijo.length;
  return '$prefijo${intencion.substring(0, maximoParaLaIntencion)}';
}

/// Cómo se lee, en el cuerpo del PR, cada motivo por el que algo requiere
/// criterio humano. **Traduce el nombre del enum, no lo resume, y no le
/// agrega alcance que el motivo no tiene.**
///
/// La ronda de arreglo 1 encontró exactamente ese segundo error en
/// [MotivoDeCriterio.nadieDioCuenta]: decía «nadie dio cuenta de este
/// sujeto», y el doc comment de ese valor, en `core`, dice que dos de sus
/// tres hechos **no tienen sujeto en absoluto** — el
/// entorno derivado sin ningún control que corriera, o la cascada corrida sin
/// ningún control registrado. Agregarle «de este sujeto» encogía un fallo de
/// la corrida entera a uno acotado a un sujeto puntual: exactamente la
/// traducción tranquilizadora que este archivo existe para no escribir. La
/// entrada que sí tiene sujeto ya lo muestra por separado, en el sufijo
/// `— sujeto \`...\`` que arma [_escribirLoQueRequiereCriterio]; esta prosa no
/// necesita nombrarlo de nuevo, y nombrarlo aquí sería afirmar que siempre
/// hay uno.
///
/// **Las diez ramas, comparadas una por una contra su doc comment en esta
/// ronda de arreglo** (el de cada valor de [MotivoDeCriterio], en `core`):
/// - `hallazgo`: el doc dice que se emite sobre todos los sujetos del paso, o
///   sobre ninguno. «El control encontró algo» no afirma ni una cosa ni la
///   otra, así que no contradice ningún caso — sin cambios.
/// - `declaradoNoMirado`: el doc mismo dice «ese sujeto» — a diferencia de
///   `nadieDioCuenta`, acá el sujeto es parte de la definición, no un agregado
///   de esta traducción — sin cambios.
/// - `nadieDioCuenta`: **el único con un error real.** Decía «nadie dio
///   cuenta de este sujeto»; el doc nombra tres hechos y dos de los tres no
///   tienen sujeto — corregido a «nadie dio cuenta», sin calificador.
/// - `ajenoAlStack`: el doc dice «el sujeto no es de este stack» — siempre
///   hay sujeto en la propia definición — sin cambios.
/// - `noSePudoMirar`, `instrumentoFallo`: la prosa ya calca el doc casi
///   palabra por palabra — sin cambios.
/// - `intentoIncompleto`: paráfrasis («no terminó» por «no llegó a
///   terminar»), mismo alcance que el doc — sin cambios.
/// - `residuoGeneral`: el doc dice «no ata a ningún sujeto» y la prosa lo
///   conserva tal cual — sin cambios.
/// - `entornoNoDerivado`: el doc habla de la cascada entera, nunca de «este
///   sujeto» — «el entorno no se derivó» no le agrega alcance — sin cambios.
/// - `candidatoAlterado`: el doc dice que **ningún** sujeto se puede dar por
///   cubierto — «el candidato se alteró» tampoco nombra un sujeto puntual —
///   sin cambios.
String _nombreDeMotivo(MotivoDeCriterio motivo) => switch (motivo) {
  MotivoDeCriterio.hallazgo => 'el control encontró algo',
  MotivoDeCriterio.declaradoNoMirado => 'el control declaró que no lo miró',
  MotivoDeCriterio.nadieDioCuenta => 'nadie dio cuenta',
  MotivoDeCriterio.ajenoAlStack => 'el sujeto no es de este stack',
  MotivoDeCriterio.noSePudoMirar => 'no se pudo establecer qué era',
  MotivoDeCriterio.intentoIncompleto => 'el control empezó y no terminó',
  MotivoDeCriterio.instrumentoFallo => 'el arnés se rompió',
  MotivoDeCriterio.residuoGeneral => 'residuo que no ata a ningún sujeto',
  MotivoDeCriterio.entornoNoDerivado => 'el entorno no se derivó',
  MotivoDeCriterio.candidatoAlterado => 'el candidato se alteró',
};

/// Las entradas sin sujeto primero: son las que hablan de la corrida entera
/// —el entorno que no se derivó, la cascada que no dejó control registrado—
/// y no de un sujeto puntual, así que preceden a las que sí lo nombran.
/// **Estable**: no reordena las entradas dentro de cada uno de los dos
/// grupos, para no sugerir una prioridad entre ellas que nadie afirmó.
List<EntradaDeCriterio> _sinSujetoPrimero(List<EntradaDeCriterio> entradas) => [
  ...entradas.where((e) => e.sujeto == null),
  ...entradas.where((e) => e.sujeto != null),
];

void _escribirLoQueQuedoCubierto(
  StringBuffer buffer,
  List<AfirmacionCubierta> cubierto,
) {
  buffer.writeln('## Qué quedó cubierto');
  buffer.writeln();
  if (cubierto.isEmpty) {
    buffer.writeln('Ningún sujeto quedó cubierto en esta corrida.');
  } else {
    for (final c in cubierto) {
      // `afirmacion.id` no es `controlId`: un control puede declarar más de
      // una afirmación el día que tenga evidencia por sujeto, así que las
      // dos identidades se muestran, no solo la del control.
      buffer.writeln(
        '- **${c.sujeto}** (control `${c.controlId}`, afirmación '
        '`${c.afirmacion.id}`): ${c.afirmacion.demuestra}. No demuestra: '
        '${c.afirmacion.noDemuestra}.',
      );
    }
  }
  buffer.writeln();
}

void _escribirLoQueRequiereCriterio(
  StringBuffer buffer,
  List<EntradaDeCriterio> requiereCriterio,
) {
  buffer.writeln('## Qué requiere criterio humano');
  buffer.writeln();
  if (requiereCriterio.isEmpty) {
    buffer.writeln('Nada quedó pendiente de criterio humano en esta corrida.');
  } else {
    for (final e in _sinSujetoPrimero(requiereCriterio)) {
      final sujeto = e.sujeto == null ? '' : ' — sujeto `${e.sujeto}`';
      final control = e.controlId == null ? '' : ' — control `${e.controlId}`';
      buffer.writeln(
        '- **${_nombreDeMotivo(e.motivo)}**$sujeto$control: '
        '${e.detalle}',
      );
    }
  }
  buffer.writeln();
}

/// El cuerpo completo del PR. **Arma las secciones en el orden que impone
/// ADR-016** y cierra con [marcadorEstable], que sigue viviendo en el módulo
/// vecino que habla con la API porque la clave de la búsqueda idempotente
/// pertenece a quien busca.
///
/// **Lo que no aparece acá, a propósito**: ninguna ruta del workspace local,
/// ningún campo que el revisor remoto no pueda ver por su cuenta. Todo lo que
/// esta función lee sale de [ArtefactoDeRevision] y de sus tipos —ninguno
/// lleva una ruta de disco—, así que no hay nada que filtrar por accidente
/// mientras esa condición se sostenga.
String cuerpoDeGitHub(PullRequestRequest solicitud) {
  final artefacto = solicitud.draft.artefacto;
  final superficie = artefacto.superficie;
  final buffer = StringBuffer();

  buffer.writeln(artefacto.alcanceDeLoAfirmado);
  buffer.writeln();

  // El título trunca la intención al límite de GitHub (ver
  // `tituloDeGitHub`); acá va completa siempre. Sin esto, un título largo
  // dejaba la intención sin ningún lugar donde el revisor remoto pudiera
  // leerla entera — el JSON de la corrida es local y `git` lo ignora, así
  // que el cuerpo del PR es la única superficie que le queda.
  buffer.writeln('## Intención');
  buffer.writeln();
  buffer.writeln(artefacto.intent);
  buffer.writeln();

  if (solicitud.incompleto) {
    // Antes de cualquier cosa que se lea como verde: es la advertencia
    // obligatoria de ADR-016, y por eso no espera a las secciones de abajo.
    buffer.writeln('> [!WARNING]');
    buffer.writeln(
      '> La superficie de verificación no salió verde '
      '(`${superficie.estado.name}`). Lo que sigue certifica solo lo que '
      'cada afirmación cubierta dice, sujeto por sujeto — no el cambio '
      'entero.',
    );
    buffer.writeln();
  }

  _escribirLoQueQuedoCubierto(buffer, superficie.cubierto);
  _escribirLoQueRequiereCriterio(buffer, superficie.requiereCriterio);

  if (artefacto.plan != null) {
    buffer.writeln('## Plan');
    buffer.writeln();
    buffer.writeln(artefacto.plan);
  } else {
    // Presente si y solo si no hay plan: sin esto, un artefacto sin plan
    // afirmaría por omisión que no hacía falta ninguno.
    buffer.writeln('## Por qué no hay plan');
    buffer.writeln();
    buffer.writeln(artefacto.sinPlanPorque);
  }
  buffer.writeln();

  buffer.writeln(marcadorEstable(solicitud));

  return buffer.toString();
}
