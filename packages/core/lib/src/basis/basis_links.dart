/// Una versión exacta citada: un ID persistido o, sólo en una entrada,
/// `new:<key>` de un registro creado en el mismo lote.
final class BasisReference {
  BasisReference({required this.ref, required this.version});

  factory BasisReference.fromJson(Map<String, Object?> json) => BasisReference(
    ref: json['ref']! as String,
    version: json['version']! as int,
  );

  final String ref;
  final int version;

  Map<String, Object?> toJson() => {'ref': ref, 'version': version};
}

/// La decisión aceptada a la que corresponde un pendiente de revisión: la
/// regla [ref] en su versión [version], y quién revisará si se sabe.
final class BasisDecisionReview {
  BasisDecisionReview({
    required this.ref,
    required this.version,
    required this.reviewer,
  });

  factory BasisDecisionReview.fromJson(Map<String, Object?> json) =>
      BasisDecisionReview(
        ref: json['ref']! as String,
        version: json['version']! as int,
        reviewer: json['reviewer'] as String?,
      );

  final String ref;
  final int version;

  /// Null: responsable por definir.
  final String? reviewer;

  Map<String, Object?> toJson() => {
    'ref': ref,
    'version': version,
    'reviewer': reviewer,
  };
}
