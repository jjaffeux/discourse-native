import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_skeleton.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_chrome_scroll_view.dart';
import 'chat_controller.dart';
import 'chat_inbox.dart';
import 'chat_inbox_filters.dart';
import 'chat_plugin.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

export 'chat_inbox_filters.dart' show ChatChannelJoinedFilter;

class ChatBrowseChannelsView extends StatefulWidget {
  const ChatBrowseChannelsView({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatBrowseChannelsView> createState() => _ChatBrowseChannelsViewState();
}

class _ChatBrowseChannelsViewState extends State<ChatBrowseChannelsView> {
  late final ChatController _chat;
  late final TextEditingController _filterController;
  late final ScrollController _scrollController;
  Timer? _filterTimer;
  Object? _request;
  List<ChatChannel> _channels = const [];
  int _nextOffset = 0;
  ChatChannelBrowseStatus _status = ChatChannelBrowseStatus.all;
  ChatChannelJoinedFilter _joined = ChatChannelJoinedFilter.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  VoidCallback? _unregisterRefresher;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController();
    _scrollController = ScrollController()..addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request != null) return;
    _chat = PluginUiScope.require(context, chatControllerService);
    final saved = _chat.inboxFilters.browseFor(widget.siteUrl);
    _filterController.text = saved.query;
    _status = saved.status;
    _joined = saved.membership;
    _unregisterRefresher = PluginUiScope.require(context, chatShellService)
        .registerRouteRefresher(
          widget.siteUrl,
          ChatPlugin.browseRouteId,
          () => _load(reset: true),
        );
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _unregisterRefresher?.call();
    _request = Object();
    _filterTimer?.cancel();
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fed by the field's onChanged rather than a controller listener: the
  // controller also notifies on focus and caret moves, and a reset for those
  // would drop the pages already loaded.
  void _filterChanged(String query) {
    _chat.inboxFilters.browseFor(widget.siteUrl).query = query;
    _filterTimer?.cancel();
    _filterTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_load(reset: true)),
    );
  }

  // A failed page is retried only from its Try again row: every scroll
  // update near the end would otherwise resend it as soon as it fails.
  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >
            paginationPrefetchDistance(_scrollController.position) ||
        !_hasMore ||
        _loadingMore ||
        _error != null) {
      return;
    }
    unawaited(_load(reset: false));
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _loadingMore || !_hasMore)) return;
    final token = Object();
    _request = token;
    setState(() {
      if (reset) {
        _loading = true;
        _nextOffset = 0;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    final offset = _nextOffset;
    final result = await _chat.fetchBrowseChannels(
      widget.siteUrl,
      filter: _filterController.text,
      status: _status,
      offset: offset,
    );
    if (!mounted || !identical(_request, token)) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      _error = result.error;
      if (result.page case final page?) {
        _nextOffset = offset + page.rowCount;
        _channels = reset
            ? page.channels
            : List.unmodifiable([..._channels, ...page.channels]);
        _hasMore = page.hasMore && page.rowCount > 0;
      } else if (reset) {
        _channels = const [];
        _hasMore = false;
      }
    });
  }

  List<ChatChannel> get _visibleChannels => switch (_joined) {
    ChatChannelJoinedFilter.all => _channels,
    ChatChannelJoinedFilter.joined => [
      for (final channel in _channels)
        if ((_chat.channel(widget.siteUrl, channel.id) ?? channel)
            .membership
            .following)
          channel,
    ],
    ChatChannelJoinedFilter.notJoined => [
      for (final channel in _channels)
        if (!(_chat.channel(widget.siteUrl, channel.id) ?? channel)
            .membership
            .following)
          channel,
    ],
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _chat,
    builder: (context, _) => ChatChromeScrollView(
      header: FocusTraversalGroup(
        policy: WidgetOrderTraversalPolicy(),
        child: ContentReadingLaneBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: DSpacing.md,
            children: [
              ChatBrowseNavigation(
                siteUrl: widget.siteUrl,
                page: ChatBrowsePage.channels,
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = DInput(
                    size: DControlSize.field,
                    key: const ValueKey('chat-browse-filter'),
                    controller: _filterController,
                    onChanged: _filterChanged,
                    hintText: 'Find a channel',
                    semanticLabel: 'Find a channel',
                    prefix: const DIcon(DIcons.magnifyingGlass),
                  );
                  final filters = Wrap(
                    spacing: DSpacing.controlGap,
                    runSpacing: DSpacing.controlGap,
                    children: [
                      ChatBrowseFilter<ChatChannelBrowseStatus>(
                        key: const ValueKey('chat-browse-status'),
                        value: _status,
                        label: _status == ChatChannelBrowseStatus.all
                            ? 'Status'
                            : _statusLabel(_status),
                        semanticLabel: 'Status',
                        emphasized: _status != ChatChannelBrowseStatus.all,
                        entries: [
                          for (final status in ChatChannelBrowseStatus.values)
                            DSelectOption(
                              value: status,
                              label: _statusLabel(status),
                              child: Text(_statusLabel(status)),
                            ),
                        ],
                        onChanged: (status) {
                          if (status == _status) return;
                          setState(() => _status = status);
                          _chat.inboxFilters.browseFor(widget.siteUrl).status =
                              status;
                          unawaited(_load(reset: true));
                        },
                      ),
                      ChatBrowseFilter<ChatChannelJoinedFilter>(
                        key: const ValueKey('chat-browse-joined'),
                        value: _joined,
                        label: _joined == ChatChannelJoinedFilter.all
                            ? 'Membership'
                            : _joinedLabel(_joined),
                        semanticLabel: 'Membership',
                        emphasized: _joined != ChatChannelJoinedFilter.all,
                        entries: [
                          for (final joined in ChatChannelJoinedFilter.values)
                            DSelectOption(
                              value: joined,
                              label: _joinedLabel(joined),
                              child: Text(_joinedLabel(joined)),
                            ),
                        ],
                        onChanged: (joined) {
                          setState(() => _joined = joined);
                          _chat.inboxFilters
                                  .browseFor(widget.siteUrl)
                                  .membership =
                              joined;
                        },
                      ),
                    ],
                  );
                  return constraints.maxWidth >=
                          MediaQuery.textScalerOf(context).scale(600)
                      ? Row(
                          spacing: DSpacing.controlGap,
                          children: [
                            Expanded(child: search),
                            filters,
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: DSpacing.controlGap,
                          children: [search, filters],
                        );
                },
              ),
            ],
          ),
        ),
      ),
      list: _buildResults,
    ),
  );

  Widget _buildResults(BuildContext context, bool lazy) {
    if (_loading) {
      return ContentReadingLane(
        basePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        builder: (context, lane) => ChatBrowseSkeleton(
          page: ChatBrowsePage.channels,
          scrollable: lazy,
          padding: lane.padding,
        ),
      );
    }
    final channels = _visibleChannels;
    if (channels.isEmpty && !_hasMore && _error != null) {
      return _BrowseMessage(
        icon: DIcons.triangleExclamation,
        message: _error!,
        action: 'Try again',
        onAction: () => unawaited(_load(reset: true)),
      );
    }
    final resultCount = channels.isEmpty ? 1 : channels.length;
    final hasFooter = _loadingMore || _error != null || _hasMore;
    final itemCount = resultCount + (hasFooter ? 1 : 0);
    Widget item(BuildContext context, int index) {
      if (channels.isEmpty && index == 0) {
        return _BrowseMessage(
          icon: DIcons.magnifyingGlass,
          message: _hasMore
              ? 'No matching channels loaded yet.'
              : 'No channels match these filters.',
        );
      }
      if (index < channels.length) {
        final channel = channels[index];
        return ValueListenableBuilder<ChatChannel?>(
          valueListenable: _chat.channelRef(widget.siteUrl, channel.id),
          builder: (context, current, _) => _ChannelRow(
            siteUrl: widget.siteUrl,
            channel: current ?? channel,
            chat: _chat,
            onChanged: _replaceChannel,
          ),
        );
      }
      if (_loadingMore) {
        return const ChatBrowseSkeleton(page: ChatBrowsePage.channels, rows: 2);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            if (_error case final error?) ...[
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],
            DButton(
              label: Text(_error == null ? 'Load more' : 'Try again'),
              onPressed: () => unawaited(_load(reset: false)),
            ),
          ],
        ),
      );
    }

    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      builder: (context, lane) => lazy
          ? ListView.builder(
              key: const PageStorageKey('chat-browse-channels'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: lane.padding,
              itemCount: itemCount,
              itemBuilder: item,
            )
          // Scrolling with the filters cannot prefetch the next page, so its
          // Load more row stays the way to reach it.
          : Padding(
              padding: lane.padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < itemCount; index++)
                    item(context, index),
                ],
              ),
            ),
    );
  }

  void _replaceChannel(ChatChannel channel) {
    final index = _channels.indexWhere((value) => value.id == channel.id);
    if (index < 0 || !mounted) return;
    setState(() {
      _channels = List.unmodifiable([..._channels]..[index] = channel);
    });
  }

  static String _statusLabel(ChatChannelBrowseStatus status) =>
      switch (status) {
        ChatChannelBrowseStatus.all => 'All',
        ChatChannelBrowseStatus.open => 'Open',
        ChatChannelBrowseStatus.closed => 'Closed',
        ChatChannelBrowseStatus.archived => 'Archived',
      };

  static String _joinedLabel(ChatChannelJoinedFilter filter) =>
      switch (filter) {
        ChatChannelJoinedFilter.all => 'All',
        ChatChannelJoinedFilter.joined => 'Joined',
        ChatChannelJoinedFilter.notJoined => 'Not joined',
      };
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.siteUrl,
    required this.channel,
    required this.chat,
    required this.onChanged,
  });

  final String siteUrl;
  final ChatChannel channel;
  final ChatController chat;
  final ValueChanged<ChatChannel> onChanged;

  @override
  Widget build(BuildContext context) {
    final following = channel.membership.following;
    final busy = chat.channelFollowWriteInFlight(siteUrl, channel.id);
    final canJoin = channel.canJoin && channel.status == ChatChannelStatus.open;
    final status = switch (channel.status) {
      ChatChannelStatus.open => null,
      ChatChannelStatus.readOnly => 'Read only',
      ChatChannelStatus.closed => 'Closed',
      ChatChannelStatus.archived => 'Archived',
    };
    final unread = channel.tracking.unreadCount;
    final summary =
        '${unread == 0 ? 'No' : unread} unread ${unread == 1 ? 'message' : 'messages'}${status == null ? '' : ' · $status'}';
    final row = Column(
      children: [
        const DSeparator(),
        ChatChannelMenu(
          siteUrl: siteUrl,
          channelId: channel.id,
          channel: channel,
          child: DItem(
            key: ValueKey('chat-browse-channel-${channel.id}'),
            shape: DItemShape.fullWidth,
            onPressed: () => unawaited(_open(context)),
            children: [
              DItemMedia(
                variant: DItemMediaVariant.avatar,
                child: ChatConversationAvatar(
                  siteUrl: siteUrl,
                  channel: channel,
                  size: 32,
                ),
              ),
              DItemContent(
                children: [
                  DItemTitle(
                    child: Text(
                      channel.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DItemDescription(child: Text(summary)),
                ],
              ),
              DItemActions(
                children: [
                  DButton(
                    key: ValueKey(
                      following
                          ? 'chat-unfollow-${channel.id}'
                          : 'chat-join-${channel.id}',
                    ),
                    label: Text(following ? 'Joined' : 'Join'),
                    semanticLabel:
                        '${following ? 'Leave' : 'Join'} ${channel.title}',
                    shape: DButtonShape.pill,
                    variant: following
                        ? DButtonVariant.outline
                        : DButtonVariant.primary,
                    onPressed: !following && !canJoin
                        ? null
                        : () => _changeFollowing(context, !following),
                    loading: busy,
                    loadingLabel: Text(following ? 'Leaving…' : 'Joining…'),
                  ),
                  if (following)
                    ChatChannelMenu(
                      siteUrl: siteUrl,
                      channelId: channel.id,
                      channel: channel,
                    )
                  else
                    DDropdownMenu(
                      content: DDropdownMenuContent(
                        children: [
                          DDropdownMenuItem(
                            onPressed: () => unawaited(_open(context)),
                            child: const Text('Open channel'),
                          ),
                          if (canJoin)
                            DDropdownMenuItem(
                              onPressed: busy
                                  ? null
                                  : () => _changeFollowing(context, true),
                              child: const Text('Join channel'),
                            ),
                        ],
                      ),
                      child: DDropdownMenuTrigger(
                        builder: (context, menu) => DButton.iconOnly(
                          tooltip: 'Open ${channel.title} menu',
                          icon: const DIcon(DIcons.ellipsisVertical),
                          variant: DButtonVariant.ghost,
                          size: DButtonSize.small,
                          focusNode: menu.focusNode,
                          hasPopup: true,
                          expanded: menu.open,
                          onPressed: menu.toggle,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    if (following) return row;
    return DContextMenu(
      content: DContextMenuContent(
        semanticLabel: '${channel.title} menu',
        children: [
          DDropdownMenuItem(
            onPressed: () => unawaited(_open(context)),
            child: const Text('Open channel'),
          ),
          if (canJoin)
            DDropdownMenuItem(
              onPressed: busy ? null : () => _changeFollowing(context, true),
              child: const Text('Join channel'),
            ),
        ],
      ),
      child: DContextMenuTrigger(focusable: false, child: row),
    );
  }

  Future<void> _open(BuildContext context) async {
    try {
      final resolved = await chat.ensureChannel(siteUrl, channel.id);
      if (!context.mounted) return;
      if (resolved == null) throw StateError('Channel unavailable');
      PluginUiScope.require(context, chatShellService).openChannel(channel.id);
    } catch (_) {
      if (context.mounted) {
        DToast.show(
          context,
          'Could not open this channel.',
          type: DToastType.error,
        );
      }
    }
  }

  Future<void> _changeFollowing(BuildContext context, bool following) async {
    final error = await chat.updateChannelFollowing(
      siteUrl,
      channel,
      following,
    );
    if (!context.mounted) return;
    if (error != null) {
      DToast.show(context, error, type: DToastType.error);
      return;
    }
    final changed = chat.channel(siteUrl, channel.id);
    if (changed != null) onChanged(changed);
  }
}

class _BrowseMessage extends StatelessWidget {
  const _BrowseMessage({
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final DIconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: DEmpty(
        children: [
          DEmptyHeader(
            children: [
              DEmptyMedia(variant: DEmptyMediaVariant.icon, child: DIcon(icon)),
              DEmptyTitle(message),
            ],
          ),
          if (action case final label?)
            DEmptyContent(
              children: [DButton(label: Text(label), onPressed: onAction)],
            ),
        ],
      ),
    ),
  );
}
