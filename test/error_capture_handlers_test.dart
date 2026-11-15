import 'package:discourse_native/src/app_bootstrap.dart';
import 'package:discourse_native/src/foundation/error_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('records a framework error and keeps presenting it', (
    tester,
  ) async {
    final log = ErrorLog();
    final presented = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    final originalPlatform = PlatformDispatcher.instance.onError;
    FlutterError.onError = presented.add;
    installFlutterErrorCapture(log);
    final installed = FlutterError.onError!;
    FlutterError.onError = original;
    PlatformDispatcher.instance.onError = originalPlatform;

    final details = FlutterErrorDetails(
      exception: StateError('layout failed'),
      stack: StackTrace.fromString('#0      a (package:a/a.dart:1:1)'),
    );
    installed(details);
    installed(FlutterErrorDetails(exception: StateError('no stack')));

    expect(presented.first, same(details));
    expect(log.entries.map((entry) => entry.source), [
      ErrorSource.framework,
      ErrorSource.framework,
    ]);
    expect(log.entries.first.message, 'Bad state: layout failed');
    expect(log.entries.last.stack, isEmpty);
  });

  testWidgets('records an uncaught platform error and defers the verdict', (
    tester,
  ) async {
    final dispatcher = PlatformDispatcher.instance;
    final original = dispatcher.onError;
    final originalFramework = FlutterError.onError;
    addTearDown(() {
      dispatcher.onError = original;
      FlutterError.onError = originalFramework;
    });

    for (final handled in [true, false, null]) {
      final log = ErrorLog();
      dispatcher.onError = handled == null ? null : (_, _) => handled;
      installFlutterErrorCapture(log);
      FlutterError.onError = originalFramework;

      final verdict = dispatcher.onError!(
        StateError('uncaught'),
        StackTrace.empty,
      );

      expect(verdict, handled ?? false);
      expect(log.entries.single.source, ErrorSource.platform);
    }
  });
}
