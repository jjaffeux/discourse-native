import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'data/byte_cache_store.dart';
import 'data/media_pipeline.dart';
import 'diagnostics/diagnostics.dart';
import 'foundation/timezone_environment.dart';
import 'macos_launch_screen.dart';
import 'plugin_api/core_plugin_manifest.dart';
import 'plugin_api/plugin_runtime.dart';

typedef AppBootstrapUnhandledErrorReporter =
    void Function(
      Object error,
      StackTrace stackTrace, {
      required String source,
    });

abstract interface class AppBootstrapHost {
  void ensureFlutterInitialized();

  Future<void> initializeTimezoneEnvironment();

  Future<void> createDiagnostics();

  void installDiagnosticsSink();

  void installRecordingHttpOverrides();

  AppBootstrapUnhandledErrorReporter installGlobalErrorHandlers();

  void initializePlugins();

  Future<void> initializePersistentMediaCache();

  void scheduleAfterFirstFrame(Future<void> Function() work);

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

final class AppBootstrap {
  AppBootstrap({required this._host});

  factory AppBootstrap.production({
    PluginManifest manifest = corePluginManifest,
  }) => AppBootstrap(host: _ProductionAppBootstrapHost(manifest));

  final AppBootstrapHost _host;

  void start() {
    final parentZone = Zone.current;
    AppBootstrapUnhandledErrorReporter? globalErrors;

    unawaited(
      runZonedGuarded<Future<void>>(
            () async {
              _host.ensureFlutterInitialized();
              await _host.createDiagnostics();
              _host.installDiagnosticsSink();
              _host.installRecordingHttpOverrides();
              globalErrors = _host.installGlobalErrorHandlers();
              _host.initializePlugins();
              _host.launchApplication();
              _host.scheduleAfterFirstFrame(() async {
                await Future.wait([
                  _runDeferredInitialization(
                    _host.initializeTimezoneEnvironment,
                    operation: 'timezone.initialize',
                    source: 'timezone',
                  ),
                  _runDeferredInitialization(
                    _host.initializePersistentMediaCache,
                    operation: 'image.initializePersistentCache',
                    source: 'image',
                  ),
                ]);
              });
            },
            (error, stackTrace) {
              globalErrors?.call(error, stackTrace, source: 'zone');
              // Recording must not turn a crash into successful continuation.
              parentZone.handleUncaughtError(error, stackTrace);
            },
          ) ??
          Future<void>.value(),
    );
  }

  Future<void> _runDeferredInitialization(
    Future<void> Function() initialize, {
    required String operation,
    required String source,
  }) async {
    try {
      await initialize();
    } catch (error, stackTrace) {
      // Optional platform services must never take down an already-visible UI.
      _host.reportError(
        error,
        stackTrace,
        operation: operation,
        source: source,
        handled: true,
        degraded: true,
      );
    }
  }
}

final class _ProductionAppBootstrapHost implements AppBootstrapHost {
  _ProductionAppBootstrapHost(this._manifest);

  final PluginManifest _manifest;
  late final DiagnosticsController _diagnostics;
  late final InstalledPlugins _plugins;

  @override
  void ensureFlutterInitialized() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  Future<void> initializeTimezoneEnvironment() =>
      TimezoneEnvironment.instance.initialize();

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
  void initializePlugins() {
    _plugins = PluginInstaller.install(_manifest);
  }

  @override
  Future<void> initializePersistentMediaCache() async {
    final mediaStore = await FileByteCacheStore.applicationCache();
    MediaPipeline.replace(MediaPipeline(store: mediaStore));
  }

  @override
  void scheduleAfterFirstFrame(Future<void> Function() work) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(work()));
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
    runApp(DiscourseApp(diagnostics: _diagnostics, plugins: _plugins));
    MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  }
}
