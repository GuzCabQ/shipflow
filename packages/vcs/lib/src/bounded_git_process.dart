import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

/// El cupo de Git de una operación: a lo sumo 12 procesos y 20 segundos
/// de ejecución acumulada, compartidos por todas sus consultas. El tiempo
/// entre consultas no consume el cupo.
final class GitBudget {
  GitBudget({this.maxProcesses = 12, this.total = const Duration(seconds: 20)});

  final int maxProcesses;
  final Duration total;
  var _started = 0;
  var _elapsed = Duration.zero;

  /// Los intentos admitidos, aunque el proceso no llegue a arrancar.
  int get started => _started;

  Duration get remaining => total - _elapsed;

  /// Admite y reserva un intento, sin esperar nada entre decidir y contar:
  /// devuelve su plazo, el menor entre [perProcess] y lo que queda, o null si
  /// no hay cupo de procesos o de tiempo.
  Duration? _admit(Duration perProcess) {
    final deadline = perProcess < remaining ? perProcess : remaining;
    if (_started >= maxProcesses || deadline <= Duration.zero) return null;
    _started++;
    return deadline;
  }

  void _charge(Duration elapsed) => _elapsed += elapsed;
}

/// Lo que devolvió una consulta, o por qué se cortó: `git_timeout`,
/// `git_output_limit`, `git_budget` o `git_start`.
final class GitCommandResult {
  const GitCommandResult(this.exitCode, this.stdout, this.stderr, [this.cut]);

  const GitCommandResult.cut(String this.cut)
    : exitCode = -1,
      stdout = const [],
      stderr = const [];

  final int exitCode;
  final List<int> stdout;
  final List<int> stderr;
  final String? cut;
}

/// Opciones que preceden a toda consulta: sin locks opcionales y sin
/// fsmonitor ni caché de no seguidos, que ejecutarían o escribirían por su
/// cuenta. Las rutas literales se piden por comando: `check-ignore` recibe
/// rutas, no pathspecs, y rechaza esa opción.
const _globalOptions = [
  '--no-optional-locks',
  '-c',
  'core.fsmonitor=false',
  '-c',
  'core.untrackedCache=false',
];

/// Un proceso Git acotado: ejecutable absoluto, argumentos en lista sin
/// shell, entorno saneado, plazo y salida máximos, y el cupo de [budget].
final class BoundedGitProcess {
  BoundedGitProcess({
    required this.executable,
    required this.parentEnvironment,
    required this.budget,
    this.perProcess = const Duration(seconds: 5),
    this.maxOutputBytes = 1048576,
  });

  final String executable;
  final Map<String, String> parentEnvironment;
  final GitBudget budget;
  final Duration perProcess;
  final int maxOutputBytes;

  Future<GitCommandResult> run(
    List<String> args, {
    required Directory cwd,
    List<int>? input,
  }) async {
    final deadline = budget._admit(perProcess);
    if (deadline == null) return const GitCommandResult.cut('git_budget');
    final clock = Stopwatch()..start();
    try {
      final process = await Process.start(
        executable,
        [..._globalOptions, ...args],
        workingDirectory: cwd.path,
        environment: entornoSaneado(
          parentEnvironment,
          propias: _ownVariables(parentEnvironment),
        ),
        includeParentEnvironment: false,
      );
      return await _collect(process, input, deadline - clock.elapsed);
    } on ProcessException {
      return const GitCommandResult.cut('git_start');
    } finally {
      budget._charge(clock.elapsed);
    }
  }

  /// Lee hasta que el proceso termina y sus tuberías se cierran, nunca más
  /// allá de [deadline]: un nieto que retiene la tubería no alarga la espera.
  Future<GitCommandResult> _collect(
    Process process,
    List<int>? input,
    Duration deadline,
  ) async {
    final output = _BoundedOutput(maxOutputBytes, process)..listen();
    if (input != null) process.stdin.add(input);
    unawaited(process.stdin.close().catchError((Object _) {}));
    final clock = Stopwatch()..start();
    final timer = Timer(deadline, () => output.cutBy('git_timeout'));
    final exitCode = await process.exitCode;
    timer.cancel();
    await output.drain(deadline - clock.elapsed);
    if (output.cut case final cut?) return GitCommandResult.cut(cut);
    return GitCommandResult(
      exitCode,
      output.out.takeBytes(),
      output.err.takeBytes(),
    );
  }
}

/// Lo que esta consulta necesita y no hereda: sin preguntas, sin locks
/// opcionales y mensajes estables; la configuración del usuario sólo se
/// ubica por `HOME` o `XDG_CONFIG_HOME`, para respetar sus reglas de ignore.
Map<String, String> _ownVariables(Map<String, String> parent) => {
  'GIT_TERMINAL_PROMPT': '0',
  'GIT_OPTIONAL_LOCKS': '0',
  'LC_ALL': 'C',
  if (parent['XDG_CONFIG_HOME'] case final xdg?) 'XDG_CONFIG_HOME': xdg,
};

/// La salida de un proceso hasta [max] bytes entre stdout y stderr: el
/// primer trozo que no cabe corta y termina el proceso.
final class _BoundedOutput {
  _BoundedOutput(this.max, this.process);

  final int max;
  final Process process;
  final out = BytesBuilder(copy: false);
  final err = BytesBuilder(copy: false);
  final _closed = [Completer<void>(), Completer<void>()];
  final _subscriptions = <StreamSubscription<List<int>>>[];
  String? cut;

  /// Escucha las dos tuberías; su cierre se registra desde ya, aunque
  /// ocurra antes de que alguien lo espere.
  void listen() {
    for (final (i, stream) in [process.stdout, process.stderr].indexed) {
      _subscriptions.add(
        stream.listen(
          (chunk) => _add(i == 0 ? out : err, chunk),
          onDone: _closed[i].complete,
          onError: (Object _) => _closed[i].complete(),
          cancelOnError: true,
        ),
      );
    }
  }

  /// Espera el cierre de las tuberías a lo sumo [left]; después las suelta.
  Future<void> drain(Duration left) async {
    if (cut == null && left > Duration.zero) {
      await Future.wait([for (final c in _closed) c.future]).timeout(
        left,
        onTimeout: () {
          cutBy('git_timeout');
          return const [];
        },
      );
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }

  void cutBy(String why) {
    cut ??= why;
    process.kill(ProcessSignal.sigkill);
  }

  void _add(BytesBuilder into, List<int> chunk) {
    if (cut != null) return;
    if (out.length + err.length + chunk.length > max) {
      return cutBy('git_output_limit');
    }
    into.add(chunk);
  }
}
