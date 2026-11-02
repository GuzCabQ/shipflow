/// plugin_dart — el reconocimiento de proyectos Dart y Flutter.
library;

export 'package:core/core.dart' show ContextSourceKind;

export 'src/assessment/assessment_context_projection.dart'
    show projectDartAssessmentContext;
export 'src/assessment/assessment_observer.dart'
    show
        DirectiveParser,
        assessmentContract,
        assessmentPluginId,
        observeDartInputs,
        observeDartSources,
        parserVersion;
export 'src/context_source_rule.dart';
export 'src/dart_project_recognizer.dart' show recognizeDartProject;
export 'src/scan_limits.dart';
