import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_channel.dart';
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
        // Rows are ruled within their own section; the rooms heading stands
        // between the two sections without a rule on either side.
        final entries = <Widget>[
          for (final (index, channel) in channels.indexed) ...[
            if (index > 0) DSeparator(color: colors.border),
            row(channel),
          ],
          if (rooms.isNotEmpty && channels.isNotEmpty)
            const _VoiceRoomsHeading(),
          for (final (index, room) in rooms.indexed) ...[
            if (index > 0) DSeparator(color: colors.border),
            ChatInboxRoomRow(room: room),
          ],
        ];
        return DPageSurface.headed(
          title: Text(
            context.l10n.chats,
            key: const ValueKey('chat-inbox-title'),
          ),
          controls: ContentReadingLaneBox(
            padding: EdgeInsets.zero,
            child: ChatInboxFilterBar(
              siteUrl: siteUrl,
              filters: filters,
              leading: ChatBrowseNavigation(
                siteUrl: siteUrl,
                page: ChatBrowsePage.chats,
              ),
            ),
          ),
          adaptiveBodyBuilder: (context, lazy) => ContentReadingLane(
            basePadding: const EdgeInsets.symmetric(horizontal: 16),
            builder: (context, lane) {
              final empty = error != null
                  ? ChatInboxError(
                      onRetry: () =>
                          unawaited(chat.loadChannels(siteUrl, force: true)),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DSpacing.lg),
                        child: Text(
                          chatInboxEmptyMessage(filter),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
              final content = loading
                  ? ChatBrowseSkeleton(
                      page: ChatBrowsePage.chats,
                      scrollable: lazy,
                      padding: lane.padding.add(
                        EdgeInsets.only(
                          bottom: DScrollChrome.bottomInsetOf(context),
                        ),
                      ),
                    )
                  : channels.isEmpty && rooms.isEmpty
                  ? lazy
                        ? CustomScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            slivers: [
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: empty,
                              ),
                            ],
                          )
                        : empty
                  : lazy
                  ? ListView.builder(
                      key: PageStorageKey((
                        'mobile-chat-list',
                        siteUrl,
                        filter,
                      )),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: lane.padding.add(
                        EdgeInsets.only(
                          bottom: DScrollChrome.bottomInsetOf(context),
                        ),
                      ),
                      itemCount: entries.length,
                      itemBuilder: (context, index) => entries[index],
                    )
                  : Padding(
                      padding: lane.padding.add(
                        EdgeInsets.only(
                          bottom: DScrollChrome.bottomInsetOf(context),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: entries,
                      ),
                    );
              return lazy
                  ? DPullToRefresh(
                      key: ValueKey((siteUrl, filter)),
                      onRefresh: loading
                          ? null
                          : () => chat.loadChannels(siteUrl, force: true),
                      child: content,
                    )
                  : content;
            },
          ),
        );
      },
    );
  }
}

/// Starts at the rows' content edge, which is the lane edge below the width
/// where full-width rows add their own inset.
class _VoiceRoomsHeading extends StatelessWidget {
  const _VoiceRoomsHeading();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = constraints.maxWidth < 600 ? 0.0 : DSpacing.lg;
      return Padding(
        key: const ValueKey('chat-inbox-voice-rooms-heading'),
        padding: EdgeInsetsDirectional.fromSTEB(inset, 18, inset, 2),
        child: Text(
          context.l10n.voiceRooms,
          style: TextStyle(
            fontSize: DiscourseTypography.xs,
            fontWeight: FontWeight.w600,
            color: DTokens.of(context).mutedForeground,
          ),
        ),
      );
    },
  );
}
