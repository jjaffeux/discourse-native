import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_resenha/src/resenha_diagnostics.dart';
import 'package:discourse_resenha/src/resenha_diagnostics_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('injected Resenha diagnostics remains caller-owned', (
    tester,
  ) async {
    final key = GlobalKey();
    final bridgeReleased = Completer<void>();
    final first = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
      sdkLogBridges: [
        CallbackResenhaDiagnosticsSdkLogBridge(
          install: (_) {},
          uninstall: () {
            if (!bridgeReleased.isCompleted) bridgeReleased.complete();
          },
        ),
      ],
    );
    final second = await ResenhaDiagnosticsController.create(
      persistence: MemoryResenhaDiagnosticsPersistence(),
    );
    addTearDown(first.close);
    addTearDown(second.close);
    await first.startCapture();

    final store = FakeInstanceStore();
    final api = FakeDiscourseApi();
    final authenticator = FakeAuthenticator();
    final drafts = FakeDraftStore();
    final forumTabs = FakeForumTabStore();
    final trackers = FakeSiteTracker.reset();
    final updater = FakeUpdater();
    final updateStore = FakeUpdateStore();

    Widget app(ResenhaDiagnosticsController diagnostics) => DiscourseApp(
      key: key,
      store: store,
      api: api,
      authenticator: authenticator,
      drafts: drafts,
      forumTabs: forumTabs,
      trackers: trackers,
      updater: updater,
      updateStore: updateStore,
      initialRootMode: ShellRootMode.forum,
      pluginManifest: PluginManifest([_ResenhaDiagnosticsModule(diagnostics)]),
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

final class _ResenhaDiagnosticsModule implements PluginModule {
  const _ResenhaDiagnosticsModule(this.controller);

  final ResenhaDiagnosticsController controller;

  @override
  PluginDescriptor get descriptor =>
      const PluginDescriptor(id: PluginId('resenha'));

  @override
  void register(PluginRegistrar registrar) {
    final plugin = ResenhaDiagnosticsPlugin(controller: controller);
    registrar.addCapability(plugin);
    registrar.addAppLifecycle(
      plugin,
      requires: const [pluginDiagnosticsReporterPort],
    );
  }
}
