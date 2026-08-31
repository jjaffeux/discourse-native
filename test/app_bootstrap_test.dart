import 'dart:async';

import 'package:discourse_native/src/app_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('launches before optional startup operations', () async {
    final host = _RecordingBootstrapHost();

    AppBootstrap(host: host).start();
    await host.launched.future;

    expect(host.calls, [
      'ensureFlutterInitialized',
      'createDiagnostics',
      'installDiagnosticsSink',
      'installRecordingHttpOverrides',
      'installGlobalErrorHandlers',
      'initializePlugins',
      'launchApplication',
      'scheduleAfterFirstFrame',
    ]);
    expect(host.deferred.isCompleted, isFalse);

    await host.runDeferred();
    expect(host.calls.skip(8), [
      'initializeTimezoneEnvironment',
      'initializePersistentMediaCache',
    ]);
    expect(host.reportedErrors, isEmpty);
    expect(host.unhandledErrors, isEmpty);
  });

  test('reports deferred failures after the app has launched', () async {
    final host = _RecordingBootstrapHost(
      failureStage: 'initializePersistentMediaCache',
    );

    AppBootstrap(host: host).start();
    await host.launched.future;

    expect(host.calls, [
      'ensureFlutterInitialized',
      'createDiagnostics',
      'installDiagnosticsSink',
      'installRecordingHttpOverrides',
      'installGlobalErrorHandlers',
      'initializePlugins',
      'launchApplication',
      'scheduleAfterFirstFrame',
    ]);

    await host.runDeferred();
    expect(host.calls.skip(8), [
      'initializeTimezoneEnvironment',
      'initializePersistentMediaCache',
      'reportError',
    ]);
    expect(host.reportedErrors, hasLength(1));
    final reported = host.reportedErrors.single;
    expect(reported.error, same(host.failure));
    expect(reported.operation, 'image.initializePersistentCache');
    expect(reported.source, 'image');
    expect(reported.handled, isTrue);
    expect(reported.degraded, isTrue);
  });

  test('records and forwards a fatal error after handlers install', () async {
    final host = _RecordingBootstrapHost(failureStage: 'initializePlugins');

    final forwarded = await _startAndCaptureFatalError(host);

    expect(forwarded.error, same(host.failure));
    expect(host.unhandledErrors, hasLength(1));
    expect(host.unhandledErrors.single.error, same(host.failure));
    expect(host.unhandledErrors.single.stackTrace, same(forwarded.stackTrace));
    expect(host.unhandledErrors.single.source, 'zone');
    expect(host.calls, [
      'ensureFlutterInitialized',
      'createDiagnostics',
      'installDiagnosticsSink',
      'installRecordingHttpOverrides',
      'installGlobalErrorHandlers',
      'initializePlugins',
      'reportUnhandledError',
    ]);
    expect(host.launched.isCompleted, isFalse);
  });

  test('forwards a fatal error before handlers can install', () async {
    final host = _RecordingBootstrapHost(failureStage: 'createDiagnostics');

    final forwarded = await _startAndCaptureFatalError(host);

    expect(forwarded.error, same(host.failure));
    expect(host.unhandledErrors, isEmpty);
    expect(host.calls, ['ensureFlutterInitialized', 'createDiagnostics']);
    expect(host.launched.isCompleted, isFalse);
  });
}

Future<({Object error, StackTrace stackTrace})> _startAndCaptureFatalError(
  _RecordingBootstrapHost host,
) async {
  final forwarded = Completer<({Object error, StackTrace stackTrace})>();
  runZonedGuarded<void>(() => AppBootstrap(host: host).start(), (
    error,
    stackTrace,
  ) {
    if (!forwarded.isCompleted) {
      forwarded.complete((error: error, stackTrace: stackTrace));
    }
  });
  // Startup deliberately crosses several completed Future boundaries. Give
  // that finite chain enough event turns to reach the parent zone, then fail
  // diagnostically instead of leaving a missed forwarder to hang the suite.
  await pumpEventQueue(times: 20);
  expect(
    forwarded.isCompleted,
    isTrue,
    reason: 'a fatal bootstrap error was not forwarded to the parent zone',
  );
  return forwarded.future;
}

typedef _ReportedError = ({
  Object error,
  StackTrace stackTrace,
  String operation,
  String source,
  bool handled,
  bool degraded,
});

typedef _UnhandledError = ({
  Object error,
  StackTrace stackTrace,
  String source,
});

final class _RecordingBootstrapHost implements AppBootstrapHost {
  _RecordingBootstrapHost({this.failureStage});

  final String? failureStage;
  final Object failure = StateError('startup failed');
  final List<String> calls = [];
  final List<_ReportedError> reportedErrors = [];
  final List<_UnhandledError> unhandledErrors = [];
  final Completer<void> launched = Completer<void>();
  final Completer<void> deferred = Completer<void>();
  Future<void> Function()? _deferredWork;

  void _record(String stage) {
    calls.add(stage);
    if (failureStage == stage) throw failure;
  }

  @override
  Future<void> createDiagnostics() async {
    _record('createDiagnostics');
  }

  @override
  void initializePlugins() {
    _record('initializePlugins');
  }

  @override
  void ensureFlutterInitialized() {
    _record('ensureFlutterInitialized');
  }

  @override
  Future<void> initializeTimezoneEnvironment() async {
    _record('initializeTimezoneEnvironment');
  }

  @override
  Future<void> initializePersistentMediaCache() async {
    _record('initializePersistentMediaCache');
  }

  @override
  void installDiagnosticsSink() {
    _record('installDiagnosticsSink');
  }

  @override
  AppBootstrapUnhandledErrorReporter installGlobalErrorHandlers() {
    _record('installGlobalErrorHandlers');
    return (Object error, StackTrace stackTrace, {required String source}) {
      calls.add('reportUnhandledError');
      unhandledErrors.add((
        error: error,
        stackTrace: stackTrace,
        source: source,
      ));
    };
  }

  @override
  void installRecordingHttpOverrides() {
    _record('installRecordingHttpOverrides');
  }

  @override
  void launchApplication() {
    _record('launchApplication');
    launched.complete();
  }

  @override
  void scheduleAfterFirstFrame(Future<void> Function() work) {
    _record('scheduleAfterFirstFrame');
    _deferredWork = work;
  }

  Future<void> runDeferred() async {
    await _deferredWork!();
    deferred.complete();
  }

  @override
  void reportError(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    required String source,
    required bool handled,
    required bool degraded,
  }) {
    _record('reportError');
    reportedErrors.add((
      error: error,
      stackTrace: stackTrace,
      operation: operation,
      source: source,
      handled: handled,
      degraded: degraded,
    ));
  }
}
