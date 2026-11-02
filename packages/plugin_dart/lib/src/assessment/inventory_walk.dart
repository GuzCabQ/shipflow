import 'dart:io';

import 'package:core/core.dart';

import '../recognition_exclusions.dart';
import '../scan_guard.dart';
import '../scan_model.dart';
import 'assessment_diagnostics.dart';
import 'assessment_ids.dart';
import 'source_reading.dart';

/// El recorrido del universo: lista cada directorio una vez en orden de
/// nombre, sin seguir enlaces ni abrir dispositivos, excluye por política,
/// sella las fuentes de reconocimiento y anota las fuentes elegibles de
/// cada unidad. Lo que no cabe queda como entrada con su motivo.
final class InventoryWalk {
  InventoryWalk(
    this.root,
    ProjectContext context,
    this.limits,
    this.elapsed,
    this.diagnostics,
  ) : guard = RootGuard(root),
      unitPaths = {for (final u in context.recognition.units) u.path},
      omissions = {
        for (final o in context.recognition.omissions)
          o.path: o.rule.toWireName(),
      };

  final Directory root;
  final AssessmentLimits limits;
  final int Function() elapsed;
  final DiagnosticGroups diagnostics;
  final RootGuard guard;
  final Set<String> unitPaths;
  final Map<String, String> omissions;
  final inputs = <AssessmentInput>[];

  /// Ruta y unidad dueña de cada fuente elegible.
  final candidates = <(String, String)>[];
  final listed = <String>{};
  final known = <String>{};
  final excluded = <String>{};
  var entries = 0;
  var complete = true;
  var _stopped = false;

  bool get late => elapsed() > limits.maxObservationMillis;

  String absolute(String relative) =>
      relative == '.' ? root.path : '${root.path}/$relative';

  Future<void> visit(String relative, int depth) async {
    if (_stopped) return;
    if (late) return _cut(relative, 'observation_deadline');
    if (depth > limits.maxDepth) return _cut(relative, 'depth_budget');
    final room = limits.maxEntries - entries;
    final List<FileSystemEntity> children;
    try {
      children = await Directory(
        absolute(relative),
      ).list(followLinks: false).take(room + 1).toList();
    } on FileSystemException {
      return _unreadable(relative);
    }
    if (children.length > room) {
      _stopped = true;
      return _cut(relative, 'entries_budget');
    }
    entries += children.length;
    final subdirectories = await _children(relative, depth, children);
    for (final sub in subdirectories) {
      await visit(sub, depth + 1);
    }
  }

  /// Clasifica cada hijo, sella el listado de [relative] con sus entradas
  /// relevantes y devuelve los subdirectorios por recorrer.
  Future<List<String>> _children(
    String relative,
    int depth,
    List<FileSystemEntity> children,
  ) async {
    final relevant = <String>[];
    final subdirectories = <String>[];
    for (final child in children..sort(byName)) {
      final name = nameOf(child.path);
      final path = relative == '.' ? name : '$relative/$name';
      if (!isAssessmentPath(path)) {
        complete = false;
        diagnostics.add('path_not_representable', relative);
        continue;
      }
      known.add(path);
      final type = FileSystemEntity.typeSync(child.path, followLinks: false);
      final mark = type == FileSystemEntityType.directory
          ? _directory(path, name, subdirectories)
          : await _entry(path, name, depth + 1, type);
      if (mark != null) relevant.add('$name\u0000$mark');
    }
    listed.add(relative);
    inputs.add(_listed(relative, relevant));
    return subdirectories;
  }

  String _directory(String path, String name, List<String> subdirectories) {
    final rule = baselineExclusions.contains(name)
        ? 'baseline_exclusion'
        : omissions[path];
    if (rule == null) {
      subdirectories.add(path);
      return 'd';
    }
    excluded.add(path);
    inputs.add(
      _unsealed(
        path,
        AssessmentInputKind.excluded,
        AssessmentInputState.excluded,
        rule,
      ),
    );
    return 'x';
  }

  /// La marca de un hijo que no es directorio, o null si no es relevante.
  Future<String?> _entry(
    String path,
    String name,
    int depth,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.link) {
      diagnostics.add('symlink_not_followed', path);
      return 'l';
    }
    if (type != FileSystemEntityType.file) {
      diagnostics.add('special_file_skipped', path);
      return 'o';
    }
    if (sourceKindOf(name, depth) != null) {
      inputs.add(await _recognitionSource(path));
      return 'r';
    }
    if (!name.endsWith('.dart')) return null;
    final owner = deepestUnitPath(path, unitPaths);
    if (owner == null) {
      diagnostics.add('outside_units', path);
      return 'f';
    }
    candidates.add((path, owner));
    return 's';
  }

  Future<AssessmentInput> _recognitionSource(String path) async {
    final read = await readSealed(
      guard,
      absolute(path),
      limits.maxSourceBytes,
      keep: false,
    );
    if (read.reason != null) diagnostics.add(read.reason!, path);
    return AssessmentInput(
      path: path,
      kind: AssessmentInputKind.recognitionSource,
      state: read.state,
      sha256: read.sha256,
      reason: read.reason,
    );
  }

  void _cut(String relative, String reason) {
    complete = false;
    diagnostics.add(reason, relative);
    inputs.add(
      _unsealed(
        relative,
        AssessmentInputKind.directory,
        AssessmentInputState.limit,
        reason,
      ),
    );
  }

  void _unreadable(String relative) {
    complete = false;
    diagnostics.add('directory_unreadable', relative);
    inputs.add(
      _unsealed(
        relative,
        AssessmentInputKind.directory,
        AssessmentInputState.unreadable,
        'directory_unreadable',
      ),
    );
  }
}

/// El listado sellado: la huella de los pares nombre y tipo relevantes,
/// nunca tiempos de modificación.
AssessmentInput _listed(String relative, List<String> relevant) =>
    AssessmentInput(
      path: relative,
      kind: AssessmentInputKind.directory,
      state: AssessmentInputState.listed,
      sha256: textHash(relevant.join('\n')),
      reason: null,
    );

AssessmentInput _unsealed(
  String path,
  AssessmentInputKind kind,
  AssessmentInputState state,
  String reason,
) => AssessmentInput(
  path: path,
  kind: kind,
  state: state,
  sha256: null,
  reason: reason,
);
