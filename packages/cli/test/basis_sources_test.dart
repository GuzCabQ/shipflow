import 'dart:io';

import 'package:cli/src/basis/basis_canonical.dart';
import 'package:cli/src/basis/basis_sources.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'support/context_service_support.dart';

final _limits = BasisLimits.forProfile(BasisProfile.standard);

String _id(int n) =>
    '${n.toRadixString(16).padLeft(8, '0')}-0000-4000-8000-000000000000';

BasisRecordVersion local(
  int n,
  String locator, {
  String? digest,
  int version = 1,
}) => BasisRecordVersion(
  id: _id(n),
  version: version,
  previousVersion: version == 1 ? null : version - 1,
  payload: BasisSource(
    title: 'Fuente $n',
    scope: BasisScope.project(),
    lifecycle: BasisSourceLifecycle.active,
    sourceType: BasisSourceType.local,
    locator: locator,
    purpose: 'Referencia.',
    contentDigest: digest,
    observation: digest == null
        ? BasisObservation.unverified
        : BasisObservation.current,
  ),
);

/// Un almacén real que anota cada ruta que se intenta leer.
final class _Reads extends CrashingStore {
  _Reads(ContextStore real) : super(real, 1 << 30);

  final paths = <String>[];

  @override
  Future<List<int>?> readRelative(String path, {required int maxBytes}) {
    paths.add(path);
    return real.readRelative(path, maxBytes: maxBytes);
  }
}

