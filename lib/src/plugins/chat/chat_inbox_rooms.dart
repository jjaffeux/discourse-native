import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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

/// Optional capability; the Voice plugin owns permissions and the form.
abstract interface class ChatInboxRoomCreator {
  Future<void> Function(BuildContext context)? createRoom(String siteUrl);
}

final class ChatInboxRoom {
  const ChatInboxRoom({
    required this.id,
    required this.name,
    required this.people,
    required this.open,
    this.loading = false,
  });
  final int id;
  final String name;
  final int people;
  final Future<void> Function(BuildContext context) open;
  final bool loading;

  (int, String, int, bool) get _drawn => (id, name, people, loading);
}

final class ChatInboxRooms extends FrameSafeNotifier {
  ChatInboxRooms(this.filters);
  final ChatInboxFilters filters;
  ChatInboxRoomProvider? _provider;

  bool available(String siteUrl) => _provider?.available(siteUrl) ?? false;

  Future<void> Function(BuildContext context)? createRoom(String siteUrl) =>
      switch (_provider) {
        final ChatInboxRoomCreator creator => creator.createRoom(siteUrl),
        _ => null,
      };

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

  List<ChatInboxRoom> sidebarRooms(String siteUrl) => [
    for (final room in rooms(siteUrl))
      if (chatInboxWordsMatch(filters.sidebarQueryFor(siteUrl), [room.name]))
        room,
  ];

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

class ChatInboxRoomRow extends StatefulWidget {
  const ChatInboxRoomRow({super.key, required this.room, this.compact = false});
  final ChatInboxRoom room;
  final bool compact;

  @override
  State<ChatInboxRoomRow> createState() => _ChatInboxRoomRowState();
}

class _ChatInboxRoomRowState extends State<ChatInboxRoomRow> {
  Widget? _content;

  @override
  void didUpdateWidget(ChatInboxRoomRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact ||
        oldWidget.room._drawn != widget.room._drawn) {
      _content = null;
    }
  }

  // A join anywhere republishes every room, so each row receives a new
  // snapshot. Keep the mounted content unless this row's own words changed;
  // the tap handler reads the latest snapshot's `open` either way.
  @override
  Widget build(BuildContext context) =>
      _content ??= LayoutBuilder(builder: _buildRow);

  Widget _buildRow(BuildContext context, BoxConstraints constraints) {
    final room = widget.room;
    final compact = widget.compact;
    final active = room.people > 0;
    final tokens = DTokens.of(context);
    final color = active
        ? Theme.of(context).discourse.success
        : tokens.mutedForeground;
    return DItem(
      key: ValueKey('chat-inbox-room-${room.id}'),
      size: compact ? DItemSize.sm : DItemSize.standard,
      shape: compact ? DItemShape.menu : DItemShape.fullWidth,
      selectionStyle: compact
          ? DItemSelectionStyle.sidebar
          : DItemSelectionStyle.tinted,
      padding: !compact && constraints.maxWidth < 600
          ? const EdgeInsets.symmetric(vertical: DSpacing.md)
          : null,
      onPressed: () => unawaited(widget.room.open(context)),
      enabled: !room.loading,
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
            DItemDescription(
              child: Text(
                active
                    ? context.l10n.voiceRoomPeopleHere(room.people)
                    : context.l10n.voiceRoomEmpty,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? tokens.foreground : tokens.mutedForeground,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
        if (room.loading) const DSpinner(),
      ],
    );
  }
}
