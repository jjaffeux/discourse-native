import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/relative_time.dart';
import '../../shell/shell_sheet.dart';
import '../../shell/site_emoji_text.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_pin.dart';

class ChatPinnedBar extends StatefulWidget {
  const ChatPinnedBar({
    super.key,
    required this.siteUrl,
    required this.channel,
    required this.chat,
    required this.onJumpToMessage,
  });

  final String siteUrl;
  final ChatChannel channel;
  final ChatController chat;
  final ValueChanged<int> onJumpToMessage;

  @override
  State<ChatPinnedBar> createState() => _ChatPinnedBarState();
}

class _ChatPinnedBarState extends State<ChatPinnedBar> {
  int? _activeMessageId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChatPinnedBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.channel.id != widget.channel.id ||
        !identical(oldWidget.chat, widget.chat)) {
      _activeMessageId = null;
      _load();
    }
  }

  void _load({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        widget.chat.loadPinnedMessages(
          widget.siteUrl,
          widget.channel.id,
          force: force,
        ),
      );
    });
  }

  List<ChatPin> _ordered(List<ChatPin> pins) =>
      [...pins]..sort((a, b) => a.messageId.compareTo(b.messageId));

  ChatPin? _current(List<ChatPin> ordered) {
    if (ordered.isEmpty) return null;
    final active = _activeMessageId;
    if (active != null) {
      for (final pin in ordered) {
        if (pin.messageId == active) return pin;
      }
    }
    return ordered.last;
  }

  void _jump(List<ChatPin> ordered, ChatPin current) {
    widget.onJumpToMessage(current.messageId);
    final index = ordered.indexOf(current);
    setState(() {
      _activeMessageId =
          ordered[index <= 0 ? ordered.length - 1 : index - 1].messageId;
    });
  }

  Future<void> _showAll(List<ChatPin> ordered) async {
    unawaited(
      widget.chat.markPinnedMessagesRead(widget.siteUrl, widget.channel.id),
    );
    await showShellSheet<void>(
      context: context,
      title: 'Pinned messages',
      padding: EdgeInsets.zero,
      builder: (sheetContext) => ListView.builder(
        shrinkWrap: true,
        itemCount: ordered.length,
        itemBuilder: (context, index) {
          final pin = ordered[ordered.length - index - 1];
          final by = pin.pinnedBy.displayName.trim();
          final when = pin.pinnedAt == null
              ? null
              : relativeTime(pin.pinnedAt!);
          final metadata = [
            if (by.isNotEmpty) 'Pinned by $by',
            ?when,
          ].join(' · ');
          return ListTile(
            key: ValueKey('chat-pin-${pin.id}'),
            minTileHeight: 56,
            leading: const DIcon(DIcons.thumbtack, size: 18),
            title: SiteEmojiText.plain(
              pin.excerpt.isEmpty ? pin.message.raw : pin.excerpt,
              siteUrl: widget.siteUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: metadata.isEmpty ? null : Text(metadata),
            onTap: () {
              Navigator.of(sheetContext).pop();
              // The sheet outlives a bar rebuilt under a new key while it is
              // open; a pin tapped then must not reach the old bar.
              if (!mounted) return;
              widget.onJumpToMessage(pin.messageId);
              setState(() => _activeMessageId = pin.messageId);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatPinsState>(
      valueListenable: widget.chat.pinsListenable(
        widget.siteUrl,
        widget.channel.id,
      ),
      builder: (context, state, _) {
        final ordered = _ordered(state.pins);
        final current = _current(ordered);
        if (current == null) {
          if (state.error != null) {
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListTile(
                minTileHeight: 48,
                leading: const DIcon(DIcons.thumbtack, size: 16),
                title: Text(state.error!),
                trailing: DButton(
                  label: const Text('Retry'),
                  onPressed: () => _load(force: true),
                  variant: DButtonVariant.link,
                ),
              ),
            );
          }
          return state.loading
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final excerpt = current.excerpt.isEmpty
            ? current.message.raw
            : current.excerpt;
        return Material(
          color: theme.colorScheme.surfaceContainerLow,
          child: InkWell(
            key: const ValueKey('chat-pinned-message-bar'),
            onTap: () => _jump(ordered, current),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 16,
                  end: 4,
                  top: 6,
                  bottom: 6,
                ),
                child: Row(
                  children: [
                    DIcon(
                      DIcons.thumbtack,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Pinned message',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SiteEmojiText.plain(
                            excerpt,
                            siteUrl: widget.siteUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.discourse.primaryHigh,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (ordered.length > 1)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          IconButton(
                            tooltip: 'Pinned messages',
                            onPressed: () => unawaited(_showAll(ordered)),
                            icon: const DIcon(DIcons.list, size: 16),
                          ),
                          if (widget.channel.membership.hasUnseenPins)
                            PositionedDirectional(
                              top: 8,
                              end: 8,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