void main() {
  late ServiceSandbox box;
  late SecureContextStore real;
  late _Reads store;
  setUp(() async {
    box = ServiceSandbox.create();
    real = await SecureContextStore.open(box.root);
    store = _Reads(real);
  });
  tearDown(() async {
    await real.close();
    box.dispose();
  });

  /// Fuentes nuevas, sin huella registrada: se observan como al preparar.
  Future<BasisSourceReport> read(List<BasisRecordVersion> sources) =>
      BasisSourceReader(store).readSources(sources, _limits, observe: true);

  BasisSourceStatus statusOf(BasisSourceReport report, int n) =>
      report.statuses.singleWhere((s) => s.sourceId == _id(n));

  List<String> codesOf(BasisSourceStatus status) => [
    for (final d in status.diagnostics) d.code,
  ];

  test('a readable admitted source is current with its digest', () async {
    box.file('docs/politica.md', 'Revisar contratos.\n');
    final report = await read([local(1, 'docs/politica.md')]);
    expect(statusOf(report, 1).status, BasisSourceState.current);
    expect(report.readings.single.path, 'docs/politica.md');
    expect(
      report.readings.single.digest,
      bytesDigest(File(box.path('docs/politica.md')).readAsBytesSync()),
    );
  });

  test('source_changed_is_stale_not_retired', () async {
    box.file('docs/politica.md', 'v1\n');
    final first = await read([local(1, 'docs/politica.md')]);
    final digest = first.readings.single.digest;
    box.file('docs/politica.md', 'v2\n');
    final report = await read([local(1, 'docs/politica.md', digest: digest)]);
    expect(statusOf(report, 1).status, BasisSourceState.stale);
    expect(codesOf(statusOf(report, 1)), ['source_changed']);
    final again = await read([local(1, 'docs/politica.md', digest: digest)]);
    expect(statusOf(again, 1).status, BasisSourceState.stale);
  });

  test('external_reference_never_uses_network', () async {
    final external = BasisRecordVersion(
      id: _id(2),
      version: 1,
      previousVersion: null,
      payload: BasisSource(
        title: 'Guía',
        scope: BasisScope.project(),
        lifecycle: BasisSourceLifecycle.active,
        sourceType: BasisSourceType.external,
        locator: 'https://example.org/guia',
        purpose: 'Consulta.',
        contentDigest: null,
        observation: BasisObservation.unverified,
      ),
    );
    final report = await read([external]);
    expect(statusOf(report, 2).status, BasisSourceState.unverified);
    expect(codesOf(statusOf(report, 2)), ['source_external']);
    expect(store.paths, isEmpty);
    expect(report.readings, isEmpty);
  });

  group('symlink_and_secret_marker_not_hashed', () {
    test('a symlink is not followed', () async {
      box.file('docs/real.md', 'contenido\n');
      Link(box.path('docs/enlace.md')).createSync('real.md');
      final report = await read([local(1, 'docs/enlace.md')]);
      expect(statusOf(report, 1).status, BasisSourceState.unverified);
      expect(codesOf(statusOf(report, 1)), ['source_unreadable']);
      expect(report.readings, isEmpty);
    });

    test(
      'a credential marker in the content is excluded, not hashed',
      () async {
        for (final (i, text) in [
          'password = secreto\n',
          'API-KEY: abc\n',
          'clave AKIAABCDEFGHIJKLMNOP aquí\n',
          '-----BEGIN OPENSSH PRIVATE KEY-----\nx\n',
        ].indexed) {
          box.file('docs/s$i.md', text);
          final report = await read([local(1, 'docs/s$i.md')]);
          expect(
            statusOf(report, 1).status,
            BasisSourceState.excluded,
            reason: text,
          );
          expect(codesOf(statusOf(report, 1)), ['source_secret_excluded']);
          expect(report.readings, isEmpty);
        }
      },
    );

    test('a secret name or a protected folder is never opened', () async {
      for (final path in [
        '.env',
        'config/.env.local',
        'deploy/credentials.md',
        'keys/server.pem',
        '.git/config.md',
        'shipflow/local/settings.md',
        'home/.ssh/notes.md',
      ]) {
        final report = await read([local(1, path)]);
        expect(
          statusOf(report, 1).status,
          BasisSourceState.excluded,
          reason: path,
        );
        expect(codesOf(statusOf(report, 1)), ['source_path_excluded']);
      }
      expect(store.paths, isEmpty);
    });

    test('an empty assignment is not a credential', () async {
      box.file('docs/plantilla.md', 'password =\n');
      final report = await read([local(1, 'docs/plantilla.md')]);
      expect(statusOf(report, 1).status, BasisSourceState.current);
    });
  });

  test('another type is kept as an unverified reference, unopened', () async {
    box.file('docs/diagrama.png', 'x');
    final report = await read([local(1, 'docs/diagrama.png')]);
    expect(statusOf(report, 1).status, BasisSourceState.unverified);
    expect(codesOf(statusOf(report, 1)), ['source_type_not_admitted']);
    expect(store.paths, isEmpty);
  });

  test('absent, oversized or non UTF-8 sources are unverified', () async {
    box.file('docs/grande.md', 'x' * (_limits.maxSourceBytes + 1));
    File(box.path('docs/binario.md')).writeAsBytesSync([0xff, 0xfe]);
    final report = await read([
      local(1, 'docs/ausente.md'),
      local(2, 'docs/grande.md'),
      local(3, 'docs/binario.md'),
    ]);
    expect(codesOf(statusOf(report, 1)), ['source_absent']);
    expect(codesOf(statusOf(report, 2)), ['source_too_large']);
    expect(codesOf(statusOf(report, 3)), ['source_invalid_utf8']);
    expect(report.readings, isEmpty);
  });

  test(
    'the count budget stops reading and marks the report incomplete',
    () async {
      final tiny = BasisLimits.fromJson({..._limits.toJson(), 'maxSources': 1});
      box.file('docs/a.md', 'a\n');
      box.file('docs/b.md', 'b\n');
      final report = await BasisSourceReader(store).readSources(
        [local(1, 'docs/a.md'), local(2, 'docs/b.md')],
        tiny,
        observe: true,
      );
      expect(statusOf(report, 1).status, BasisSourceState.current);
      expect(codesOf(statusOf(report, 2)), ['source_budget']);
      expect(report.complete, isFalse);
    },
  );

  test('one path cited by two versions is read once', () async {
    box.file('docs/a.md', 'a\n');
    final report = await read([local(1, 'docs/a.md'), local(2, 'docs/a.md')]);
    expect(store.paths, ['docs/a.md']);
    expect(report.readings, hasLength(1));
  });

  test('reading never writes the tree', () async {
    box.file('docs/a.md', 'a\n');
    final before = box.snapshot();
    await read([local(1, 'docs/a.md')]);
    expect(box.snapshot(), before);
  });
}
