import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_inbox_rooms.dart';
import 'chat_inbox_row.dart';

class ChatInboxRoomRow extends StatefulWidget {
  const ChatInboxRoomRow({
    super.key,
    required this.room,
    this.compact = false,
    this.frame = ChatInboxRowFrame.page,
  });
  final ChatInboxRoom room;

  /// The denser row of the sidebar's own voice section. Otherwise the room is
  /// drawn as a chat's row is, in [frame].
  final bool compact;
  final ChatInboxRowFrame frame;

  @override
  State<ChatInboxRoomRow> createState() => _ChatInboxRoomRowState();
}

class _ChatInboxRoomRowState extends State<ChatInboxRoomRow> {
  Widget? _content;

  (int, String, int, bool) _drawn(ChatInboxRoom room) =>
      (room.id, room.name, room.people, room.loading);

  @override
  void didUpdateWidget(ChatInboxRoomRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compact != widget.compact ||
        oldWidget.frame != widget.frame ||
        _drawn(oldWidget.room) != _drawn(widget.room)) {
      _content = null;
    }
  }

  // A join anywhere republishes every room, so each row receives a new
  // snapshot. Keep the mounted content unless this row's own words changed;
  // the tap handler reads the latest snapshot's `open` either way.
  @override
  Widget build(BuildContext context) => _content ??= _buildRow(context);

  Widget _buildRow(BuildContext context) {
    final room = widget.room;
    final compact = widget.compact;
    final active = room.people > 0;
    final tokens = DTokens.of(context);
    final color = active
        ? Theme.of(context).discourse.success
        : tokens.mutedForeground;
    final mark = DAvatar(
      dimension: compact ? 32 : ChatInboxRowFrame.mark,
      decorative: true,
      fallback: DAvatarFallback(
        child: DIcon(DIcons.microphoneLines, color: color),
      ),
    );
    final name = Text(
      room.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontWeight: active ? FontWeight.w700 : FontWeight.w500),
    );
    final people = Text(
      active
          ? context.l10n.voiceRoomPeopleHere(room.people)
          : context.l10n.voiceRoomEmpty,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: active ? tokens.foreground : tokens.mutedForeground,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      ),
    );
    void open() => unawaited(widget.room.open(context));
    if (!compact) {
      return ChatInboxRowSurface(
        itemKey: ValueKey('chat-inbox-room-${room.id}'),
        frame: widget.frame,
        boxed: false,
        enabled: !room.loading,
        onPressed: open,
        mark: mark,
        words: ChatInboxRowWords(
          name: name,
          line: people,
          tail: room.loading ? const DSpinner() : null,
        ),
      );
    }
    return DItem(
      key: ValueKey('chat-inbox-room-${room.id}'),
      size: DItemSize.sm,
      shape: DItemShape.menu,
      selectionStyle: DItemSelectionStyle.sidebar,
      onPressed: open,
      enabled: !room.loading,
      children: [
        DItemMedia(variant: DItemMediaVariant.avatar, child: mark),
        DItemContent(
          children: [
            DItemTitle(child: name),
            DItemDescription(child: people),
          ],
        ),
        if (room.loading) const DSpinner(),
      ],
    );
  }
}
