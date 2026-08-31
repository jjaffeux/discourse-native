abstract interface class DiagnosticErrorCause {
  Object get diagnosticCause;

  StackTrace? get diagnosticCauseStackTrace;
}
