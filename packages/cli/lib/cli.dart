library;

export 'src/build_version.dart';
export 'src/cli_application.dart' show respondStatically;
export 'src/cli_command.dart'
    show
        CliCommand,
        RejectUsage,
        ReportBudgetProfile,
        RunInitDryRun,
        ShowHelp,
        ShowVersion,
        StaticCommand,
        parseCliCommand;
export 'src/cli_emitter.dart';
export 'src/cli_process_boundary.dart';
export 'src/cli_response.dart';
export 'src/logical_root.dart' show corroborateLogicalRoot, maxLogicalRootBytes;
export 'src/bounded_recognition_json.dart'
    show encodeRecognitionWithinLimit, recognitionSchemaVersion;
export 'src/recognition_presenter.dart' show presentRecognition, reportLimitsOf;
export 'src/recognition_runner.dart'
    show RecognitionContributor, currentWorkingDirectory, runCli;
