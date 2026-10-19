import 'dart:io';

import 'package:core/core.dart';

import 'context_source_observer.dart';
import 'context_source_rule.dart';
import 'derived_observation_budget.dart';
import 'manifest_evidence.dart';
import 'pubspec_observer.dart';
import 'recognition_codes.dart';
import 'recognition_exclusions.dart';
import 'scan_guard.dart';
import 'scan_limits.dart';
import 'scan_model.dart';
import 'stable_file_reader.dart';

export 'scan_model.dart';

/// Recorre [root] en orden de ruta, sin seguir enlaces y dentro de
/// [limits]. En cada directorio analiza primero su manifiesto, para saber
/// qué árboles excluye antes de entrar en ellos; al final consulta los
/// metadatos de [contextSources] en la raíz y en cada raíz de unidad. Lo que
/// no pudo mirar queda como limitación bloqueante; todo lo retenido se cobra
/// a [budget] antes de crearse.
Future<ScanResult> scanProject(
  Directory root, {
  ScanLimits limits = const ScanLimits(),
  DirectoryLister list = listWithoutFollowing,
  ByteReader readBytes = readBoundedBytes,
  DerivedObservationBudget? budget,
  List<ContextSourceRule> contextSources = const [],
}) async {
  final scan = _Scan(
    RootGuard(root),
    limits,
    list,
    readBytes,
    budget ?? DerivedObservationBudget(const ReportLimits()),
    contextSources,
  );
  await scan.visit(root, 0);
  scan.observeContext();
  return scan.result();
}

final class _Scan {
  _Scan(
    this.guard,
    this.limits,
    this.list,
    this.readBytes,
    this.budget,
    this.rules,
  ) : _fileRules = {
        for (final rule in rules)
          if (!rule.expectsDirectory) rule.relativePath,
      };

  final RootGuard guard;
  final ScanLimits limits;
  final DirectoryLister list;
  final ByteReader readBytes;
  final DerivedObservationBudget budget;
  final List<ContextSourceRule> rules;
  final Set<String> _fileRules;
  final sources = <ScannedSource>[];
  final limitations = <RecognitionLimitation>[];
  final manifests = <ManifestEvidence>[];
  final manifestLimitations = <RecognitionLimitation>[];
  final omissions = <OmissionDraft>[];
  final _exclusions = <String, OmissionDraft>{};
  final _scopes = {'.'};
  var _contextSources = <ContextSource>[];
  var _entries = 0;
  var _manifests = 0;
  var _sourceBytes = 0;
  var _stopped = false;

  ScanResult result() => ScanResult(
    sources: sources..sort((a, b) => a.path.compareTo(b.path)),
    limitations: limitations,
    manifests: manifests
      ..sort((a, b) => a.facts.source.path.compareTo(b.facts.source.path)),
    manifestLimitations: manifestLimitations,
    omissions: omissions..sort((a, b) => a.path.compareTo(b.path)),
    contextSources: _contextSources
      ..sort(
        (a, b) => a.scopePath == b.scopePath
            ? a.path.compareTo(b.path)
            : a.scopePath.compareTo(b.scopePath),
      ),
  );

  /// Pide a lo sumo una entrada más de las que caben: si el directorio no
  /// cabe entero se corta en él, porque qué entradas llegaron primero depende
  /// del orden del sistema de archivos.
  Future<void> visit(Directory directory, int depth) async {
    final deep = depth + 1 > limits.maxDepth;
    final room = limits.maxEntries - _entries;
    final children = await _list(directory, deep ? 1 : room + 1);
    if (children == null) return;
    final why = depth == 0 ? null : guard.escapedDirectory(directory.path);
    if (why != null) return _block(why.code, why.message, directory.path);
    if (children.length > room) {
      return _stop('entradas', limits.maxEntries, directory.path);
    }
    _entries += children.length;
    if (children.isEmpty) return;
    if (deep) {
      return _block(
        LimitationCode.scanLimitReached,
        'excede la profundidad máxima de ${limits.maxDepth}; no se inspeccionó',
        directory.path,
      );
    }
    await _visitChildren(children..sort(byName), depth + 1);
  }

  /// El manifiesto regular primero, y después el resto en orden de nombre.
  Future<void> _visitChildren(
    List<FileSystemEntity> children,
    int depth,
  ) async {
    final manifest = children
        .where((c) => c is File && nameOf(c.path) == manifestFileName)
        .firstOrNull;
    for (final child in [?manifest, ...children.where((c) => c != manifest)]) {
      if (_stopped) return;
      await _visitEntity(child, depth);
    }
  }

  /// Hasta [count] entradas de [directory], o null si no se pudo listar.
  Future<List<FileSystemEntity>?> _list(Directory directory, int count) async {
    try {
      return await list(directory).take(count).toList();
    } on FileSystemException {
      _block(
        LimitationCode.subtreeUnreadable,
        'no se pudo listar este directorio; su contenido no se inspeccionó',
        directory.path,
      );
      return null;
    }
  }

