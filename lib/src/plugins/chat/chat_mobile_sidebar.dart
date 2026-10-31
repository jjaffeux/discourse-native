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
class ChatMobileSidebar extends StatefulWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatMobileSidebar> createState() => _ChatMobileSidebarState();
}

class _ChatMobileSidebarState extends State<ChatMobileSidebar> {
  final _expanded = <ChatInboxSectionKind>{};
  bool _roomsExpanded = false;
  String get siteUrl => widget.siteUrl;

  @override
  void didUpdateWidget(ChatMobileSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) {
      _expanded.clear();
      _roomsExpanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    final filters = chat.inboxFilters;
    final roomService = PluginUiScope.optional(context, chatInboxRoomsService);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, filters, roomService, shell]),
      builder: (context, _) {
        final filter = filters.filterFor(siteUrl);
        final channels = chatInboxConversations(chat, siteUrl, filter);
        final rooms = roomService?.rooms(siteUrl) ?? const <ChatInboxRoom>[];
        final error = chat.channelsError(siteUrl);
        final loading =
            !chat.channelsLoaded(siteUrl) &&
            (chat.channelsLoading(siteUrl) || error == null);
        final colors = DTokens.of(context);
        Widget row(ChatChannel channel) => ValueListenableBuilder<ChatChannel?>(
          key: ValueKey(channel.id),
          valueListenable: chat.channelRef(siteUrl, channel.id),
          builder: (context, current, _) => ChatInboxRow(
            siteUrl: siteUrl,
            channel: current ?? channel,
            selected: shell.visibleChannelId == channel.id,
            onPressed: () => shell.openChannel(channel.id),
          ),
        );
        // Rows are ruled within their own section; the rooms heading stands
        // between the two sections without a rule on either side.
        final createRoom = roomService?.createRoom(siteUrl);
        final sections = chatInboxSections(channels, filter.sort);
        final alone = sections.length + (rooms.isEmpty ? 0 : 1) == 1;
        final roomSlice = ChatInboxSectionSlice(
          rooms,
          expanded: _roomsExpanded,
          alone: alone,
        );
        List<Widget> sectionRows(ChatInboxSection section) {
          final expanded = _expanded.contains(section.kind);
          final slice = ChatInboxSectionSlice(
            section.channels,
            expanded: expanded,
            alone: alone,
            keep: (channel) => channel.id == shell.visibleChannelId,
          );
          return [
            ChatInboxSectionHeading(kind: section.kind),
            for (final (index, channel) in slice.visible.indexed) ...[
              if (index > 0) DSeparator(color: colors.border),
              row(channel),
            ],
            if (slice.canFold)
              ChatInboxMore(
                key: ValueKey(('chat-more', section.kind)),
                hidden: slice.hidden,
                expanded: expanded,
                onPressed: () => setState(() {
                  if (!_expanded.add(section.kind)) {
                    _expanded.remove(section.kind);
                  }
                }),
              ),
          ];
        }

        final entries = <Widget>[
          ChatInboxNavigation(
            key: ValueKey(('chat-navigation', siteUrl)),
            siteUrl: siteUrl,
          ),
          for (final section in sections) ...sectionRows(section),
          if (rooms.isNotEmpty || createRoom != null)
            const _VoiceRoomsHeading(),
          for (final (index, room) in roomSlice.visible.indexed) ...[
            if (index > 0) DSeparator(color: colors.border),
            ChatInboxRoomRow(room: room),
          ],
          if (roomSlice.canFold)
            ChatInboxMore(
              key: const ValueKey('chat-more-voice-rooms'),
              hidden: roomSlice.hidden,
              expanded: _roomsExpanded,
              onPressed: () => setState(() => _roomsExpanded = !_roomsExpanded),
            ),
          if (createRoom != null)
            DButton(
              variant: DButtonVariant.ghost,
              icon: const DIcon(DIcons.plus),
              label: Text(context.l10n.newVoiceRoom),
              onPressed: () => unawaited(createRoom(context)),
            ),
          if (!loading && channels.isEmpty && rooms.isEmpty)
            error != null
                ? ChatInboxError(
                    onRetry: () =>
                        unawaited(chat.loadChannels(siteUrl, force: true)),
                  )
                : Padding(
                    padding: const EdgeInsets.all(DSpacing.lg),
                    child: Text(
                      chatInboxEmptyMessage(filter),
                      textAlign: TextAlign.center,
                    ),
                  ),
        ];
        return DPageSurface.headed(
          title: Text(
            context.l10n.chats,
            key: const ValueKey('chat-inbox-title'),
          ),
          controls: ContentReadingLaneBox(
            padding: EdgeInsets.zero,
            child: ChatInboxFilterBar(siteUrl: siteUrl, filters: filters),
          ),
          adaptiveBodyBuilder: (context, lazy) => ContentReadingLane(
            basePadding: const EdgeInsets.symmetric(horizontal: 16),
            builder: (context, lane) {
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
                      onRefresh: loading || chat.channelsLoading(siteUrl)
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
