import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/file_byte_cache_store.dart';
import 'data/http_basic_auth.dart';
import 'data/linux_application_directories.dart';
import 'data/linux_preferences_store.dart';
import 'data/media_pipeline.dart';
import 'foundation/error_log.dart';
import 'foundation/startup_timeline.dart';
import 'foundation/timezone_environment.dart';
import 'macos_launch_screen.dart';
import 'plugin_api/core_plugin_manifest.dart';
import 'plugin_api/plugin_runtime.dart';
import 'shell/component_styleguide_scope.dart';

abstract interface class AppBootstrapHost {
  /// Runs first, so a failure of any later stage is already captured.
  void installErrorCapture(ErrorLog log);

  void ensureFlutterInitialized();

  /// Runs before anything can reach preferences: `SharedPreferences` caches
  /// its first read for the rest of the process.
  void installPreferencesStore();

  /// Starts the slow local reads that do not need the widget tree, so they
  /// run alongside the first build rather than after it.
  void preloadLocalState();

  Future<void> initializeTimezoneEnvironment();

  void initializePlugins();

  Future<void> initializePersistentMediaCache();

  Future<void> restrictApplicationDirectories();

  void scheduleAfterFirstFrame(Future<void> Function() work);

  void launchApplication();
}

final class AppBootstrap {
  AppBootstrap({required this._host, ErrorLog? errorLog})
    : _errorLog = errorLog ?? ErrorLog.instance;

  factory AppBootstrap.production({
    PluginManifest manifest = corePluginManifest,
    required ComponentStyleguideOpener openComponentStyleguide,
  }) => AppBootstrap(
    host: _ProductionAppBootstrapHost(manifest, openComponentStyleguide),
  );

  final AppBootstrapHost _host;
  final ErrorLog _errorLog;
  bool _admitted = false;
  ({Object error, StackTrace stack})? _failure;

  void start() {
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
    if (_admitted) return;
    _admitted = true;
    // The binding and `runApp` must share a zone, so the whole launch runs
    // inside the guard. A guarded zone would also swallow a synchronous
    // startup failure, which is why `_launch` keeps it for the rethrow below.
    final parent = Zone.current;
    runZonedGuarded(_launch, (error, stack) {
      _errorLog.record(error, stack, source: ErrorSource.zone);
      parent.handleUncaughtError(error, stack);
    });
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
  }

  void _launch() {
    try {
      markStartup('main');
      _host.installErrorCapture(_errorLog);
      _host.ensureFlutterInitialized();
      _host.installPreferencesStore();
      _host.preloadLocalState();
      markStartup('binding ready');
      _host.initializePlugins();
      markStartup('plugins installed');
      _host.launchApplication();
      markStartup('first frame scheduled');
      _host.scheduleAfterFirstFrame(() async {
        await Future.wait([
          _runDeferredInitialization(_host.initializeTimezoneEnvironment),
          _runDeferredInitialization(_host.initializePersistentMediaCache),
          _runDeferredInitialization(_host.restrictApplicationDirectories),
        ]);
      });
    } catch (error, stack) {
      // Startup is not transactional: repeating partial installation can
      // construct a second runtime or assign the production plugin graph twice.
      _failure = (error: error, stack: stack);
      _errorLog.record(error, stack, source: ErrorSource.startup);
    }
  }

  Future<void> _runDeferredInitialization(
    Future<void> Function() initialize,
  ) async {
    try {
      await initialize();
    } catch (error, stack) {
      // Deferred startup work must never take down an already-visible UI.
      _errorLog.record(error, stack, source: ErrorSource.startup);
    }
  }
}

/// Records framework and uncaught platform errors into [log], then hands each
/// to whatever handled it before, so reporting to the console is unchanged.
void installFlutterErrorCapture(ErrorLog log) {
  final presentFrameworkError = FlutterError.onError;
  FlutterError.onError = (details) {
    log.record(details.exception, details.stack, source: ErrorSource.framework);
    presentFrameworkError?.call(details);
  };
  final dispatcher = PlatformDispatcher.instance;
  final handlePlatformError = dispatcher.onError;
  dispatcher.onError = (error, stack) {
    log.record(error, stack, source: ErrorSource.platform);
    return handlePlatformError?.call(error, stack) ?? false;
  };
}

final class _ProductionAppBootstrapHost implements AppBootstrapHost {
  _ProductionAppBootstrapHost(this._manifest, this._openComponentStyleguide);

  final PluginManifest _manifest;
  final ComponentStyleguideOpener _openComponentStyleguide;
  late final InstalledPlugins _plugins;

  @override
  void installErrorCapture(ErrorLog log) => installFlutterErrorCapture(log);

  @override
  void ensureFlutterInitialized() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  void installPreferencesStore() {
    LinuxPreferencesStore.install(
      file: () async =>
          linuxPreferencesFile(await getApplicationSupportDirectory()),
    );
  }

  @override
  void preloadLocalState() {
    // A failure here is left for the load that needs the credentials, which
    // retries and reports it.
    unawaited(HttpBasicAuthStore.instance.load().catchError((Object _) {}));
  }

  @override
  Future<void> initializeTimezoneEnvironment() =>
      TimezoneEnvironment.instance.initialize();

  @override
  void initializePlugins() {
    _plugins = PluginInstaller.install(_manifest);
  }

  @override
  Future<void> initializePersistentMediaCache() async {
    final root = await getApplicationCacheDirectory();
    final mediaStore = await FileByteCacheStore.applicationCache(root);
    MediaPipeline.replace(MediaPipeline(store: mediaStore));
  }

  @override
  Future<void> restrictApplicationDirectories() =>
      restrictLinuxApplicationDirectories(
        supportDirectory: getApplicationSupportDirectory,
        cacheDirectory: getApplicationCacheDirectory,
      );

  @override
  void scheduleAfterFirstFrame(Future<void> Function() work) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(work()));
  }

  @override
  void launchApplication() {
    runApp(
      DiscourseApp(
        plugins: _plugins,
        openComponentStyleguide: _openComponentStyleguide,
      ),
    );
    MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  }
}
