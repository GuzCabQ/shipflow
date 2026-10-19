import 'dart:convert';

import 'package:plugin_dart/src/project_scanner.dart';
import 'package:plugin_dart/src/pubspec_observer.dart';
import 'package:plugin_dart/src/stable_file_reader.dart';
import 'package:test/test.dart';

ScannedSource manifest(Object text, {String path = 'pubspec.yaml'}) {
  final bytes = text is String ? utf8.encode(text) : text as List<int>;
  return ScannedSource(
    path,
    SourceKind.manifest,
    StableSource(bytes, 'sha256:${'0' * 64}'),
  );
}

List<String> codes(ManifestObservation observation) => [
  for (final limitation in observation.limitations) limitation.code,
];

void main() {
  test('un paquete puro: nombre y restricción del SDK', () {
    final observed = observeManifest(
      manifest('name: app\nenvironment:\n  sdk: ^3.5.0\n'),
    );
    final facts = observed.facts!;
    expect(facts.name, 'app');
    expect(facts.sdkConstraint?.text, '^3.5.0');
    expect(facts.flutterConstraint, isNull);
    expect(facts.flutterDependency, isFalse);
    expect(facts.pathDependencies, isEmpty);
    expect(facts.workspace, isEmpty);
    expect(observed.limitations, isEmpty);
  });

  test('la dependencia flutter con sdk: flutter', () {
    final facts = observeManifest(
      manifest('name: app\ndependencies:\n  flutter:\n    sdk: flutter\n'),
    ).facts!;
    expect(facts.flutterDependency, isTrue);
  });

  test('una dependencia flutter que no viene del sdk no cuenta', () {
    final facts = observeManifest(
      manifest('name: app\ndependencies:\n  flutter: ^1.0.0\n'),
    ).facts!;
    expect(facts.flutterDependency, isFalse);
  });

  test('la restricción de flutter en environment', () {
    final facts = observeManifest(
      manifest('name: app\nenvironment:\n  flutter: ">=3.0.0"\n'),
    ).facts!;
    expect(facts.flutterConstraint?.text, '>=3.0.0');
  });

  test('los miembros del workspace', () {
    final facts = observeManifest(
      manifest('name: root\nworkspace:\n  - packages/b\n  - packages/a\n'),
    ).facts!;
    expect(
      [for (final m in facts.workspace) m.text],
      ['packages/b', 'packages/a'],
    );
  });

  test('las dependencias locales de las tres secciones', () {
    final facts = observeManifest(
      manifest('''
name: app
dependencies:
  local: {path: ../local}
  hosted: ^1.0.0
  remote: {git: https://example.invalid/x.git}
dev_dependencies:
  helper:
    path: tool/helper
dependency_overrides:
  forced: {path: vendor/forced}
'''),
    ).facts!;
    expect(
      [
        for (final d in facts.pathDependencies)
          '${d.section}.${d.name}=${d.path}',
      ],
      [
        'dependencies.local=../local',
        'dev_dependencies.helper=tool/helper',
        'dependency_overrides.forced=vendor/forced',
      ],
    );
  });

  group('lo inválido se informa, nunca desaparece', () {
    test('YAML malformado', () {
      final observed = observeManifest(manifest('name: [sin cerrar\n'));
      expect(observed.facts, isNull);
      expect(codes(observed), ['invalid_manifest']);
      expect(observed.limitations.single.blocking, isTrue);
      expect(observed.limitations.single.path, 'pubspec.yaml');
    });

    test('un documento que no es un mapa', () {
      final observed = observeManifest(manifest('- a\n- b\n'));
      expect(observed.facts, isNull);
      expect(codes(observed), ['invalid_manifest']);
    });

    test('bytes que no son UTF-8', () {
      final observed = observeManifest(manifest([0x6e, 0x3a, 0xff, 0x0a]));
      expect(observed.facts, isNull);
      expect(codes(observed), ['invalid_manifest']);
    });

    test('tipos escalares equivocados conservan lo demás', () {
      final observed = observeManifest(
        manifest('name: 3\nenvironment:\n  sdk: 7\n  flutter: [x]\n'),
      );
      expect(observed.facts!.name, isNull);
      expect(observed.facts!.sdkConstraint, isNull);
      expect(observed.facts!.flutterConstraint, isNull);
      expect(codes(observed), [
        'invalid_manifest',
        'invalid_manifest',
        'invalid_manifest',
      ]);
    });

    test('un anidamiento profundo e irrelevante se acota sin caer', () {
      final watch = Stopwatch()..start();
      final observed = observeManifest(
        manifest('name: app\nx: ${'[' * 20000}${']' * 20000}\n'),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(observed.facts, isNull);
      expect(codes(observed), ['invalid_manifest']);
    });
  });

  group('el anidamiento por bloques también se acota sin caer', () {
    for (final (name, text) in [
      ('secuencias', 'name: a\nx:\n  ${'- ' * 10000}z\n'),
      ('claves explícitas', 'name: a\nx:\n  ${'? ' * 10000}z\n'),
      (
        'sangrías',
        'name: a\n${[for (var i = 0; i < 300; i++) '${' ' * i}k$i:'].join('\n')} v\n',
      ),
    ]) {
      test(name, () {
        final watch = Stopwatch()..start();
        final observed = observeManifest(manifest(text));
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(observed.facts, isNull);
        expect(codes(observed), ['invalid_manifest']);
      });
    }

    test('un manifiesto real con sangría normal no se rechaza', () {
      final observed = observeManifest(
        manifest('name: a\ndependencies:\n  b:\n    path: ../b\n'),
      );
      expect(observed.limitations, isEmpty);
    });
  });

  group('un valor de más de 4096 bytes', () {
    test('conserva un adelanto válido y lo declara truncado', () {
      final observed = observeManifest(manifest('name: ${'ñ' * 3000}\n'));
      final name = observed.facts!.name!;
      expect(utf8.encode(name).length, lessThanOrEqualTo(4096));
      expect(name, endsWith('…'));
      expect(utf8.decode(utf8.encode(name)), name);
      expect(name.replaceAll('…', '').replaceAll('ñ', ''), isEmpty);
      expect(codes(observed), ['observed_value_truncated']);
      expect(observed.limitations.single.blocking, isTrue);
    });

    test('una restricción y un miembro conservan su adelanto', () {
      final observed = observeManifest(
        manifest(
          'name: a\nenvironment:\n  sdk: "${'^' * 5000}"\n'
          'workspace:\n  - ${'w' * 5000}\n',
        ),
      );
      for (final value in [
        observed.facts!.sdkConstraint!,
        observed.facts!.workspace.single.shown,
      ]) {
        expect(value.truncated, isTrue);
        expect(utf8.encode(value.text).length, lessThanOrEqualTo(4096));
        expect(value.text, endsWith('…'));
      }
      expect(codes(observed), [
        'observed_value_truncated',
        'observed_value_truncated',
      ]);
    });

    for (final (name, key, path) in [
      ('una clave de dependencia', 'k' * 5000, 'p'),
      ('la clave y la ruta juntas', 'k' * 3000, 'p' * 3000),
    ]) {
      test('$name conserva su adelanto marcado como truncado', () {
        final observed = observeManifest(
          manifest('name: a\ndependencies:\n  $key: {path: $path}\n'),
        );
        final dependency = observed.facts!.pathDependencies.single;
        expect(dependency.truncated, isTrue);
        expect(
          utf8.encode(dependency.evidenceValue).length,
          lessThanOrEqualTo(4096),
        );
        expect(dependency.evidenceValue, endsWith('…'));
        expect(codes(observed), ['observed_value_truncated']);
        for (final limitation in observed.limitations) {
          expect(
            utf8.encode(limitation.message).length,
            lessThanOrEqualTo(4096),
          );
        }
      });
    }

    test('justo 4096 bytes no se trunca', () {
      final observed = observeManifest(manifest('name: ${'a' * 4096}\n'));
      expect(observed.facts!.name, 'a' * 4096);
      expect(observed.limitations, isEmpty);
    });
  });

  group('description is optional and never blocks', () {
    test('a string description is kept as declared', () {
      final observed = observeManifest(
        manifest('name: app\ndescription: "Una app \\u001b[31m"\n'),
      );
      expect(observed.facts!.description, 'Una app \u001b[31m');
      expect(observed.limitations, isEmpty);
    });

    test('an absent description is not informed', () {
      final observed = observeManifest(manifest('name: app\n'));
      expect(observed.facts!.description, isNull);
      expect(observed.limitations, isEmpty);
    });

    for (final (name, value) in [
      ('a non-string description', '[1, 2]'),
      ('a description over 4096 bytes', 'ñ' * 2049),
    ]) {
      test('$name is omitted with a non-blocking limitation', () {
        final observed = observeManifest(
          manifest('name: app\ndescription: $value\n'),
        );
        expect(observed.facts!.description, isNull);
        expect(observed.limitations.map((l) => '${l.code}:${l.blocking}'), [
          'optional_description_unavailable:false',
        ]);
      });
    }

    test('exactly 4096 bytes is kept whole', () {
      final value = 'ñ' * 2048;
      final observed = observeManifest(
        manifest('name: app\ndescription: $value\n'),
      );
      expect(observed.facts!.description, value);
      expect(observed.limitations, isEmpty);
    });
  });
}
