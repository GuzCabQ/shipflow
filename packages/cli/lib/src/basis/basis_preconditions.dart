import 'package:core/core.dart';

import '../context/state_layout.dart';
import 'basis_sources.dart';

/// Lo que una aceptación o una recuperación revalida: el mismo proyecto y
/// contexto, la base esperada y las fuentes leídas al preparar.
final class BasisPreconditions {
  BasisPreconditions({
    required this.state,
    required this.projectId,
    required this.currentBasisDigest,
    required this.expectedBasisDigest,
    required this.contextProjectDigest,
    required this.sourceReads,
    required this.sources,
  });

  /// El proyecto V2 tal como está al revalidar.
  final BasisEnvironment state;
  final String projectId;

  /// La huella del documento vigente ahora; null si no existe.
  final String? currentBasisDigest;
  final String? expectedBasisDigest;
  final String contextProjectDigest;
  final List<BasisSourceReading> sourceReads;

  /// Las lecturas de la operación que revalida.
  final BasisSourceSession sources;
}

/// La primera precondición que ya no se cumple, o null. Una aprobación
/// nunca se transfiere a otra base, otro contexto u otros bytes de fuente.
Future<BasisDiagnostic?> checkBasisPreconditions(BasisPreconditions p) async =>
    _project(p.state) ?? _identity(p) ?? await _sources(p);

/// Ninguna operación de init o de assess sin terminar, y un contexto
/// disponible y válido.
BasisDiagnostic? _project(BasisEnvironment state) {
  if (state.contextRecoveryPending || state.assessmentRecoveryPending) {
    return _failure(
      'recovery_required',
      'Hay una operación de init o de assess sin terminar.',
      state.contextRecoveryPending
          ? transactionPath
          : assessmentTransactionPath,
    );
  }
  if (state.context != BasisIntegrity.valid) {
    return _failure(
      'context_required',
      'El contexto inicial no está disponible y válido.',
      projectPath,
    );
  }
  return null;
}

/// El mismo proyecto, el mismo contexto y la misma base que al preparar.
BasisDiagnostic? _identity(BasisPreconditions p) {
  if (p.state.projectId != p.projectId ||
      p.state.contextDigest != p.contextProjectDigest) {
    return _failure(
      'base_changed',
      'El contexto inicial cambió desde que se preparó el borrador.',
      projectPath,
    );
  }
  if (p.currentBasisDigest != p.expectedBasisDigest) {
    return _failure(
      'base_changed',
      'La base cambió desde que se preparó el borrador.',
      basisDocumentPath,
    );
  }
  return null;
}

/// Cada fuente leída al preparar se vuelve a leer con la misma huella. Lo
/// que no cabe en el presupuesto de la operación no se da por vigente.
Future<BasisDiagnostic?> _sources(BasisPreconditions p) async {
  final checks = [
    for (final (i, read) in p.sourceReads.indexed) _recorded(i, read),
  ];
  final report = await p.sources.read(checks);
  String? unread;
  for (final (i, status) in report.statuses.indexed) {
    if (status.diagnostics.any((d) => d.code == 'source_budget')) {
      unread ??= p.sourceReads[i].path;
    } else if (status.status != BasisSourceState.current) {
      return _failure(
        'source_changed',
        'Una fuente cambió o ya no se puede leer desde que se preparó.',
        p.sourceReads[i].path,
      );
    }
  }
  if (unread == null) return null;
  return _failure(
    'budget_exceeded',
    'Las fuentes no caben en el presupuesto de lectura de esta operación: '
        'no se pueden revalidar y no se publica.',
    unread,
  );
}

/// [read] como una versión de fuente con la huella que registró.
BasisRecordVersion _recorded(int i, BasisSourceReading read) =>
    BasisRecordVersion(
      id: '00000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
      version: 1,
      previousVersion: null,
      payload: BasisSource(
        title: read.path,
        scope: BasisScope.project(),
        lifecycle: BasisSourceLifecycle.active,
        sourceType: BasisSourceType.local,
        locator: read.path,
        purpose: read.path,
        contentDigest: read.digest,
        observation: BasisObservation.current,
      ),
    );

BasisDiagnostic _failure(String code, String message, String path) =>
    BasisDiagnostic(code: code, message: message, path: path);
