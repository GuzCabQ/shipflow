/// `vcs` — rama, commits y PR. **Agnóstico del lenguaje, del agente y de la
/// forja.**
///
/// Lo primero y lo segundo los sostienen reglas de arquitectura. Lo tercero lo
/// sostiene el corte entre `ChangeSink` —local, `git`— y `PullRequestSink`
/// —remoto, un proveedor—: acá vive solo el primero.
library;

export 'src/repositorio.dart';
export 'src/secretos.dart';
