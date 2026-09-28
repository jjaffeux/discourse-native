import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_channel.dart';
import 'chat_chrome_scroll_view.dart';
import 'chat_inbox.dart';
import 'chat_inbox_rooms.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// Mobile's combined inbox keeps its filters while visiting a conversation.
class ChatMobileSidebar extends StatelessWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    final filters = chat.inboxFilters;
    final roomService = PluginUiScope.optional(context, chatInboxRoomsService);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, filters, roomService]),
      builder: (context, _) {
        final filter = filters.filterFor(siteUrl);
        final channels = chatInboxConversations(chat, siteUrl, filter);
        final rooms = roomService?.rooms(siteUrl) ?? const <ChatInboxRoom>[];
        final error = chat.channelsError(siteUrl);
        final loading =
            chat.channelsLoading(siteUrl) ||
            (!chat.channelsLoaded(siteUrl) && error == null);
        final colors = DTokens.of(context);
        Widget row(ChatChannel channel) => ValueListenableBuilder<ChatChannel?>(
          key: ValueKey(channel.id),
          valueListenable: chat.channelRef(siteUrl, channel.id),
          builder: (context, current, _) => ChatInboxRow(
            siteUrl: siteUrl,
            channel: current ?? channel,
            onPressed: () => shell.openChannel(channel.id),
          ),
        );
        return ChatChromeScrollView(
          header: ContentReadingLaneBox(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ChatBrowseNavigation(
                  siteUrl: siteUrl,
                  page: ChatBrowsePage.chats,
                ),
                const SizedBox(height: DSpacing.md),
                ChatInboxFilterBar(siteUrl: siteUrl, filters: filters),
                const SizedBox(height: DSpacing.sm),
                DSeparator(color: colors.border),
              ],
            ),
          ),
          list: (context, lazy) => ContentReadingLane(
            basePadding: const EdgeInsets.symmetric(horizontal: 16),
            builder: (context, lane) => loading
                ? ChatBrowseSkeleton(
                    page: ChatBrowsePage.chats,
                    scrollable: lazy,
                    padding: lane.padding,
                  )
                : error != null && channels.isEmpty && rooms.isEmpty
                ? ChatInboxError(
                    onRetry: () =>
                        unawaited(chat.loadChannels(siteUrl, force: true)),
                  )
                : channels.isEmpty && rooms.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DSpacing.lg),
                      child: Text(
                        chatInboxEmptyMessage(filter),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : lazy
                ? ListView.separated(
                    key: PageStorageKey(('mobile-chat-list', siteUrl, filter)),
                    padding: lane.padding,
                    itemCount:
                        channels.length +
                        rooms.length +
                        (rooms.isNotEmpty && channels.isNotEmpty ? 1 : 0),
                    separatorBuilder: (context, _) =>
                        DSeparator(color: colors.border),
                    itemBuilder: (context, index) {
                      if (index < channels.length) return row(channels[index]);
                      final roomIndex = index - channels.length;
                      if (channels.isNotEmpty && roomIndex == 0) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(context.l10n.voiceRooms),
                        );
                      }
                      return ChatInboxRoomRow(
                        room: rooms[roomIndex - (channels.isEmpty ? 0 : 1)],
                      );
                    },
                  )
                : Padding(
                    padding: lane.padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, channel) in channels.indexed) ...[
                          if (index > 0) DSeparator(color: colors.border),
                          row(channel),
                        ],
                        if (rooms.isNotEmpty && channels.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(context.l10n.voiceRooms),
                          ),
                        for (final room in rooms) ChatInboxRoomRow(room: room),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
