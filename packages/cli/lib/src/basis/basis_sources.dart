import 'dart:convert';
import 'dart:math';

import 'package:core/core.dart';

import '../context/secure_context_store.dart';
import 'basis_canonical.dart';
import 'basis_source_policy.dart';

/// Lee las fuentes locales citadas por el almacén anclado: archivos
/// regulares bajo la raíz, sin seguir enlaces, dentro de las cotas por
/// archivo, totales y de cantidad. Nunca recorre el árbol, nunca usa la red
/// y nunca guarda el cuerpo.
final class BasisSourceReader {
  BasisSourceReader(this.store);

  final ContextStore store;

  /// Las lecturas de una operación: cada ruta se lee a lo sumo una vez y
  /// todas cobran de un solo presupuesto de [limits].
  BasisSourceSession session(BasisLimits limits) =>
      BasisSourceSession._(store, limits);

  /// Una lectura suelta, con su propio presupuesto.
  Future<BasisSourceReport> readSources(
    List<BasisRecordVersion> sources,
    BasisLimits limits, {
    bool observe = false,
  }) => session(limits).read(sources, observe: observe);
}

/// Lo leído en una operación, por ruta, y lo cobrado de sus presupuestos:
/// una fase posterior de la misma operación usa la misma observación en
/// vez de volver a leer.
final class BasisSourceSession {
  BasisSourceSession._(this.store, this.limits);

  final ContextStore store;
  final BasisLimits limits;
  final _digests = <String, String>{};
  final _failures = <String, String>{};
  var _opened = 0;
  var _bytes = 0;

  /// Con [observe], una fuente sin huella registrada se lee para
  /// registrarla y queda `current` si se pudo leer; sin [observe] nunca es
  /// `current`, porque no hay con qué compararla.
  Future<BasisSourceReport> read(
    List<BasisRecordVersion> sources, {
    bool observe = false,
  }) async {
    final statuses = <BasisSourceStatus>[];
    final readings = <String, String>{};
    var complete = true;
    for (final record in sources) {
      final payload = record.payload;
      if (payload is! BasisSource) continue;
      final (state, code) = await _state(payload, observe: observe);
      if (code == 'source_budget') complete = false;
      if (_digests[payload.locator] case final digest?) {
        readings[payload.locator] = digest;
      }
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
        for (final MapEntry(:key, :value) in readings.entries)
          BasisSourceReading(path: key, digest: value),
      ],
      complete: complete,
    );
  }

  /// El estado de [source] frente a la huella que registró, si la tiene.
  Future<(BasisSourceState, String?)> _state(
    BasisSource source, {
    required bool observe,
  }) async {
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
    final failure = _failures[path] ?? await _read(path);
    if (failure != null) return _failed(failure);
    final recorded = source.contentDigest;
    if (recorded == null) {
      return observe
          ? (BasisSourceState.current, null)
          : (BasisSourceState.unverified, 'source_not_recorded');
    }
    return recorded == _digests[path]
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
    if (_digests.containsKey(path)) return null;
    final failure = await _readOnce(path);
    if (failure != null) _failures[path] = failure;
    return failure;
  }

  /// Cada lectura se acota por lo que queda del presupuesto total y cobra
  /// lo que de verdad leyó; agotado, no se abre nada más.
  Future<String?> _readOnce(String path) async {
    final remaining = limits.maxTotalSourceBytes - _bytes;
    if (_opened >= limits.maxSources || remaining <= 0) return 'source_budget';
    _opened++;
    final cap = min(limits.maxSourceBytes, remaining);
    final List<int>? content;
    try {
      content = await store.readRelative(path, maxBytes: cap);
    } on ContextStoreFailure {
      return 'source_unreadable';
    }
    if (content == null) return 'source_absent';
    _bytes += content.length;
    if (content.length > cap) {
      return cap == limits.maxSourceBytes
          ? 'source_too_large'
          : 'source_budget';
    }
    final String text;
    try {
      text = utf8.decode(content);
    } on FormatException {
      return 'source_invalid_utf8';
    }
    if (hasCredentialMarker(text)) return 'source_secret_excluded';
    _digests[path] = bytesDigest(content);
    return null;
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
