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
/// - **regla** — [Rule] y sus requisitos de instalación.
/// - **observación** — trazas, hallazgos inferenciales y resultados.
/// - **credencial** — [Credential], el único tipo que no serializa.
/// - **puertos** — solo interfaces. `core` no implementa ninguno; quién lo
///   hace y cuáles siguen sin implementación está declarado en
///   `arquitectura.json`, y verificado en los dos sentidos.
library;

export 'src/alcance.dart';
export 'src/credencial.dart';
export 'src/entidades.dart';
export 'src/observacion.dart';
export 'src/puertos.dart';
export 'src/regla.dart';
export 'src/valores.dart';
