import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_panel.dart';
import 'chat_controller.dart';
import 'chat_find_field.dart';
import 'chat_inbox.dart';
import 'chat_inbox_filters.dart';
import 'chat_inbox_room_row.dart';
import 'chat_inbox_rooms.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// What chat's list hands the place that shows it: its rows, top to bottom,
/// and whether it is still waiting for them.
@immutable
final class ChatListingView {
  const ChatListingView._(
    this.entries,
    this._indexes, {
    required this.loading,
    required this.refreshing,
  });

  final List<Widget> entries;

  /// Nothing has loaded yet, so the place draws its own placeholder.
  final bool loading;
  final bool refreshing;
  final Map<Key, int> _indexes;

  /// Where a mounted row now stands, so a lazy list keeps it across a reorder.
  int? indexOf(Key key) => _indexes[key];
}

/// Chat's list, the one the Chats page and chat's side both show: each
/// group's unread first and the most recent after, found by name and by what
/// was said, the way to the threads heading the channels and the way to the
/// rest of them closing them.
///
/// The chat controller notifies for every message in every followed channel,
/// for tracking echoes and for read credits. The list is laid out again only
/// when what it shows, or its order, changes; each row follows its own
/// channel and selection.
class ChatListing extends StatefulWidget {
  const ChatListing({
    super.key,
    required this.siteUrl,
    required this.place,
    required this.frame,
    required this.builder,
  });

  final String siteUrl;
  final ChatInboxPlace place;
  final ChatInboxRowFrame frame;
  final Widget Function(BuildContext context, ChatListingView view) builder;

  @override
  State<ChatListing> createState() => _ChatListingState();
}

typedef _Room = ({int id, String name, int people, bool loading});

@immutable
final class _ChatListingLayout {
  const _ChatListingLayout({
    required this.sort,
    required this.query,
    required this.order,
    required this.freshIds,
    required this.lines,
    required this.rooms,
    required this.canCreateRoom,
    required this.loading,
    required this.refreshing,
    required this.failed,
    required this.activeChannelId,
    required this.unreadThreads,
    required this.channelsWay,
    required this.threadsWay,
    required this.emptyMessage,
  });

  final ChatInboxSort sort;
  final String query;

  /// Each group's kind followed by the ids it lists, in order.
  final List<Object> order;
  final List<int> freshIds;
  final Map<int, ChatInboxFoundLine> lines;
  final List<_Room> rooms;
  final bool canCreateRoom;
  final bool loading;
  final bool refreshing;
  final bool failed;
  final int? activeChannelId;
  final int unreadThreads;
  final bool channelsWay;
  final bool threadsWay;
  final String emptyMessage;

  @override
  bool operator ==(Object other) =>
      other is _ChatListingLayout &&
      sort == other.sort &&
      query == other.query &&
      canCreateRoom == other.canCreateRoom &&
      loading == other.loading &&
      refreshing == other.refreshing &&
      failed == other.failed &&
      activeChannelId == other.activeChannelId &&
      unreadThreads == other.unreadThreads &&
      channelsWay == other.channelsWay &&
      threadsWay == other.threadsWay &&
      emptyMessage == other.emptyMessage &&
      listEquals(order, other.order) &&
      listEquals(freshIds, other.freshIds) &&
      mapEquals(lines, other.lines) &&
      listEquals(rooms, other.rooms);

  @override
  int get hashCode => Object.hash(
    sort,
    query,
    canCreateRoom,
    loading,
    refreshing,
    failed,
    activeChannelId,
    unreadThreads,
    channelsWay,
    threadsWay,
    emptyMessage,
    Object.hashAll(order),
    Object.hashAll(freshIds),
    Object.hashAll(rooms),
  );
}

class _ChatListingState extends State<ChatListing> {
  final _expanded = <ChatInboxSectionKind>{};
  bool _roomsExpanded = false;
  ChatController? _chat;
  ChatInboxRooms? _rooms;
  ChatShellService? _shell;
  Listenable? _sources;
  late _ChatListingLayout _layout;
  ChatListingView? _view;

