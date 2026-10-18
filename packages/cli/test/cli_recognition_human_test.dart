import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recognition_reports.dart';

void main() {
  test('un reconocimiento completo, sección por sección', () {
    final response = presentRecognition(report(), json: false);
    expect(response.channel, CliOutputChannel.stdout);
    expect(response.exitCode, 0);
    expect(
      response.payload,
      'Shipflow · reconocimiento\n'
      'Estado: recognized\n'
      'Raíz solicitada: /solicitada\n'
      'Raíz resuelta: /resuelta\n'
      'Git: absent\n'
      'Candidatos:\n'
      '  - stack · Stack · plugin plugin · evidencia e0001, e0002\n'
      'Unidades:\n'
      '  - u0001 · a · package · packages/a · evidencia e0001\n'
      '  - u0002 · b · package · packages/b · evidencia e0002\n'
      'Evidencia:\n'
      '  - e0001 · manifest.package_name · packages/a/manifest · a · '
      'sha256:e0001e0001e0001e0001e0001e0001e0001e0001\n'
      '  - e0002 · manifest.package_name · packages/b/manifest · b · '
      'sha256:e0002e0002e0002e0002e0002e0002e0002e0002\n'
      'Conflictos:\n'
      '  ninguno\n'
      'Limitaciones:\n'
      '  ninguno\n'
      'Propuesta: elegible\n'
      '  - record_project_identity · Registra la identidad del proyecto '
      'reconocido.\n'
      '  - enable_stack_plugin · Habilita el plugin del stack reconocido.\n'
      'Efectos: 0 archivos, 0 directorios, 0 procesos, 0 solicitudes de red.\n',
    );
  });

  test('hallazgos, Git detectado y una propuesta no elegible', () {
    final payload = presentRecognition(
      report(
        repository: const RepositoryContext(
          status: RepositoryStatus.detected,
          root: '/repo',
          relation: RepositoryRelation.ancestor,
        ),
        conflicts: [
          RecognitionConflict(
            code: 'versions_disagree',
            message: 'no coinciden',
            evidenceIds: const ['e0002', 'e0001'],
          ),
        ],
        limitations: const [
          RecognitionLimitation(
            code: 'note',
            message: 'sin ruta',
            path: null,
            blocking: false,
          ),
          RecognitionLimitation(
            code: 'subtree_unreadable',
            message: 'no se pudo listar',
            path: 'cerrado',
            blocking: true,
          ),
        ],
      ),
      json: false,
    ).payload;
    expect(payload, contains('Estado: ambiguous\n'));
    expect(payload, contains('Git: detected · ancestor · /repo\n'));
    expect(
      payload,
      contains(
        'Conflictos:\n'
        '  - versions_disagree · no coinciden · evidencia e0001, e0002\n',
      ),
    );
    expect(
      payload,
      contains(
        'Limitaciones:\n'
        '  - note · bloqueante: no · sin ruta · sin ruta\n'
        '  - subtree_unreadable · bloqueante: sí · cerrado · no se pudo listar\n',
      ),
    );
    expect(payload, contains('Propuesta: no elegible\n  ninguna\nEfectos:'));
  });

  test('una raíz inválida no tiene raíz resuelta ni Git', () {
    final payload = presentRecognition(
      RecognitionReport.invalidRoot(
        requestedRoot: '/no-existe',
        reason: const RecognitionLimitation(
          code: 'root_not_found',
          message: 'la raíz no existe',
          path: null,
          blocking: true,
        ),
      ),
      json: false,
    );
    expect(payload.exitCode, 66);
    expect(payload.payload, contains('Raíz resuelta: no disponible\n'));
    expect(payload.payload, contains('Git: indeterminate\n'));
    expect(payload.payload, contains('Candidatos:\n  ninguno\n'));
  });

  test('cada valor dinámico ocupa una sola línea segura', () {
    final hostile = 'a\nb\u202Ec\x1b[2J';
    final payload = presentRecognition(
      report(unitName: hostile),
      json: false,
    ).payload;
    final lines = payload.split('\n');
    final benign = presentRecognition(report(), json: false).payload;
    expect(lines.length, benign.split('\n').length);
    expect(payload, contains(r'a\nb\u{202e}c\x1b[2J'));
    expect(payload, isNot(contains('\u202E')));
    expect(payload, isNot(contains('\x1b')));
  });

  test('un valor de más de 240 runes visibles se corta con …', () {
    final payload = presentRecognition(
      report(unitName: 'x' * 300),
      json: false,
    ).payload;
    final unitLine = payload
        .split('\n')
        .firstWhere((String l) => l.startsWith('  - u0002'));
    expect(unitLine, contains(' · ${'x' * 240}… · '));
    expect(unitLine, isNot(contains('x' * 241)));
  });

  test('la vista humana y la JSON salen del mismo reporte', () {
    final source = report();
    expect(
      presentRecognition(source, json: false).exitCode,
      presentRecognition(source, json: true).exitCode,
    );
  });
}
