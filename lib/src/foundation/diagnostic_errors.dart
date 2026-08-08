import '../diagnostics/diagnostics_controller.dart';

final Expando<bool> _reportedImageErrors = Expando<bool>(
  'diagnostics reported image errors',
);

/// Records an image/provider failure that a widget deliberately replaces with
/// fallback UI. Flutter does not forward errors consumed by `errorBuilder` to
/// the global framework handler, so this is the terminal reporting boundary.
void reportImageError(
  Object error,
  StackTrace? stackTrace, {
  String operation = 'image.render',
}) {
  try {
    // Image.errorBuilder can be called again for the same cached exception on
    // every rebuild. Its identity remains reachable from the Image state, so a
    // weak marker records that underlying failure exactly once without keeping
    // the exception (or decoder payload) alive itself.
    if (_reportedImageErrors[error] ?? false) return;
    _reportedImageErrors[error] = true;
  } on Object {
    // Rare primitive thrown values cannot be Expando keys. Reporting them is
    // still preferable to letting diagnostics affect image fallback behavior.
  }
  DiagnosticsSink.current.reportError(
    error,
    stackTrace ?? StackTrace.current,
    operation: operation,
    source: 'image',
    severity: DiagnosticSeverity.warning,
    handled: true,
    degraded: true,
  );
}
