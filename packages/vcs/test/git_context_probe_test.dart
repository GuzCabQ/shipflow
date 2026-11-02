@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';
import 'package:vcs/vcs.dart';

import 'git_support.dart';

const _own = ['shipflow/project.json', 'shipflow/.gitignore'];

void main() {
  final sandbox = GitSandbox()..register();

  Future<GitObservation> observe(
    Directory root, {
    Map<String, String>? environment,
    Duration perProcess = const Duration(seconds: 5),
  }) => GitContextAdapter(
    parentEnvironment: environment ?? realPath(),
    perProcess: perProcess,
  ).observe(root, ownPaths: _own);

  group('absence is not an error, and an error is not absence', () {
    test('no git executable is not_installed', () async {
      final empty = sandbox.directory('vacio');
      final observation = await observe(
        sandbox.directory('raiz'),
        environment: {'PATH': empty.path, 'HOME': sandbox.base.path},
      );
      expect(observation.state, GitState.notInstalled);
      expect(observation.processesStarted, 0);
    });

    test('a folder outside any repository is not_repository', () async {
      final observation = await observe(sandbox.directory('suelta'));
      expect(observation.state, GitState.notRepository);
      expect(observation.binding, isNull);
    });

    test('a damaged repository is unavailable, not absent', () async {
      final repo = sandbox.repository('roto');
      File('${repo.path}/.git/HEAD').writeAsStringSync('basura\n');
      final observation = await observe(repo);
      expect(observation.state, GitState.unavailable);
      expect(observation.code, isNotNull);
    });

    test('a process past its deadline is killed and unavailable', () async {
      final slow = sandbox.fakeGit('lento', '/bin/sleep 20');
      final watch = Stopwatch()..start();
      final observation = await observe(
        sandbox.directory('raiz'),
        environment: {'PATH': slow.path, 'HOME': sandbox.base.path},
        perProcess: const Duration(milliseconds: 500),
      );
      expect(observation.state, GitState.unavailable);
      expect(observation.code, 'git_timeout');
      expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('an output flood is cut and unavailable', () async {
      final noisy = sandbox.fakeGit(
        'ruidoso',
        '/usr/bin/head -c 3000000 /dev/zero',
      );
      final observation = await observe(
        sandbox.directory('raiz'),
        environment: {'PATH': noisy.path, 'HOME': sandbox.base.path},
      );
      expect(observation.state, GitState.unavailable);
      expect(observation.code, 'git_output_limit');
    });
  });

  group('a usable repository', () {
    test(
      'binding and prefix from a nested root, without widening it',
      () async {
        final repo = sandbox.repository('repo');
        final root = Directory('${repo.path}/apps/app')
          ..createSync(recursive: true);
        final observation = await observe(root);
        expect(observation.state, GitState.available);
        final binding = observation.binding!;
        expect(binding.repositoryRoot, repo.path);
        expect(binding.prefix, 'apps/app/');
        expect(binding.gitDir, '${repo.path}/.git');
        expect(binding.commonDir, '${repo.path}/.git');
        expect(observation.excludePath, '${repo.path}/.git/info/exclude');
        expect(observation.linkedWorktree, isFalse);
        expect(observation.processesStarted, lessThanOrEqualTo(12));
      },
    );

    test('tracked and ignored own paths are observed, never changed', () async {
      final repo = sandbox.repository('repo');
      sandbox.file('repo/shipflow/project.json', '{}\n');
      git(['add', 'shipflow/project.json'], repo);
      sandbox.file('repo/.gitignore', 'shipflow/.gitignore\n');
      final status = git(['status', '--porcelain'], repo).stdout;
      final observation = await observe(repo);
      expect(observation.tracked, ['shipflow/project.json']);
      final rule = observation.ignoredBy['shipflow/.gitignore']!;
      expect(rule.source, '${repo.path}/.gitignore');
      expect(rule.pattern, 'shipflow/.gitignore');
      expect(git(['status', '--porcelain'], repo).stdout, status);
    });
  });

  group('the child is bounded and literal', () {
    test(
      'a sanitized environment, a list of arguments and no fsmonitor',
      () async {
        final witness = '${sandbox.base.path}/testigo';
        final spy = sandbox.fakeGit(
          'espia',
          '/usr/bin/env > "$witness.env"; printf "%s\\n" "\$@" >> "$witness.args"; exit 1',
        );
        await observe(
          sandbox.directory('raiz'),
          environment: {
            'PATH': spy.path,
            'HOME': sandbox.base.path,
            'GIT_DIR': '/evil',
            'GIT_CONFIG_GLOBAL': '/evil/config',
          },
        );
        final env = File('$witness.env').readAsStringSync();
        expect(env, isNot(contains('GIT_DIR=')));
        expect(env, isNot(contains('GIT_CONFIG_GLOBAL=')));
        expect(env, contains('GIT_TERMINAL_PROMPT=0'));
        final args = File('$witness.args').readAsStringSync();
        expect(args, contains('core.fsmonitor=false'));
      },
    );

    test(
      'a relative PATH entry or one inside the project is never run',
      () async {
        final root = sandbox.directory('proyecto');
        final witness = File('${sandbox.base.path}/ejecutado');
        sandbox.fakeGit('proyecto/bin', '/usr/bin/touch "${witness.path}"');
        final observation = await observe(
          root,
          environment: {
            'PATH': 'bin:${root.path}/bin::.',
            'HOME': sandbox.base.path,
          },
        );
        expect(observation.state, GitState.notInstalled);
        expect(witness.existsSync(), isFalse);
      },
    );

    test('literalGitPathsNeverBecomeShell', () async {
      final repo = sandbox.repository('repo');
      const name = r'a [b]!*#$(touch testigo) ; `touch otro` ñ';
      final root = Directory('${repo.path}/$name')..createSync();
      git(['config', 'core.fsmonitor', 'touch fsmonitor-testigo'], repo);
      final observation = await observe(root);
      expect(observation.state, GitState.available);
      expect(observation.binding!.prefix, '$name/');
      for (final witness in ['testigo', 'otro', 'fsmonitor-testigo']) {
        for (final dir in [repo.path, root.path, sandbox.base.path]) {
          expect(File('$dir/$witness').existsSync(), isFalse, reason: dir);
        }
      }
    });
  });
}
