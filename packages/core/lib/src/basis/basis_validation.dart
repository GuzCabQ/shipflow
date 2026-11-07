import 'dart:convert';

import '../context/context_validation.dart';
import 'basis_enums.dart';
import 'basis_limits.dart';
import 'basis_model.dart';
import 'basis_payload.dart';

/// Rechazos con el código estable del catálogo de bootstrap.
void requireBasis(bool condition, String code, String at) =>
    requireSemantic(condition, code, at);

/// Exige que [text] quepa en [maxBytes] bytes UTF-8.
void requireText(String text, int maxBytes, String at) => requireBasis(
  isWellFormedText(text) && utf8.encode(text).length <= maxBytes,
  'budget_exceeded',
  at,
);

final _forbidden = RegExp(r'[\\*?\[\]{}\u0000-\u001f\u007f]');
final _drive = RegExp(r'^[A-Za-z]:');

/// Un prefijo relativo normalizado: sin `.`/`..`, tramos vacíos, barra
/// inicial o final, backslash, control, glob ni unidad.
bool isBasisPrefix(String path) =>
    path.isNotEmpty &&
    !path.startsWith('/') &&
    !path.endsWith('/') &&
    !_forbidden.hasMatch(path) &&
    !_drive.hasMatch(path) &&
    path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');

/// Si [prefix] cubre [path] por segmentos: `lib/a` cubre `lib/a/x`, no
/// `lib/ab`. Sensible a mayúsculas; no depende de que el archivo exista.
bool prefixCovers(String prefix, String path) =>
    path == prefix || path.startsWith('$prefix/');

void validateBasisScope(BasisScope scope, String at) {
  final paths = scope.kind == BasisScopeKind.paths;
  requireBasis(
    paths ? scope.paths.isNotEmpty : scope.paths.isEmpty,
    'invalid_schema',
    at,
  );
  requireBasis(
    scope.paths.toSet().length == scope.paths.length,
    'invalid_schema',
    at,
  );
  for (final (i, path) in scope.paths.indexed) {
    requireText(path, maxBasisReasonText, '$at/paths/$i');
    requireBasis(isBasisPrefix(path), 'unsafe_path', '$at/paths/$i');
  }
}

/// Si una autoridad sobre [actor] alcanza [target]: un actor de proyecto
/// alcanza todo; uno de rutas, sólo prefijos que ya cubre. Un ámbito
/// desconocido no lo alcanza un actor de rutas.
bool scopeCovers(BasisScope actor, BasisScope target) => switch (actor.kind) {
  BasisScopeKind.project => true,
  BasisScopeKind.unknown => false,
  BasisScopeKind.paths =>
    target.kind == BasisScopeKind.paths &&
        target.paths.every(
          (path) => actor.paths.any((p) => prefixCovers(p, path)),
        ),
};

/// Si [actor] puede dejar [payload] tal como está: cubre su ámbito, o es
/// un pendiente abierto o una propuesta de ámbito desconocido, que
/// cualquier actor puede registrar sin declarar que lo resolvió.
bool authorizes(BasisActor actor, BasisPayload payload) {
  if (scopeCovers(actor.scope, payload.scope)) return true;
  if (actor.scope.kind == BasisScopeKind.unknown) return false;
  if (payload.scope.kind != BasisScopeKind.unknown) return false;
  return switch (payload) {
    BasisPending(:final status) => status == BasisPendingStatus.open,
    BasisRule(:final lifecycle) => lifecycle == BasisRuleLifecycle.proposed,
    _ => false,
  };
}

void validateBasisActor(BasisActor actor, String at) {
  requireText(actor.label, maxBasisShortText, '$at/label');
  requireText(actor.role, maxBasisShortText, '$at/role');
  validateBasisScope(actor.scope, '$at/scope');
  requireBasis(
    actor.scope.kind != BasisScopeKind.unknown,
    'authority_scope',
    '$at/scope',
  );
}

/// Las reglas de [payload] que no dependen de otros registros.
void validateBasisPayload(BasisPayload payload, String at) {
  requireText(payload.title, maxBasisShortText, '$at/title');
  validateBasisScope(payload.scope, '$at/scope');
  switch (payload) {
    case BasisSource():
      _source(payload, at);
    case BasisRule():
      _rule(payload, at);
    case BasisPending():
      _pending(payload, at);
  }
}

