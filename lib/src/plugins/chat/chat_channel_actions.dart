import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

enum _ChannelAction { settings, star, leave }

enum _NotificationAction { never, mention, always, mute }

class ChatChannelMenu extends StatelessWidget {
  const ChatChannelMenu({
    super.key,
    required this.siteUrl,
    required this.channelId,
    this.child,
    this.channel,
  });

  final String siteUrl;
  final int channelId;

  /// A directory row can provide a channel not yet held by the inbox.
  final ChatChannel? channel;

  /// The row receiving context gestures; omitted for a visible menu button.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, current, _) {
        final channel = current ?? this.channel;
        if (channel == null || !channel.membership.following) {
          return child ?? const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) => _ChannelMenu(
            siteUrl: siteUrl,
            channel: channel,
            chat: chat,
            child: child,
          ),
        );
      },
    );
  }
}

class _ChannelMenu extends StatelessWidget {
  const _ChannelMenu({
    required this.siteUrl,
    required this.channel,
    required this.chat,
    this.child,
  });

  final String siteUrl;
  final ChatChannel channel;
  final ChatController chat;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final notificationBusy = chat.channelNotificationWriteInFlight(
      siteUrl,
      channel.id,
    );
    final starBusy = chat.channelStarWriteInFlight(siteUrl, channel.id);
    final followBusy = chat.channelFollowWriteInFlight(siteUrl, channel.id);
    final membership = channel.membership;
    final items = <Widget>[
      DDropdownMenuSub(
        key: ValueKey('chat-channel-notifications-${channel.id}'),
        leading: const DIcon(DIcons.bell, size: 16),
        width: 220,
        trigger: const Text('Notifications'),
        children: [
          for (final action in const [
            _NotificationAction.never,
            _NotificationAction.mention,
            _NotificationAction.always,
          ])
            DDropdownMenuItem(
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
              trailing: _notificationSelected(membership, action)
                  ? const DIcon(DIcons.check, size: 14)
                  : null,
              child: Text(_notificationLabel(action)),
            ),
          const DDropdownMenuSeparator(),
          DDropdownMenuItem(
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
            leading: DIcon(
              membership.muted ? DIcons.discourseBellSlash : DIcons.bell,
              size: 16,
            ),
            trailing: membership.muted
                ? const DIcon(DIcons.check, size: 14)
                : null,
            child: Text(membership.muted ? 'Unmute channel' : 'Mute channel'),
          ),
        ],
      ),
      DDropdownMenuItem(
        key: ValueKey('chat-channel-menu-settings-${channel.id}'),
        onPressed: () => _applyChannelAction(
          context,
          chat,
          siteUrl,
          channel,
          _ChannelAction.settings,
        ),
        leading: const DIcon(DIcons.gear, size: 16),
        child: const Text('Channel settings'),
      ),
      DDropdownMenuItem(
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
        leading: DIcon(
          membership.starred ? DIcons.star : DIcons.farStar,
          size: 16,
        ),
        child: Text(
          membership.starred
              ? 'Remove from starred channels'
              : 'Add to starred channels',
        ),
      ),
      DDropdownMenuItem(
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
        leading: const DIcon(DIcons.xmark, size: 16),
        variant: DDropdownMenuItemVariant.destructive,
        child: Text(
          channel.isDirectMessage ? 'Close channel' : 'Leave channel',
        ),
      ),
    ];
    const constraints = BoxConstraints(
      minWidth: 240,
      maxWidth: 380,
      maxHeight: 440,
    );
    if (child case final row?) {
      return DContextMenu(
        content: DContextMenuContent(
          semanticLabel: '${channel.title} menu',
          width: 280,
          constraints: constraints,
          children: items,
        ),
        child: DContextMenuTrigger(focusable: false, child: row),
      );
    }
    return DDropdownMenu(
      content: DDropdownMenuContent(
        width: 280,
        constraints: constraints,
        children: items,
      ),
      child: DDropdownMenuTrigger(
        builder: (context, menu) => DButton.iconOnly(
          key: ValueKey('chat-channel-menu-button-${channel.id}'),
          tooltip: 'Open ${channel.title} menu',
          variant: DButtonVariant.ghost,
          size: DButtonSize.small,
          focusNode: menu.focusNode,
          expanded: menu.open,
          hasPopup: true,
          onPressed: menu.toggle,
          icon: const DIcon(DIcons.ellipsisVertical),
        ),
      ),
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
  final toast = DToast.maybeOf(context);
  final error = await chat.updateChannelStarred(
    siteUrl,
    channel.id,
    !channel.membership.starred,
  );
  if (error != null && toast?.isDisposed == false) {
    toast!.add(DToastOptions(description: error, type: DToastType.error));
  }
}

Future<void> _leaveChannel(
  BuildContext context,
  ChatController chat,
  String siteUrl,
  ChatChannel channel,
) async {
  final shell = PluginUiScope.require(context, chatShellService);
  final toast = DToast.maybeOf(context);
  final error = await chat.updateChannelFollowing(siteUrl, channel, false);
  if (error != null) {
    if (toast?.isDisposed == false) {
      toast!.add(DToastOptions(description: error, type: DToastType.error));
    }
    return;
  }

  if (shell.visibleChannelId != channel.id) return;
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
  final toast = DToast.maybeOf(context);
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
  if (error != null && toast?.isDisposed == false) {
    toast!.add(DToastOptions(description: error, type: DToastType.error));
  }
}
