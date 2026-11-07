import 'dart:convert';

import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import 'basis_canonical.dart';
import 'basis_source_policy.dart';

/// Lee las fuentes locales citadas, una sola vez por ruta, por el almacén
/// anclado: archivos regulares bajo la raíz, sin seguir enlaces, dentro de
/// las cotas por archivo, totales y de cantidad. Nunca recorre el árbol,
/// nunca usa la red y nunca guarda el cuerpo.
final class BasisSourceReader {
  BasisSourceReader(this.store);

  final ContextStore store;

  /// Con [observe], una fuente sin huella registrada se lee para
  /// registrarla y queda `current` si se pudo leer; sin [observe] nunca es
  /// `current`, porque no hay con qué compararla.
  Future<BasisSourceReport> readSources(
    List<BasisRecordVersion> sources,
    BasisLimits limits, {
    bool observe = false,
  }) async {
    final run = _Run(store, limits, observe: observe);
    final statuses = <BasisSourceStatus>[];
    for (final record in sources) {
      final payload = record.payload;
      if (payload is! BasisSource) continue;
      final (state, code) = await run.state(payload);
      statuses.add(
        BasisSourceStatus(
          sourceId: record.id,
          sourceVersion: record.version,
          status: state,
          diagnostics: [if (code != null) _diagnostic(code, payload.locator)],
        ),
      );
    }
    return BasisSourceReport(
      statuses: statuses,
      readings: [
        for (final MapEntry(:key, :value) in run.digests.entries)
          BasisSourceReading(path: key, digest: value),
      ],
      complete: !run.budgetHit,
    );
  }
}

/// Una lectura: lo ya leído por ruta y lo cobrado de los presupuestos.
final class _Run {
  _Run(this.store, this.limits, {required this.observe});

  final ContextStore store;
  final BasisLimits limits;
  final bool observe;
  final digests = <String, String>{};
  final failures = <String, String>{};
  var opened = 0;
  var bytes = 0;
  var budgetHit = false;

  /// El estado de [source] frente a la huella que registró, si la tiene.
  Future<(BasisSourceState, String?)> state(BasisSource source) async {
    if (source.sourceType == BasisSourceType.external) {
      return (BasisSourceState.unverified, 'source_external');
    }
    final path = source.locator;
    if (isExcludedSourcePath(path)) {
      return (BasisSourceState.excluded, 'source_path_excluded');
    }
    if (!isAdmittedSourceType(path)) {
      return (BasisSourceState.unverified, 'source_type_not_admitted');
    }
    final failure = failures[path] ?? await _read(path);
    if (failure != null) return _failed(failure);
    final recorded = source.contentDigest;
    if (recorded == null) {
      return observe
          ? (BasisSourceState.current, null)
          : (BasisSourceState.unverified, 'source_not_recorded');
    }
    return recorded == digests[path]
        ? (BasisSourceState.current, null)
        : (BasisSourceState.stale, 'source_changed');
  }

  (BasisSourceState, String) _failed(String code) => (
    code == 'source_secret_excluded'
        ? BasisSourceState.excluded
        : BasisSourceState.unverified,
    code,
  );

  /// Lee [path] si no se leyó; el código del fallo, o null si quedó leída.
  Future<String?> _read(String path) async {
    if (digests.containsKey(path)) return null;
    final failure = await _readOnce(path);
    if (failure != null) failures[path] = failure;
    return failure;
  }

  Future<String?> _readOnce(String path) async {
    if (opened >= limits.maxSources) return _budget();
    opened++;
    final List<int>? content;
    try {
      content = await store.readRelative(path, maxBytes: limits.maxSourceBytes);
    } on ContextStoreFailure {
      return 'source_unreadable';
    }
    if (content == null) return 'source_absent';
    if (content.length > limits.maxSourceBytes) return 'source_too_large';
    if (bytes + content.length > limits.maxTotalSourceBytes) return _budget();
    bytes += content.length;
    final String text;
    try {
      text = utf8.decode(content);
    } on FormatException {
      return 'source_invalid_utf8';
    }
    if (hasCredentialMarker(text)) return 'source_secret_excluded';
    digests[path] = bytesDigest(content);
    return null;
  }

  String _budget() {
    budgetHit = true;
    return 'source_budget';
  }
}

const _messages = {
  'source_external':
      'Referencia externa: se conserva sin descargarla ni autenticarla.',
  'source_path_excluded':
      'Ubicación o nombre protegido: no se abre ni se calcula su huella.',
  'source_type_not_admitted':
      'Tipo no admitido: se conserva como referencia sin abrirla.',
  'source_secret_excluded':
      'Parece contener una credencial: no se guarda su huella.',
  'source_unreadable':
      'No se pudo leer como archivo regular bajo la raíz; los enlaces no se '
      'siguen.',
  'source_absent': 'La fuente ya no existe en esa ruta.',
  'source_too_large': 'La fuente supera el máximo por archivo; no se trunca.',
  'source_invalid_utf8': 'La fuente no es UTF-8 válido.',
  'source_budget': 'Se agotó el presupuesto de lectura de fuentes.',
  'source_changed': 'El contenido cambió desde su registro.',
  'source_not_recorded':
      'Se registró sin huella: no se puede saber si cambió. Prepárala de '
      'nuevo para observarla.',
};

BasisDiagnostic _diagnostic(String code, String path) =>
    BasisDiagnostic(code: code, message: _messages[code]!, path: path);
