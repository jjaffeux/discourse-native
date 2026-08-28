import 'dart:io';

import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
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
    expect(
      () => controller.pluginSession.require(chatControllerService),
      throwsStateError,
    );
  });

  test('core package is isolated from Resenha and native media SDKs', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final dependency in const [
      'discourse_resenha:',
      'flutter_webrtc:',
      'livekit_client:',
    ]) {
      expect(
        pubspec,
        isNot(contains(dependency)),
        reason: '$dependency belongs only to the full application profile.',
      );
    }

    final forbiddenImports = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final package in const [
        'package:discourse_resenha/',
        'package:flutter_webrtc/',
        'package:livekit_client/',
      ]) {
        if (source.contains(package)) {
          forbiddenImports.add('${entity.path} imports $package');
        }
      }
    }

    expect(
      Directory('lib/src/plugins/resenha').existsSync(),
      isFalse,
      reason: 'Resenha implementation belongs in packages/discourse_resenha.',
    );
    expect(
      forbiddenImports,
      isEmpty,
      reason:
          'The core package must boot without Resenha, WebRTC, or LiveKit.\n'
          '${forbiddenImports.join('\n')}',
    );
  });
}
