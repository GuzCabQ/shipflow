/// Los códigos de las limitaciones que el reconocimiento puede informar.
abstract final class LimitationCode {
  static const symlinkNotFollowed = 'symlink_not_followed';
  static const subtreeUnreadable = 'subtree_unreadable';
  static const scanLimitReached = 'scan_limit_reached';
  static const sourceTooLarge = 'source_too_large';
  static const sourceUnreadable = 'source_unreadable';
  static const sourceChanged = 'source_changed_during_scan';
  static const invalidManifest = 'invalid_manifest';
  static const invalidToolchainMarker = 'invalid_toolchain_marker';
  static const invalidConstraint = 'invalid_constraint';
  static const pathDependencyOutsideRoot = 'path_dependency_outside_root';
  static const observedValueTruncated = 'observed_value_truncated';
}
