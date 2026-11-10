@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';
import 'support/store_spy_support.dart';

/// Un shim de Git que anota cada invocación en [log]. Con [falla], falla desde
/// la segunda consulta de versión, como `gitFailingAfterObservation`.
String _shim(ServiceSandbox box, String log, {required bool falla}) {
  final dir = Directory('${box.base.path}/shim-${falla ? 'falla' : 'sano'}')
    ..createSync();
  final seen = '${dir.path}/visto';
  final fallo = falla
      ? 'case " \$* " in *" --version "*)\n'
            '  if [ -f "$seen" ]; then exit 128; fi\n'
            '  : > "$seen" ;;\n'
            'esac\n'
      : '';
  File('${dir.path}/git').writeAsStringSync(
    '#!/bin/sh\n'
    'echo "git \$*" >> "$log"\n'
    '$fallo'
    'exec /usr/bin/git "\$@"\n',
  );
  Process.runSync('/bin/chmod', ['+x', '${dir.path}/git']);
  return dir.path;
}

/// Lo que se observa de la segunda invocación, sin plan, con Git que falla.
typedef _Ventana = ({
  int exitCode,
  List<String> codigos,
  int aperturas,
  int cierres,
  int gitEnVentana,
  int gitTrasCierre,
});

/// Cuenta la ventana de administración de un [tramo] del log.
_Ventana _contar(int exitCode, List<String> codigos, List<String> tramo) {
  final apertura = tramo.indexOf('open admin');
  final cierre = tramo.indexOf('close admin');
  bool esGit(String l) => l.startsWith('git ');
  return (
    exitCode: exitCode,
    codigos: codigos,
    aperturas: tramo.where((l) => l == 'open admin').length,
    cierres: tramo.where((l) => l == 'close admin').length,
    gitEnVentana: apertura < 0 || cierre < 0
        ? 0
        : tramo.sublist(apertura + 1, cierre).where(esGit).length,
    gitTrasCierre: cierre < 0
        ? 0
        : tramo.sublist(cierre + 1).where(esGit).length,
  );
}

const _marca = '--- segunda invocación: plan nulo con Git que falla';

void _anotar(String log, String linea) =>
    File(log).writeAsStringSync('$linea\n', mode: FileMode.append);

/// La segunda invocación, sin plan y con Git que falla al corroborar.
Future<ContextOperationResult> _segundaSinPlan(
  ServiceSandbox box,
  String log,
  Map<String, String> git,
  AdminSpies spies,
) {
  _anotar(log, _marca);
  final cerrar = spies.opener(onClose: () async => _anotar(log, 'close admin'));
  return box.run(
    ContextOperation.init,
    sharing: SharingChoice.local,
    git: git,
    openAdministration: (dir) async {
      _anotar(log, 'open admin');
      return cerrar(dir);
    },
  );
}

/// Corre init sin plan y cuenta lo que ocurre entre la apertura y el cierre
/// de la administración en la segunda invocación.
Future<_Ventana> _ventanaSinPlan(ServiceSandbox box) async {
  final log = '${box.base.path}/orden.log';
  final git = {
    'PATH': _shim(box, log, falla: true),
    'HOME': Platform.environment['HOME']!,
  };
  final spies = AdminSpies();
  try {
    await box.run(
      ContextOperation.init,
      sharing: SharingChoice.local,
      git: box.realGit,
      openAdministration: spies.opener(),
    );
    final second = await _segundaSinPlan(box, log, git, spies);
    final lineas = File(log).readAsLinesSync();
    return _contar(second.exitCode, [
      for (final d in second.diagnostics) d.code,
    ], lineas.sublist(lineas.indexOf(_marca) + 1));
  } finally {
    await spies.dispose();
  }
}

void main() {
  late ServiceSandbox box;
  setUp(() {
    box = ServiceSandbox.create()
      ..project()
      ..gitInit();
  });
  tearDown(() => box.dispose());

  test(
    'caso sin plan: la comprobación Git del plan nulo ocurre entre la apertura y el cierre, una vez',
    () async {
      final v = await _ventanaSinPlan(box);
      expect(v.exitCode, 65);
      expect(v.codigos, contains('git_unavailable'));
      expect(v.aperturas, 1, reason: 'el plan nulo abre administración');
      expect(v.cierres, 1, reason: 'un único cierre');
      expect(
        v.gitEnVentana,
        greaterThan(0),
        reason: 'la comprobación del plan nulo corre antes del cierre',
      );
      expect(
        v.gitTrasCierre,
        0,
        reason: 'ninguna llamada Git después del cierre',
      );
    },
  );

  test(
    'processesStarted coincide con las llamadas Git de la misma invocación',
    () async {
      final log = '${box.base.path}/git.log';
      final git = {
        'PATH': _shim(box, log, falla: false),
        'HOME': Platform.environment['HOME']!,
      };
      for (final sharing in [SharingChoice.local, SharingChoice.share]) {
        File(log).writeAsStringSync('');
        final r = await box.run(
          ContextOperation.init,
          sharing: sharing,
          git: git,
        );
        final llamadas = File(
          log,
        ).readAsLinesSync().where((l) => l.startsWith('git')).length;
        expect(r.exitCode, 0, reason: sharing.name);
        expect(r.effects.processesStarted, llamadas, reason: sharing.name);
      }
    },
  );

  test(
    'dos invocaciones consecutivas no arrastran resultados ni efectos',
    () async {
      final first = await box.run(
        ContextOperation.init,
        sharing: SharingChoice.local,
        git: box.realGit,
      );
      final second = await box.run(
        ContextOperation.init,
        sharing: SharingChoice.local,
        git: box.realGit,
      );
      expect(first.exitCode, 0);
      expect(second.exitCode, 0);
      expect(second.diagnostics.where((d) => d.code == 'initialized'), isEmpty);
      expect(second.effects.filesCreated, isEmpty);
    },
  );
}
