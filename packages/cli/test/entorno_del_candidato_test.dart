/// **La prueba decisiva**: un error inyectado SOLO en el candidato produce un
/// diagnóstico que apunta al candidato, el repositorio real no cambia, y el
/// candidato sigue íntegro después de la cascada.
///
/// `cli` es el único paquete que ve `vcs` y `plugin_dart` a la vez, y por eso la
/// composición vive acá, **en una prueba**: todavía no hay coordinador
/// productivo —`Cascada.correr` deriva su estado del desenlace de los pasos y no
/// tiene dónde meter «el entorno no se pudo derivar»— y eso está declarado en
/// `arquitectura.json` y en el README, no insinuado.
library;

import 'dart:io';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:orchestration/orchestration.dart';
import 'package:plugin_dart/plugin_dart.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

class _TodoEsFuente implements ArtifactPolicy {
  const _TodoEsFuente();
  @override
  bool isGenerated(String path) => false;
  @override
  bool isEditable(String path) => path.trim().isNotEmpty;
}

const presupuesto = Duration(minutes: 3);

/// La composición que una rebanada futura va a volver productiva: preparar,
/// derivar, comprobar la integridad, correr la cascada, comprobar otra vez.
///
/// Escrita una vez acá para que la regla «una alteración hace la corrida no
/// concluyente, nunca roja» tenga dónde probarse. Deja en [medidas] cuánto tardó
/// cada control.
Future<EstadoDeCorrida> verificarCandidato(
  PreparedCandidate c, {
  required List<String> archivos,
  required List<String> sujetos,
  required Map<String, Duration> medidas,
  void Function()? entreCascadaYControl,
}) async {
  final reloj = Stopwatch()..start();
  final entorno = await const EntornoDart().derivar(
    c.root,
    archivos: archivos,
    presupuesto: presupuesto,
  );
  medidas['derivar'] = reloj.elapsed;
  // Las dos variantes que no son `EntornoDerivado` hacen la corrida no
  // concluyente: no se puede afirmar nada sobre un árbol que no se pudo dejar
  // en condiciones de ser medido.
  if (entorno is! EntornoDerivado) return EstadoDeCorrida.noConcluyente;

  reloj.reset();
  final antes = await c.alteraciones();
  medidas['integridad'] = reloj.elapsed;
  if (antes.isNotEmpty) return EstadoDeCorrida.noConcluyente;

  final resultado = await cascadaPorDefecto(
    directorio: c.root,
    presupuesto: presupuesto,
  ).correr(sujetos);

  entreCascadaYControl?.call();

  // **Y otra vez después.** Nada le impide a un verificador escribir en el
  // workspace: corren herramientas ajenas sobre un directorio escribible.
  if ((await c.alteraciones()).isNotEmpty) return EstadoDeCorrida.noConcluyente;
  return resultado.estado;
}

