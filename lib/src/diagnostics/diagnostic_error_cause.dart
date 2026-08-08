/// An application-facing exception which translated a lower-level failure.
///
/// Diagnostics unwraps this at the terminal operation boundary so it can keep
/// the original type and stack without recording both the intermediate error
/// and its user-facing translation.
abstract interface class DiagnosticErrorCause {
  Object get diagnosticCause;

  StackTrace? get diagnosticCauseStackTrace;
}
