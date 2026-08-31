import '../diagnostics/diagnostics_controller.dart';

void reportStorageFailure(
  Object error,
  StackTrace stackTrace,
  String operation, {
  DiagnosticSeverity severity = DiagnosticSeverity.warning,
}) => DiagnosticsSink.current.reportError(
  error,
  stackTrace,
  operation: operation,
  source: 'storage',
  severity: severity,
  handled: true,
  degraded: true,
);
