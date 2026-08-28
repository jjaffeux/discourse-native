import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_extension.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('the core manifest boots without optional plugin services', (
    tester,
  ) async {
    final plugins = PluginInstaller.install(corePluginManifest);
    final controller = ShellController(
      instanceStore: FakeInstanceStore(),
      api: FakeDiscourseApi(),
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      plugins: plugins,
    );
    addTearDown(() async {
      controller.dispose();
      await plugins.close();
    });

    await controller.load();
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: const MaterialApp(home: SizedBox()),
      ),
    );

    expect(plugins.descriptors, isEmpty);
    expect(plugins.registry.plugins, isEmpty);
    expect(() => controller.chat, throwsStateError);
  });
}
