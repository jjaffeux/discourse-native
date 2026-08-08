import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/diagnostics/diagnostics.dart';

void main() {
  final parentZone = Zone.current;
  DiagnosticsGlobalErrorBinding? globalErrors;

  void recordGlobal(
    Object error,
    StackTrace stackTrace, {
    required String source,
  }) {
    globalErrors?.reportUnhandledError(error, stackTrace, source: source);
  }

  unawaited(
    runZonedGuarded<Future<void>>(
          () async {
            WidgetsFlutterBinding.ensureInitialized();
            final controller = await DiagnosticsController.create();
            DiagnosticsSink.install(controller);
            RecordingHttpOverrides.install(controller);
            globalErrors = DiagnosticsGlobalErrorBinding.install(controller);

            runApp(DiscourseApp(diagnostics: controller));
          },
          (error, stackTrace) {
            recordGlobal(error, stackTrace, source: 'zone');
            // Recording must not turn a crash into a successful continuation.
            // Hand it back to the parent zone after preserving the evidence.
            parentZone.handleUncaughtError(error, stackTrace);
          },
        ) ??
        Future<void>.value(),
  );
}
