import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_inbox.dart';
import 'chat_inbox_filters.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

int _unreadCount(ChatChannel channel) =>
    math.max(channel.tracking.unreadCount, channel.tracking.mentionCount) +
    channel.tracking.watchedThreadsUnreadCount;

/// An account-owned glance at the live conversation directory.
class ChatHeaderMenu extends StatefulWidget {
  const ChatHeaderMenu({
    super.key,
    required this.siteUrl,
    required this.onDismiss,
  });
  final String siteUrl;
  final VoidCallback onDismiss;

  @override
  State<ChatHeaderMenu> createState() => _ChatHeaderMenuState();
}

class _ChatHeaderMenuState extends State<ChatHeaderMenu> {
  ChatInboxKind _kind = ChatInboxKind.all;
  ChatController? _chat;
  PluginSiteLease? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = PluginUiScope.require(context, chatControllerService);
    if (identical(chat, _chat)) return;
    _chat = chat;
    _owner = chat.captureAccount(widget.siteUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _owner!.isCurrent) {
        unawaited(chat.loadChannels(widget.siteUrl));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat!;
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        if (!_owner!.isCurrent) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onDismiss();
          });
          return const SizedBox.shrink();
        }
        final all = chatInboxConversations(
          chat,
          widget.siteUrl,
          const ChatInboxFilter(),
        );
        final channels =
            all
                .where(
                  (c) => switch (_kind) {
                    ChatInboxKind.directMessages => c.isDirectMessage,
                    ChatInboxKind.channels => !c.isDirectMessage,
                    _ => true,
                  },
                )
                .toList()
              ..sort((a, b) {
                final unread =
                    (b.badge.isVisible ? 1 : 0) - (a.badge.isVisible ? 1 : 0);
                return unread != 0
                    ? unread
                    : all.indexOf(a).compareTo(all.indexOf(b));
              });
        int count(ChatInboxKind kind) => all
            .where(
              (c) => switch (kind) {
                ChatInboxKind.directMessages => c.isDirectMessage,
                ChatInboxKind.channels => !c.isDirectMessage,
                _ => true,
              },
            )
            .fold(0, (sum, c) => sum + _unreadCount(c));
        return DesktopHeaderMenu<ChatInboxKind>(
          title: context.l10n.chat,
          action: context.l10n.openChatMenu,
          onAction: () {
            if (!_owner!.isCurrent) return;
            widget.onDismiss();
            unawaited(shell.openHeaderShortcut(mobile: false));
          },
          filters: [
            DesktopHeaderMenuFilter(
              ChatInboxKind.all,
              context.l10n.all,
              unread: count(ChatInboxKind.all),
            ),
            DesktopHeaderMenuFilter(
              ChatInboxKind.channels,
              context.l10n.channels,
              unread: count(ChatInboxKind.channels),
            ),
            DesktopHeaderMenuFilter(
              ChatInboxKind.directMessages,
              context.l10n.directMessages,
              unread: count(ChatInboxKind.directMessages),
            ),
          ],
          value: _kind,
          onChanged: (kind) => setState(() => _kind = kind),
          child: chat.channelsLoading(widget.siteUrl) && all.isEmpty
              ? const Center(child: DSpinner())
              : chat.channelsError(widget.siteUrl) != null && all.isEmpty
              ? ChatInboxError(
                  onRetry: () =>
                      unawaited(chat.loadChannels(widget.siteUrl, force: true)),
                )
              : channels.isEmpty
              ? Center(
                  child: Text(
                    chatInboxEmptyMessage(ChatInboxFilter(kind: _kind)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(6),
                  children: [
                    for (final c in channels)
                      DesktopHeaderMenuRow(
                        key: ValueKey('chat-header-channel-${c.id}'),
                        title: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        description: SiteEmojiText.plain(
                          '${!c.isDirectMessage && c.lastMessageUsername != null ? '${c.lastMessageUsername}: ' : ''}${c.lastMessagePreview ?? ''}',
                          siteUrl: widget.siteUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        leading: ChatConversationAvatar(
                          siteUrl: widget.siteUrl,
                          channel: c,
                          size: 32,
                        ),
                        time: chatInboxActivityAt(c) == null
                            ? null
                            : relativeTime(chatInboxActivityAt(c)!),
                        unread: c.badge.isVisible,
                        count: _unreadCount(c),
                        semanticLabel: c.badge.isVisible
                            ? '${c.title}, ${context.l10n.unreadConversation}'
                            : c.title,
                        onPressed: () {
                          if (!_owner!.isCurrent) return;
                          widget.onDismiss();
                          shell.openChannel(c.id);
                        },
                      ),
                  ],
                ),
        );
      },
    );
  }
}
