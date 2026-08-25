import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/shell_sheet.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';

/// Opens the current account's notification settings for one followed channel.
class ChatChannelNotificationButton extends StatelessWidget {
  const ChatChannelNotificationButton({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final chat = PluginScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null || !channel.membership.following) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final busy = chat.channelNotificationWriteInFlight(
              siteUrl,
              channelId,
            );
            return IconButton(
              key: const ValueKey('chat-channel-notification-button'),
              tooltip: 'Channel notifications',
              onPressed: busy
                  ? null
                  : () => unawaited(
                      showShellSheet<void>(
                        context: context,
                        title: 'Channel notifications',
                        dialogOnDesktop: true,
                        builder: (context) => _ChannelNotificationSettings(
                          chat: chat,
                          siteUrl: siteUrl,
                          channelId: channelId,
                        ),
                      ),
                    ),
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    )
                  : DIcon(_iconFor(channel.membership), size: 18),
            );
          },
        );
      },
    );
  }
}

DIconData _iconFor(ChatMembership membership) {
  if (membership.muted) return DIcons.discourseBellSlash;
  return switch (membership.notificationLevel) {
    ChatChannelNotificationLevel.never => DIcons.discourseBellSlash,
    ChatChannelNotificationLevel.mention => DIcons.farBell,
    ChatChannelNotificationLevel.always => DIcons.discourseBellExclamation,
  };
}

class _ChannelNotificationSettings extends StatelessWidget {
  const _ChannelNotificationSettings({
    required this.chat,
    required this.siteUrl,
    required this.channelId,
  });

  final ChatController chat;
  final String siteUrl;
  final int channelId;

  void _notice(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _change(
    BuildContext context, {
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) async {
    final error = await chat.updateChannelNotifications(
      siteUrl,
      channelId,
      muted: muted,
      notificationLevel: notificationLevel,
    );
    if (error != null && context.mounted) _notice(context, error);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null) {
          return const Text('This channel is no longer available.');
        }
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final membership = channel.membership;
            final busy = chat.channelNotificationWriteInFlight(
              siteUrl,
              channelId,
            );
            Widget option({
              required ChatChannelNotificationLevel level,
              required String title,
              required String subtitle,
            }) {
              final selected = membership.notificationLevel == level;
              return ListTile(
                key: ValueKey('chat-channel-notification-${level.name}'),
                enabled: !busy,
                leading: DIcon(switch (level) {
                  ChatChannelNotificationLevel.never =>
                    DIcons.discourseBellSlash,
                  ChatChannelNotificationLevel.mention => DIcons.farBell,
                  ChatChannelNotificationLevel.always =>
                    DIcons.discourseBellExclamation,
                }),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: selected ? const DIcon(DIcons.check) : null,
                selected: selected,
                onTap: busy || selected
                    ? null
                    : () =>
                          unawaited(_change(context, notificationLevel: level)),
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                option(
                  level: ChatChannelNotificationLevel.never,
                  title: 'Never',
                  subtitle: 'Do not send push notifications',
                ),
                option(
                  level: ChatChannelNotificationLevel.mention,
                  title: 'Mentions',
                  subtitle: 'Notify for mentions',
                ),
                option(
                  level: ChatChannelNotificationLevel.always,
                  title: 'All activity',
                  subtitle: 'Notify for every message',
                ),
                const Divider(),
                SwitchListTile.adaptive(
                  key: const ValueKey('chat-channel-muted-setting'),
                  secondary: const DIcon(DIcons.discourseBellSlash),
                  title: const Text('Mute channel'),
                  subtitle: const Text('Hide unread indicators and alerts'),
                  value: membership.muted,
                  onChanged: busy
                      ? null
                      : (muted) => unawaited(_change(context, muted: muted)),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
