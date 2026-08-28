import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_services.dart';
import 'package:discourse_native/src/plugins/resenha/resenha_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';

void main() {
  test('core-only preserves and safely presents an unknown plugin row', () {
    final plugins = PluginInstaller.install(corePluginManifest);
    addTearDown(plugins.close);
    final source = <String, dynamic>{
      'id': 51,
      'notification_type': 29,
      'notification_type_name': 'chat_mention',
      'fancy_title': 'Safe envelope alert',
      'data': {
        'topic_title': 'Opaque Chat alert',
        'chat_channel_id': 9,
        'future': {'kept': true},
      },
    };

    final notification = DiscourseNotification.fromJson(source);
    final resolved = plugins.registry.resolveNotification(notification);

    expect(notification.typeId, const NotificationTypeId(29));
    expect(notification.typeName, const NotificationTypeName('chat_mention'));
    expect(notification.toJson(), source);
    expect(resolved.presentation.icon.name, 'bell');
    expect(notification.title, 'Safe envelope alert');
    expect(notification.data['topic_title'], 'Opaque Chat alert');
    expect(resolved.presentation.phrase, 'Safe envelope alert');
    expect(resolved.path, isNull);
  });

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
    expect(controller.pluginSession.maybeService(resenhaShellService), isNull);
    expect(
      () => controller.pluginSession.require(chatControllerService),
      throwsStateError,
    );
    expect(
      () => controller.pluginSession.require(resenhaControllerService),
      throwsStateError,
    );
  });
}
