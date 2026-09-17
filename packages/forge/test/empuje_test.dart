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
}
