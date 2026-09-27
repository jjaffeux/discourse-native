import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import '../chat/chat_contract.dart';
import 'voice_controller.dart';
import 'voice_join.dart';
import 'voice_shell_service.dart';

const voiceChatInboxService = PluginServiceKey<ChatInboxRooms>(
  owner: PluginId('voice'),
  name: 'chat-inbox',
);

final class VoiceChatInbox implements ChatInboxRoomProvider {
  const VoiceChatInbox(this.controller, this.shell);
  final VoiceController controller;
  final VoiceShellService shell;

  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);

  @override
  bool available(String siteUrl) =>
      controller.supportedPlatform &&
      shell.currentInstance?.url == siteUrl &&
      shell.currentInstance?.isConnected == true &&
      shell.enabledFor(siteUrl) &&
      controller.directory(siteUrl) != null;

  @override
  List<ChatInboxRoom> rooms(String siteUrl) => !available(siteUrl)
      ? const []
      : [
          for (final room in controller.directory(siteUrl)!.rooms)
            ChatInboxRoom(
              id: room.id,
              name: room.name,
              people: room.participants.length,
              open: (context) async {
                if (!available(siteUrl)) return;
                await joinVoiceRoom(
                  context,
                  controller: controller,
                  siteUrl: siteUrl,
                  siteName: shell.currentInstance!.title,
                  room: room,
                  ifCurrent: () => available(siteUrl),
                  meshPrivacyWarningEnabled: shell.meshPrivacyWarningEnabledFor(
                    siteUrl,
                  ),
                );
              },
            ),
        ];
}
