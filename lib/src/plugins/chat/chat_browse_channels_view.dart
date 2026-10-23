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
              child: LayoutBuilder(
                key: const ValueKey('chat-browse-controls'),
                builder: _buildControls,
              ),
            ),
          ),
        ),
        adaptiveBodyBuilder: (context, lazy) =>
            RepaintBoundary(child: _buildResults(context, lazy)),
      ),
    ),
  );

  Widget _buildControls(BuildContext context, BoxConstraints constraints) {
    final textScaler = MediaQuery.textScalerOf(context);
    final navigation = ChatBrowseNavigation(
      siteUrl: widget.siteUrl,
      page: ChatBrowsePage.channels,
    );
    final search = DInput(
      size: DControlSize.field,
      key: const ValueKey('chat-browse-filter'),
      controller: _filterController,
      onChanged: _browse.changeQuery,
      hintText: context.l10n.findAChannel,
      semanticLabel: context.l10n.findAChannel,
      prefix: const DIcon(DIcons.magnifyingGlass),
    );
    final status = ChatBrowseFilter<ChatChannelBrowseStatus>(
      key: const ValueKey('chat-browse-status'),
      value: _browse.status,
      label: _browse.status == ChatChannelBrowseStatus.all
          ? context.l10n.status
          : _statusLabel(_browse.status),
      semanticLabel: context.l10n.status,
      emphasized: _browse.status != ChatChannelBrowseStatus.all,
      options: {
        for (final status in ChatChannelBrowseStatus.values)
          status: _statusLabel(status),
      },
      onChanged: _browse.changeStatus,
    );
    final membership = ChatBrowseFilter<ChatChannelJoinedFilter>(
      key: const ValueKey('chat-browse-joined'),
      value: _browse.membership,
      label: _browse.membership == ChatChannelJoinedFilter.all
          ? context.l10n.membership
          : _joinedLabel(_browse.membership),
      semanticLabel: context.l10n.membership,
      emphasized: _browse.membership != ChatChannelJoinedFilter.all,
      options: {
        for (final joined in ChatChannelJoinedFilter.values)
          joined: _joinedLabel(joined),
      },
      onChanged: _browse.changeMembership,
    );
    // A desktop lane holds the directory switch, search and both filters in
    // the one bar the mockup draws; narrower lanes stack them.
    if (constraints.maxWidth >= textScaler.scale(760)) {
      return DControlWrap(
        wrap: false,
        spacing: DSpacing.controlGap,
        children: [
          navigation,
          DControlExpanded(child: search),
          status,
          membership,
        ],
      );
    }
    final filters = Wrap(
      spacing: DSpacing.controlGap,
      runSpacing: DSpacing.controlGap,
      children: [status, membership],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: DSpacing.md,
      children: [
        navigation,
        if (constraints.maxWidth >= textScaler.scale(600))
          Row(
            spacing: DSpacing.controlGap,
            children: [
              Expanded(child: search),
              filters,
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: DSpacing.controlGap,
            children: [search, filters],
          ),
      ],
    );
  }

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
    final hasFooter =
        _browse.loadingMore || _browse.error != null || _browse.hasMore;
    Widget footer(BuildContext context) {
      if (_browse.loadingMore) {
        return const ChatBrowseSkeleton(page: ChatBrowsePage.channels, rows: 1);
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
      // Scrolling with the filters cannot prefetch the next page, so its
      // Load more row stays the way to reach it.
      builder: (context, lane) => CustomScrollView(
        key: lazy ? const PageStorageKey('chat-browse-channels') : null,
        controller: lazy ? _scrollController : null,
        primary: false,
        shrinkWrap: !lazy,
        physics: lazy
            ? const AlwaysScrollableScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: lane.padding,
            sliver: SliverMainAxisGroup(
              slivers: [
                if (channels.isEmpty)
                  SliverToBoxAdapter(
                    child: _BrowseMessage(
                      icon: DIcons.magnifyingGlass,
                      message: _browse.hasMore
                          ? context.l10n.noMatchingChannelsLoadedYet
                          : context.l10n.noChannelsMatchTheseFilters,
                    ),
                  )
                else
                  DPlaceCardGrid(
                    itemCount: channels.length,
                    itemBuilder: (context, index) =>
                        ValueListenableBuilder<ChatChannel?>(
                          valueListenable: _chat.channelRef(
                            widget.siteUrl,
                            channels[index].id,
                          ),
                          builder: (context, current, _) => _ChannelCard(
                            siteUrl: widget.siteUrl,
                            channel: current ?? channels[index],
                            chat: _chat,
                            onChanged: _browse.replaceChannel,
                          ),
                        ),
                  ),
                if (hasFooter)
                  SliverToBoxAdapter(child: Builder(builder: footer)),
              ],
            ),
          ),
        ],
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
      ChatChannelStatus.readOnly => context.l10n.readOnly,
      ChatChannelStatus.closed => context.l10n.closed,
      ChatChannelStatus.archived => context.l10n.archived,
    };
    final unread = channel.tracking.unreadCount;
    final description = channel.description?.trim();
    final color = channel.categoryColor ?? DTokens.of(context).mutedForeground;
    final card = DPlaceCard(
      key: ValueKey('chat-browse-channel-${channel.id}'),
      onPressed: () => unawaited(_open(context)),
      strong: unread > 0,
      muted: channel.membership.muted,
      unreadCount: unread > 0 ? '$unread' : null,
      semanticLabel: unread > 0
          ? context.l10n.unreadChatbrowsechannelsview(
              'false',
              unread,
              'true',
              '',
              '',
              unread.toString(),
            )
          : null,
      leading: DPlaceCardMark(
        color: color,
        child: switch (channel.emoji) {
          final emoji? => EmojiImage(
            url: PluginUiScope.require(
              context,
              chatEmojiHostService,
            ).resolveUrl(siteUrl, emoji),
            size: 13,
            alt: ':$emoji:',
          ),
          null => DIcon(DIcons.hashtag, size: 13, color: color),
        },
      ),
      title: Text(channel.title),
      description: description == null || description.isEmpty
          ? null
          : Text(description),
      footer: Text(
        [
          countLabel(channel.membershipsCount, CountNoun.member),
          ?status,
        ].join(' · '),
      ),
      trailing: following
          ? ChatChannelMenu(
              siteUrl: siteUrl,
              channelId: channel.id,
              channel: channel,
            )
          : DDropdownMenu(
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
                  tooltip: context.l10n.openMenu(channel.title),
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
      action: DButton(
        key: ValueKey(
          following ? 'chat-unfollow-${channel.id}' : 'chat-join-${channel.id}',
        ),
        label: Text(following ? context.l10n.joined : context.l10n.join),
        semanticLabel: context.l10n.messageChatbrowsechannelsview(
          following.toString(),
          following ? context.l10n.leave : '',
          channel.title,
          following ? '' : context.l10n.join,
        ),
        shape: DButtonShape.pill,
        size: DButtonSize.small,
        variant: following ? DButtonVariant.outline : DButtonVariant.primary,
        onPressed: !following && !canJoin
            ? null
            : () => _changeFollowing(context, !following),
        loading: busy,
        loadingLabel: Text(
          following ? context.l10n.leaving : context.l10n.joining,
        ),
      ),
    );
    if (following) {
      return ChatChannelMenu(
        siteUrl: siteUrl,
        channelId: channel.id,
        channel: channel,
        child: card,
      );
    }
    return DContextMenu(
      content: DContextMenuContent(
        semanticLabel: context.l10n.menu(channel.title),
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
      child: DContextMenuTrigger(focusable: false, child: card),
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
