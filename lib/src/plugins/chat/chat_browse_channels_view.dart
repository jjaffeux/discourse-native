import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/shell_scope.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_services.dart';
import 'chat_shell_extension.dart';

enum ChatChannelJoinedFilter { all, joined, notJoined }

/// Native counterpart to Chat's Browse Channels directory.
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
  ChatChannelBrowseStatus _status = ChatChannelBrowseStatus.all;
  ChatChannelJoinedFilter _joined = ChatChannelJoinedFilter.all;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filterController = TextEditingController()..addListener(_filterChanged);
    _scrollController = ScrollController()..addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request != null) return;
    _chat = PluginScope.require(context, chatControllerService);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _request = Object();
    _filterTimer?.cancel();
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _filterChanged() {
    _filterTimer?.cancel();
    _filterTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_load(reset: true)),
    );
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 600 ||
        !_hasMore ||
        _loadingMore) {
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
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    final result = await _chat.fetchBrowseChannels(
      widget.siteUrl,
      filter: _filterController.text,
      status: _status,
      offset: reset ? 0 : _channels.length,
    );
    if (!mounted || !identical(_request, token)) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      _error = result.error;
      if (result.page case final page?) {
        _channels = reset
            ? page.channels
            : List.unmodifiable([..._channels, ...page.channels]);
        _hasMore = page.hasMore;
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
        if (channel.membership.following) channel,
    ],
    ChatChannelJoinedFilter.notJoined => [
      for (final channel in _channels)
        if (!channel.membership.following) channel,
    ],
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          children: [
            TextField(
              key: const ValueKey('chat-browse-filter'),
              controller: _filterController,
              decoration: const InputDecoration(
                labelText: 'Find a channel',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ChatChannelBrowseStatus>(
                    key: const ValueKey('chat-browse-status'),
                    initialValue: _status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final status in ChatChannelBrowseStatus.values)
                        DropdownMenuItem(
                          value: status,
                          child: Text(_statusLabel(status)),
                        ),
                    ],
                    onChanged: (status) {
                      if (status == null || status == _status) return;
                      setState(() => _status = status);
                      unawaited(_load(reset: true));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<ChatChannelJoinedFilter>(
                    key: const ValueKey('chat-browse-joined'),
                    initialValue: _joined,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Membership',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final joined in ChatChannelJoinedFilter.values)
                        DropdownMenuItem(
                          value: joined,
                          child: Text(_joinedLabel(joined)),
                        ),
                    ],
                    onChanged: (joined) {
                      if (joined != null) setState(() => _joined = joined);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      Expanded(child: _buildResults(context)),
    ],
  );

  Widget _buildResults(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final channels = _visibleChannels;
    if (channels.isEmpty && _error != null) {
      return _BrowseMessage(
        icon: DIcons.triangleExclamation,
        message: _error!,
        action: 'Try again',
        onAction: () => unawaited(_load(reset: true)),
      );
    }
    if (channels.isEmpty) {
      return const _BrowseMessage(
        icon: DIcons.magnifyingGlass,
        message: 'No channels match these filters.',
      );
    }

    final hasFooter = _loadingMore || _error != null || _hasMore;
    return RefreshIndicator.adaptive(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        key: const PageStorageKey('chat-browse-channels'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: channels.length + (hasFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index < channels.length) {
            return _ChannelCard(
              siteUrl: widget.siteUrl,
              channel: channels[index],
              chat: _chat,
              onChanged: _replaceChannel,
            );
          }
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator.adaptive()),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                if (_error case final error?) ...[
                  Text(error, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                ],
                OutlinedButton(
                  onPressed: () => unawaited(_load(reset: false)),
                  child: Text(_error == null ? 'Load more' : 'Try again'),
                ),
              ],
            ),
          );
        },
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

class _ChannelCard extends StatelessWidget {
  const _ChannelCard({
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
    return Card(
      key: ValueKey('chat-browse-channel-${channel.id}'),
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: following
            ? () => ShellScope.read(context).openChatChannel(channel.id)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: DIcon(
                  channel.readRestricted ? DIcons.lock : DIcons.comment,
                  color: channel.categoryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            channel.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (status != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              status,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${channel.membershipsCount} ${channel.membershipsCount == 1 ? 'member' : 'members'}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    if (channel.description case final description?
                        when description.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: following
                          ? OutlinedButton(
                              key: ValueKey('chat-unfollow-${channel.id}'),
                              onPressed: busy
                                  ? null
                                  : () => _changeFollowing(context, false),
                              child: Text(busy ? 'Saving…' : 'Unfollow'),
                            )
                          : FilledButton(
                              key: ValueKey('chat-join-${channel.id}'),
                              onPressed: busy || !canJoin
                                  ? null
                                  : () => _changeFollowing(context, true),
                              child: Text(busy ? 'Joining…' : 'Join'),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeFollowing(BuildContext context, bool following) async {
    final error = await chat.updateChannelFollowing(
      siteUrl,
      channel,
      following,
    );
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
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
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(icon, size: 28),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          if (action case final label?) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(label)),
          ],
        ],
      ),
    ),
  );
}