  String get _siteUrl => widget.siteUrl;

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
    _view = null;
  }

  @override
  void didUpdateWidget(ChatListing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) {
      _expanded.clear();
      _roomsExpanded = false;
    }
    // A parent that rebuilds hands over a new builder and nothing else. The
    // rows stand as they are unless what they are laid out from changed.
    final layout = _read();
    if (layout != _layout || oldWidget.frame != widget.frame) {
      _layout = layout;
      _view = null;
    }
  }

  List<ChatInboxRoom> _listedRooms() =>
      _rooms?.roomsFor(widget.place, _siteUrl) ?? const [];

  _ChatListingLayout _read() {
    final chat = _chat!;
    final shell = _shell!;
    final filter = chat.inboxFilters.filterFor(_siteUrl);
    final query = chat.inboxFilters.queryFor(widget.place, _siteUrl).trim();
    final available = shell.chatAvailable(_siteUrl);
    final found = available
        ? chat.findConversations(_siteUrl, query)
        : (
            channels: const <ChatChannel>[],
            lines: const <int, ChatInboxFoundLine>{},
          );
    final sections = query.isNotEmpty
        ? [
            if (found.channels.isNotEmpty)
              (kind: ChatInboxSectionKind.results, channels: found.channels),
          ]
        : chatInboxSections(found.channels, filter.sort);
    final error = available ? chat.channelsError(_siteUrl) : null;
    final refreshing = available && chat.channelsLoading(_siteUrl);
    final settings = chat.siteConfigFor(_siteUrl).chatSettings;
    final ways = available && shell.isConnected(_siteUrl);
    final listed = available
        ? chat.inboxConversations(_siteUrl, filter)
        : const <ChatChannel>[];
    return _ChatListingLayout(
      sort: filter.sort,
      query: query,
      order: [
        for (final section in sections) ...[
          section.kind,
          for (final channel in section.channels) channel.id,
        ],
      ],
      freshIds: [
        for (final channel in found.channels)
          if (chatInboxIsNew(channel)) channel.id,
      ],
      lines: found.lines,
      rooms: [
        for (final room in _listedRooms())
          (
            id: room.id,
            name: room.name,
            people: room.people,
            loading: room.loading,
          ),
      ],
      canCreateRoom: _rooms?.createRoom(_siteUrl) != null,
      loading:
          available &&
          !chat.channelsLoaded(_siteUrl) &&
          (refreshing || error == null),
      refreshing: refreshing,
      failed: error != null,
      activeChannelId: shell.visibleChannelId,
      unreadThreads: settings.threadsEnabled
          ? chatInboxUnreadThreads(listed)
          : 0,
      channelsWay: ways && settings.publicChannelsEnabled,
      threadsWay: ways && settings.threadsEnabled,
      emptyMessage: chatInboxEmptyMessage(filter),
    );
  }

  void _changed() {
    final layout = _read();
    if (layout == _layout) return;
    setState(() {
      _layout = layout;
      _view = null;
    });
  }

  // A room row holds its provider's `open`, a closure over that room's latest
  // snapshot, so each provider notification has to reach the row even when
  // nothing drawn differs. Providers do not notify for chat traffic.
  void _roomsChanged() => setState(() {
    _layout = _read();
    _view = null;
  });

  @override
  void dispose() {
    _sources?.removeListener(_changed);
    _rooms?.removeListener(_roomsChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _view ??= _buildView(context));

  void _toggle(ChatInboxSectionKind kind) => setState(() {
    if (!_expanded.add(kind)) _expanded.remove(kind);
    _view = null;
  });

  void _browse(String words) => unawaited(
    showChatChannelBrowser(context, siteUrl: _siteUrl, words: words),
  );

  ChatListingView _buildView(BuildContext context) {
    final chat = _chat!;
    final layout = _layout;
    final frame = widget.frame;
    final l10n = context.l10n;
    final rule = Padding(
      padding: EdgeInsets.symmetric(horizontal: frame.edge),
      child: DSeparator(color: DTokens.of(context).border),
    );
    final sections = <ChatInboxSection>[];
    for (final entry in layout.order) {
      if (entry is ChatInboxSectionKind) {
        sections.add((kind: entry, channels: <ChatChannel>[]));
      } else if (chat.channel(_siteUrl, entry as int) case final channel?) {
        sections.last.channels.add(channel);
      }
    }
    final finding = layout.query.isNotEmpty;
    // The channels, or the one list: what heads it is the way to their
    // threads and what closes it the way to the channels you are not in. It
    // is listed even with nothing in it, so the ways never go missing.
    final waysKind = layout.sort == ChatInboxSort.newest
        ? ChatInboxSectionKind.allChats
        : ChatInboxSectionKind.channels;
    final hasWays = !finding && (layout.channelsWay || layout.threadsWay);
    if (hasWays && !sections.any((section) => section.kind == waysKind)) {
      sections.add((kind: waysKind, channels: <ChatChannel>[]));
    }
    final rooms = _listedRooms();
    final showRooms = rooms.isNotEmpty || (layout.canCreateRoom && !finding);
    final alone = sections.length + (showRooms ? 1 : 0) == 1;
    final fresh = layout.freshIds.toSet();
    final entries = <Widget>[];

    Widget threadsRow() => ChatInboxWayRow(
      key: const ValueKey('chat-inbox-threads-card'),
      frame: frame,
      icon: DIcons.comments,
      title: l10n.threads,
      description: layout.unreadThreads > 0
          ? l10n.chatThreadsNewReplies(layout.unreadThreads)
          : l10n.chatThreadsWay,
      count: layout.unreadThreads,
      onPressed: () => _shell!.openMyThreads(),
    );

    for (final (at, section) in sections.indexed) {
      final kind = section.kind;
      final expanded =
          kind == ChatInboxSectionKind.results || _expanded.contains(kind);
      final slice = ChatInboxSectionSlice(
        section.channels,
        expanded: expanded,
        alone: alone,
        keep: (channel) => channel.id == layout.activeChannelId,
        isNew: chatInboxIsNew,
      );
      final list = slice.visible;
      final ways = hasWays && kind == waysKind;
      // In the one list the way to the threads stands among what is unread:
      // after what is also starred, or after all of it when no thread is new.
      final threadsAt = !ways || !layout.threadsWay
          ? -1
          : kind == ChatInboxSectionKind.allChats
          ? list
                .where(
                  (channel) =>
                      fresh.contains(channel.id) &&
                      (layout.unreadThreads == 0 || channel.membership.starred),
                )
                .length
          : 0;
      void addThreads() {
        entries.add(threadsRow());
        if (list.isNotEmpty && layout.unreadThreads == 0) entries.add(rule);
      }

      entries.add(
        ChatInboxSectionHeading(
          key: ValueKey(('chat-inbox-heading', kind)),
          kind: kind,
          first: at == 0,
          edge: frame.edge,
        ),
      );
      for (final (index, channel) in list.indexed) {
        if (index == threadsAt) addThreads();
        entries.add(
          ChatInboxEntry(
            key: ValueKey(channel.id),
            siteUrl: _siteUrl,
            channelId: channel.id,
            frame: frame,
            showStar: kind != ChatInboxSectionKind.starred,
            menuButton: widget.place == ChatInboxPlace.side,
            found: layout.lines[channel.id],
          ),
        );
        final boxed =
            fresh.contains(channel.id) && channel.id != layout.activeChannelId;
        if (index < list.length - 1 && !boxed) entries.add(rule);
      }
      if (threadsAt >= list.length) addThreads();
      if (kind != ChatInboxSectionKind.results && slice.canFold) {
        entries.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: frame.edge),
            child: ChatInboxMore(
              key: ValueKey(('chat-more', kind)),
              hidden: slice.hidden,
              hiddenUnread: slice.hiddenUnread,
              expanded: expanded,
              onPressed: () => _toggle(kind),
            ),
          ),
        );
      }
      if (ways && layout.channelsWay) {
        entries.add(
          ChatInboxWayRow(
            key: const ValueKey('chat-inbox-channels-card'),
            frame: frame,
            icon: DIcons.hashtag,
            title: l10n.browseChannels,
            description: l10n.chatBrowseWay,
            onPressed: () => _browse(''),
          ),
        );
      }
    }

    if (showRooms) {
      final createRoom = _rooms?.createRoom(_siteUrl);
      final slice = ChatInboxSectionSlice(
        rooms,
        expanded: _roomsExpanded || finding,
        alone: alone,
      );
      entries.add(
        ChatInboxSectionHeading.rooms(
          key: const ValueKey('chat-inbox-voice-rooms-heading'),
          first: sections.isEmpty,
          edge: frame.edge,
        ),
      );
      for (final (index, room) in slice.visible.indexed) {
        entries.add(
          ChatInboxRoomRow(
            key: ValueKey(('chat-room', room.id)),
            room: room,
            frame: frame,
          ),
        );
        if (index < slice.visible.length - 1) entries.add(rule);
      }
      if (slice.canFold && !finding) {
        entries.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: frame.edge),
            child: ChatInboxMore(
              key: const ValueKey('chat-more-voice-rooms'),
              hidden: slice.hidden,
              expanded: _roomsExpanded,
              onPressed: () => setState(() {
                _roomsExpanded = !_roomsExpanded;
                _view = null;
              }),
            ),
          ),
        );
      }
      if (createRoom != null && !finding) {
        entries.add(
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: frame.edge,
              vertical: DSpacing.sm,
            ),
            child: DButton(
              variant: DButtonVariant.outline,
              icon: const DIcon(DIcons.plus),
              label: Text(l10n.newVoiceRoom),
              onPressed: () => unawaited(createRoom(context)),
            ),
          ),
        );
      }
    }

    final nothingListed =
        sections.every((section) => section.channels.isEmpty) && rooms.isEmpty;
    if (finding) {
      // What is found among your own chats, then the way to every channel,
      // the words carried there.
      if (nothingListed) {
        entries.add(
          Padding(
            key: const ValueKey('chat-inbox-no-matches'),
            padding: EdgeInsets.fromLTRB(frame.edge, 18, frame.edge, 4),
            child: Text(
              l10n.chatNoneMatch(layout.query),
              style: TextStyle(
                fontSize: 13.5,
                color: DTokens.of(context).mutedForeground,
              ),
            ),
          ),
        );
      }
      if (layout.channelsWay) {
        entries
          ..add(const SizedBox(height: 8))
          ..add(
            ChatInboxWayRow(
              key: const ValueKey('chat-inbox-channels-card'),
              frame: frame,
              icon: DIcons.hashtag,
              title: l10n.chatBrowseAllChannels,
              description: l10n.chatBrowseAllChannelsFor(layout.query),
              onPressed: () => _browse(layout.query),
            ),
          );
      }
    } else if (nothingListed && !layout.loading) {
      entries.insert(
        0,
        layout.failed
            ? ChatInboxError(
                onRetry: () =>
                    unawaited(chat.loadChannels(_siteUrl, force: true)),
              )
            : Padding(
                key: const ValueKey('chat-inbox-empty'),
                padding: EdgeInsets.symmetric(
                  horizontal: frame.edge,
                  vertical: DSpacing.lg,
                ),
                child: Text(
                  layout.emptyMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DTokens.of(context).mutedForeground),
                ),
              ),
      );
    }

    return ChatListingView._(
      entries,
      {for (final (index, entry) in entries.indexed) ?entry.key: index},
      loading: layout.loading,
      refreshing: layout.refreshing,
    );
  }
}

