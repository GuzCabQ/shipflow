import 'assessment_grammar.dart';
import 'basis_grammar.dart';
import 'cli_command.dart';
import 'cli_grammar.dart';

const _root = Grammar({versionFlag, ...helpFlags});
const _init = Grammar(
  {dryRunFlag, refreshFlag, recoverFlag, ...helpFlags},
  acceptsBudget: true,
  acceptsSharing: true,
);
const _doctor = Grammar(helpFlags, acceptsBudget: true);

/// Decide el comando sólo a partir de [arguments]: no lee nada más.
CliCommand parseCliCommand(List<String> arguments) {
  final json = arguments.contains(jsonFlag);
  if (arguments.isNotEmpty && arguments.first == initCommand) {
    return _parseInit(arguments.sublist(1), json: json);
  }
  if (arguments.isNotEmpty && arguments.first == doctorCommand) {
    return _parseDoctor(arguments.sublist(1), json: json);
  }
  if (arguments.isNotEmpty && arguments.first == assessCommand) {
    return parseAssess(arguments.sublist(1), json: json);
  }
  if (arguments.isNotEmpty && arguments.first == bootstrapCommand) {
    return parseBootstrap(arguments.sublist(1), json: json);
  }
  if (_root.firstProblem(arguments) case final problem?) {
    return RejectUsage(problem, HelpTopic.root, json: json);
  }
  if (arguments.contains(versionFlag)) return ShowVersion(json: json);
  return ShowHelp(HelpTopic.root, json: json);
}

CliCommand _parseInit(List<String> options, {required bool json}) {
  if (_init.firstProblem(options) case final problem?) {
    return RejectUsage(problem, HelpTopic.init, json: json);
  }
  if (options.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.init, json: json);
  }
  final profile = budgetProfileIn(options);
  final sharing = sharingIn(options);
  if (options.contains(dryRunFlag)) {
    return RunInitDryRun(json: json, budgetProfile: profile);
  }
  if (options.contains(refreshFlag)) {
    return RunInitRefresh(json: json, budgetProfile: profile, sharing: sharing);
  }
  if (options.contains(recoverFlag)) {
    return RunInitRecover(json: json, budgetProfile: profile);
  }
  return RunInit(json: json, budgetProfile: profile, sharing: sharing);
}

CliCommand _parseDoctor(List<String> options, {required bool json}) {
  if (_doctor.firstProblem(options) case final problem?) {
    return RejectUsage(problem, HelpTopic.doctor, json: json);
  }
  if (options.any(helpFlags.contains)) {
    return ShowHelp(HelpTopic.doctor, json: json);
  }
  return RunDoctor(json: json, budgetProfile: budgetProfileIn(options));
}
