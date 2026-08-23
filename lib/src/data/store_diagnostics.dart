import '../diagnostics/diagnostics_controller.dart';

/// How a persistence failure is reported, for every store that has one.
///
/// Stores degrade rather than fail: a width that will not read opens at its
/// default, a document that will not write is written again next time. So the
/// classification is always the same one — sourced to storage, handled, and
/// degraded — and stating it here rather than in each store keeps thirteen
/// copies of it from drifting apart. Only [severity] varies, and only where
/// what was lost is worse than a warning.
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
