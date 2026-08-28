import 'dart:async';

import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_services.dart';
import 'chat_shell_extension.dart';

enum _ChannelAction { settings, star, leave }

enum _NotificationAction { never, mention, always, mute }

/// The web-equivalent action menu revealed beside one channel sidebar row.
///
/// Desktop keeps the notification choices in a submenu. Touch uses the same
/// command set in a bottom sheet reached by holding the row.
class ChatChannelMenuButton extends StatelessWidget {
  const ChatChannelMenuButton({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  static Future<void> showSheet({
    required BuildContext context,
    required String siteUrl,
    required int channelId,
  }) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final channel = chat.channel(siteUrl, channelId);
    if (channel == null) return Future<void>.value();

    return showShellSheet<void>(
      context: context,
      title: channel.title,
      padding: const EdgeInsets.all(6),
      builder: (context) => _ChannelActionsSheet(
        siteUrl: siteUrl,
        channelId: channelId,
        chat: chat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null || !channel.membership.following) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) => _DesktopChannelMenu(
            siteUrl: siteUrl,
            channel: channel,
            chat: chat,
          ),
        );
      },
    );
  }
}

class _DesktopChannelMenu extends StatelessWidget {
  const _DesktopChannelMenu({
    required this.siteUrl,
    required this.channel,
    required this.chat,
  });

  final String siteUrl;
  final ChatChannel channel;
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notificationBusy = chat.channelNotificationWriteInFlight(
      siteUrl,
      channel.id,
    );
    final starBusy = chat.channelStarWriteInFlight(siteUrl, channel.id);
    final followBusy = chat.channelFollowWriteInFlight(siteUrl, channel.id);
    final membership = channel.membership;
    final menuStyle = MenuStyle(
      backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      maximumSize: const WidgetStatePropertyAll(Size(380, 440)),
    );

    return MenuAnchor(
      style: menuStyle,
      menuChildren: [
        SubmenuButton(
          key: ValueKey('chat-channel-notifications-${channel.id}'),
          leadingIcon: const DIcon(DIcons.bell, size: 16),
          menuStyle: menuStyle,
          menuChildren: [
            for (final action in const [
              _NotificationAction.never,
              _NotificationAction.mention,
              _NotificationAction.always,
            ])
              MenuItemButton(
                key: ValueKey(
                  'chat-channel-notification-${channel.id}-${action.name}',
                ),
                onPressed: notificationBusy
                    ? null
                    : () => unawaited(
                        _applyNotificationAction(
                          context,
                          chat,
                          siteUrl,
                          channel,
                          action,
                        ),
                      ),
                trailingIcon: _notificationSelected(membership, action)
                    ? const DIcon(DIcons.check, size: 14)
                    : null,
                child: Text(_notificationLabel(action)),
              ),
            const Divider(height: 1),
            MenuItemButton(
              key: ValueKey('chat-channel-mute-${channel.id}'),
              onPressed: notificationBusy
                  ? null
                  : () => unawaited(
                      _applyNotificationAction(
                        context,
                        chat,
                        siteUrl,
                        channel,
                        _NotificationAction.mute,
                      ),
                    ),
              leadingIcon: DIcon(
                membership.muted ? DIcons.discourseBellSlash : DIcons.bell,
                size: 16,
              ),
              trailingIcon: membership.muted
                  ? const DIcon(DIcons.check, size: 14)
                  : null,
              child: Text(membership.muted ? 'Unmute channel' : 'Mute channel'),
            ),
          ],
          child: const Text('Notifications'),
        ),
        MenuItemButton(
          key: ValueKey('chat-channel-menu-settings-${channel.id}'),
          onPressed: () => _applyChannelAction(
            context,
            chat,
            siteUrl,
            channel,
            _ChannelAction.settings,
          ),
          leadingIcon: const DIcon(DIcons.gear, size: 16),
          child: const Text('Channel settings'),
        ),
        MenuItemButton(
          key: ValueKey('chat-channel-menu-star-${channel.id}'),
          onPressed: starBusy
              ? null
              : () => _applyChannelAction(
                  context,
                  chat,
                  siteUrl,
                  channel,
                  _ChannelAction.star,
                ),
          leadingIcon: DIcon(
            membership.starred ? DIcons.star : DIcons.farStar,
            size: 16,
          ),
          child: Text(
            membership.starred
                ? 'Remove from starred channels'
                : 'Add to starred channels',
          ),
        ),
        MenuItemButton(
          key: ValueKey('chat-channel-menu-leave-${channel.id}'),
          onPressed: followBusy
              ? null
              : () => _applyChannelAction(
                  context,
                  chat,
                  siteUrl,
                  channel,
                  _ChannelAction.leave,
                ),
          leadingIcon: const DIcon(DIcons.xmark, size: 16),
          style: MenuItemButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            iconColor: theme.colorScheme.error,
          ),
          child: Text(
            channel.isDirectMessage ? 'Close channel' : 'Leave channel',
          ),
        ),
      ],
      builder: (context, menu, child) => IconButton(
        key: ValueKey('chat-channel-menu-button-${channel.id}'),
        constraints: const BoxConstraints.tightFor(width: 24, height: 32),
        padding: EdgeInsets.zero,
        tooltip: 'Open ${channel.title} menu',
        onPressed: menu.open,
        icon: const DIcon(DIcons.ellipsisVertical, size: 16),
      ),
    );
  }
}

