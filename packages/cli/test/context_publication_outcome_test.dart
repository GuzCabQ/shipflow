import 'package:cli/src/context/context_decisions.dart';
import 'package:cli/src/context/context_publication_outcome.dart';
import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'las listas de diagnósticos son inmodificables y no siguen a la entrada',
    () {
      final entrada = [diagnostic('a', 'uno')];
      final refused = PublicationRefused(diagnostics: entrada);
      final nothing = NothingToPublish(
        sharing: const ContextSharing(
          choice: SharingChoice.local,
          gitState: GitState.notChecked,
          effective: SharingEffective.unverified,
        ),
        diagnostics: entrada,
      );
      entrada.add(diagnostic('b', 'dos'));
      expect(refused.diagnostics, hasLength(1));
      expect(nothing.diagnostics, hasLength(1));
      expect(
        () => refused.diagnostics.add(diagnostic('c', 'tres')),
        throwsUnsupportedError,
      );
      expect(
        () => nothing.diagnostics.add(diagnostic('c', 'tres')),
        throwsUnsupportedError,
      );
    },
  );

  test('el desenlace se ejecuta exhaustivo sobre sus tres variantes', () {
    String nombre(PublicationOutcome o) => switch (o) {
      NothingToPublish() => 'nada',
      PublicationRefused(:final journalLeft) =>
        journalLeft ? 'diario' : 'rechazo',
      PublicationCompleted() => 'completa',
    };
    expect(nombre(PublicationRefused(diagnostics: const [])), 'rechazo');
    expect(
      nombre(PublicationRefused(diagnostics: const [], journalLeft: true)),
      'diario',
    );
  });
}
