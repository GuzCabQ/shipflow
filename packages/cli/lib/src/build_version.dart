/// La versión incorporada al ejecutable con `-DSHIPFLOW_VERSION=<semver>`.
const String buildVersion = bool.hasEnvironment('SHIPFLOW_VERSION')
    ? String.fromEnvironment('SHIPFLOW_VERSION')
    : '0.0.0-dev';
