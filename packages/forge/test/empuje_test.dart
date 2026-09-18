import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:forge/forge.dart';
import 'package:test/test.dart';

/// El nombre del programa que mide el FIN de un proceso. Es una constante y
/// no un literal suelto porque la prueba lo BUSCA en `bin/` por este prefijo,
/// en vez de escribir su ruta completa — ver el comentario de esa prueba.
const nombreDelInstrumento = 'ayuda_fin_del_proceso';

void main() {
  late Directory temporal;
  late HttpServer servidor;
  final autorizaciones = <String?>[];

  /// El OID del commit que arma `setUp`, leído de `git rev-parse HEAD`.
  ///
  /// **No es `'HEAD'` ni una constante inventada**: desde esta ronda,
  /// `empujar` exige un OID completo antes de lanzar nada, así que una
  /// revisión simbólica no llegaría al proceso y estas pruebas dejarían de
  /// ejercitar lo que dicen ejercitar. Sale del repositorio de verdad, que
  /// es además la única forma de que el `push` tenga sentido: es el objeto
  /// que efectivamente existe ahí.
  late String revisionDeLaCabeza;

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
    final cabeza = await Process.run(
      'git',
      const ['rev-parse', 'HEAD'],
      workingDirectory: trabajo.path,
      environment: {'PATH': Platform.environment['PATH']!, 'HOME': casa.path},
      includeParentEnvironment: false,
    );
    expect(cabeza.exitCode, 0, reason: '${cabeza.stderr}');
    revisionDeLaCabeza = (cabeza.stdout as String).trim();
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
      revision: revisionDeLaCabeza,
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
      revision: revisionDeLaCabeza,
      rama: 'rebanada-1',
    );
    expect(r, isA<NoEmpujado>());
    expect((r as NoEmpujado).desenlace.retryable, isTrue);
  });

  test('un programa que no se puede lanzar es PushFailed, no PushUnknown, y '
      'no expone la credencial en ningún texto del desenlace', () async {
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
      revision: revisionDeLaCabeza,
      rama: 'rebanada-1',
    );

    expect(r, isA<NoEmpujado>());
    expect(
      (r as NoEmpujado).desenlace,
      isA<PushFailed>(),
      reason:
          'si el proceso NUNCA arrancó, el efecto remoto no pudo ocurrir: no '
          'hubo nada capaz de hablar con el remoto. `PushUnknown` mandaba a '
          'buscar allá un efecto imposible, que es la clase de duda que este '
          'repositorio existe para no fabricar.',
    );
    expect(
      (r.desenlace as PushFailed).causa,
      CausaDePublicacion.noSePudoLanzar,
      reason:
          '«no se pudo determinar la causa» sobre un programa que no está en '
          'el `PATH` es falso y no accionable. Que este `catch` no LEA la '
          'excepción no vuelve desconocido el hecho: qué rama corrió es '
          'información propia del código, no del texto de la excepción.',
    );
    expect(
      r.desenlace.retryable,
      isTrue,
      reason: 'un fork que falló por recursos puede andar en el próximo',
    );

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
      revision: revisionDeLaCabeza,
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
      revision: revisionDeLaCabeza,
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
      revision: revisionDeLaCabeza,
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

  test(
    'una revisión que no es un OID completo no lanza NINGÚN proceso',
    () async {
      // El defecto que esta prueba fija tenía un desenlace posible y uno solo:
      // `empujar` arma el refspec `<revisión>:refs/heads/<rama>`, y con la
      // revisión vacía eso es `:refs/heads/<rama>` — la forma documentada de
      // BORRAR la rama del remoto. O sea que una revisión en blanco no
      // producía un push fallido: producía el borrado de la rama de destino.
      //
      // **Lo que se afirma es que no se lanzó nada, no que el desenlace sea
      // lindo.** Un rechazo que devolviera la causa correcta DESPUÉS de lanzar
      // `git` pasaría una prueba que solo mirara el desenlace, y el borrado ya
      // habría ocurrido. Por eso el programa es un espía que deja rastro con
      // solo arrancar.
      final espia = File('${temporal.path}/espia-revision.sh');
      await espia.writeAsString(
        '#!/bin/sh\ntouch "${temporal.path}/se-lanzo-por-revision"\nexit 0\n',
      );
      await Process.run('chmod', ['+x', espia.path]);
      final rastro = File('${temporal.path}/se-lanzo-por-revision');

      final empuje = EmpujeAislado(
        directorio: '${temporal.path}/trabajo',
        entornoDelPadre: EntornoDelProceso({
          'PATH': Platform.environment['PATH']!,
          'HOME': '${temporal.path}/casa',
        }),
        programa: espia.path,
      );

      // Las formas que un llamador distraído produce de verdad: la vacía —la
      // que borra—, una revisión simbólica, una abreviada de las que git
      // acepta en la línea de comandos, y dos que tienen el largo correcto
      // pero no son hexadecimales o le sobra un carácter.
      final invalidas = <String>[
        '',
        '   ',
        'HEAD',
        'main',
        'a4e66d5',
        'a4e66d50d152b67d451a9028fd1cf54c71e18e7',
        'a4e66d50d152b67d451a9028fd1cf54c71e18e790',
        'z4e66d50d152b67d451a9028fd1cf54c71e18e79',
      ];
      for (final invalida in invalidas) {
        final credencial = _CredencialEspia('ghp_no_debe_desenvolverse');
        final r = await empuje.empujar(
          urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
          credencial: credencial,
          revision: invalida,
          rama: 'rebanada-1',
        );
        expect(r, isA<NoEmpujado>());
        expect((r as NoEmpujado).desenlace, isA<PushFailed>());
        expect(
          (r.desenlace as PushFailed).causa,
          CausaDePublicacion.revisionInvalida,
        );
        expect(
          r.desenlace.retryable,
          isFalse,
          reason: 'la misma revisión vuelve a no ser un OID la próxima vez',
        );
        expect(
          rastro.existsSync(),
          isFalse,
          reason:
              'con la revisión «$invalida» se lanzó un proceso. Con la revisión '
              'vacía ese proceso es `git push <remoto> :refs/heads/<rama>`, que '
              'BORRA la rama del remoto.',
        );
        expect(
          credencial.desenvuelta,
          isFalse,
          reason:
              'el rechazo ocurre antes de armar el destino, así que el secreto '
              'no tiene por qué haberse desenvuelto',
        );
      }

      // El control positivo, sin el cual una validación que rechazara
      // cualquier revisión pasaría este archivo entero y rompería la
      // publicación: con el OID de verdad, el lanzamiento sí ocurre.
      await empuje.empujar(
        urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
        credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
        revision: revisionDeLaCabeza,
        rama: 'rebanada-1',
      );
      expect(
        rastro.existsSync(),
        isTrue,
        reason:
            'con un OID completo el push tiene que lanzarse: una validación '
            'que rechace todo no es una validación, es una publicación rota',
      );
    },
  );

  test(
    'un git que no termina vence, se mata, y no queda ningún proceso huérfano',
    () async {
      // `Process.run` sin presupuesto esperaba para siempre: un remoto que
      // acepta la conexión y no contesta, un filtro, un `git` trabado. El
      // flujo no producía ningún desenlace, que es lo contrario del
      // invariante de este paquete — el desenlace se declara.
      //
      // El `exec` no es decorativo: sin él, el `sh` lanzaría `sleep` como
      // HIJO suyo y matar al `sh` dejaría al `sleep` vivo, con lo que la
      // prueba estaría midiendo la muerte de un proceso distinto del que se
      // cuelga. Con `exec`, el PID que se anota es el mismo que se bloquea.
      final bloqueante = File('${temporal.path}/bloqueante.sh');
      await bloqueante.writeAsString(
        '#!/bin/sh\necho \$\$ > "${temporal.path}/pid-bloqueante"\n'
        'exec sleep 300\n',
      );
      await Process.run('chmod', ['+x', bloqueante.path]);

      final empuje = EmpujeAislado(
        directorio: '${temporal.path}/trabajo',
        entornoDelPadre: EntornoDelProceso({
          'PATH': Platform.environment['PATH']!,
          'HOME': '${temporal.path}/casa',
        }),
        programa: bloqueante.path,
        presupuesto: const Duration(milliseconds: 300),
      );

      final r = await empuje.empujar(
        urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
        credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
        revision: revisionDeLaCabeza,
        rama: 'rebanada-1',
      );

      expect(r, isA<NoEmpujado>());
      expect(
        (r as NoEmpujado).desenlace,
        isA<PushUnknown>(),
        reason:
            'al interrumpirlo se pierde quien sabía cómo terminó: el packfile '
            'puede haber llegado entero. `PushFailed` afirmaría que del otro '
            'lado no hay nada.',
      );
      expect(r.desenlace.retryable, isTrue);

      // Y el proceso no quedó dando vueltas. Sin el `kill`, `sleep 300`
      // sobrevive a la corrida entera: el desenlace se habría declarado y el
      // proceso seguiría vivo, que es media promesa presentada como entera.
      final archivoDePid = File('${temporal.path}/pid-bloqueante');
      expect(
        archivoDePid.existsSync(),
        isTrue,
        reason: 'el programa bloqueante ni siquiera llegó a anotar su PID',
      );
      final pid = int.parse(archivoDePid.readAsStringSync().trim());
      var vivo = true;
      for (var intento = 0; intento < 100 && vivo; intento++) {
        // `kill -0` no manda ninguna señal: solo pregunta si el proceso
        // existe. Se consulta en un bucle corto porque entre el `SIGKILL` y
        // la desaparición del proceso hay un instante que es del sistema
        // operativo, no de este código.
        final consulta = await Process.run('kill', ['-0', '$pid']);
        vivo = consulta.exitCode == 0;
        if (vivo) await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(
        vivo,
        isFalse,
        reason:
            'el proceso $pid sobrevivió al vencimiento: el presupuesto cortó '
            'la espera pero no el proceso, y eso deja un huérfano por cada '
            'push colgado',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'un hijo que escribe más de lo que entra en la tubería igual termina',
    () async {
      // El drenaje no es prolijidad: es lo que impide que el presupuesto se
      // dispare por la razón equivocada. Las tuberías del hijo tienen un
      // buffer finito en el núcleo —del orden de 64 KiB—; un hijo que escribe
      // más que eso se BLOQUEA escribiendo hasta que alguien lea. `git push`
      // es locuaz por `stderr`, así que sin drenar, un push perfectamente
      // sano se cuelga, vence, y se reporta como `PushUnknown`: un falso
      // desenlace ambiguo fabricado por nuestro propio cliente.
      //
      // 200 000 bytes por cada flujo, bien por encima del buffer, y salida 0.
      final charlatan = File('${temporal.path}/charlatan.sh');
      await charlatan.writeAsString(
        '#!/bin/sh\n'
        "head -c 200000 /dev/zero | tr '\\0' 'x'\n"
        "head -c 200000 /dev/zero | tr '\\0' 'y' >&2\n"
        'exit 0\n',
      );
      await Process.run('chmod', ['+x', charlatan.path]);

      final empuje = EmpujeAislado(
        directorio: '${temporal.path}/trabajo',
        entornoDelPadre: EntornoDelProceso({
          'PATH': Platform.environment['PATH']!,
          'HOME': '${temporal.path}/casa',
        }),
        programa: charlatan.path,
        presupuesto: const Duration(seconds: 5),
      );

      final r = await empuje.empujar(
        urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
        credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
        revision: revisionDeLaCabeza,
        rama: 'rebanada-1',
      );

      expect(
        r,
        isA<Empujado>(),
        reason:
            'el hijo salió con 0 después de escribir 400 000 bytes. Si esto da '
            '`PushUnknown`, nadie está leyendo las tuberías: el hijo se '
            'bloqueó escribiendo y el presupuesto lo mató por un cuelgue que '
            'causamos nosotros.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('un descendiente que conserva la tubería no cuelga el drenaje '
      'posterior a la salida', () async {
    // **El cuelgue que la propia ronda de arreglo reintrodujo por la puerta
    // de al lado.** Con los flujos drenados pero esperados SIN presupuesto
    // después de recibir el código de salida, basta con que un nieto herede
    // el descriptor y lo conserve: `git` sale, `exitCode` llega, y los dos
    // `await` del drenaje no vuelven nunca. `empujar` no produce ningún
    // desenlace — que es exactamente el hallazgo 5 del autor.
    //
    // El `&` deja al `sleep` con el stdout y el stderr del padre heredados,
    // y el padre sale de inmediato con 0: la situación exacta, en miniatura,
    // de `git` saliendo mientras `git-remote-https` sigue vivo.
    final conNieto = File('${temporal.path}/con-nieto.sh');
    await conNieto.writeAsString(
      '#!/bin/sh\nsleep 300 &\necho "\$!" > "${temporal.path}/pid-nieto"\n'
      'exit 0\n',
    );
    await Process.run('chmod', ['+x', conNieto.path]);
    addTearDown(() async {
      final archivo = File('${temporal.path}/pid-nieto');
      if (!archivo.existsSync()) return;
      await Process.run('kill', ['-9', archivo.readAsStringSync().trim()]);
    });

    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      }),
      programa: conNieto.path,
      presupuesto: const Duration(milliseconds: 300),
    );

    final r = await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
      credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: revisionDeLaCabeza,
      rama: 'rebanada-1',
    );

    // El código de salida fue 0 y eso no cambia porque el texto se haya
    // perdido: lo que el presupuesto del drenaje sacrifica es la clasificación
    // de la causa, no el desenlace.
    expect(
      r,
      isA<Empujado>(),
      reason:
          'el hijo salió con 0; lo único pendiente era una tubería que un '
          'nieto no soltó',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('el stdin del hijo se cierra: un programa que lee no se queda '
      'esperando', () async {
    // `Process.run` cerraba el stdin del hijo; `Process.start` lo deja
    // abierto. Sin cerrarlo, un `git` que leyera de ahí dejaba de fallar al
    // instante y pasaba a colgarse hasta agotar el presupuesto, saliendo como
    // `PushUnknown`: el cambio de lanzador habría convertido un fallo
    // inmediato en una duda de dos minutos.
    //
    // El programa lee hasta EOF con `read`, que es una construcción del
    // propio intérprete de la línea de comandos y no un ejecutable aparte:
    // así esta prueba no depende de que exista ningún binario más en el
    // `PATH` del entorno donde corra. Con el stdin cerrado ve EOF de entrada
    // y sale con 0; sin cerrar, espera.
    final lector = File('${temporal.path}/lee-stdin.sh');
    await lector.writeAsString(
      '#!/bin/sh\nwhile read -r linea; do :; done\nexit 0\n',
    );
    await Process.run('chmod', ['+x', lector.path]);

    final empuje = EmpujeAislado(
      directorio: '${temporal.path}/trabajo',
      entornoDelPadre: EntornoDelProceso({
        'PATH': Platform.environment['PATH']!,
        'HOME': '${temporal.path}/casa',
      }),
      programa: lector.path,
      presupuesto: const Duration(seconds: 2),
    );

    final r = await empuje.empujar(
      urlDelRemoto: 'http://127.0.0.1:${servidor.port}/x.git',
      credencial: const Credential('ghp_x', label: 'SHIPFLOW_GITHUB_TOKEN'),
      revision: revisionDeLaCabeza,
      rama: 'rebanada-1',
    );

    expect(
      r,
      isA<Empujado>(),
      reason:
          'el programa leyó stdin y salió con 0. Si esto da `PushUnknown`, su '
          'stdin nunca se cerró: se quedó esperando una entrada que nadie le '
          'iba a mandar hasta que venció el presupuesto.',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'el proceso TERMINA aunque un nieto conserve la tubería',
    () async {
      // **Esta prueba mide lo que la ronda anterior no midió.** Poner
      // `.timeout(...)` sobre un `join()` hace que `empujar` DEVUELVA a tiempo
      // —eso ya lo comprueba la prueba de arriba— y no cierra nada: `timeout`
      // abandona el futuro, pero la suscripción que lo alimenta sigue viva y la
      // tubería sigue abierta. Un proceso con trabajo pendiente no termina, y
      // el ejecutable del comando —bajo `packages/cli/bin/`— vuelve de `main`
      // a propósito en vez de llamar a `exit`. O sea que el cuelgue no estaba
      // cerrado: estaba mudado del desenlace al fin del proceso.
      //
      // Por eso lo que se mide acá NO es lo que devuelve `empujar` sino CUÁNTO
      // TARDA EN TERMINAR un proceso que hizo un `empujar`. Eso no se puede
      // afirmar desde adentro del proceso de prueba —que no termina hasta que
      // termina la suite entera—, así que se corre un proceso aparte:
      // el ejecutable `ayuda_fin_del_proceso` de este paquete, que hace un
      // `empujar` y vuelve de `main`.
      //
      // Medido en esta plataforma, con el nieto durmiendo 20 s y un presupuesto
      // de 300 ms: con el drenaje soltado, el proceso entero termina en ~0,8 s;
      // con el `join()` abandonado, en ~20,3 s — cuando muere el nieto. En
      // producción ese nieto es el ayudante de transporte de `git` sobre una
      // conexión muerta, o sea sin cota.
      // **El instrumento se BUSCA, no se escribe su ruta, y las dos cosas
      // que eso evita están medidas.**
      //
      // Una: correrlo como ejecutable del paquete —`run` con el nombre— hace
      // que la herramienta de paquetes precompile un `snapshot` DENTRO del
      // directorio de artefactos del checkout compartido. Medido: el arnés
      // de sabotajes compara ese directorio antes y después de su corrida y
      // reporta
      // «el checkout compartido cambió durante la corrida», que es su alarma
      // más grave. Invocar el archivo directamente no escribe nada: medido
      // también, cinco archivos antes y cinco después.
      //
      // Dos: escribir la ruta obliga a nombrar la extensión de los archivos
      // fuente, y la regla que acota el nombre del lenguaje a su plugin y al
      // composition root caza esa cadena acá, con razón — su propia
      // declaración dice que un `endsWith` de la extensión tiene que
      // dispararla.
      //
      // Buscarlo por su nombre distintivo no es esquivar ninguna de las dos:
      // es la forma que no las provoca. Las dos raíces cubren correr la
      // suite desde el repositorio o desde el paquete.
      final raizDelPaquete = Directory('packages/forge').existsSync()
          ? 'packages/forge'
          : '.';
      final ejecutables = Directory('$raizDelPaquete/bin').listSync();
      final instrumento = ejecutables
          .whereType<File>()
          .where(
            (f) => f.uri.pathSegments.last.startsWith(nombreDelInstrumento),
          )
          .toList();
      expect(
        instrumento,
        hasLength(1),
        reason: 'no se encontró el instrumento «$nombreDelInstrumento»',
      );

      final conNieto = File('${temporal.path}/nieto-que-hereda.sh');
      await conNieto.writeAsString(
        '#!/bin/sh\nsleep 20 &\necho "\$!" > "${temporal.path}/pid-del-nieto"\n'
        'exit 0\n',
      );
      await Process.run('chmod', ['+x', conNieto.path]);
      addTearDown(() async {
        final archivo = File('${temporal.path}/pid-del-nieto');
        if (!archivo.existsSync()) return;
        await Process.run('kill', ['-9', archivo.readAsStringSync().trim()]);
      });

      final reloj = Stopwatch()..start();
      final r = await Process.run(
        // El mismo intérprete que corre esta suite: no se busca uno por `PATH`.
        Platform.resolvedExecutable,
        [
          instrumento.single.path,
          // El instrumento tiene dos modos: este mide el subproceso; el otro
          // —`forja`, en la suite del cliente de la API— mide el socket.
          'empuje',
          '${temporal.path}/trabajo',
          conNieto.path,
          revisionDeLaCabeza,
          'http://127.0.0.1:${servidor.port}/x.git',
        ],
      );
      reloj.stop();

      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(
        r.stdout,
        contains('desenlace=Empujado'),
        reason: 'el hijo salió con 0: el desenlace no cambia por el nieto',
      );
      // El desenlace se computa rápido en las DOS formas —esa es la trampa que
      // esta prueba existe para no repetir—, así que se afirma sobre el fin del
      // proceso y no sobre eso. Diez segundos es el punto medio entre el ~0,8 s
      // que tarda soltando la tubería y los ~20,3 s que tarda sin soltarla: no
      // es una marca de rendimiento, es la diferencia entre terminar y esperar
      // a que muera el nieto.
      expect(
        reloj.elapsed,
        lessThan(const Duration(seconds: 10)),
        reason:
            'el proceso siguió vivo después de computar el desenlace: quedó una '
            'suscripción escuchando la tubería que el nieto conserva. Abandonar '
            'el futuro con `timeout` no la cancela; hay que soltarla.',
      );
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
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
