import 'package:core/core.dart';
import 'package:test/test.dart';

import 'basis_fixtures.dart';
import 'basis_history_test.dart' show rejects;

void main() {
  void invalid(BasisPayload payload, String code) => expect(
    () => validateBasisDocument(
      documentOf([
        [versionOf(1, 1, payload)],
      ]),
    ),
    rejects(code),
  );

  test('an active rule needs a known scope', () {
    invalid(ruleOf(scope: BasisScope.unknown()), 'unknown_active_scope');
    replayBasis(
      documentOf([
        [
          versionOf(
            1,
            1,
            ruleOf(
              scope: BasisScope.unknown(),
              lifecycle: BasisRuleLifecycle.proposed,
            ),
          ),
        ],
      ]),
    );
  });

  test('an active prohibition needs alternative and exception policy', () {
    invalid(
      ruleOf(ruleClass: BasisRuleClass.prohibition),
      'missing_alternative',
    );
    invalid(
      ruleOf(
        ruleClass: BasisRuleClass.prohibition,
        alternative: 'Usar la API pública.',
        policy: BasisExceptionPolicy.unspecified,
      ),
      'missing_alternative',
    );
  });

  test('prefixes are relative, normalized and without globs', () {
    for (final path in [
      '../x',
      'lib/../x',
      '/abs',
      'lib/a/',
      'lib//a',
      'lib\\a',
      'lib/*',
      'C:x',
      './lib',
      'lib/\u001b',
    ]) {
      invalid(ruleOf(scope: paths([path])), 'unsafe_path');
    }
  });

  test('prefix matching is by segments and case-sensitive', () {
    expect(prefixCovers('lib/a', 'lib/a/x.md'), isTrue);
    expect(prefixCovers('lib/a', 'lib/a'), isTrue);
    expect(prefixCovers('lib/a', 'lib/ab'), isFalse);
    expect(prefixCovers('lib/a', 'Lib/a'), isFalse);
  });

  test('a paths actor cannot accept a global rule nor narrow one', () {
    final local = actorOf(paths(['lib/a']));
    expect(
      () => validateBasisDocument(
        documentOf(
          [
            [versionOf(1, 1, ruleOf())],
          ],
          actors: [local],
        ),
      ),
      rejects('authority_scope'),
    );
    expect(
      () => validateBasisDocument(
        documentOf(
          [
            [versionOf(1, 1, ruleOf())],
            [
              versionOf(1, 2, ruleOf(scope: paths(['lib/a']))),
            ],
          ],
          actors: [actorOf(), local],
        ),
      ),
      rejects('authority_scope'),
    );
  });

  test('a paths actor may register an open pending of unknown scope', () {
    final local = actorOf(paths(['lib/a']));
    replayBasis(
      documentOf(
        [
          [versionOf(1, 1, pendingOf(scope: BasisScope.unknown()))],
        ],
        actors: [local],
      ),
    );
  });

  test('replacements point to another rule and never cycle', () {
    final document = documentOf([
      [versionOf(1, 1, ruleOf()), versionOf(2, 1, ruleOf())],
      [
        versionOf(
          1,
          2,
          ruleOf(
            lifecycle: BasisRuleLifecycle.replaced,
            replacementRef: uuid(2),
          ),
        ),
        versionOf(
          2,
          2,
          ruleOf(
            lifecycle: BasisRuleLifecycle.replaced,
            replacementRef: uuid(1),
          ),
        ),
      ],
    ]);
    expect(() => validateBasisDocument(document), rejects('invalid_reference'));
  });

  test('a resolution cites a rule accepted before, never the same batch', () {
    final resolved = pendingOf(
      status: BasisPendingStatus.resolved,
      resolution: 'rule:${uuid(1)}@1',
    );
    expect(
      () => validateBasisDocument(
        documentOf([
          [versionOf(1, 1, ruleOf()), versionOf(2, 1, resolved)],
        ]),
      ),
      rejects('invalid_reference'),
    );
    replayBasis(
      documentOf([
        [versionOf(1, 1, ruleOf()), versionOf(2, 1, pendingOf())],
        [versionOf(2, 2, resolved)],
      ]),
    );
  });

  test('a source-supported rule cites an existing source version', () {
    invalid(ruleOf(support: BasisSupport.sourceSupported), 'invalid_reference');
    invalid(
      ruleOf(
        support: BasisSupport.sourceSupported,
        sourceRefs: [BasisReference(ref: uuid(9), version: 1)],
      ),
      'invalid_reference',
    );
    replayBasis(
      documentOf([
        [
          versionOf(9, 1, sourceOf()),
          versionOf(
            1,
            1,
            ruleOf(
              support: BasisSupport.sourceSupported,
              sourceRefs: [BasisReference(ref: uuid(9), version: 1)],
            ),
          ),
        ],
      ]),
    );
  });

  test('every text field has a bound', () {
    invalid(ruleOf(statement: 'x' * (16 * 1024 + 1)), 'budget_exceeded');
    invalid(pendingOf(revisitWhen: 'x' * (4 * 1024 + 1)), 'budget_exceeded');
  });

  test('an external source is an https reference never read', () {
    BasisSource external(String locator) => BasisSource(
      title: 'Guía',
      scope: BasisScope.project(),
      lifecycle: BasisSourceLifecycle.active,
      sourceType: BasisSourceType.external,
      locator: locator,
      purpose: 'Consulta.',
      contentDigest: null,
      observation: BasisObservation.unverified,
    );
    replayBasis(
      documentOf([
        [versionOf(1, 1, external('https://example.org/guia'))],
      ]),
    );
    for (final locator in [
      'http://example.org',
      'https://user:pw@example.org',
      'https://example.org/?token=x',
      'https://example.org/#x',
    ]) {
      invalid(external(locator), 'unsafe_path');
    }
  });
}
