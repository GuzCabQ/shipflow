import 'dart:io';

import 'package:core/core.dart';

/// La carpeta de estado propio, relativa a la raíz.
const stateDirectory = 'shipflow';
const projectPath = 'shipflow/project.json';
const gitignorePath = 'shipflow/.gitignore';
const settingsPath = 'shipflow/local/settings.json';
const transactionPath = 'shipflow/local/transaction.json';
const previousPath = 'shipflow/local/previous.json';

/// El levantamiento portable y el journal de su publicación (V3).
const assessmentDocumentPath = 'shipflow/assessment.json';
const assessmentTransactionPath = 'shipflow/local/assessment-transaction.json';

/// La base guiada portable, su borrador y el journal de su publicación (V4).
const basisDocumentPath = 'shipflow/basis.json';
const basisDraftPath = 'shipflow/local/basis-draft.json';
const basisTransactionPath = 'shipflow/local/basis-transaction.json';

/// Los bytes exactos del `.gitignore` que genera init.
const generatedGitignore =
    '# Local operational state; project.json remains shareable.\n/local/\n';

/// Más entradas que éstas no pueden ser sólo el estado propio: un staging
/// activo por protocolo y temporales acotados.
const _maxStateEntries = 128;

const _directories = {
  'local',
  'local/staging',
  'local/locks',
  'local/assessment-staging',
};
const _lock = 'local/locks/context.lock';
const _stagedNames = {
  'project.json',
  'settings.before.json',
  'settings.after.json',
};
final _temporary = RegExp(
  r'^(?:local/(?:staging/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}'
  r'-[0-9a-f]{12}/)?)?\.(?:project\.json|settings\.json|transaction\.json|'
  r'previous\.json|\.gitignore|settings\.before\.json|settings\.after\.json)'
  r'\.[0-9a-f]{16}\.tmp$',
);

final _assessmentTemporary = RegExp(
  r'^(?:\.assessment\.json|local/\.assessment-transaction\.json|'
  r'local/assessment-staging/[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab]'
  r'[0-9a-f]{3}-[0-9a-f]{12}/\.candidate\.json)\.[0-9a-f]{16}\.tmp$',
);

/// Si [path], relativa a la raíz, tiene la forma de un temporal de una
/// publicación de assess. La forma no prueba propiedad.
bool isAssessmentTemporary(String path) =>
    path.startsWith('$stateDirectory/') &&
    _assessmentTemporary.hasMatch(path.substring(stateDirectory.length + 1));

/// Si [path], relativa a la raíz, tiene la forma de un temporal de una
/// publicación propia. La forma no prueba propiedad: sólo un journal válido
/// autoriza a retirarlo.
bool isOwnTemporary(String path) =>
    path.startsWith('$stateDirectory/') &&
    _temporary.hasMatch(path.substring(stateDirectory.length + 1));

/// Qué hay en `shipflow/` respecto del contrato V2.
enum StateOwnershipKind {
  /// No existe: puede inicializarse.
  absent,

  /// Un directorio vacío: puede inicializarse.
  empty,

  /// Sólo el andamiaje que crea init: puede reintentarse.
  bootstrap,

  /// Un contexto o una transacción propia que cumple el formato.
  owned,

  /// Con la forma de Shipflow, pero un documento no valida o hay restos que
  /// no se pueden acreditar: se conserva y se diagnostica.
  invalid,

  /// Contenido de otra herramienta o entidades que el contrato no admite.
  foreign,
}

/// La clasificación y las rutas, relativas a la raíz, que la justifican.
final class StateOwnership {
  StateOwnership(
    this.kind, [
    List<String> findings = const [],
    this.assessmentJournal = false,
  ]) : findings = List.unmodifiable(findings);

  final StateOwnershipKind kind;
  final List<String> findings;

  /// Si hay un journal de assess válido: sólo `assess --recover` lo
  /// termina; init no lo recupera ni adivina un orden con el suyo.
  final bool assessmentJournal;

  /// Sólo un estado propio comprobado, o su ausencia, se omite del
  /// reconocimiento: el nombre por sí solo no prueba propiedad.
  bool get authorizesOmission => const {
    StateOwnershipKind.absent,
    StateOwnershipKind.empty,
    StateOwnershipKind.bootstrap,
    StateOwnershipKind.owned,
  }.contains(kind);
}

enum DocumentKind {
  project,
  settings,
  transaction,
  assessment,
  assessmentTransaction,
}

