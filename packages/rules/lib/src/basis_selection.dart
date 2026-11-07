import 'package:core/core.dart';

/// La selección determinista de la base para [path] (null: todo el estado
/// actual). Siempre incluye las reglas globales y lo de ámbito desconocido;
/// no interpreta la prosa ni filtra por palabras o imports.
BasisSelection selectBasis(BasisDocument basis, {String? path}) =>
    selectBasisLedger(replayBasisLedger(basis), path: path);

/// [selectBasis] sobre una historia ya reconstruida, como la de un
/// candidato todavía no aceptado.
BasisSelection selectBasisLedger(BasisLedger ledger, {String? path}) {
  final chosen = <String, BasisRecordVersion>{};
  final candidates = <BasisRecordVersion>[];
  for (final record in ledger.current.values) {
    if (!_live(record.payload)) continue;
    candidates.add(record);
    if (_applies(record.payload, path)) chosen[_key(record)] = record;
  }
  _citedSources(ledger, chosen);
  _reviewsOfSelectedRules(ledger, chosen);
  final excluded = candidates.where((r) => !chosen.containsKey(_key(r)));
  final all = chosen.values.toList()..sort(compareBasisVersions);
  final pending = [
    for (final r in all)
      if (_isPending(r.payload)) r,
  ];
  return BasisSelection(
    selected: [
      for (final r in all)
        if (!_isPending(r.payload)) r,
    ],
    pending: pending,
    reviewTargets: _targets(ledger, pending),
    excludedCount: excluded.length,
  );
}

String _key(BasisRecordVersion r) => '${r.id}@${r.version}';

/// Lo que forma parte del estado actual consultable: reglas activas o
/// propuestas, fuentes activas y pendientes abiertos. Lo inactivo queda en
/// la historia.
bool _live(BasisPayload payload) => switch (payload) {
  BasisRule(:final lifecycle) =>
    lifecycle == BasisRuleLifecycle.active ||
        lifecycle == BasisRuleLifecycle.proposed,
  BasisSource(:final lifecycle) => lifecycle == BasisSourceLifecycle.active,
  BasisPending(:final status) => status == BasisPendingStatus.open,
  _ => false,
};

/// Propuestas y pendientes van en su propia sección, no como normas.
bool _isPending(BasisPayload payload) => switch (payload) {
  BasisPending() => true,
  BasisRule(:final lifecycle) => lifecycle == BasisRuleLifecycle.proposed,
  _ => false,
};

/// Sin ruta, todo; con ruta, lo global, lo desconocido y los prefijos que
/// se solapan con la ruta por segmentos.
bool _applies(BasisPayload payload, String? path) {
  if (path == null) return true;
  final scope = payload.scope;
  return switch (scope.kind) {
    BasisScopeKind.project || BasisScopeKind.unknown => true,
    BasisScopeKind.paths => scope.paths.any(
      (p) => prefixCovers(p, path) || prefixCovers(path, p),
    ),
  };
}

/// Las fuentes que citan las reglas vigentes seleccionadas entran en su
/// versión citada, aunque su ámbito difiera o ya exista una más nueva.
void _citedSources(BasisLedger ledger, Map<String, BasisRecordVersion> chosen) {
  for (final record in [...chosen.values]) {
    final payload = record.payload;
    if (payload is! BasisRule ||
        payload.lifecycle != BasisRuleLifecycle.active) {
      continue;
    }
    for (final ref in payload.sourceRefs) {
      final source = ledger.versionOf(ref.ref, ref.version);
      if (source != null) chosen[_key(source)] = source;
    }
  }
}

/// Una revisión abierta ligada al ID de una regla seleccionada se muestra
/// aunque su versión o su ámbito difieran.
void _reviewsOfSelectedRules(
  BasisLedger ledger,
  Map<String, BasisRecordVersion> chosen,
) {
  final rules = {
    for (final r in chosen.values)
      if (r.payload is BasisRule) r.id,
  };
  for (final record in ledger.current.values) {
    final payload = record.payload;
    if (payload is BasisPending &&
        payload.status == BasisPendingStatus.open &&
        rules.contains(payload.decisionReview?.ref)) {
      chosen[_key(record)] = record;
    }
  }
}

/// Las versiones exactas que citan las revisiones abiertas devueltas,
/// deduplicadas en orden de ID y versión.
List<BasisRecordVersion> _targets(
  BasisLedger ledger,
  List<BasisRecordVersion> pending,
) {
  final targets = <String, BasisRecordVersion>{};
  for (final record in pending) {
    final link = switch (record.payload) {
      BasisPending(:final decisionReview?) => decisionReview,
      _ => null,
    };
    final target = link == null
        ? null
        : ledger.versionOf(link.ref, link.version);
    if (target != null) targets[_key(target)] = target;
  }
  return targets.values.toList()..sort(compareBasisVersions);
}
