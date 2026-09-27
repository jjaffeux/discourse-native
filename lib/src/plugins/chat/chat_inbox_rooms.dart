import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_inbox_filters.dart';

const chatInboxRoomsService = PluginServiceKey<ChatInboxRooms>(
  owner: PluginId('chat'),
  name: 'inbox-rooms',
);

/// Voice supplies room data and actions without making Chat depend on Voice.
abstract interface class ChatInboxRoomProvider implements Listenable {
  bool available(String siteUrl);
  List<ChatInboxRoom> rooms(String siteUrl);
}

final class ChatInboxRoom {
  const ChatInboxRoom({
    required this.id,
    required this.name,
    required this.people,
    required this.open,
  });
  final int id;
  final String name;
  final int people;
  final Future<void> Function(BuildContext context) open;
}

final class ChatInboxRooms extends FrameSafeNotifier {
  ChatInboxRooms(this.filters);
  final ChatInboxFilters filters;
  ChatInboxRoomProvider? _provider;

  bool available(String siteUrl) => _provider?.available(siteUrl) ?? false;

  bool includesRooms(String siteUrl) =>
      switch (filters.filterFor(siteUrl).kind) {
        ChatInboxKind.all || ChatInboxKind.voiceRooms => true,
        _ => false,
      };

  List<ChatInboxRoom> rooms(String siteUrl) {
    final filter = filters.filterFor(siteUrl);
    if (!includesRooms(siteUrl)) {
      return const [];
    }
    return [
      for (final room in _provider?.rooms(siteUrl) ?? <ChatInboxRoom>[])
        if (!filter.unreadOnly || room.people > 0) room,
    ];
  }

  VoidCallback attach(ChatInboxRoomProvider provider) {
    _provider?.removeListener(notifySafely);
    _provider = provider..addListener(notifySafely);
    notifySafely();
    return () {
      if (!identical(_provider, provider)) return;
      provider.removeListener(notifySafely);
      _provider = null;
      notifySafely();
    };
  }

  @override
  void dispose() {
    _provider?.removeListener(notifySafely);
    super.dispose();
  }
}

class ChatInboxRoomRow extends StatelessWidget {
  const ChatInboxRoomRow({super.key, required this.room, this.compact = false});
  final ChatInboxRoom room;
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildRow);

  Widget _buildRow(BuildContext context, BoxConstraints constraints) {
    final active = room.people > 0;
    final color = active
        ? Theme.of(context).discourse.success
        : DTokens.of(context).mutedForeground;
    return DItem(
      key: ValueKey('chat-inbox-room-${room.id}'),
      size: compact ? DItemSize.sm : DItemSize.standard,
      shape: compact ? DItemShape.standard : DItemShape.fullWidth,
      padding: !compact && constraints.maxWidth < 600
          ? const EdgeInsets.symmetric(vertical: DSpacing.md)
          : null,
      onPressed: () => unawaited(room.open(context)),
      children: [
        DItemMedia(
          variant: DItemMediaVariant.avatar,
          child: DAvatar(
            dimension: compact ? 32 : 40,
            decorative: true,
            fallback: DAvatarFallback(
              child: DIcon(DIcons.microphoneLines, color: color),
            ),
          ),
        ),
        DItemContent(
          children: [
            DItemTitle(
              child: Text(
                room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
