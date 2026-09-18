/// La entrada de `ship`: qué se publica, y las reglas que lo impiden.
///
/// **No hay valor por omisión que barra el árbol de trabajo.** Sin
/// `--file` ni `--slice`, la invocación falla en vez de inferir «todos los
/// cambios detectados». Barrer el árbol metería en el pull request cambios
/// que nadie planeó, y el artefacto de revisión los declararía **cubiertos**
/// —por ADR-012—, que es pedirle a una persona que no los mire. Un default
/// que barre reintroduce **en la entrada** el falso verde que el resto del
/// diseño cierra en la salida: los archivos se declaran, no se detectan.
///
/// El estilo es el de `interpretarGlobales`: comprobar la presencia de una
/// bandera con `contains` no es interpretarla, y por eso una bandera
/// desconocida falla en vez de ignorarse.
library;

import '../uso.dart';

/// Lo que la invocación de `ship` dijo, ya interpretado.
class EntradaDeShip {
  final String? intent;

  /// Los archivos declarados con `--file`. Vacía cuando la selección viene
  /// de `--slice`: resolver esa rebanada en archivos es de la tarea
  /// siguiente, que todavía no existe.
  final List<String> archivos;

  final String? branch;
  final String? base;
  final bool dryRun;
  final bool yes;
  final bool allowIncomplete;

  EntradaDeShip({
    required this.intent,
    required List<String> archivos,
    required this.branch,
    required this.base,
    required this.dryRun,
    required this.yes,
    required this.allowIncomplete,
  }) : archivos = List.unmodifiable(archivos);
}

/// Interpreta la invocación de `ship` entera.
///
/// El orden de las comprobaciones repite el de `interpretarGlobales`: la
/// contradicción entre `--file` y `--slice` se rechaza antes que nada, porque
/// no hay forma de honrar las dos. Después, las banderas que nadie puede
/// aceptar. Recién ahí las reglas que dependen de cuál de las dos formas se
/// usó, y por último la que motiva este archivo: cero archivos —el default
/// que se rechaza— y archivos repetidos, que `apply` exige declarar una sola
/// vez porque compara con igualdad literal.
EntradaDeShip interpretarShip(List<String> args) {
  String? intent;
  String? slice;
  String? branch;
  String? base;
  var dryRun = false, yes = false, allowIncomplete = false;
  final archivos = <String>[];
  final desconocidas = <String>[];

  String valorDe(int indiceDeBandera, String bandera) {
    final indiceDeValor = indiceDeBandera + 1;
    if (indiceDeValor >= args.length) {
      throw UsoInvalido(
        '$bandera necesita un valor',
        'Pasá $bandera seguido del valor.',
      );
    }
    return args[indiceDeValor];
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '--intent':
        intent = valorDe(i, a);
        i++;
      case '--file':
        archivos.add(valorDe(i, a));
        i++;
      case '--slice':
        slice = valorDe(i, a);
        i++;
      case '--branch':
        branch = valorDe(i, a);
        i++;
      case '--base':
        base = valorDe(i, a);
        i++;
      case '--dry-run':
        dryRun = true;
      case '--yes':
        yes = true;
      case '--allow-incomplete':
        allowIncomplete = true;
      default:
        desconocidas.add(a);
    }
  }

  if (archivos.isNotEmpty && slice != null) {
    throw const UsoInvalido(
      '--file y --slice son excluyentes',
      'Elegí una forma: `--file` (con --intent) para archivos sueltos, o '
          '`--slice` para una rebanada ya declarada.',
    );
  }

  if (desconocidas.isNotEmpty) {
    throw UsoInvalido(
      'bandera desconocida: «${desconocidas.first}»',
      'Las banderas de `ship` son --intent, --file, --slice, --branch, '
          '--base, --dry-run, --yes y --allow-incomplete.',
    );
  }

  if (archivos.isNotEmpty && intent == null) {
    throw const UsoInvalido(
      '--intent es obligatorio con --file',
      'Pasá --intent "descripción" junto con --file.',
    );
  }

  if (slice != null && intent != null) {
    throw const UsoInvalido(
      '--intent no se acepta con --slice',
      'La rebanada ya trae su intención declarada; sacá --intent.',
    );
  }

  if (archivos.isEmpty && slice == null) {
    throw const UsoInvalido(
      'no se declaró ningún archivo',
      'Pasá --file (uno o más, junto con --intent) o --slice con la '
          'rebanada ya declarada. `ship` no infiere el árbol de trabajo.',
    );
  }

  final vistos = <String>{};
  for (final archivo in archivos) {
    if (!vistos.add(archivo)) {
      throw UsoInvalido(
        'archivo repetido: «$archivo»',
        'Cada archivo se declara una sola vez. Sacá el duplicado de --file.',
      );
    }
  }

  return EntradaDeShip(
    intent: intent,
    archivos: archivos,
    branch: branch,
    base: base,
    dryRun: dryRun,
    yes: yes,
    allowIncomplete: allowIncomplete,
  );
}