  Future<void> _visitEntity(FileSystemEntity entity, int depth) async {
    final relative = guard.relative(entity.path);
    if (entity is! File && baselineExclusions.contains(nameOf(relative))) {
      return _omit(OmissionDraft(relative, OmissionRule.baselineExclusion, []));
    }
    switch (entity) {
      case Link() || Directory() when _exclusions[relative] != null:
        _omit(_exclusions[relative]!);
      case Link() when _optionalCandidate(relative):
        return;
      case Link():
        _block(LimitationCode.symlinkNotFollowed, linkMessage, entity.path);
      case Directory():
        if (guard.escapedDirectory(entity.path) case final why?) {
          return _block(why.code, why.message, entity.path);
        }
        await visit(entity, depth);
      case File():
        final kind = _kindOf(nameOf(relative), depth);
        if (kind == null) return;
        if (guard.escapedFile(entity.path) case final why?) {
          return _block(why.code, why.message, entity.path);
        }
        await _accept(entity, kind);
    }
  }

  /// Un enlace con el nombre de un archivo opcional del catálogo, en una
  /// raíz de unidad, no bloquea: se informa como fuente candidata.
  bool _optionalCandidate(String relative) => _scopes.any(
    (scope) => _fileRules.contains(
      scope == '.'
          ? relative
          : relative.startsWith('$scope/')
          ? relative.substring(scope.length + 1)
          : null,
    ),
  );

  SourceKind? _kindOf(String name, int depth) => switch (name) {
    manifestFileName => SourceKind.manifest,
    fvmConfigFileName when depth == 1 => SourceKind.fvmConfig,
    flutterVersionFileName when depth == 1 => SourceKind.flutterVersionFile,
    _ => null,
  };

  Future<void> _accept(File file, SourceKind kind) async {
    final isManifest = kind == SourceKind.manifest;
    if (isManifest && ++_manifests > limits.maxManifests) {
      return _stop('manifiestos', limits.maxManifests, file.path);
    }
    final read = await readStableFile(
      file,
      maxBytes: isManifest ? limits.maxManifestBytes : limits.maxMarkerBytes,
      readBytes: _revalidatedRead,
    );
    if (guard.escapedFile(file.path) case final why?) {
      return _block(why.code, why.message, file.path);
    }
    if (read is StableSource) return _keep(file, kind, read);
    final (code, message) = rejectionOf(read);
    _block(code, message, file.path);
  }

  void _keep(File file, SourceKind kind, StableSource read) {
    if (_sourceBytes + read.size > limits.maxTotalSourceBytes) {
      return _stop('bytes', limits.maxTotalSourceBytes, file.path);
    }
    _sourceBytes += read.size;
    final source = ScannedSource(guard.relative(file.path), kind, read);
    sources.add(source);
    if (kind == SourceKind.manifest) _analyze(source);
  }

  /// Una sola vez: sus hechos sirven al reconocedor y sus exclusiones, al
  /// resto del recorrido de este directorio. Sólo un paquete con nombre y
  /// sin limitaciones bloqueantes concede exclusiones.
  void _analyze(ScannedSource source) {
    final observation = observeManifest(source, budget: budget);
    manifestLimitations.addAll(observation.limitations);
    final facts = observation.facts;
    if (facts == null) return;
    final evidence = ManifestEvidence(facts);
    manifests.add(evidence);
    if (facts.name == null) return;
    _scopes.add(evidence.unitPath);
    if (observation.limitations.every((l) => !l.blocking)) {
      _exclusions.addAll(exclusionsOf(evidence));
    }
  }

  /// Las fuentes candidatas, con las entradas que queden. Si el recorrido ya
  /// se cortó, no hay presupuesto que consultar.
  void observeContext() {
    if (_stopped || rules.isEmpty) return;
    final (:sources, :stoppedAt) = observeContextSources(
      [..._scopes]..sort(),
      rules,
      ContextProbe(
        root: guard.root,
        maxDepth: limits.maxDepth,
        omitted: (path) => omissions.any(
          (o) => path == o.path || path.startsWith('${o.path}/'),
        ),
        consumeEntry: () => _entries < limits.maxEntries && ++_entries > 0,
        budget: budget,
      ),
    );
    _contextSources = sources;
    if (stoppedAt != null) {
      _stop('entradas', limits.maxEntries, '${guard.root.path}/$stoppedAt');
    }
  }

  /// Revalida antes de cada lectura, no sólo antes de la primera: abrir lo
  /// que ya no es la fuente enumerada podría leer fuera de la raíz o, con un
  /// FIFO, no volver nunca. El motivo exacto lo informa [_accept] después.
  Future<List<int>> _revalidatedRead(File file, int maxBytes) {
    if (guard.escapedFile(file.path) != null) {
      throw const FileSystemException('cambió antes de leerse');
    }
    return readBytes(file, maxBytes);
  }

  void _stop(String what, int max, String path) {
    _stopped = true;
    _block(
      LimitationCode.scanLimitReached,
      'se alcanzó el máximo de $max $what; el resto no se inspeccionó',
      path,
    );
  }

  /// Cobrada antes de crearse, como cada omisión.
  void _omit(OmissionDraft draft) {
    budget.row([draft.path, draft.rule.toWireName()]);
    omissions.add(draft);
  }

  void _block(String code, String message, String path) {
    final relative = guard.relative(path);
    budget.row([code, message, relative]);
    limitations.add(
      RecognitionLimitation(
        code: code,
        message: message,
        path: relative,
        blocking: true,
      ),
    );
  }
}
