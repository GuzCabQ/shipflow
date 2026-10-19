import 'dart:io';

import 'package:core/core.dart';

import 'derived_observation_budget.dart';
import 'evidence_draft.dart';
import 'manifest_evidence.dart';
import 'path_dependency_boundary.dart';
import 'recognition_codes.dart';
import 'recognition_exclusions.dart';
import 'relation_diagnostics.dart';

/// Una relación ya ubicada, antes de tener ID: los IDs dependen del orden
/// de todas. Su fila se cobró al crearse.
typedef _Pending = ({
  RelationKind kind,
  String fromPath,
  String? declaredName,
  String? target,
  String? unitId,
  RelationStatus status,
  List<EvidenceDraft> evidence,
});

/// Las relaciones locales que declaran [manifests], sobre lo ya recorrido:
/// no abre contenidos ni vuelve a listar árboles. Sólo queda corroborada
/// una relación cuyo destino es una unidad observada y, si es una
/// dependencia, con el mismo nombre; si no, queda sin resolver, con una
/// limitación bloqueante o un conflicto que la ubica. Cada fila se cobra a
/// [budget] antes de crearse, y cada referencia al proyectarla con [ids].
({
  List<RecognitionRelation> relations,
  List<RecognitionLimitation> limitations,
  List<ConflictDraft> conflicts,
})
resolveLocalRelations({
  required Directory root,
  required List<ManifestEvidence> manifests,
  required List<ProjectUnit> units,
  required List<OmissionDraft> omissions,
  required Map<EvidenceDraft, String> ids,
  required DerivedObservationBudget budget,
}) {
  final resolver = _Resolver(root, omissions, budget, {
    for (final unit in units) unit.path: unit,
  });
  manifests.forEach(resolver.register);
  for (final manifest in manifests) {
    resolver.declarationsOf(manifest).forEach(resolver.resolve);
  }
  return (
    relations: resolver.relations(ids),
    limitations: resolver.limitations,
    conflicts: resolver.conflicts,
  );
}

final class _Resolver {
  _Resolver(this.root, this.omissions, this.budget, this.units);

  final Directory root;
  final List<OmissionDraft> omissions;
  final DerivedObservationBudget budget;
  final Map<String, ProjectUnit> units;
  final _targets = <String, EvidenceDraft>{};
  final pending = <_Pending>[];
  final limitations = <RecognitionLimitation>[];
  final conflicts = <ConflictDraft>[];

  /// Las dependencias locales y los miembros del workspace de [manifest],
  /// cada uno con su evidencia. Registra su nombre como destino posible.
  Iterable<(ManifestEvidence, Declaration)> declarationsOf(
    ManifestEvidence manifest,
  ) sync* {
    final facts = manifest.facts;
    for (final (i, d) in facts.pathDependencies.indexed) {
      yield (
        manifest,
        Declaration(
          RelationKind.localDependency,
          d.evidenceValue,
          d.truncated ? null : d.name,
          d.truncated ? null : d.path,
          manifest.pathDependencies[i],
        ),
      );
    }
    for (final (i, member) in facts.workspace.indexed) {
      yield (
        manifest,
        Declaration(
          RelationKind.workspaceMember,
          'workspace: ${member.text}',
          null,
          member.truncated ? null : member.text,
          manifest.workspace[i],
        ),
      );
    }
  }

  void register(ManifestEvidence manifest) {
    if (manifest.name case final name?) _targets[manifest.unitPath] = name;
  }

  /// Un valor truncado ya bloquea en su manifiesto y no se interpreta.
  void resolve((ManifestEvidence, Declaration) declared) {
    final (manifest, declaration) = declared;
    final path = declaration.path;
    final placement = path == null ? null : _place(manifest, declaration);
    final target = placement is ReferenceInside ? placement.path : null;
    final unit = placement is ReferenceInside && placement.exists
        ? units[target]
        : null;
    final source = manifest.facts.source.path;
    if (placement != null) {
      final problem = relationProblem(
        declaration,
        placement,
        unitFound: unit != null,
        root: root.path,
      );
      if (problem case (final code, final message)?) {
        _block(code, message, source);
      }
    }
    _keep(manifest, declaration, target, unit);
  }

