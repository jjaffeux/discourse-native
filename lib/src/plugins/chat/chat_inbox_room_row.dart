import 'dart:async';

import 'package:discourse_native/discourse_plugin_contracts.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_inbox_rooms.dart';

class ChatInboxRoomRow extends StatefulWidget {
  const ChatInboxRoomRow({super.key, required this.room, this.compact = false});
  final ChatInboxRoom room;
  final bool compact;

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
        _drawn(oldWidget.room) != _drawn(widget.room)) {
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
