import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'data/avatar_loader.dart';
import 'data/bounded_http_overrides.dart';
import 'data/byte_cache_store.dart';
import 'data/emoji_cache.dart';
import 'data/media_request_coordinator.dart';
import 'diagnostics/diagnostics.dart';
import 'plugins/local_dates/local_date_environment.dart';
import 'plugins/resenha/resenha_diagnostics.dart';
import 'plugins/resenha/resenha_sdk_diagnostics.dart';

typedef AppBootstrapUnhandledErrorReporter =
    void Function(
      Object error,
      StackTrace stackTrace, {
      required String source,
    });

/// Platform-facing operations whose order and failure policy are owned by
/// [AppBootstrap].
abstract interface class AppBootstrapHost {
  void ensureFlutterInitialized();

  Future<void> initializeLocalDates();

  void installBoundedHttpOverrides();

  Future<void> createDiagnostics();

  void installDiagnosticsSink();

  void installRecordingHttpOverrides();

  AppBootstrapUnhandledErrorReporter installGlobalErrorHandlers();

  Future<void> createResenhaDiagnostics();

  Future<void> initializePersistentMediaCache();

  void reportError(
    Object error,
    StackTrace stackTrace, {
    required String operation,
    required String source,
    required bool handled,
    required bool degraded,
  });

  void launchApplication();
}

/// Owns the required startup order, the optional cache boundary, and root-zone
/// error forwarding.
final class AppBootstrap {
  AppBootstrap({required this._host});

  factory AppBootstrap.production() =>
      AppBootstrap(host: _ProductionAppBootstrapHost());

  final AppBootstrapHost _host;

  void start() {
    final parentZone = Zone.current;
    AppBootstrapUnhandledErrorReporter? globalErrors;

    unawaited(
      runZonedGuarded<Future<void>>(
            () async {
              _host.ensureFlutterInitialized();
              await _host.initializeLocalDates();
              _host.installBoundedHttpOverrides();
              await _host.createDiagnostics();
              _host.installDiagnosticsSink();
              _host.installRecordingHttpOverrides();
              globalErrors = _host.installGlobalErrorHandlers();
              await _host.createResenhaDiagnostics();

              try {
                await _host.initializePersistentMediaCache();
              } catch (error, stackTrace) {
                // Persistent media caching is an optimization. An unavailable
                // cache directory must not keep the forum from opening.
                _host.reportError(
                  error,
                  stackTrace,
                  operation: 'image.initializePersistentCache',
                  source: 'image',
                  handled: true,
                  degraded: true,
                );
              }

              _host.launchApplication();
            },
            (error, stackTrace) {
              globalErrors?.call(error, stackTrace, source: 'zone');
              // Recording must not turn a crash into a successful continuation.
              // Preserve the evidence, then return the failure to the zone that
              // launched the application.
              parentZone.handleUncaughtError(error, stackTrace);
            },
          ) ??
          Future<void>.value(),
    );
  }
}

final class _ProductionAppBootstrapHost implements AppBootstrapHost {
  late final DiagnosticsController _diagnostics;
  late final ResenhaDiagnosticsController _resenhaDiagnostics;

  @override
  void ensureFlutterInitialized() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  Future<void> initializeLocalDates() =>
      LocalDateEnvironment.instance.initialize();

  @override
  void installBoundedHttpOverrides() {
    BoundedHttpOverrides.install();
  }

  @override
  Future<void> createDiagnostics() async {
    _diagnostics = await DiagnosticsController.create();
  }

  @override
  void installDiagnosticsSink() {
    DiagnosticsSink.install(_diagnostics);
  }

  @override
  void installRecordingHttpOverrides() {
    RecordingHttpOverrides.install(_diagnostics);
  }

  @override
  AppBootstrapUnhandledErrorReporter installGlobalErrorHandlers() {
    final binding = DiagnosticsGlobalErrorBinding.install(_diagnostics);
    return (Object error, StackTrace stackTrace, {required String source}) =>
        binding.reportUnhandledError(error, stackTrace, source: source);
  }

  @override
  Future<void> createResenhaDiagnostics() async {
    _resenhaDiagnostics = await ResenhaDiagnosticsController.create(
      sdkLogBridges: [NativeResenhaDiagnosticsSdkLogBridge()],
    );
  }

  @override
  Future<void> initializePersistentMediaCache() async {
    final mediaStore = await FileByteCacheStore.applicationCache();
    AvatarLoader.instance = AvatarLoader(
      coordinator: MediaRequestCoordinator.shared,
      store: mediaStore,
    );
    EmojiCache.instance = EmojiCache(
      coordinator: MediaRequestCoordinator.shared,
      store: mediaStore,
    );
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
    _diagnostics.reportError(
      error,
      stackTrace,
      operation: operation,
      source: source,
      handled: handled,
      degraded: degraded,
    );
  }

  @override
  void launchApplication() {
    runApp(
      DiscourseApp(
        diagnostics: _diagnostics,
        resenhaDiagnostics: _resenhaDiagnostics,
      ),
    );
  }
}
