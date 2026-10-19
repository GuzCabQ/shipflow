import 'dart:convert';

import 'package:cli/cli.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

import 'recognition_reports.dart';

/// La respuesta JSON completa que jsonEncode escribiría para [report].
String referenceJson(RecognitionReport report) {
  final exitCode = report.status == RecognitionStatus.recognized ? 0 : 65;
  return '${jsonEncode({'schemaVersion': 1, 'type': 'init_dry_run', ...report.toJson(), 'exitCode': exitCode})}\n';
}

int bytesOf(String text) => utf8.encode(text).length;

/// Un reporte con [count] evidencias de valor [value]: dentro de las cotas
/// derivadas, pero con un JSON que los escapes pueden inflar.
RecognitionReport inflated(String value, {int count = 1}) => RecognitionReport(
  status: RecognitionStatus.ambiguous,
  requestedRoot: '/solicitada',
  resolvedRoot: '/resuelta',
  repository: const RepositoryContext(
    status: RepositoryStatus.absent,
    root: null,
    relation: RepositoryRelation.none,
  ),
  candidates: const [],
  units: const [],
  evidence: [for (var i = 0; i < count; i++) _evidence(i, value)],
  conflicts: const [],
  limitations: const [],
  relations: const [],
  contextSources: const [],
  omissions: const [],
  proposal: RecognitionProposal(
    eligible: false,
    pluginIds: const [],
    actions: const [],
  ),
  effects: RecognitionEffects.none,
);

RecognitionEvidence _evidence(int index, String value) => RecognitionEvidence(
  id: 'e${index.toString().padLeft(4, '0')}',
  kind: 'k',
  role: EvidenceRole.identity,
  label: 'Nombre del paquete',
  path: 'p',
  value: value,
  fingerprint: 'f',
);

void main() {
  group('encodeRecognitionWithinLimit', () {
    test('json_budget_counts_envelope_and_newline', () {
      final source = report();
      final expected = referenceJson(source);
      final exact = bytesOf(expected);
      expect(encodeRecognitionWithinLimit(source, maxBytes: exact), expected);
      expect(encodeRecognitionWithinLimit(source, maxBytes: exact - 1), isNull);
    });

    test('json_escaping_expands', () {
      // Controles, comillas, barra, fuera del BMP y un sustituto suelto:
      // el tamaño real es el del encoder, no el del texto original.
      final source = inflated('\x01"\\\n😀\u{D800}ñ');
      final expected = referenceJson(source);
      final exact = bytesOf(expected);
      expect(exact, greaterThan(bytesOf(jsonEncode(source.toJson()))));
      expect(encodeRecognitionWithinLimit(source, maxBytes: exact), expected);
      expect(encodeRecognitionWithinLimit(source, maxBytes: exact - 1), isNull);
    });
  });

  group('presentRecognition mide el JSON aunque se pida la vista humana', () {
    // 250 valores de 4000 controles: 1 MB de texto derivado, 6 MB de JSON.
    final big = inflated('\x01' * 4000, count: 250);

    String messageOf(CliResponse response) =>
        (((jsonDecode(response.payload) as Map)['limitations'] as List).single
                as Map)['message']
            as String;

    test('human_and_json_have_same_overflow_status', () {
      final json = presentRecognition(big, json: true);
      final human = presentRecognition(big, json: false);
      expect(json.exitCode, 65);
      expect(human.exitCode, 65);
      expect(messageOf(json), contains('tamaño JSON del reporte'));
      expect(messageOf(json), contains('perfil normal'));
      expect(human.payload, contains('tamaño JSON del reporte'));
      expect(human.payload, isNot(contains('\x01' * 10)));
      expect(bytesOf(json.payload), lessThanOrEqualTo(2097152));
      expect(json.payload, endsWith('}\n'));
      expect('\n'.allMatches(json.payload), hasLength(1));
    });

    test('el perfil ampliado mide contra su propia cota', () {
      final response = presentRecognition(
        big,
        json: true,
        budgetProfile: ReportBudgetProfile.extended,
      );
      expect(messageOf(response), contains('perfil ampliado'));
      expect(bytesOf(response.payload), lessThanOrEqualTo(2359296));
    });

    test('un reporte que cabe sale tal cual', () {
      final small = report();
      expect(
        presentRecognition(small, json: true).payload,
        referenceJson(small),
      );
    });

    test('una raíz inválida sigue saliendo con 66', () {
      final invalid = RecognitionReport.invalidRoot(
        requestedRoot: '/no-existe',
        reason: const RecognitionLimitation(
          code: 'root_not_found',
          message: 'la raíz no existe',
          path: null,
          blocking: true,
        ),
      );
      expect(presentRecognition(invalid, json: true).exitCode, 66);
    });

    test('si ni el compacto cabe es un defecto, no otro límite', () {
      final hugeRoot = RecognitionReport(
        status: RecognitionStatus.ambiguous,
        requestedRoot: '/${'r' * 3000000}',
        resolvedRoot: '/resuelta',
        repository: big.repository,
        candidates: const [],
        units: const [],
        evidence: const [],
        conflicts: const [],
        limitations: const [],
        relations: const [],
        contextSources: const [],
        omissions: const [],
        proposal: big.proposal,
        effects: RecognitionEffects.none,
      );
      expect(() => presentRecognition(hugeRoot, json: true), throwsStateError);
    });
  });
}
