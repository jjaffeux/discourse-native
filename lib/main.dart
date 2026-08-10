import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/data/avatar_loader.dart';
import 'src/data/bounded_http_overrides.dart';
import 'src/data/byte_cache_store.dart';
import 'src/data/emoji_cache.dart';
import 'src/data/media_request_coordinator.dart';
import 'src/diagnostics/diagnostics.dart';
import 'src/plugins/local_dates/local_date_environment.dart';

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
            await LocalDateEnvironment.instance.initialize();
            BoundedHttpOverrides.install();
            final controller = await DiagnosticsController.create();
            DiagnosticsSink.install(controller);
            RecordingHttpOverrides.install(controller);
            globalErrors = DiagnosticsGlobalErrorBinding.install(controller);

            try {
              final mediaStore = await FileByteCacheStore.applicationCache();
              AvatarLoader.instance = AvatarLoader(
                coordinator: MediaRequestCoordinator.shared,
                store: mediaStore,
              );
              EmojiCache.instance = EmojiCache(
                coordinator: MediaRequestCoordinator.shared,
                store: mediaStore,
              );
            } catch (error, stackTrace) {
              // The disk cache is an optimization. A read-only/unavailable
              // cache directory must not keep the forum itself from opening.
              controller.reportError(
                error,
                stackTrace,
                operation: 'image.initializePersistentCache',
                source: 'image',
                handled: true,
                degraded: true,
              );
            }

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
