import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics.dart';
import 'package:discourse_native/src/plugins/voice/voice_diagnostics_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
