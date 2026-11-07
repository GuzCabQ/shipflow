import 'package:cli/src/context/context_prompt.dart';

/// Una terminal guionada: responde en orden y anota lo mostrado; al
/// agotarse, la entrada se cierra como un EOF real.
final class ScriptedIO implements ContextPromptIO {
  ScriptedIO(List<String> answers) : _answers = [...answers];

  final List<String> _answers;
  final shown = StringBuffer();

  @override
  bool get interactive => true;

  @override
  Future<String?> readLine() async =>
      _answers.isEmpty ? null : _answers.removeAt(0);

  @override
  void show(String text) => shown.write(text);
}
