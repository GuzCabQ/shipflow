import 'dart:convert';

import 'package:core/core.dart';

/// El tamaño máximo de un exclude que se acepta modificar.
const maxExcludeBytes = 1048576;

/// Lo que cambiaría en el exclude local, calculado sin escribir. [after] es
/// el archivo completo propuesto, o null si hay un [problem]; los bloques son
/// el texto propio antes y después, nunca reglas ajenas.
final class ManagedExcludePatch {
  const ManagedExcludePatch({
    required this.after,
    required this.changed,
    required this.beforeBlock,
    required this.afterBlock,
    this.problem,
  });

  const ManagedExcludePatch.refused(String this.problem)
    : after = null,
      changed = false,
      beforeBlock = null,
      afterBlock = null;

  final List<int>? after;
  final bool changed;
  final String? beforeBlock;
  final String? afterBlock;

  /// `exclude_too_large`, `path_not_representable` o
  /// `exclude_block_damaged`.
  final String? problem;
}

/// El patrón anclado que excluye sólo `<prefix>shipflow/` desde la raíz Git,
/// con cada metacarácter de gitignore escapado.
String excludePattern(String prefix) => '/${_escape(prefix)}$toolStatePath/';

/// El bloque propio canónico de [blockId] para [prefix], sin separador.
String excludeBlock(String prefix, String blockId) =>
    '# shipflow:$blockId:begin\n${excludePattern(prefix)}\n'
    '# shipflow:$blockId:end\n';

/// El texto que [planExclude] agregaría a [existing]: el bloque, precedido
/// del salto que falte para no pegarse a la última regla ajena.
String insertedBlock(List<int>? existing, String prefix, String blockId) {
  final text = latin1.decode(existing ?? const []);
  final separator = text.isNotEmpty && !text.endsWith('\n') ? '\n' : '';
  return '$separator${excludeBlock(prefix, blockId)}';
}

/// El exclude que corresponde a [choice] para la raíz de [prefix]: local
/// agrega el bloque propio si falta; share retira sólo el bloque propio
/// intacto, con el separador que se agregó si [ownedBlock] lo acredita.
/// Un bloque dañado o repetido no se repara: se informa.
///
/// Trabaja sobre bytes, así que las reglas ajenas sobreviven aunque no sean
/// UTF-8. No escribe: el coordinador publica [ManagedExcludePatch.after].
ManagedExcludePatch planExclude({
  required String prefix,
  required SharingChoice choice,
  required List<int>? existing,
  required String blockId,
  String? ownedBlock,
}) {
  if ((existing?.length ?? 0) > maxExcludeBytes) {
    return const ManagedExcludePatch.refused('exclude_too_large');
  }
  if (prefix.contains('\n') || prefix.contains('\r')) {
    return const ManagedExcludePatch.refused('path_not_representable');
  }
  final text = latin1.decode(existing ?? const []);
  final canonical = _asBytes(excludeBlock(prefix, blockId));
  final markers = '# shipflow:$blockId:'.allMatches(text).length;
  final copies = canonical.allMatches(text).length;
  if (markers == 0) return _absent(text, choice, prefix, blockId, existing);
  if (markers != 2 || copies != 1) {
    return const ManagedExcludePatch.refused('exclude_block_damaged');
  }
  return choice == SharingChoice.local
      ? _unchanged(text, canonical)
      : _removed(
          text,
          canonical,
          ownedBlock == null ? null : _asBytes(ownedBlock),
        );
}

ManagedExcludePatch _absent(
  String text,
  SharingChoice choice,
  String prefix,
  String blockId,
  List<int>? existing,
) {
  if (choice != SharingChoice.local) return _unchanged(text, null);
  final inserted = insertedBlock(existing, prefix, blockId);
  return ManagedExcludePatch(
    after: latin1.encode('$text${_asBytes(inserted)}'),
    changed: true,
    beforeBlock: null,
    afterBlock: inserted,
  );
}

ManagedExcludePatch _removed(String text, String canonical, String? owned) {
  final block =
      owned != null &&
          owned.endsWith(canonical) &&
          owned.allMatches(text).length == 1
      ? owned
      : canonical;
  return ManagedExcludePatch(
    after: latin1.encode(text.replaceFirst(block, '')),
    changed: true,
    beforeBlock: _asText(block),
    afterBlock: null,
  );
}

ManagedExcludePatch _unchanged(String text, String? block) =>
    ManagedExcludePatch(
      after: latin1.encode(text),
      changed: false,
      beforeBlock: block == null ? null : _asText(block),
      afterBlock: block == null ? null : _asText(block),
    );

/// [text] propio como lo verían los bytes del archivo, un carácter latin1
/// por byte UTF-8, y su inversa.
String _asBytes(String text) => latin1.decode(utf8.encode(text));
String _asText(String bytes) => utf8.decode(latin1.encode(bytes));

const _special = {r'\', '*', '?', '[', ']', '!', '#', ' '};

String _escape(String prefix) => [
  for (final char in prefix.split(''))
    _special.contains(char) ? '\\$char' : char,
].join();
