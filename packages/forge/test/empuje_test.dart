import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporal;
  late HttpServer servidor;
  final autorizaciones = <String?>[];

  setUp(() async {
    temporal = await Directory.systemTemp.createTemp('forge-empuje-');
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor.listen((pedido) async {
      autorizaciones.add(pedido.headers.value('authorization'));
      pedido.response.statusCode = HttpStatus.unauthorized;
      pedido.response.headers.set('WWW-Authenticate', 'Basic realm="x"');
      await pedido.response.close();
    });

    // Un HOME con un credential helper que deja rastro si corre.
    final casa = Directory('${temporal.path}/casa')..createSync();
    File('${casa.path}/.gitconfig').writeAsStringSync('''
[user]
\tname = t
\temail = t@t
[credential]
\thelper = "!f() { echo corrio > ${temporal.path}/helper-corrio; echo username=x; echo password=y; }; f"
''');

    // Un repositorio con un commit y un pre-push que deja rastro si corre.
    final trabajo = Directory('${temporal.path}/trabajo')..createSync();
    Future<void> git(List<String> args) async {
      final r = await Process.run(
        'git',
        args,
        workingDirectory: trabajo.path,
        environment: {'PATH': Platform.environment['PATH']!, 'HOME': casa.path},
        includeParentEnvironment: false,
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    await git(['init', '-q']);
    File('${trabajo.path}/a.txt').writeAsStringSync('a');
    await git(['add', 'a.txt']);
    await git(['commit', '-qm', 'a']);
    File('${trabajo.path}/.git/hooks/pre-push').writeAsStringSync(
      '#!/bin/sh\necho corrio > ${temporal.path}/gancho-corrio\n',
    );
    await Process.run('chmod', ['+x', '${trabajo.path}/.git/hooks/pre-push']);
  });

  tearDown(() async {
    await servidor.close(force: true);
    await temporal.delete(recursive: true);
    autorizaciones.clear();
  });

  test('la credencial llega al remoto y no al código del usuario', () async {
    final casa = '${temporal.path}/casa';
    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': casa,
      }),
    );

    final r = await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
      credencial: const Credential(
        'ghp_secreto',
        label: 'SHIPFLOW_GITHUB_TOKEN',
      ),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );

    // El remoto vio la credencial: llegó por el canal que elegimos.
    expect(autorizaciones.whereType<String>(), isNotEmpty);

    // Y nadie más la vio.
    expect(
      File('${temporal.path}/helper-corrio').existsSync(),
      isFalse,
      reason: 'el credential.helper del usuario no debe correr',
    );
    expect(
      File('${temporal.path}/gancho-corrio').existsSync(),
      isFalse,
      reason: 'el pre-push del usuario no debe correr',
    );

    // El servidor no es una forja: el push no puede terminar bien, y eso se
    // reporta como desenlace, no como excepción.
    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace, isA<PushFailed>());
    expect((r.desenlace as PushFailed).causa, CausaDePublicacion.autenticacion);
    expect((r.desenlace as PushFailed).safeReason, isNot(contains('ghp_')));
  });

  test('un remoto que no existe es red, y es reintentable', () async {
    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      }),
    );
    final r = await empuje.empujar(
      // Puerto cerrado a propósito.
      urlDelRemoto: 'http://127.0.0.1:1/x.git',
      credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );
    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace.retryable, isTrue);
  });

  test('un programa ausente no expone la credencial en ningún texto del '
      'desenlace', () async {
    const secreto = 'ghp_no_debe_aparecer_jamas';
    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      }),
      // No existe: fuerza el `ProcessException` que `empujar` atrapa antes
      // de que `git` llegue a lanzarse siquiera.
      programa: '${temporal.path}/no-existe-como-ejecutable',
    );

    final r = await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
      credencial: const Credential(secreto, label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );

    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace, isA<PushUnknown>());

    // `ProcessException` de un programa ausente lleva `destino` —la URL
    // con la credencial en el `userinfo`— en `.arguments`, y su
    // `toString()` la interpola verbatim. Esta es la comprobación de que
    // ese texto nunca sale de `empujar`: lo único que sobrevive es la
    // causa cerrada.
    expect(jsonEncode(r.desenlace.toJson()), isNot(contains(secreto)));
    expect(r.desenlace.toString(), isNot(contains(secreto)));
  });

  test('la forja que responde 403 clasifica como permisos', () async {
    // Servidor propio: el compartido de este archivo siempre responde 401
    // para la prueba de autenticación, y acá hace falta un código distinto.
    final servidor403 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    servidor403.listen((pedido) async {
      pedido.response.statusCode = HttpStatus.forbidden;
      await pedido.response.close();
    });
    addTearDown(() => servidor403.close(force: true));

    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      }),
    );
    final r = await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor403.port}/x.git',
      credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );

    // Real: `git push` contra un servidor que responde 403 sin cuerpo
    // termina con «fatal: unable to access '...': The requested URL
    // returned error: 403» — capturado corriendo `git push` a mano contra un
    // servidor HTTP que solo devuelve 403, no inventado.
    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace, isA<PushFailed>());
    expect((r.desenlace as PushFailed).causa, CausaDePublicacion.permisos);
  });

  test(
    'el clasificador reconoce un push rechazado por no ser fast-forward',
    () {
      // Texto real de `git push`, capturado empujando dos veces a un bare
      // local que había avanzado por otra rama clonada entre medio — no
      // inventado. Se prueba contra el clasificador y no de punta a punta
      // porque reproducir un rechazo así por HTTP necesitaría un backend
      // `git-http-backend` de verdad, y el texto que importa —el que decide
      // la causa— es el mismo sin importar el transporte.
      const stderr = '''
To /tmp/remoto.git
 ! [rejected]        HEAD -> main (fetch first)
error: failed to push some refs to '/tmp/remoto.git'
hint: Updates were rejected because the remote contains work that you do not
hint: have locally. This is usually caused by another repository pushing to
hint: the same ref. If you want to integrate the remote changes, use
hint: 'git pull' before pushing again.
hint: See the 'Note about fast-forwards' in 'git push --help' for details.
''';
      expect(
        EmpujeAislado.causaDeParaLaPrueba(stderr),
        CausaDePublicacion.rechazoDeLaForja,
      );
    },
  );

  test('el lanzamiento del push no entrega al hijo nada fuera de la lista '
      'blanca', () async {
    // Mismo patrón que el grupo «el único lanzamiento sin sanear tampoco ve
    // la credencial» de la suite de `RepositorioGit` en `vcs`: en vez de
    // `git`,
    // un espía que vuelca su propio entorno. Esto observa lo que
    // `Process.run` recibió de verdad en `environment:`, así que si
    // alguien sacara el `entornoSaneado(...)` del call site y pasara
    // `entornoDelPadre.paraHijos` directo, esta prueba lo notaría: esa
    // variable de más no viene de la credencial —`paraHijos` ya la
    // despoja— sino de una que la lista blanca de `entornoSaneado` no deja
    // pasar y `paraHijos` sí reenviaría.
    final espia = File('${temporal.path}/espia.sh');
    await espia.writeAsString(
      '#!/bin/sh\nenv > "${temporal.path}/entorno-visto.txt"\nexit 0\n',
    );
    await Process.run('chmod', ['+x', espia.path]);

    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
        'SHIPFLOW_GITHUB_TOKEN': 'ghp_no_debe_llegar_al_hijo',
        'UNA_VARIABLE_QUE_NO_ES_LISTA_BLANCA': 'no_debe_llegar_al_hijo',
      }),
      programa: espia.path,
    );

    await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
      credencial: const Credential(
        'ghp_del_push',
        label: 'SHIPFLOW_GITHUB_TOKEN',
      ),
      revision: 'HEAD',
      rama: 'rebanada-1',
    );

    final visto = await File(
      '${temporal.path}/entorno-visto.txt',
    ).readAsString();
    expect(visto, contains('PATH='));
    expect(visto, contains('HOME='));
    expect(visto, isNot(contains('ghp_no_debe_llegar_al_hijo')));
    expect(visto, isNot(contains('ghp_del_push')));
    expect(visto, isNot(contains('SHIPFLOW_GITHUB_TOKEN')));
    expect(visto, isNot(contains('UNA_VARIABLE_QUE_NO_ES_LISTA_BLANCA')));
    expect(visto, isNot(contains('no_debe_llegar_al_hijo')));
  });
}