  ReferencePlacement _place(ManifestEvidence manifest, Declaration d) {
    if (unsupportedForm(d.kind, d.path!) case final reason?) {
      return ReferenceUnsupported(reason);
    }
    return placeReference(
      root,
      manifest.unitPath,
      d.path!,
      omittedTree: _omittedTree,
    );
  }

  /// Corroborada sólo con unidad y, en una dependencia, el mismo nombre;
  /// un nombre distinto es un conflicto que cita ambas evidencias.
  void _keep(
    ManifestEvidence manifest,
    Declaration declaration,
    String? target,
    ProjectUnit? unit,
  ) {
    final name = unit == null ? null : _targets[unit.path];
    final evidence = [declaration.evidence, ?name];
    final mismatch =
        unit != null &&
        declaration.kind == RelationKind.localDependency &&
        declaration.name != unit.name;
    if (mismatch) _mismatch(declaration, target!, unit.name, evidence);
    final relation = (
      kind: declaration.kind,
      fromPath: manifest.unitPath,
      declaredName: declaration.name,
      target: target,
      unitId: unit?.id,
      status: unit != null && !mismatch
          ? RelationStatus.corroborated
          : RelationStatus.unresolved,
      evidence: evidence,
    );
    budget.row(_texts(relation));
    pending.add(relation);
  }

  void _mismatch(
    Declaration declaration,
    String target,
    String actual,
    List<EvidenceDraft> evidence,
  ) => conflicts.add(
    admitConflict(
      budget,
      ConflictCode.localDependencyNameMismatch,
      nameMismatch(declaration, target, actual),
      evidence,
      evidenceOf: (d) => d,
    ),
  );

  void _block(String code, String message, String path) {
    budget.row([code, message, path]);
    limitations.add(
      RecognitionLimitation(
        code: code,
        message: message,
        path: path,
        blocking: true,
      ),
    );
  }

  String? _omittedTree(String path) {
    for (final o in omissions) {
      if (path == o.path || path.startsWith('${o.path}/')) return o.path;
    }
    return null;
  }

  /// Ordenadas y con `r0001`, `r0002`…; cada ID se cobra al asignarse y
  /// cada referencia, al proyectarse.
  List<RecognitionRelation> relations(Map<EvidenceDraft, String> ids) {
    final keyed = [
      for (final p in pending)
        (p, [for (final d in p.evidence) ids[d]!]..sort()),
    ]..sort((a, b) => _compare(_key(a.$1, a.$2), _key(b.$1, b.$2)));
    return [
      for (final (index, (p, evidenceIds)) in keyed.indexed)
        _relation('r${(index + 1).toString().padLeft(4, '0')}', p, evidenceIds),
    ];
  }

  RecognitionRelation _relation(String id, _Pending p, List<String> refs) {
    budget.charge(texts: [id]);
    return RecognitionRelation(
      id: id,
      kind: p.kind,
      fromPath: p.fromPath,
      declaredName: p.declaredName,
      targetPath: p.target,
      targetUnitId: p.unitId,
      status: p.status,
      evidenceIds: budget
          .admitEach(refs, textsOf: (ref) => [ref], build: (ref) => ref)
          .toList(),
    );
  }
}

/// Los textos de la fila, salvo el ID, que se asigna después.
List<String> _texts(_Pending p) => [
  p.kind.toWireName(),
  p.fromPath,
  ?p.declaredName,
  ?p.target,
  ?p.unitId,
  p.status.toWireName(),
];

List<String> _key(_Pending p, List<String> ids) => [
  p.fromPath,
  p.kind.toWireName(),
  p.target ?? '',
  p.declaredName ?? '',
  ids.join(','),
];

int _compare(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    final order = a[i].compareTo(b[i]);
    if (order != 0) return order;
  }
  return 0;
}
