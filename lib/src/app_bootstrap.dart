import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'data/byte_cache_store.dart';
import 'data/linux_application_directories.dart';
import 'data/linux_preferences_store.dart';
import 'data/media_pipeline.dart';
import 'foundation/startup_timeline.dart';
import 'foundation/timezone_environment.dart';
import 'macos_launch_screen.dart';
import 'plugin_api/core_plugin_manifest.dart';
import 'plugin_api/plugin_runtime.dart';
import 'shell/component_styleguide_scope.dart';

abstract interface class AppBootstrapHost {
  void ensureFlutterInitialized();

  /// Runs before anything can reach preferences: `SharedPreferences` caches
  /// its first read for the rest of the process.
  void installPreferencesStore();

  Future<void> initializeTimezoneEnvironment();

  void initializePlugins();

  Future<void> initializePersistentMediaCache();

  Future<void> restrictApplicationDirectories();

  void scheduleAfterFirstFrame(Future<void> Function() work);

  void launchApplication();
}

final class AppBootstrap {
  AppBootstrap({required this._host});

  factory AppBootstrap.production({
    PluginManifest manifest = corePluginManifest,
    required ComponentStyleguideOpener openComponentStyleguide,
  }) => AppBootstrap(
    host: _ProductionAppBootstrapHost(manifest, openComponentStyleguide),
  );

  final AppBootstrapHost _host;
  bool _admitted = false;
  ({Object error, StackTrace stack})? _failure;

  void start() {
    if (_failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stack);
    }
    if (_admitted) return;
    _admitted = true;
    try {
      markStartup('main');
      _host.ensureFlutterInitialized();
      _host.installPreferencesStore();
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
      rethrow;
    }
  }

  Future<void> _runDeferredInitialization(
    Future<void> Function() initialize,
  ) async {
    try {
      await initialize();
    } catch (_) {
      // Deferred startup work must never take down an already-visible UI.
    }
  }
}

final class _ProductionAppBootstrapHost implements AppBootstrapHost {
  _ProductionAppBootstrapHost(this._manifest, this._openComponentStyleguide);

  final PluginManifest _manifest;
  final ComponentStyleguideOpener _openComponentStyleguide;
  late final InstalledPlugins _plugins;

  @override
  void ensureFlutterInitialized() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  void installPreferencesStore() {
    LinuxPreferencesStore.install();
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
    final mediaStore = await FileByteCacheStore.applicationCache();
    MediaPipeline.replace(MediaPipeline(store: mediaStore));
  }

  @override
  Future<void> restrictApplicationDirectories() =>
      restrictLinuxApplicationDirectories();

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