class _ChannelActionsSheet extends StatelessWidget {
  const _ChannelActionsSheet({
    required this.siteUrl,
    required this.channelId,
    required this.chat,
  });

  final String siteUrl;
  final int channelId;
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null || !channel.membership.following) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final notificationBusy = chat.channelNotificationWriteInFlight(
              siteUrl,
              channelId,
            );
            final starBusy = chat.channelStarWriteInFlight(siteUrl, channelId);
            final followBusy = chat.channelFollowWriteInFlight(
              siteUrl,
              channelId,
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: ValueKey('chat-channel-notifications-$channelId'),
                  leading: const DIcon(DIcons.bell),
                  trailing: const DIcon(DIcons.chevronRight, size: 14),
                  enabled: !notificationBusy,
                  title: const Text('Notifications'),
                  onTap: notificationBusy
                      ? null
                      : () => unawaited(
                          _showNotificationSheet(
                            context,
                            chat,
                            siteUrl,
                            channel,
                          ),
                        ),
                ),
                ListTile(
                  key: ValueKey('chat-channel-menu-settings-$channelId'),
                  leading: const DIcon(DIcons.gear),
                  title: const Text('Channel settings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _applyChannelAction(
                      context,
                      chat,
                      siteUrl,
                      channel,
                      _ChannelAction.settings,
                    );
                  },
                ),
                ListTile(
                  key: ValueKey('chat-channel-menu-star-$channelId'),
                  leading: DIcon(
                    channel.membership.starred ? DIcons.star : DIcons.farStar,
                  ),
                  enabled: !starBusy,
                  title: Text(
                    channel.membership.starred
                        ? 'Remove from starred channels'
                        : 'Add to starred channels',
                  ),
                  onTap: starBusy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _applyChannelAction(
                            context,
                            chat,
                            siteUrl,
                            channel,
                            _ChannelAction.star,
                          );
                        },
                ),
                ListTile(
                  key: ValueKey('chat-channel-menu-leave-$channelId'),
                  leading: DIcon(
                    DIcons.xmark,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  enabled: !followBusy,
                  textColor: Theme.of(context).colorScheme.error,
                  title: Text(
                    channel.isDirectMessage ? 'Close channel' : 'Leave channel',
                  ),
                  onTap: followBusy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _applyChannelAction(
                            context,
                            chat,
                            siteUrl,
                            channel,
                            _ChannelAction.leave,
                          );
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

Future<void> _showNotificationSheet(
  BuildContext context,
  ChatController chat,
  String siteUrl,
  ChatChannel channel,
) async {
  final selected = await showShellSheet<_NotificationAction>(
    context: context,
    title: 'Notifications',
    nested: true,
    padding: const EdgeInsets.all(6),
    builder: (context) => _NotificationActionsSheet(channel: channel),
  );
  if (selected == null || !context.mounted) return;
  Navigator.of(context).pop();
  await _applyNotificationAction(context, chat, siteUrl, channel, selected);
}

class _NotificationActionsSheet extends StatelessWidget {
  const _NotificationActionsSheet({required this.channel});

  final ChatChannel channel;

  @override
  Widget build(BuildContext context) {
    final membership = channel.membership;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in const [
          _NotificationAction.never,
          _NotificationAction.mention,
          _NotificationAction.always,
        ])
          ListTile(
            key: ValueKey(
              'chat-channel-notification-${channel.id}-${action.name}',
            ),
            trailing: _notificationSelected(membership, action)
                ? const DIcon(DIcons.check, size: 16)
                : null,
            title: Text(_notificationLabel(action)),
            onTap: () => Navigator.of(context).pop(action),
          ),
        const Divider(height: 1),
        ListTile(
          key: ValueKey('chat-channel-mute-${channel.id}'),
          leading: DIcon(
            membership.muted ? DIcons.discourseBellSlash : DIcons.bell,
          ),
          trailing: membership.muted
              ? const DIcon(DIcons.check, size: 16)
              : null,
          title: Text(membership.muted ? 'Unmute channel' : 'Mute channel'),
          onTap: () => Navigator.of(context).pop(_NotificationAction.mute),
        ),
      ],
    );
  }
}

