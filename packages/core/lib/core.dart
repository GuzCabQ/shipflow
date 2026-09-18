/// `core` — entidades y puertos del arnés. **Cero dependencias.**
///
/// Este paquete no importa nada: ni del ecosistema, ni de otro paquete del
/// workspace. Es la condición que hace que todas las flechas apunten acá y que
/// un check verifica en cada corrida (`nucleo-sin-externas`).
///
/// Qué hay adentro:
///
/// - **valores** — enums y objetos de valor, incluidos [QuotedText] y [Witness].
/// - **entidades** — el dato del dominio.
/// - **regla** — [Rule] y sus requisitos de instalación, y [Afirmacion]: qué
///   demuestra un control cuando ejecuta limpio, y qué NO.
/// - **observación** — trazas y hallazgos inferenciales.
/// - **desenlace** — el desenlace de un paso: [StepOutcome] sellado, y el
///   subconjunto propio [VerificationOutcome] que un verificador devuelve.
/// - **credencial** — [Credential], el único tipo que no serializa.
/// - **entorno** — [entornoSaneado], la lista blanca con la que se lanza
///   todo subproceso.
/// - **publicación** — el desenlace de la publicación: [PublicationOutcome]
///   sellado, con `retryable`, [EstadoDeEntrega] y [AccionSiguiente]
///   derivados de la variante y su [CausaDePublicacion]; y [esOidCompleto],
///   la única definición de qué es una revisión empujable, que el dominio
///   exige al construir la solicitud y el adapter vuelve a exigir antes de
///   lanzar el proceso.
/// - **puertos** — solo interfaces. `core` no implementa ninguno; quién lo
///   hace y cuáles siguen sin implementación está declarado en
///   `arquitectura.json`, y verificado en los dos sentidos.
/// - **superficie** — qué quedó cubierto y qué requiere criterio humano:
///   [AfirmacionCubierta], que solo se construye por su fábrica,
///   [EntradaDeCriterio] con su [MotivoDeCriterio] cerrado, la
///   [SuperficieDeVerificacion] que las junta con el estado de la corrida, y
///   el [ArtefactoDeRevision] que le pone identidad y alcance para publicarla.
library;

export 'src/alcance.dart';
export 'src/credencial.dart';
export 'src/desenlace.dart';
export 'src/entidades.dart';
export 'src/entorno.dart';
export 'src/observacion.dart';
export 'src/publicacion.dart';
export 'src/puertos.dart';
export 'src/regla.dart';
export 'src/superficie.dart';
export 'src/valores.dart';
