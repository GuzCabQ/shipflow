import 'package:core/core.dart';

import '../terminal_text.dart';

/// Lo que hará aceptar el borrador, cambio por cambio, con el ID y las
/// versiones de cada registro: también lo que deja de estar vigente, que
/// la selección del estado resultante ya no muestra.
List<String> proposedSections(BasisResponse r) {
  if (r.proposedChanges.isEmpty) return const [];
  final titles = {
    for (final v in [...r.selected, ...r.reviewTargets, ...r.pending])
      v.id: v.payload.title,
    for (final c in r.proposedChanges) c.version.id: c.version.payload.title,
  };
  return [
    '',
    'Cambios de este borrador (sólo se aplican al aceptar su huella):',
    for (final c in r.proposedChanges) ..._change(c, titles),
  ];
}

String _t(String value, [int max = 200]) => singleLine(value, maxRunes: max);

List<String> _change(BasisProposedChange c, Map<String, String> titles) {
  final v = c.version;
  final name = '«${_t(v.payload.title)}» ${_kind(v.payload)}';
  final versions = v.previousVersion == null
      ? 'versión ${v.version}'
      : 'versión ${v.previousVersion} → ${v.version}';
  final where = 'ID ${v.id} · $versions';
  return switch ((c.change, v.payload)) {
    (BasisChangeKind.create, _) => ['• Crea $name · $where'],
    (BasisChangeKind.revise, _) => ['• Revisa $name · $where'],
    (BasisChangeKind.retire, _) => [
      '• Retira $name · $where',
      '  Deja de estar vigente; sigue en la historia.',
    ],
    (BasisChangeKind.replace, BasisRule(:final replacementRef)) => [
      '• Reemplaza $name · $where',
      '  Por «${_t(titles[replacementRef] ?? replacementRef ?? '')}»; '
          'sigue en la historia.',
    ],
    (BasisChangeKind.resolve, BasisPending(:final resolution)) => [
      '• Resuelve $name · $where',
      '  Resolución: ${_t(resolution ?? '', 400)}',
    ],
    _ => ['• ${c.change.toWireName()} $name · $where'],
  };
}

String _kind(BasisPayload payload) => switch (payload) {
  BasisRule() => '(regla)',
  BasisSource() => '(fuente)',
  _ => '(pendiente)',
};