bool _notificationSelected(
  ChatMembership membership,
  _NotificationAction action,
) {
  if (membership.muted) return false;
  return membership.notificationLevel ==
      switch (action) {
        _NotificationAction.never => ChatChannelNotificationLevel.never,
        _NotificationAction.mention => ChatChannelNotificationLevel.mention,
        _NotificationAction.always => ChatChannelNotificationLevel.always,
        _NotificationAction.mute => null,
      };
}

String _notificationLabel(_NotificationAction action) => switch (action) {
  _NotificationAction.never => 'Never',
  _NotificationAction.mention => 'Mentions only',
  _NotificationAction.always => 'All activity',
  _NotificationAction.mute => 'Mute channel',
};

void _applyChannelAction(
  BuildContext context,
  ChatController chat,
  String siteUrl,
  ChatChannel channel,
  _ChannelAction action,
) {
  switch (action) {
    case _ChannelAction.settings:
      PluginUiScope.require(
        context,
        chatShellService,
      ).openChannelInfo(siteUrl: siteUrl, channelId: channel.id);
      return;
    case _ChannelAction.star:
      unawaited(_toggleStarred(context, chat, siteUrl, channel));
      return;
    case _ChannelAction.leave:
      unawaited(_leaveChannel(context, chat, siteUrl, channel));
      return;
  }
}

Future<void> _toggleStarred(
  BuildContext context,
  ChatController chat,
  String siteUrl,
  ChatChannel channel,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await chat.updateChannelStarred(
    siteUrl,
    channel.id,
    !channel.membership.starred,
  );
  if (error != null) messenger?.showSnackBar(SnackBar(content: Text(error)));
}

Future<void> _leaveChannel(
  BuildContext context,
  ChatController chat,
  String siteUrl,
  ChatChannel channel,
) async {
  final shell = PluginUiScope.require(context, chatShellService);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await chat.updateChannelFollowing(siteUrl, channel, false);
  if (error != null) {
    messenger?.showSnackBar(SnackBar(content: Text(error)));
    return;
  }

  final remaining = [
    ...chat.publicChannels(siteUrl),
    ...chat.directChannels(siteUrl),
  ];
  if (remaining.isNotEmpty) {
    shell.openChannel(remaining.first.id);
  } else {
    shell.openBrowseChannels();
  }
}

Future<void> _applyNotificationAction(
  BuildContext context,
  ChatController chat,
  String siteUrl,
  ChatChannel channel,
  _NotificationAction action,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = switch (action) {
    _NotificationAction.mute => await chat.updateChannelNotifications(
      siteUrl,
      channel.id,
      muted: !channel.membership.muted,
    ),
    _ => await chat.updateChannelNotifications(
      siteUrl,
      channel.id,
      notificationLevel: switch (action) {
        _NotificationAction.never => ChatChannelNotificationLevel.never,
        _NotificationAction.mention => ChatChannelNotificationLevel.mention,
        _NotificationAction.always => ChatChannelNotificationLevel.always,
        _NotificationAction.mute => null,
      },
    ),
  };
  if (error != null) messenger?.showSnackBar(SnackBar(content: Text(error)));
}
