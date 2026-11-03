import 'dart:io';

import 'package:cli/src/assessment/assessment_codec.dart';
import 'package:cli/src/assessment/assessment_store.dart';
import 'package:cli/src/context/secure_context_store.dart';
import 'package:core/core.dart';

import 'assessment_fixtures.dart';
import 'context_service_support.dart';

const operationA = '22222222-2222-4222-8222-222222222222';
const operationB = '33333333-3333-4333-8333-333333333333';

/// Un proyecto inicializado por V2, sin Git, listo para guardar
/// levantamientos con su almacén anclado real.
final class AssessmentBox {
  AssessmentBox._(this.box);

  static Future<AssessmentBox> initialized() async {
    final box = ServiceSandbox.create()..project();
    await box.run(ContextOperation.init);
    return AssessmentBox._(box);
  }

  final ServiceSandbox box;

  String path(String relative) => box.path(relative);

  File get document => File(path(assessmentPath));

  /// [body] con un almacén abierto sobre la raíz, envuelto si se pide.
  Future<T> withStore<T>(
    Future<T> Function(AssessmentStore store) body, {
    ContextStore Function(ContextStore real)? wrap,
  }) async {
    final real = await SecureContextStore.open(box.root);
    try {
      return await body(AssessmentStore(wrap == null ? real : wrap(real)));
    } finally {
      await real.close();
    }
  }

  /// Publica [document] con revalidaciones que no cambian nada, salvo que
  /// se pida otra cosa.
  Future<AssessmentPublication> publish(
    AssessmentDocument document, {
    String operationId = operationA,
    String? expected,
    Future<void> Function()? revalidate,
    ContextStore Function(ContextStore real)? wrap,
  }) => withStore(
    (store) => store.publish(
      document,
      operationId: operationId,
      expectedSha256: expected,
      baseContextDigest: document.current.contextDigest,
      preconditions: () async {},
      revalidate: revalidate ?? () async {},
    ),
    wrap: wrap,
  );

  /// Lo que hay bajo `shipflow/`, por ruta y bytes.
  Map<String, String> state() => {
    for (final e in Directory(
      path('shipflow'),
    ).listSync(recursive: true, followLinks: false).whereType<File>())
      e.path.substring(box.root.path.length + 1): sha256Of(e.readAsBytesSync()),
  };

  void dispose() => box.dispose();
}

/// La primera revisión del paquete y una segunda que la desplaza.
Future<(AssessmentDocument, AssessmentDocument)> twoRevisions() async {
  final first = await loadAssessmentFixture('valid-local.json');
  final zero = await loadAssessmentFixture('valid-zero-references.json');
  return (
    first,
    AssessmentDocument(
      projectId: first.projectId,
      revision: 2,
      current: zero.current,
      previous: first.current,
    ),
  );
}
