import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'owned Voice diagnostics do not gate bootstrap on history hydration',
    () async {
      final hydrationStarted = Completer<void>();
      final releaseHydration = Completer<void>();
      final ordinary = await DiagnosticsController.create(
        persistence: MemoryDiagnosticsPersistence(),
        sessionId: 'voice-bootstrap',
      );
      final plugin = VoiceDiagnosticsPlugin(
        persistenceFactory: () async {
          hydrationStarted.complete();
          await releaseHydration.future;
          return MemoryVoiceDiagnosticsPersistence();
        },
      );
      final installed = PluginInstaller.install(
        PluginManifest([_OwnedVoiceDiagnosticsModule(plugin)]),
      );
      addTearDown(() async {
        if (!releaseHydration.isCompleted) releaseHydration.complete();
        await installed.close();
        await ordinary.close();
      });

      final startup = installed.startPhase(
        PluginStartupPhase.bootstrap,
        bindings: PluginHostBindings([
          PluginHostPort<Object>(
            pluginDiagnosticsReporterPort,
            PluginDiagnosticsReporter.fixed(ordinary),
          ),
        ]),
      );
      await hydrationStarted.future;
      await startup.timeout(const Duration(seconds: 1));
      expect(releaseHydration.isCompleted, isFalse);

      plugin.record(
        'voice.bootstrap.early-error',
        severity: DiagnosticSeverity.error,
      );
      expect(
        ordinary.events.whereType<DiagnosticLogEvent>().map(
          (event) => event.name,
        ),
        contains('voice.bootstrap.early-error'),
      );

      var flushCompleted = false;
      final flushing = plugin.flush().then((_) => flushCompleted = true);
      await pumpEventQueue(times: 1);
      expect(flushCompleted, isFalse);
      releaseHydration.complete();
      await flushing;
    },
  );

  testWidgets('injected Voice diagnostics remain caller-owned', (tester) async {
    final key = GlobalKey();
    final bridgeReleased = Completer<void>();
    final first = await VoiceDiagnosticsController.create(
      persistence: MemoryVoiceDiagnosticsPersistence(),
      sdkLogBridges: [
        CallbackVoiceDiagnosticsSdkLogBridge(
          install: (_) {},
          uninstall: () {
            if (!bridgeReleased.isCompleted) bridgeReleased.complete();
          },
        ),
      ],
    );
    final second = await VoiceDiagnosticsController.create(
      persistence: MemoryVoiceDiagnosticsPersistence(),
    );
    addTearDown(first.close);
    addTearDown(second.close);
    await first.startCapture();

    final host = await PluginHostHarness.forApp(
      transport: RecordingPluginTransport(),
    );
    addTearDown(host.close);

    Widget app(VoiceDiagnosticsController diagnostics) => host.buildApp(
      key: key,
      manifest: PluginManifest([_VoiceDiagnosticsModule(diagnostics)]),
    );

    await tester.pumpWidget(app(first));
    await tester.pump();
    expect(first.captureEnabled, isTrue);

    await tester.pumpWidget(app(second));
    await tester.pump();

    expect(bridgeReleased.isCompleted, isFalse);
    expect(first.captureEnabled, isTrue);
    expect(second.captureEnabled, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await first.close();
    await second.close();
    expect(bridgeReleased.isCompleted, isTrue);
  });
}

final class _OwnedVoiceDiagnosticsModule implements PluginModule {
  const _OwnedVoiceDiagnosticsModule(this.plugin);

  final VoiceDiagnosticsPlugin plugin;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('voice'));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(plugin);
    registrar.addAppLifecycle(
      plugin,
      requires: const [pluginDiagnosticsReporterPort],
    );
  }
}

final class _VoiceDiagnosticsModule implements PluginModule {
  const _VoiceDiagnosticsModule(this.controller);

  final VoiceDiagnosticsController controller;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('voice'));

  @override
  void register(PluginRegistrar registrar) {
    final plugin = VoiceDiagnosticsPlugin(controller: controller);
    registrar.addCapability(plugin);
    registrar.addAppLifecycle(
      plugin,
      requires: const [pluginDiagnosticsReporterPort],
    );
  }
}
