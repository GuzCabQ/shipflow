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

    // El remoto vio LA credencial, no una cualquiera. La aserción vieja
    // —«llegó algún encabezado»— pasaba en verde con el secreto reemplazado
    // por una constante en `_conCredencial`: lo único que exigía era que
    // `git` hubiera mandado ALGO. Acá se decodifica el `Basic` y se exige
    // que adentro esté ESTE secreto.
    //
    // Se afirma sobre booleanos y cifras, nunca sobre la lista decodificada:
    // si esto falla, `package:test` imprime el valor `Actual`, y sobre la
    // lista cruda eso es el secreto en la consola y en el log de CI — la
    // misma disciplina que sostiene `safeReason` en el resto del archivo.
    final basicos = autorizaciones
        .whereType<String>()
        .where((a) => a.startsWith('Basic '))
        .map((a) => utf8.decode(base64.decode(a.substring('Basic '.length))))
        .toList();
    expect(
      basicos.length,
      greaterThan(0),
      reason: 'el remoto no recibió ningún `Basic`: la credencial no llegó',
    );
    expect(
      basicos.every((b) => b.contains('ghp_secreto')),
      isTrue,
      reason:
          'llegó un `Basic`, pero no lleva el secreto que se le pasó a '
          '`empujar`. Con una constante en lugar del secreto, la forja real '
          'contestaría 401 y el desenlace diría «la credencial no fue '
          'aceptada»: un bug nuestro reportado como un problema del token '
          'del usuario.',
    );

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

  test('un remoto que no es https se rechaza antes de tocar la credencial y '
      'antes de lanzar git', () async {
    // `_conCredencial` mete el secreto en el `userinfo` sin mirar el
    // esquema: con `http://` contra un host que no es loopback, el token
    // viaja en claro. Nadie produce hoy esa URL —la raíz de composición es
    // de la rebanada de `ship`— y por eso ninguna revisión por tarea lo vio.
    //
    // DOS controles, porque el doc comment promete dos cosas distintas y el
    // espía de proceso solo sostiene una: que el rechazo ocurre antes del
    // LANZAMIENTO. Mover la validación a después de `credencial.use(...)` y
    // antes de `Process.run` sobreviviría a ese espía solo, aunque el
    // comentario diga «antes de tocar la credencial». La credencial espía
    // cierra esa segunda mitad: anota si alguien llegó a desenvolver el
    // secreto.
    final espia = File('${temporal.path}/espia-esquema.sh');
    await espia.writeAsString(
      '#!/bin/sh\ntouch "${temporal.path}/se-lanzo"\nexit 0\n',
    );
    await Process.run('chmod', ['+x', espia.path]);

    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      }),
      programa: espia.path,
    );

    const secreto = 'ghp_no_debe_viajar_en_claro';
    final credencial = _CredencialEspia(secreto);
    final r = await empuje.empujar(
      urlDelRemoto: 'http://forja.invalido/duenio/repo.git',
      credencial: credencial,
      revision: 'HEAD',
      rama: 'rebanada-1',
    );

    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace, isA<PushFailed>());
    expect(
      (r.desenlace as PushFailed).causa,
      CausaDePublicacion.configuracionInsegura,
    );
    expect(
      r.desenlace.retryable,
      isFalse,
      reason: 'el mismo canal vuelve a estar en claro la próxima vez',
    );
    expect(
      File('${temporal.path}/se-lanzo').existsSync(),
      isFalse,
      reason: 'el rechazo tiene que ocurrir ANTES de lanzar nada',
    );
    expect(
      credencial.desenvuelta,
      isFalse,
      reason:
          'el rechazo tiene que ocurrir ANTES de tocar la credencial, que es '
          'lo que promete el comentario de `empujar`: con la validación '
          'movida a después de `credencial.use(...)` el secreto ya estaría '
          'interpolado en una URL que nadie va a usar',
    );
    // Ni la URL rechazada ni el secreto aparecen en ningún texto que salga.
    expect(jsonEncode(r.desenlace.toJson()), isNot(contains(secreto)));
    expect(
      (r.desenlace as PushFailed).safeReason,
      isNot(contains('forja.invalido')),
    );
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
    // Se afirma sobre el CONJUNTO DE NOMBRES, nunca sobre `visto` crudo. Dos
    // motivos, y los dos importan acá:
    //
    // 1. Si `includeParentEnvironment` se pusiera en `true`, el hijo
    //    heredaría además el entorno real de quien corre la suite. Ninguna
    //    de las cadenas que este archivo conoce de antemano (el secreto, la
    //    variable inventada) existe en ESE entorno, así que buscarlas con
    //    `contains` pasaría en verde igual — es el mismo agujero que esta
    //    ronda vino a cerrar. Lo que sí cambia con la herencia real es la
    //    FORMA del conjunto: pasa de {PATH, HOME} más el residuo de
    //    plataforma de abajo, a varias decenas de nombres del sistema. Por
    //    eso se afirma el conjunto, no una búsqueda de texto.
    // 2. Si esta prueba falla, `package:test` imprime el valor `Actual`
    //    completo. Sobre `visto` crudo eso es el entorno entero del hijo,
    //    token incluido, en la consola y en el log de CI — la misma
    //    disciplina que sostiene `safeReason` en el resto del archivo.
    //    `nombres` son solo claves, nunca valores: un fallo acá nombra qué
    //    variable no debía estar, sin repetir su contenido.
    final nombres = _nombresDelEntorno(visto);

    // Medido en esta plataforma (macOS, con `/bin/sh` invocando `env`): el
    // proceso recibe exactamente `PATH` y `HOME` —lo que pasa la lista
    // blanca de `entornoSaneado`— más `PWD`, `SHLVL` y `_`, que no vienen de
    // `environment:` sino que los agrega el propio intérprete de la
    // línea de comandos (`PWD`/`SHLVL`) y el comando `env` (`_`) al
    // arrancar. Es un residuo del mecanismo de espionaje, no de lo que
    // `empujar` construye. Si CI —que corre en Linux— agrega alguna otra
    // variable propia del `sh` de esa plataforma, esta lista tiene que
    // crecer con esa medición, nunca borrarse para que la prueba pase.
    const residuoDeLaPlataforma = {'PWD', 'SHLVL', '_'};
    const listaBlanca = {'PATH', 'HOME'};
    final permitidos = {...listaBlanca, ...residuoDeLaPlataforma};

    expect(
      nombres.difference(permitidos),
      isEmpty,
      reason:
          'el hijo recibió variables fuera de la lista blanca esperada '
          '(más el residuo de plataforma ya medido y declarado). Esto pasa '
          'si `includeParentEnvironment` se puso en `true`, o si '
          '`entornoSaneado` dejó de aplicarse en el lanzamiento.',
    );
    expect(
      nombres.containsAll(listaBlanca),
      isTrue,
      reason:
          'faltan de la lista blanca variables que sí deberían llegar al '
          'hijo (PATH, HOME).',
    );
  });
}

