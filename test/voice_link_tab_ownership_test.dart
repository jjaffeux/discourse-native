import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/plugins/voice/voice_api.dart';
import 'package:discourse_native/src/plugins/voice/voice_controller.dart';
import 'package:discourse_native/src/plugins/voice/voice_models.dart';
import 'package:discourse_native/src/plugins/voice/voice_services.dart';
import 'package:discourse_native/src/plugins/voice/voice_shell_service.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/voice_fake_chat_conversations.dart';

const _site = 'https://voice.example.com';
const _room = <String, dynamic>{
  'id': 7,
  'name': 'Lounge',
  'slug': 'lounge',
  'public': true,
  'room_type': 'open',
};

void main() {
  for (final boundary in ['directory', 'room']) {
    for (final leaveSource in [true, false]) {
      testWidgets(
        'Voice $boundary lookup stays in its source tab (switch: $leaveSource)',
        (tester) async {
          final transport = RecordingPluginTransport(
            responses: const {
              'GET /voice/rooms.json': {'rooms': <Object?>[]},
              'GET /voice/rooms/lounge.json': _room,
            },
            responders: {
              'POST /voice/rooms/7/join.json': (_) =>
                  throw const WriteException(WriteFailure.forbidden),
            },
          );
          final gate = Completer<Map<String, dynamic>>();
          final started = Completer<void>();
          final path = boundary == 'directory'
              ? 'GET /voice/rooms.json'
              : 'GET /voice/rooms/lounge.json';
          transport.responders[path] = (_) {
            started.complete();
            return gate.future;
          };
          addTearDown(() {
            if (!gate.isCompleted) gate.complete(transport.responses[path]!);
          });
          final module = _VoiceLinkModule(transport);
          final plugins = PluginInstaller.install(PluginManifest([module]));
          addTearDown(plugins.close);
          const user = DiscourseUser(id: 1, username: 'reader');
          final shell = ShellController(
            instanceStore: FakeInstanceStore([
              instance('voice.example.com').copyWith(user: user),
            ]),
            api: FakeDiscourseApi(
              user: user,
              feeds: const {'/latest.json': []},
            ),
            authenticator: FakeAuthenticator()..keys[_site] = 'key',
            drafts: FakeDraftStore(),
            trackers: FakeSiteTracker.reset(),
            plugins: plugins,
          );
          var disposed = false;
          addTearDown(() {
            if (!disposed) shell.dispose();
          });
          await shell.load();
          await tester.pumpWidget(
            ShellScope(
              controller: shell,
              child: MaterialApp(
                home: Scaffold(
                  body: LinkTarget.content(
                    content: ContentRoute.preferences(),
                    child: DButton(
                      onPressed: () {},
                      label: const Text('Another page'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final source = shell.activeTabId!;
          final route = shell.currentContent!;
          final opening = module.voice.openPluginUrl(
            '/voice/r/lounge/invited-by/Older',
          );
          await started.future;
          if (leaveSource) {
            await tester.tap(
              find.text('Another page'),
              kind: PointerDeviceKind.mouse,
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.widgetWithText(DContextMenuItem, 'Open in new main tab'),
            );
            await tester.pumpAndSettle();
            final copied = shell.tabsForCurrentForum.last.id;
            expect(copied, isNot(source));
            shell.selectTab(copied);
            expect(shell.handleBack(canReturnToSidebar: false), isTrue);
            await tester.pumpAndSettle();
            expect(shell.currentContent, same(route));
            expect(shell.activeTabId, copied);
          }
          final currentTab = shell.activeTabId;
          gate.complete(transport.responses[path]!);
          expect(await opening, isTrue);
          await tester.pumpAndSettle();
          expect(shell.activeTabId, currentTab);
          if (leaveSource) {
            expect(shell.currentContent, same(route));
            expect(
              shell.currentWorkspace!.tabById(source)!.currentContent,
              same(route),
            );
          } else {
            expect(shell.currentContent?.id, 'voice-room-7');
          }
          await module.controller.join(
            siteUrl: _site,
            siteName: 'Voice',
            room: VoiceRoom.fromJson(_room),
          );
          expect(
            transport.writes.last.body['invited_by'],
            leaveSource ? isNull : 'older',
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            disposed = true;
            shell.dispose();
            await shell.pluginTeardown;
          });
        },
      );
    }
  }
}

final class _VoiceLinkModule implements PluginModule {
  _VoiceLinkModule(this.transport);
  final RecordingPluginTransport transport;
  late VoiceController controller;
  late VoiceShellService voice;
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(id: voicePluginId);
  @override
  void register(PluginRegistrar registrar) {
    registrar.addSession((bindings, _) {
      controller = VoiceController(
        api: VoiceApi(transport),
        requests: bindings.require(corePluginRequestPort),
        chatConversations: FakeChatConversationCapability(),
        trackerFor: (_) => null,
        userIdFor: (_) => 1,
        onCallSiteChanged: () {},
      );
      voice = VoiceShellService(
        controller: controller,
        host: bindings.require(corePluginRouteNavigationPort),
        recordingEnabled: (_) => false,
      );
      return PluginSessionContribution(
        lifecycle: _VoiceLifecycle(controller),
        services: [PluginService<Object>(voiceShellService, voice)],
      );
    }, requires: const [corePluginRequestPort, corePluginRouteNavigationPort]);
  }
}

final class _VoiceLifecycle extends PluginSessionLifecycle {
  _VoiceLifecycle(this.controller);
  final VoiceController controller;
  @override
  void forget(String siteUrl) => controller.forget(siteUrl);
  @override
  Future<void> close() => controller.close();
}
