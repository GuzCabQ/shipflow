/// **Un instrumento de medición de la suite, no un comando del producto.**
///
/// Vive en `bin/` y no en `test/` por dos motivos, los dos del arnés: un
/// archivo de `test/` que ninguna suite importa es un huérfano para el grafo,
/// y nombrar su ruta desde la suite obliga a escribir la extensión de los
/// archivos fuente, que la regla que acota el nombre del lenguaje a su plugin
/// y al composition root caza con razón. Como ejecutable del paquete se corre
/// por su NOMBRE, sin ruta ni extensión, y el grafo lo alcanza porque todo
/// ejecutable de `bin/` es un punto de entrada por convención.
///
/// Nadie lo compone en ningún flujo: lo único que lo invoca son las suites de
/// este paquete, bajo `packages/forge/test/`.
///
/// **Dos modos, porque son dos salidas distintas del proceso hacia afuera** y
/// las dos tenían el mismo defecto: un futuro abandonado que deja algo
/// abierto. `empuje` corre un `empujar` contra el programa que se le pase;
/// `forja` corre un `open` contra una URL que contesta encabezados y nunca
/// cierra el cuerpo. En los dos casos **vuelve de `main` sin llamar a
/// `exit`**, igual que el ejecutable del comando bajo
/// `packages/cli/bin/`, que fija `exitCode` y vuelve a propósito. Esa es toda la gracia: un proceso
/// que vuelve de `main` sigue vivo mientras le quede trabajo pendiente —una
/// suscripción a una tubería, por ejemplo—, así que CUÁNDO TERMINA ESTE
/// PROCESO es la medición que la suite no puede hacer desde adentro de sí
/// misma.
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';

Future<void> main(List<String> argumentos) async {
  final modo = argumentos.first;
  final desenlace = switch (modo) {
    'empuje' => await _medirElEmpuje(argumentos.sublist(1)),
    'forja' => await _medirLaForja(argumentos.sublist(1)),
    _ => throw ArgumentError.value(modo, 'modo', 'no es «empuje» ni «forja»'),
  };

  // El tipo del desenlace. No sale nada más: lo que se mide afuera es cuánto
  // tarda este proceso en terminar DESPUÉS de esta línea.
  stdout.writeln('desenlace=${desenlace.runtimeType}');
}

/// El camino del subproceso: `git push` contra un programa que se cuelga o
/// que deja un nieto con la tubería heredada.
Future<Object> _medirElEmpuje(List<String> argumentos) async {
  final [directorio, programa, revision, urlDelRemoto] = argumentos;

  final empuje = EmpujeAislado(
    directorio: directorio,
    entornoDelPadre: EntornoDelProceso({
      'PATH': Platform.environment['PATH'] ?? '',
    }),
    programa: programa,
    presupuesto: const Duration(milliseconds: 300),
  );

  return empuje.empujar(
    urlDelRemoto: urlDelRemoto,
    credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
    revision: revision,
    rama: 'rebanada-1',
  );
}

/// El camino de la red: un `open` contra una URL que manda encabezados y no
/// cierra el cuerpo nunca.
///
/// Los `.timeout(...)` de ese archivo hacen que `open` DEVUELVA a tiempo y no
/// cierran el socket —abandonan el futuro, que es lo mismo que hacía el
/// drenaje del empuje antes de soltarse—. Lo que lo cierra es una sola línea,
/// el `close(force: true)` del `finally`, y esto es lo que la pincha: sin
/// ella el proceso queda vivo hasta que el otro lado suelte el socket.
Future<Object> _medirLaForja(List<String> argumentos) async {
  final [base, revision, arbol] = argumentos;

  final salida = SalidaDePrDeGitHub(
    configuracion: ConfiguracionDeGitHub(
      duenio: 'duenio',
      repositorio: 'repo',
      baseDeLaApi: Uri.parse(base),
      urlDelRemoto: '\$base/duenio/repo.git',
    ),
    credenciales: const _CredencialFija(),
    empuje: EmpujeAislado(
      directorio: Directory.systemTemp.path,
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH'] ?? '',
      }),
      programa: 'true',
    ),
    presupuestoDeRed: const Duration(milliseconds: 200),
  );

  return salida.open(
    PullRequestRequest(
      draft: PullRequestDraft(
        runId: 'corrida-1',
        branch: 'rama-1',
        base: 'main',
        artefacto: ArtefactoDeRevision(
          superficie: SuperficieDeVerificacion(
            cubierto: const [],
            requiereCriterio: const [],
            estado: EstadoDeCorrida.verde,
          ),
          candidato: CandidateIdentity(
            contentRevision: arbol,
            baseRevision: 'base-1',
          ),
          intent: 'medir cuándo termina el proceso',
          plan: null,
          sinPlanPorque: 'no hay elementos de trabajo',
          alcanceDeLoAfirmado: ArtefactoDeRevision.alcanceSoloPR,
        ),
      ),
      revision: revision,
      arbolDeLaRevision: arbol,
    ),
  );
}

/// La credencial de la medición. No se lee de ningún lado: este programa no
/// es un comando y no tiene que descubrir nada del entorno.
class _CredencialFija implements CredentialSource {
  const _CredencialFija();

  @override
  Future<Credential?> read(String key) async =>
      const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN');
}
