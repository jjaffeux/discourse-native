import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_browse_session.dart';
import 'chat_browse_skeleton.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
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
  late ChatController _chat;
  late TextEditingController _filterController;
  ChatShellService? _shell;
  late final ScrollController _scrollController;
  ChatBrowseSession? _session;
  ChatBrowseSession get _browse => _session!;
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
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    _bindSession(chat, shell);
  }

  @override
  void didUpdateWidget(ChatBrowseChannelsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl) {
      _bindSession(
        PluginUiScope.require(context, chatControllerService),
        PluginUiScope.require(context, chatShellService),
      );
    }
  }

  void _bindSession(ChatController chat, ChatShellService shell) {
    if (_session != null &&
        identical(chat, _chat) &&
        identical(shell, _shell) &&
        _browse.siteUrl == widget.siteUrl) {
      return;
    }
    _unregisterRefresher?.call();
    _session?.dispose();
    _chat = chat;
    _shell = shell;
    final session = ChatBrowseSession(chat: chat, siteUrl: widget.siteUrl);
    _session = session;
    // Replacing the field avoids notifying the mounted input during build.
    _filterController.dispose();
    _filterController = TextEditingController(text: session.query);
    session.addListener(_sessionChanged);
    _unregisterRefresher = shell.registerRouteRefresher(
      widget.siteUrl,
      ChatPlugin.browseRouteId,
      session.refresh,
    );
    unawaited(session.refresh());
  }

  void _sessionChanged() => setState(() {});

  @override
  void dispose() {
    _unregisterRefresher?.call();
    _session?.dispose();
    _filterController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter >
            paginationPrefetchDistance(_scrollController.position)) {
      return;
    }
    unawaited(_browse.loadMore());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _chat,
    builder: (context, _) => DScrollChromePagination(
      hasMore: _browse.hasMore,
      loading: _browse.loading || _browse.loadingMore,
      child: DPageSurface.headed(
        title: Text(context.l10n.browseChannels),
        // Scroll fades and mobile chrome must not repaint the fixed filters.
        controls: RepaintBoundary(
          child: FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: ContentReadingLaneBox(
              padding: EdgeInsets.zero,
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
                        onChanged: _browse.changeQuery,
                        hintText: context.l10n.findAChannel,
                        semanticLabel: context.l10n.findAChannel,
                        prefix: const DIcon(DIcons.magnifyingGlass),
                      );
                      final filters = Wrap(
                        spacing: DSpacing.controlGap,
                        runSpacing: DSpacing.controlGap,
                        children: [
                          ChatBrowseFilter<ChatChannelBrowseStatus>(
                            key: const ValueKey('chat-browse-status'),
                            value: _browse.status,
                            label: _browse.status == ChatChannelBrowseStatus.all
                                ? context.l10n.status
                                : _statusLabel(_browse.status),
                            semanticLabel: context.l10n.status,
                            emphasized:
                                _browse.status != ChatChannelBrowseStatus.all,
                            options: {
                              for (final status
                                  in ChatChannelBrowseStatus.values)
                                status: _statusLabel(status),
                            },
                            onChanged: _browse.changeStatus,
                          ),
                          ChatBrowseFilter<ChatChannelJoinedFilter>(
                            key: const ValueKey('chat-browse-joined'),
                            value: _browse.membership,
                            label:
                                _browse.membership ==
                                    ChatChannelJoinedFilter.all
                                ? context.l10n.membership
                                : _joinedLabel(_browse.membership),
                            semanticLabel: context.l10n.membership,
                            emphasized:
                                _browse.membership !=
                                ChatChannelJoinedFilter.all,
                            options: {
                              for (final joined
                                  in ChatChannelJoinedFilter.values)
                                joined: _joinedLabel(joined),
                            },
                            onChanged: _browse.changeMembership,
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
        ),
        adaptiveBodyBuilder: (context, lazy) =>
            RepaintBoundary(child: _buildResults(context, lazy)),
      ),
    ),
  );

  Widget _buildResults(BuildContext context, bool lazy) {
    if (_browse.loading) {
      return ContentReadingLane(
        basePadding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + DScrollChrome.bottomInsetOf(context),
        ),
        builder: (context, lane) => ChatBrowseSkeleton(
          page: ChatBrowsePage.channels,
          scrollable: lazy,
          padding: lane.padding,
        ),
      );
    }
    final channels = _browse.visibleChannels;
    if (channels.isEmpty && !_browse.hasMore && _browse.error != null) {
      return _BrowseMessage(
        icon: DIcons.triangleExclamation,
        message: _browse.error!,
        action: context.l10n.tryAgain,
        onAction: () => unawaited(_browse.refresh()),
      );
    }
    final resultCount = channels.isEmpty ? 1 : channels.length;
    final hasFooter =
        _browse.loadingMore || _browse.error != null || _browse.hasMore;
    final itemCount = resultCount + (hasFooter ? 1 : 0);
    Widget item(BuildContext context, int index) {
      if (channels.isEmpty && index == 0) {
        return _BrowseMessage(
          icon: DIcons.magnifyingGlass,
          message: _browse.hasMore
              ? context.l10n.noMatchingChannelsLoadedYet
              : context.l10n.noChannelsMatchTheseFilters,
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
            onChanged: _browse.replaceChannel,
          ),
        );
      }
      if (_browse.loadingMore) {
        return const ChatBrowseSkeleton(page: ChatBrowsePage.channels, rows: 2);
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            if (_browse.error case final error?) ...[
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],
            DButton(
              label: Text(
                _browse.error == null
                    ? context.l10n.loadMore
                    : context.l10n.tryAgain,
              ),
              onPressed: () => unawaited(_browse.loadMore(retry: true)),
            ),
          ],
        ),
      );
    }

    return ContentReadingLane(
      basePadding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + DScrollChrome.bottomInsetOf(context),
      ),
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

  static String _statusLabel(ChatChannelBrowseStatus status) =>
      switch (status) {
        ChatChannelBrowseStatus.all => appL10n.all,
        ChatChannelBrowseStatus.open => appL10n.open,
        ChatChannelBrowseStatus.closed => appL10n.closed,
        ChatChannelBrowseStatus.archived => appL10n.archived,
      };

  static String _joinedLabel(ChatChannelJoinedFilter filter) =>
      switch (filter) {
        ChatChannelJoinedFilter.all => appL10n.all,
        ChatChannelJoinedFilter.joined => appL10n.joined,
        ChatChannelJoinedFilter.notJoined => appL10n.notJoined,
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
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildRow);

  Widget _buildRow(BuildContext context, BoxConstraints constraints) {
    final following = channel.membership.following;
    final busy = chat.channelFollowWriteInFlight(siteUrl, channel.id);
    final canJoin = channel.canJoin && channel.status == ChatChannelStatus.open;
    final status = switch (channel.status) {
      ChatChannelStatus.open => null,
      ChatChannelStatus.readOnly => context.l10n.readOnly,
      ChatChannelStatus.closed => context.l10n.closed,
      ChatChannelStatus.archived => context.l10n.archived,
    };
    final unread = channel.tracking.unreadCount;
    final summary = context.l10n.unreadChatbrowsechannelsview(
      (unread == 0).toString(),
      unread,
      (status == null).toString(),
      ((unread == 0) ? (context.l10n.no) : '').toString(),
      ((!(status == null)) ? (status) : '').toString(),
      ((!(unread == 0)) ? (unread) : '').toString(),
    );
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
            padding: constraints.maxWidth < 600
                ? const EdgeInsets.symmetric(vertical: DSpacing.md)
                : null,
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
                    label: Text(
                      following ? context.l10n.joined : context.l10n.join,
                    ),
                    semanticLabel: context.l10n.messageChatbrowsechannelsview(
                      (following).toString(),
                      ((following) ? (context.l10n.leave) : '').toString(),
                      (channel.title).toString(),
                      ((!(following)) ? (context.l10n.join) : '').toString(),
                    ),
                    shape: DButtonShape.pill,
                    variant: following
                        ? DButtonVariant.outline
                        : DButtonVariant.primary,
                    onPressed: !following && !canJoin
                        ? null
                        : () => _changeFollowing(context, !following),
                    loading: busy,
                    loadingLabel: Text(
                      following ? context.l10n.leaving : context.l10n.joining,
                    ),
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
                            child: Text(context.l10n.openChannel),
                          ),
                          if (canJoin)
                            DDropdownMenuItem(
                              onPressed: busy
                                  ? null
                                  : () => _changeFollowing(context, true),
                              child: Text(context.l10n.joinChannel),
                            ),
                        ],
                      ),
                      child: DDropdownMenuTrigger(
                        builder: (context, menu) => DButton.iconOnly(
                          tooltip: context.l10n.openMenu(
                            (channel.title).toString(),
                          ),
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
        semanticLabel: context.l10n.menu((channel.title).toString()),
        children: [
          DDropdownMenuItem(
            onPressed: () => unawaited(_open(context)),
            child: Text(context.l10n.openChannel),
          ),
          if (canJoin)
            DDropdownMenuItem(
              onPressed: busy ? null : () => _changeFollowing(context, true),
              child: Text(context.l10n.joinChannel),
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
          appL10n.couldNotOpenThisChannel,
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