/// What chat's list is found and laid out by, the same over the page and the
/// side: its field first, then the switch between by kind and one list.
class ChatListingControls extends StatefulWidget {
  const ChatListingControls({
    super.key,
    required this.siteUrl,
    required this.place,
    this.field = true,
  });

  final String siteUrl;
  final ChatInboxPlace place;

  /// Whether the field to find a chat is shown over the order switch.
  final bool field;

  @override
  State<ChatListingControls> createState() => _ChatListingControlsState();
}

class _ChatListingControlsState extends State<ChatListingControls> {
  final _focus = FocusNode();
  final _text = TextEditingController();

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = PluginUiScope.require(
      context,
      chatControllerService,
    ).inboxFilters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.sm,
      children: [
        if (widget.field)
          ListenableBuilder(
            listenable: filters,
            builder: (context, _) {
              final query = filters.queryFor(widget.place, widget.siteUrl);
              if (_text.text != query) {
                _text.value = TextEditingValue(
                  text: query,
                  selection: TextSelection.collapsed(offset: query.length),
                );
              }
              return ChatFindField(
                key: const ValueKey('chat-search-entry'),
                controller: _text,
                focusNode: _focus,
                placeholder: context.l10n.findAChat,
                onChanged: (value) =>
                    filters.setQuery(widget.place, widget.siteUrl, value),
              );
            },
          ),
        ChatInboxFilterBar(siteUrl: widget.siteUrl, filters: filters),
      ],
    );
  }
}

