import 'package:core/core.dart';

/// Qué impide concluir cada código y qué acción existe para él. Nunca un
/// mensaje del sistema ni del parser.
const _meaning = <String, (String, String)>{
  'claims_budget': ('references_unknown', 'use_extended_profile'),
  'depth_budget': ('inventory_incomplete', 'use_extended_profile'),
  'directory_unreadable': ('inventory_incomplete', 'check_permissions'),
  'entries_budget': ('inventory_incomplete', 'use_extended_profile'),
  'observation_deadline': ('references_unknown', 'use_extended_profile'),
  'outside_units': ('not_in_universe', 'none'),
  'parse_deadline': ('references_unknown', 'use_extended_profile'),
  'parse_failed': ('references_unknown', 'review_source'),
  'path_not_representable': ('inventory_incomplete', 'none'),
  'reference_unresolved': ('connection_unknown', 'review_source'),
  'source_budget': ('references_unknown', 'use_extended_profile'),
  'source_changed': ('references_unknown', 'retry_assess'),
  'source_too_large': ('references_unknown', 'none'),
  'source_unreadable': ('references_unknown', 'check_permissions'),
  'special_file_skipped': ('entry_not_inspected', 'none'),
  'symlink_not_followed': ('link_not_inspected', 'none'),
};

/// Los diagnósticos agrupados por código: la cuenta total y hasta cinco
/// rutas de ejemplo, nunca miles de avisos repetidos.
final class DiagnosticGroups {
  final _paths = <String, List<String>>{};
  final _counts = <String, int>{};

  void add(String code, String path) {
    if (!_meaning.containsKey(code)) {
      throw ArgumentError.value(code, 'code', 'sin significado declarado');
    }
    _counts[code] = (_counts[code] ?? 0) + 1;
    if (isAssessmentPath(path)) _paths.putIfAbsent(code, () => []).add(path);
  }

  bool get isEmpty => _counts.isEmpty;

  List<AssessmentDiagnostic> build() => [
    for (final code in _counts.keys.toList()..sort())
      AssessmentDiagnostic(
        code: code,
        path: null,
        consequence: _meaning[code]!.$1,
        actionCode: _meaning[code]!.$2,
        count: _counts[code]!,
        examples: ({...?_paths[code]}.toList()..sort()).take(5).toList(),
      ),
  ];
}