void _source(BasisSource s, String at) {
  requireText(s.purpose, maxBasisReasonText, '$at/purpose');
  requireText(s.locator, maxBasisReasonText, '$at/locator');
  final local = s.sourceType == BasisSourceType.local;
  requireBasis(
    local ? isBasisPrefix(s.locator) : isExternalLocator(s.locator),
    'unsafe_path',
    '$at/locator',
  );
  final read = s.observation == BasisObservation.current;
  requireBasis(
    local || s.observation == BasisObservation.unverified,
    'invalid_schema',
    '$at/observation',
  );
  requireBasis(
    (read && local) == (s.contentDigest != null),
    'invalid_schema',
    '$at/contentDigest',
  );
}

/// Una referencia externa HTTPS sin usuario, contraseña, consulta ni
/// fragmento: nunca se descarga, sólo se conserva.
bool isExternalLocator(String locator) {
  final uri = Uri.tryParse(locator);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      !locator.contains(RegExp(r'[\s\u0000-\u001f\u007f]'));
}

void _rule(BasisRule r, String at) {
  requireText(r.statement, maxBasisStatementText, '$at/statement');
  requireText(r.reason, maxBasisReasonText, '$at/reason');
  if (r.alternative case final a?) {
    requireText(a, maxBasisReasonText, '$at/alternative');
  }
  if (r.lifecycle == BasisRuleLifecycle.active) _active(r, at);
  requireBasis(
    (r.replacementRef != null) == (r.lifecycle == BasisRuleLifecycle.replaced),
    'invalid_reference',
    '$at/replacementRef',
  );
  requireBasis(
    r.support != BasisSupport.sourceSupported || r.sourceRefs.isNotEmpty,
    'invalid_reference',
    '$at/sourceRefs',
  );
  _uniqueRefs(r.sourceRefs, '$at/sourceRefs');
}

/// Activa exige ámbito conocido y, si prohíbe, alternativa y política de
/// excepción explícitas: si faltan, se guarda como propuesta.
void _active(BasisRule r, String at) {
  requireBasis(
    r.scope.kind != BasisScopeKind.unknown,
    'unknown_active_scope',
    '$at/scope',
  );
  requireBasis(
    r.ruleClass != BasisRuleClass.prohibition ||
        (r.alternative != null &&
            r.exceptionPolicy != BasisExceptionPolicy.unspecified),
    'missing_alternative',
    '$at/alternative',
  );
}

void _pending(BasisPending p, String at) {
  requireText(p.question, maxBasisStatementText, '$at/question');
  requireText(p.reason, maxBasisReasonText, '$at/reason');
  requireText(p.revisitWhen, maxBasisReasonText, '$at/revisitWhen');
  final resolution = p.resolution;
  requireBasis(
    (resolution != null) == (p.status == BasisPendingStatus.resolved),
    'invalid_schema',
    '$at/resolution',
  );
  if (resolution != null) {
    requireText(resolution, maxBasisReasonText, '$at/resolution');
    requireBasis(
      parseRuleResolution(resolution) != null ||
          _disposition.hasMatch(resolution),
      'invalid_reference',
      '$at/resolution',
    );
  }
  if (p.decisionReview?.reviewer case final reviewer?) {
    requireText(reviewer, maxBasisShortText, '$at/decisionReview/reviewer');
  }
  _uniqueRefs(p.sourceRefs, '$at/sourceRefs');
}

final _ruleResolution = RegExp(r'^rule:([0-9a-f-]{36})@([1-9][0-9]{0,9})$');
final _disposition = RegExp(r'^disposition:\S');

/// La regla y versión de una resolución `rule:<uuid>@<version>`, o null.
BasisReference? parseRuleResolution(String resolution) {
  final match = _ruleResolution.firstMatch(resolution);
  if (match == null || !isUuidV4(match[1]!)) return null;
  return BasisReference(ref: match[1]!, version: int.parse(match[2]!));
}

void _uniqueRefs(List<BasisReference> refs, String at) => requireBasis(
  refs.map((r) => '${r.ref}@${r.version}').toSet().length == refs.length,
  'invalid_schema',
  at,
);