/// Chat's controls pin over its list as it scrolls under them.
class ChatSidebarInboxHeader extends StatelessWidget {
  const ChatSidebarInboxHeader({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) => Padding(
        // On the edge the rows' marks stand on.
        padding: DControlStyle.isTouch(context)
            ? const EdgeInsets.fromLTRB(10, 10, 10, 6)
            : const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: ChatListingControls(
          siteUrl: siteUrl,
          place: ChatInboxPlace.side,
          // Without chat there is nothing for its field to find.
          field: shell.isConnected(siteUrl) && shell.chatAvailable(siteUrl),
        ),
      ),
    );
  }
}

/// Chat's side: the Chats page's list laid out as a sliver, so it scrolls
/// with the panel's other sections.
class ChatSidebarInbox extends StatelessWidget {
  const ChatSidebarInbox({super.key, required this.siteUrl});

  final String siteUrl;

  /// A sidebar's body is already 8 in from the panel's edge.
  static const frame = ChatInboxRowFrame(edge: 8);

  @override
  Widget build(BuildContext context) => ChatListing(
    siteUrl: siteUrl,
    place: ChatInboxPlace.side,
    frame: frame,
    builder: (context, view) => view.loading
        ? const SliverToBoxAdapter(child: _ChatSidebarInboxSkeleton())
        : SliverList.builder(
            itemCount: view.entries.length,
            findChildIndexCallback: view.indexOf,
            itemBuilder: (context, index) => view.entries[index],
          ),
  );
}

/// Reserves the rows the inbox is about to draw; the filters above it are
/// already final, so only the rows are placeholders.
class _ChatSidebarInboxSkeleton extends StatelessWidget {
  const _ChatSidebarInboxSkeleton();

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    key: const ValueKey('chat-inbox-loading-skeleton'),
    semanticsLabel: context.l10n.loadingConversations,
    color: skeletonFill(context, on: SkeletonSurface.panel),
    child: Column(
      children: [
        for (var row = 0; row < 6; row++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                const DSkeleton.circle(diameter: ChatInboxRowFrame.mark),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      FractionallySizedBox(
                        widthFactor: row.isEven ? .65 : .5,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 12),
                      ),
                      FractionallySizedBox(
                        widthFactor: row.isEven ? .85 : .7,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
