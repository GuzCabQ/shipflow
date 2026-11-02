import 'dart:ffi';
import 'dart:io';

import 'package:core/core.dart';

import '../terminal_text.dart';
import 'context_request.dart';

/// La terminal de una invocación humana. Sin terminal no se pregunta: el
/// resultado pide la elección por flag.
abstract interface class ContextPromptIO {
  /// Si hay una persona en una terminal para contestar.
  bool get interactive;

  /// La siguiente línea, o null al cerrarse la entrada.
  Future<String?> readLine();

  void show(String text);
}

/// La entrada y salida estándar del proceso.
final class TerminalPromptIO implements ContextPromptIO {
  const TerminalPromptIO();

  @override
  bool get interactive =>
      (Platform.isLinux || Platform.isMacOS) &&
      _isatty(0) == 1 &&
      stdout.hasTerminal;

  // Un dispositivo de caracteres como /dev/null no permite contestar.
  static final _isatty = DynamicLibrary.process()
      .lookupFunction<Int32 Function(Int32), int Function(int)>(
        'isatty',
        isLeaf: true,
      );

  @override
  Future<String?> readLine() async => stdin.readLineSync();

  @override
  void show(String text) => stdout.write(text);
}

/// Cuántas respuestas no reconocidas se toleran antes de cancelar.
const _maxAttempts = 20;

/// Pregunta cómo conservar el contexto: `1` comparte, `2` mantiene sólo
/// aquí, `?` muestra el detalle técnico y `q` cancela. Enter vacío no elige
/// ni consiente; el cierre de la entrada cancela. Null es cancelar.
Future<SharingChoice?> askSharing(
  ContextPromptIO io,
  SharingQuestion question,
) async {
  io.show(_intro(question));
  for (var attempt = 0; attempt < _maxAttempts; attempt++) {
    io.show(_options(question));
    final answer = (await io.readLine())?.trim();
    switch (answer) {
      case null || 'q':
        return null;
      case '1':
        return SharingChoice.share;
      case '2':
        return SharingChoice.local;
      case '?':
        io.show(_detail);
      case '':
        break;
      default:
        io.show('No reconozco esa respuesta.\n');
    }
  }
  return null;
}

String _intro(SharingQuestion question) {
  final stacks = question.stacks.isEmpty
      ? 'el proyecto'
      : question.stacks.map((s) => singleLine(s, maxRunes: 40)).join(', ');
  final units = question.units == 1
      ? '1 paquete'
      : '${question.units} paquetes';
  return 'Shipflow reconoció $stacks con $units. Puede guardar este contexto '
      'para no repetir el reconocimiento cuando vuelvas.\n'
      '¿Cómo quieres conservarlo?\n\n';
}

String _options(SharingQuestion question) =>
    '  1) Compartir con el proyecto — recomendado\n'
    '     Se prepara para conservarlo junto al proyecto y compartirlo. Todavía '
    'tienes que incluirlo cuando guardes los cambios del proyecto: elegirlo no '
    'significa que ya se compartió.\n'
    '  2) Mantenerlo sólo aquí\n'
    '     Queda disponible en esta copia, no se incluye al compartir cambios y '
    'necesitas un respaldo para recuperarlo si pierdes la copia o cambias de '
    'equipo.\n'
    '${question.sharedExclude ? '     En este repositorio, esta elección alcanza también la misma ruta en las otras copias de trabajo de este equipo.\n' : ''}'
    '  ?) Detalle técnico    q) Cancelar\n'
    'Elige 1, 2, ? o q: ';

const _detail =
    '\nDetalle técnico:\n'
    '  1 deja shipflow/project.json y shipflow/.gitignore listos para '
    'versionarlos con Git; Shipflow no ejecuta git add, commit ni push.\n'
    '  2 agrega una regla propia para shipflow/ en el exclude local de Git '
    '(info/exclude del repositorio); no quita del índice archivos ya '
    'seguidos.\n'
    '  En los dos casos, shipflow/local/ queda fuera del repositorio.\n\n';