void main() {
  late Directory raiz;
  late RepositorioGit repo;

  String git(List<String> args) {
    final r = Process.runSync('git', args, workingDirectory: raiz.path);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(" ")} → ${r.exitCode}: ${r.stderr}');
    }
    return (r.stdout as String).trim();
  }

  void escribir(String ruta, String contenido) {
    final f = File('${raiz.path}/$ruta');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(contenido);
  }

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('decisiva_');
    // La forma de este repositorio, mínima: raíz de workspace con un miembro, y
    // un manifiesto que NO es miembro y que la rebanada no va a tocar.
    escribir(
      'pubspec.yaml',
      'name: ws\nenvironment:\n  sdk: ^3.11.0\nworkspace:\n  - packages/a\n',
    );
    escribir(
      'packages/a/pubspec.yaml',
      'name: a\nenvironment:\n  sdk: ^3.11.0\nresolution: workspace\n',
    );
    escribir('packages/a/lib/a.dart', 'int sano() => 1;\n');
    escribir('tool/x/pubspec.yaml', 'name: x\nenvironment:\n  sdk: ^3.11.0\n');
    escribir('tool/x/lib/x.dart', 'int otro() => 2;\n');

    // El lockfile se fija UNA vez y se versiona; lo generado, no. Es lo que
    // hace del fixture un candidato y no un árbol de trabajo.
    final r = Process.runSync('dart', [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: raiz.path);
    if (r.exitCode != 0) {
      throw StateError('no pude fijar el lockfile: ${r.stderr}');
    }
    for (final e in Directory(raiz.path).listSync(recursive: true)) {
      if (e is Directory && e.path.endsWith('.dart_tool')) {
        e.deleteSync(recursive: true);
      }
    }

    git(['init', '--initial-branch=main', '.']);
    git(['config', 'user.email', 'p@p']);
    git(['config', 'user.name', 'prueba']);
    git(['add', '-A']);
    git(['commit', '-m', 'base']);
    repo = RepositorioGit(
      directorio: raiz.path,
      politica: const _TodoEsFuente(),
    );
  });
  tearDown(() => raiz.deleteSync(recursive: true));

  PullRequestSlice rebanada(String intent, List<String> files) =>
      PullRequestSlice(id: 'r1', intent: intent, files: files);

  test('el error inyectado se ve en el candidato, y el repositorio real no '
      'cambia', () async {
    escribir(
      'packages/a/lib/a.dart',
      "int sano() => 1;\nint roto = 'no soy un int';\n",
    );
    final antes = git(['status', '--porcelain']);
    final c = await repo.prepareCandidate(
      rebanada('romper a propósito', ['packages/a/lib/a.dart']),
    );
    try {
      final entorno = await const EntornoDart().derivar(
        c.root,
        archivos: ['packages/a/lib/a.dart'],
        presupuesto: presupuesto,
      );
      expect(entorno, isA<EntornoDerivado>(), reason: '$entorno');
      expect(
        (entorno as EntornoDerivado).raices,
        1,
        reason: 'tool/x no se toca: no existe para esta rebanada',
      );
      expect(Directory('${c.root}/tool/x/.dart_tool').existsSync(), isFalse);
      expect(await c.alteraciones(), isEmpty);

      final resultado = await cascadaPorDefecto(
        directorio: c.root,
        presupuesto: presupuesto,
      ).correr(['packages/a/lib']);
      expect(resultado.estado, EstadoDeCorrida.rojo);

      final diagnosticos = [
        for (final d in resultado.desenlaces.values)
          if (d is Executed) ...d.diagnostics,
      ];
      expect(diagnosticos, isNotEmpty);
      for (final d in diagnosticos) {
        expect(
          d.file,
          contains(c.root),
          reason: 'el diagnóstico apunta al candidato, no al árbol del usuario',
        );
      }

      expect(
        await c.alteraciones(),
        isEmpty,
        reason: 'la cascada no escribió en el candidato',
      );
      expect(
        git(['status', '--porcelain']),
        antes,
        reason: 'el repositorio real sigue exactamente igual',
      );
      expect(
        Directory('${raiz.path}/.dart_tool').existsSync(),
        isFalse,
        reason: 'la derivación escribió en el candidato, no en el árbol real',
      );
    } finally {
      await c.dispose();
    }
  });

  test(
    'la integridad y la derivación caben en su presupuesto, y se registran',
    () async {
      escribir('packages/a/lib/a.dart', 'int sano() => 2;\n');
      final c = await repo.prepareCandidate(
        rebanada('medir', ['packages/a/lib/a.dart']),
      );
      final medidas = <String, Duration>{};
      try {
        final estado = await verificarCandidato(
          c,
          archivos: ['packages/a/lib/a.dart'],
          sujetos: ['packages/a/lib'],
          medidas: medidas,
        );
        expect(estado, EstadoDeCorrida.verde);
        // **El techo es la aserción; la cifra, el dato.** Es medición registrada
        // sobre ESTE árbol, no evidencia sobre un monorepo: el costo del control
        // de integridad y de la derivación en un repositorio grande sigue siendo
        // una pregunta abierta, y esto no la contesta — la acota.
        expect(medidas['derivar'], lessThan(presupuesto));
        expect(medidas['integridad'], lessThan(presupuesto));
        print(
          'medido acá · derivar ${medidas['derivar']!.inMilliseconds} ms · '
          'integridad ${medidas['integridad']!.inMilliseconds} ms',
        );
      } finally {
        await c.dispose();
      }
    },
  );

  test('una alteración DESPUÉS de la cascada da no concluyente, aunque la '
      'cascada haya dado rojo', () async {
    escribir(
      'packages/a/lib/a.dart',
      "int sano() => 1;\nint roto = 'no soy un int';\n",
    );
    final c = await repo.prepareCandidate(
      rebanada('alterar', ['packages/a/lib/a.dart']),
    );
    try {
      final estado = await verificarCandidato(
        c,
        archivos: ['packages/a/lib/a.dart'],
        sujetos: ['packages/a/lib'],
        medidas: {},
        entreCascadaYControl: () => File(
          '${c.root}/packages/a/pubspec.yaml',
        ).writeAsStringSync('name: otro\n'),
      );
      expect(estado, EstadoDeCorrida.noConcluyente);
      expect(
        estado,
        isNot(EstadoDeCorrida.rojo),
        reason:
            'la cascada dio rojo, y no se puede afirmar ni eso sobre un árbol '
            'que dejó de ser el que se fijó',
      );
    } finally {
      await c.dispose();
    }
  });
}
