const manifestFileName = 'pubspec.yaml';
const fvmConfigFileName = '.fvmrc';
const flutterVersionFileName = 'flutter-version.txt';

enum SourceKind { manifest, fvmConfig, flutterVersionFile }

/// Qué fuente es un archivo llamado [name] a [depth] tramos de la raíz: los
/// marcadores de toolchain sólo cuentan en la raíz misma.
SourceKind? sourceKindOf(String name, int depth) => switch (name) {
  manifestFileName => SourceKind.manifest,
  fvmConfigFileName when depth == 1 => SourceKind.fvmConfig,
  flutterVersionFileName when depth == 1 => SourceKind.flutterVersionFile,
  _ => null,
};

/// Los nombres que nunca se recorren, en cualquier profundidad.
const baselineExclusions = {
  '.git',
  '.dart_tool',
  'build',
  '.symlinks',
  'Pods',
  'node_modules',
};