/// Qué documento es [path], relativa a la raíz.
DocumentKind documentKindOf(String path) => path == assessmentDocumentPath
    ? DocumentKind.assessment
    : path == assessmentTransactionPath
    ? DocumentKind.assessmentTransaction
    : path.endsWith('transaction.json')
    ? DocumentKind.transaction
    : path.contains('settings')
    ? DocumentKind.settings
    : DocumentKind.project;

/// Lo que hay bajo `shipflow/`, sólo por metadatos y ya ordenado.
final class ObservedLayout {
  ObservedLayout(this.entries);

  final List<String> entries;
  final documents = <String>[];
  final temporaries = <String>[];
  final staging = <String>[];

  /// Temporales y candidatos de assess: sólo un journal de assess los
  /// acredita, o un candidato completo y propio.
  final assessmentTemporaries = <String>[];
  final assessmentCandidates = <String>[];
  var hasGitignore = false;
}

/// La forma de `shipflow/`: un [StateOwnership] si ya decide (ausente, no
/// directorio, ajeno), o un [ObservedLayout] con sus documentos por leer.
Future<Object> observeStateLayout(Directory root) async {
  final base = '${root.path}/$stateDirectory';
  final type = FileSystemEntity.typeSync(base, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return StateOwnership(StateOwnershipKind.absent);
  }
  if (type != FileSystemEntityType.directory) {
    return StateOwnership(StateOwnershipKind.foreign, [stateDirectory]);
  }
  final listed = await _list(Directory(base));
  if (listed == null) {
    return StateOwnership(StateOwnershipKind.foreign, [stateDirectory]);
  }
  final layout = ObservedLayout([for (final (path, _) in listed) path]);
  final foreign = [
    for (final (path, type) in listed)
      if (!_place(layout, path, type)) '$stateDirectory/$path',
  ];
  if (foreign.isNotEmpty) {
    return StateOwnership(StateOwnershipKind.foreign, foreign);
  }
  return layout;
}

/// Hasta [_maxStateEntries] entradas, relativas a `shipflow/`, o null si no
/// caben o no se pueden listar.
Future<List<(String, FileSystemEntityType)>?> _list(Directory base) async {
  try {
    final entities = await base
        .list(recursive: true, followLinks: false)
        .take(_maxStateEntries + 1)
        .toList();
    if (entities.length > _maxStateEntries) return null;
    return [
      for (final e in entities)
        (
          e.path.substring(base.path.length + 1),
          FileSystemEntity.typeSync(e.path, followLinks: false),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
  } on FileSystemException {
    return null;
  }
}

/// Anota [path] en [layout] si el contrato lo admite con ese tipo.
bool _place(ObservedLayout layout, String path, FileSystemEntityType type) {
  final directory = type == FileSystemEntityType.directory;
  final file = type == FileSystemEntityType.file;
  final segments = path.split('/');
  if (directory) {
    return _directories.contains(path) ||
        _stagingDirectory(segments) ||
        _assessmentStaging(segments);
  }
  if (!file) return false;
  final full = '$stateDirectory/$path';
  if (path == '.gitignore') return layout.hasGitignore = true;
  if (path == _lock) return true;
  if (_temporary.hasMatch(path)) return _add(layout.temporaries, full);
  if (_placeAssessment(layout, path, segments)) return true;
  if (_stagingDirectory(segments.take(3).toList()) &&
      segments.length == 4 &&
      _stagedNames.contains(segments[3])) {
    return _add(layout.staging, full);
  }
  return const {
        'project.json',
        'local/settings.json',
        'local/transaction.json',
        'local/previous.json',
        'assessment.json',
        'local/assessment-transaction.json',
      }.contains(path) &&
      _add(layout.documents, full);
}

bool _stagingDirectory(List<String> segments) =>
    segments.length == 3 &&
    segments[0] == 'local' &&
    segments[1] == 'staging' &&
    isUuidV4(segments[2]);

/// Anota un temporal o un candidato de assess; false si no es ninguno.
bool _placeAssessment(
  ObservedLayout layout,
  String path,
  List<String> segments,
) {
  final full = '$stateDirectory/$path';
  if (_assessmentTemporary.hasMatch(path)) {
    return _add(layout.assessmentTemporaries, full);
  }
  return _assessmentStaging(segments.take(3).toList()) &&
      segments.length == 4 &&
      segments[3] == 'candidate.json' &&
      _add(layout.assessmentCandidates, full);
}

bool _assessmentStaging(List<String> segments) =>
    segments.length == 3 &&
    segments[0] == 'local' &&
    segments[1] == 'assessment-staging' &&
    isUuidV4(segments[2]);

bool _add(List<String> into, String path) {
  into.add(path);
  return true;
}