/// Una [Credential] que anota si alguien llegó a desenvolver el secreto.
///
/// No hay otra forma de observarlo: `use` es el único acceso al secreto —ese
/// es el punto del tipo— y no deja rastro por su cuenta. Con esto, «no se
/// tocó la credencial» es una aserción y no una promesa de un comentario.
class _CredencialEspia extends Credential {
  bool desenvuelta = false;

  _CredencialEspia(super.secreto) : super(label: 'SHIPFLOW_GITHUB_TOKEN');

  @override
  T use<T>(T Function(String secreto) f) {
    desenvuelta = true;
    return super.use(f);
  }
}

/// Los NOMBRES de las variables que volcó `env`, sin sus valores.
///
/// **No parte por `\n` a secas.** `env` separa una variable de la siguiente
/// con un salto de línea, pero el VALOR de una variable puede contener saltos
/// de línea propios — una línea de continuación no tiene la forma
/// `NOMBRE=...`, así que no cuenta como una variable nueva. Partir a secas
/// convertiría cada línea de un valor multilínea en un nombre falso.
Set<String> _nombresDelEntorno(String textoDeEnv) {
  final patronDeNombre = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)=');
  return {
    for (final linea in const LineSplitter().convert(textoDeEnv))
      if (patronDeNombre.firstMatch(linea) case final m?) m.group(1)!,
  };
}
