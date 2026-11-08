import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_inbox.dart';
import 'chat_inbox_filters.dart';
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

/// Everything the inbox draws from the chat, filter, shell and room sources.
///
/// The chat controller notifies for every message in every followed channel,
/// for tracking echoes and for read credits. The list is laid out again only
/// when one of these changes; each row follows its own channel and selection.
@immutable
final class _ChatMobileInboxLayout {
  const _ChatMobileInboxLayout({
    required this.filter,
    required this.channelIds,
    required this.starredIds,
    required this.rooms,
    required this.canCreateRoom,
    required this.loading,
    required this.refreshing,
    required this.failed,
    required this.visibleChannelId,
  });

  final ChatInboxFilter filter;
  final List<int> channelIds;
  final List<int> starredIds;
  final List<({int id, String name, int people, bool loading})> rooms;
  final bool canCreateRoom;
  final bool loading;
  final bool refreshing;
  final bool failed;
  final int? visibleChannelId;

  @override
  bool operator ==(Object other) =>
      other is _ChatMobileInboxLayout &&
      filter == other.filter &&
      canCreateRoom == other.canCreateRoom &&
      loading == other.loading &&
      refreshing == other.refreshing &&
      failed == other.failed &&
      visibleChannelId == other.visibleChannelId &&
      listEquals(channelIds, other.channelIds) &&
      listEquals(starredIds, other.starredIds) &&
      listEquals(rooms, other.rooms);

  @override
  int get hashCode => Object.hash(
    filter,
    canCreateRoom,
    loading,
    refreshing,
    failed,
    visibleChannelId,
    Object.hashAll(channelIds),
    Object.hashAll(starredIds),
    Object.hashAll(rooms),
  );
}

class _ChatMobileSidebarState extends State<ChatMobileSidebar> {
  final _expanded = <ChatInboxSectionKind>{};
  bool _roomsExpanded = false;
  ChatController? _chat;
  ChatInboxRooms? _rooms;
  ChatShellService? _shell;
  Listenable? _sources;
  late _ChatMobileInboxLayout _layout;
  String get siteUrl => widget.siteUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = PluginUiScope.require(context, chatControllerService);
    final rooms = PluginUiScope.optional(context, chatInboxRoomsService);
    final shell = PluginUiScope.require(context, chatShellService);
    if (!identical(chat, _chat) ||
        !identical(rooms, _rooms) ||
        !identical(shell, _shell)) {
      _sources?.removeListener(_changed);
      _rooms?.removeListener(_roomsChanged);
      _chat = chat;
      _rooms = rooms?..addListener(_roomsChanged);
      _shell = shell;
      _sources = Listenable.merge([chat, chat.inboxFilters, shell])
        ..addListener(_changed);
    }
    _layout = _read();
  }

  @override
  void didUpdateWidget(ChatMobileSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) {
      _expanded.clear();
      _roomsExpanded = false;
      _layout = _read();
    }
  }

  _ChatMobileInboxLayout _read() {
    final chat = _chat!;
    final filter = chat.inboxFilters.filterFor(siteUrl);
    final channels = chatInboxConversations(chat, siteUrl, filter);
    final error = chat.channelsError(siteUrl);
    final refreshing = chat.channelsLoading(siteUrl);
    return _ChatMobileInboxLayout(
      filter: filter,
      channelIds: [for (final channel in channels) channel.id],
      starredIds: [
        for (final channel in channels)
          if (channel.membership.starred) channel.id,
      ],
      rooms: [
        for (final room in _rooms?.rooms(siteUrl) ?? const <ChatInboxRoom>[])
          (
            id: room.id,
            name: room.name,
            people: room.people,
            loading: room.loading,
          ),
      ],
      canCreateRoom: _rooms?.createRoom(siteUrl) != null,
      loading: !chat.channelsLoaded(siteUrl) && (refreshing || error == null),
      refreshing: refreshing,
      failed: error != null,
      visibleChannelId: _shell?.visibleChannelId,
    );
  }

  void _changed() {
    final layout = _read();
    if (layout == _layout) return;
    setState(() => _layout = layout);
  }

  // A room row holds its provider's `open`, a closure over that room's latest
  // snapshot, so each provider notification has to reach the row even when
  // nothing drawn differs. Providers do not notify for chat traffic.
  void _roomsChanged() => setState(() => _layout = _read());

  @override
  void dispose() {
    _sources?.removeListener(_changed);
    _rooms?.removeListener(_roomsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat!;
    final layout = _layout;
    final filter = layout.filter;
    final channels = [
      for (final id in layout.channelIds) ?chat.channel(siteUrl, id),
    ];
    final rooms = _rooms?.rooms(siteUrl) ?? const <ChatInboxRoom>[];
    final loading = layout.loading;
    final colors = DTokens.of(context);
    Widget row(ChatChannel channel) => ChatInboxEntry(
      key: ValueKey(channel.id),
      siteUrl: siteUrl,
      channelId: channel.id,
      compact: false,
    );
    // Rows are ruled within their own section; the rooms heading stands
    // between the two sections without a rule on either side.
    final createRoom = _rooms?.createRoom(siteUrl);
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
        keep: (channel) => channel.id == layout.visibleChannelId,
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
      for (final section in sections) ...sectionRows(section),
      if (rooms.isNotEmpty || createRoom != null) const _VoiceRoomsHeading(),
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
          variant: DButtonVariant.outline,
          icon: const DIcon(DIcons.plus),
          label: Text(context.l10n.newVoiceRoom),
          onPressed: () => unawaited(createRoom(context)),
        ),
      if (!loading && channels.isEmpty && rooms.isEmpty)
        layout.failed
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
      title: Text(context.l10n.chats, key: const ValueKey('chat-inbox-title')),
      controls: ContentReadingLaneBox(
        padding: EdgeInsets.zero,
        child: ChatInboxFilterBar(siteUrl: siteUrl, filters: chat.inboxFilters),
      ),
      secondaryControls: ContentReadingLaneBox(
        padding: EdgeInsets.zero,
        child: ChatInboxNavigation(
          key: ValueKey(('chat-navigation', siteUrl)),
          siteUrl: siteUrl,
        ),
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
                  key: PageStorageKey(('mobile-chat-list', siteUrl, filter)),
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
                  onRefresh: loading || layout.refreshing
                      ? null
                      : () => chat.loadChannels(siteUrl, force: true),
                  child: content,
                )
              : content;
        },
      ),
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
