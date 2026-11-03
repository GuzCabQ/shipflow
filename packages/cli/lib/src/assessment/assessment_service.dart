import 'dart:io';

import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import 'assessment_binding.dart';
import 'assessment_observe_flow.dart';
import 'assessment_recover_flow.dart';
import 'assessment_show_flow.dart';
import 'assessment_snapshot_builder.dart';

export 'assessment_binding.dart' show ContextBasisProjector;
export 'assessment_snapshot_builder.dart' show AssessmentProducerInfo;

/// Lo que el plugin observa del código: inyectado por la raíz de
/// composición, porque el CLI no conoce el stack.
typedef AssessmentObserver =
    Future<AssessmentObservation> Function(
      Directory root,
      ProjectContext context,
      AssessmentLimits limits,
    );

/// El inventario compartido sin parser, para comprobar vigencia.
typedef AssessmentInputObserver =
    Future<List<AssessmentInput>> Function(
      Directory root,
      ProjectContext context,
      AssessmentLimits limits,
    );

/// El doctor de V2 con el perfil pedido: sólo lee.
typedef ContextDoctor =
    Future<ContextOperationResult> Function(AssessmentProfile profile);

/// Qué pide una invocación de assess.
final class AssessmentRequest {
  const AssessmentRequest({
    required this.operation,
    this.profile = AssessmentProfile.standard,
    this.previous = false,
  });

  final AssessmentOperation operation;
  final AssessmentProfile profile;

  /// Sólo con show: la revisión anterior, como historia.
  final bool previous;
}

/// Compone preflight V2, observación, vigencia, admisión, almacenamiento y
/// comparación para una raíz ya resuelta. Cada operación devuelve un único
/// resultado, del que salen la vista humana y el JSON.
final class AssessmentService {
  AssessmentService({
    required this.root,
    required this.store,
    required this.observe,
    required this.observeInputs,
    required this.basisOf,
    required this.doctor,
    required this.version,
    required this.now,
    required this.newId,
    AssessmentProducerInfo? producer,
    AssessmentLimits Function(AssessmentProfile)? limitsFor,
  }) : producer = producer ?? _unnamed,
       _limitsFor = limitsFor;

  final Directory root;
  final ContextStore store;
  final AssessmentObserver observe;
  final AssessmentInputObserver observeInputs;
  final ContextBasisProjector basisOf;
  final ContextDoctor doctor;
  final String version;
  final DateTime Function() now;
  final String Function() newId;
  final AssessmentProducerInfo producer;
  final AssessmentLimits Function(AssessmentProfile)? _limitsFor;

  AssessmentLimits limits(AssessmentProfile profile) =>
      _limitsFor?.call(profile) ?? AssessmentLimits.forProfile(profile);

  Future<AssessmentResult> run(AssessmentRequest request) =>
      switch (request.operation) {
        AssessmentOperation.observe => observeAssessmentFlow(this, request),
        AssessmentOperation.show => showAssessmentFlow(this, request),
        AssessmentOperation.recover => recoverAssessmentFlow(this, request),
      };
}

/// El productor por omisión de las pruebas; la raíz de composición nombra
/// el plugin real.
const AssessmentProducerInfo _unnamed = (
  contract: 'source-topology-v3.2',
  pluginId: 'plugin_dart',
  parserVersion: '14.1.0',
);
