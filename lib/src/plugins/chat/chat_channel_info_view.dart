import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/content_reading_lane.dart';
import '../../shell/user_card.dart';
import '../../shell/user_status.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../utils/pagination.dart';
import 'chat_channel.dart';
import 'chat_channel_editor.dart';
import 'chat_channel_status.dart';
import 'chat_controller.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_shell_service.dart';
import 'chat_user_avatar.dart';

class ChatChannelInfoView extends StatelessWidget {
  const ChatChannelInfoView({
    super.key,
    required this.siteUrl,
    required this.channelId,
    required this.tab,
    required this.chat,
  });

  final String siteUrl;
  final int channelId;
  final ChatChannelInfoTab tab;
  final ChatController chat;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null) {
          return const Center(
            child: Text('This channel is no longer available.'),
          );
        }

        if (tab == ChatChannelInfoTab.members &&
            channel.status != ChatChannelStatus.open) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            PluginUiScope.require(
              context,
              chatShellService,
            ).openChannelInfo(siteUrl: siteUrl, channelId: channelId);
          });
          return const Center(child: DSpinner(size: DSpacing.xl));
        }

        return Column(
          children: [
            if (channel.status == ChatChannelStatus.open)
              _ChannelInfoTabs(
                siteUrl: siteUrl,
                channel: channel,
                selected: tab,
              ),
            Expanded(
              child: switch (tab) {
                ChatChannelInfoTab.settings => _ChannelSettings(
                  siteUrl: siteUrl,
                  channelId: channelId,
                  chat: chat,
                ),
                ChatChannelInfoTab.members => _ChannelMembers(
                  siteUrl: siteUrl,
                  channelId: channelId,
                  membershipsCount: channel.membershipsCount,
                  chat: chat,
                ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _ChannelInfoTabs extends StatelessWidget {
  const _ChannelInfoTabs({
    required this.siteUrl,
    required this.channel,
    required this.selected,
  });

  final String siteUrl;
  final ChatChannel channel;
  final ChatChannelInfoTab selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final leadingSpace = constraints.maxWidth <= 740 ? 8.0 : 22.0;
            return SizedBox(
              key: const ValueKey('chat-channel-info-tabs'),
              width: double.infinity,
              height: 58,
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: leadingSpace),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DTabs<ChatChannelInfoTab>.controlled(
                    value: selected,
                    onChanged: (tab) {
                      if (tab == null || tab == selected) return;
                      PluginUiScope.require(
                        context,
                        chatShellService,
                      ).openChannelInfo(
                        siteUrl: siteUrl,
                        channelId: channel.id,
                        tab: tab,
                      );
                    },
                    children: [
                      DTabList<ChatChannelInfoTab>(
                        variant: DTabListVariant.line,
                        children: [
                          const DTabTrigger(
                            key: ValueKey('chat-channel-info-settings-tab'),
                            value: ChatChannelInfoTab.settings,
                            child: Text('Settings'),
                          ),
                          DTabTrigger(
                            key: const ValueKey(
                              'chat-channel-info-members-tab',
                            ),
                            value: ChatChannelInfoTab.members,
                            child: Text(
                              channel.isCategoryChannel
                                  ? 'Members (${channel.membershipsCount})'
                                  : 'Members',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChannelSettings extends StatelessWidget {
  const _ChannelSettings({
    required this.siteUrl,
    required this.channelId,
    required this.chat,
  });

  final String siteUrl;
  final int channelId;
  final ChatController chat;

  void _notice(BuildContext context, String message) {
    DToast.show(context, message, type: DToastType.error);
  }

  Future<void> _changeNotifications(
    BuildContext context, {
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
  }) async {
    final error = await chat.updateChannelNotifications(
      siteUrl,
      channelId,
      muted: muted,
      notificationLevel: notificationLevel,
    );
    if (error != null && context.mounted) _notice(context, error);
  }

  Future<void> _toggleThreading(BuildContext context, bool enabled) async {
    final error = await chat.updateChannelThreading(
      siteUrl,
      channelId,
      enabled,
    );
    if (error != null && context.mounted) _notice(context, error);
  }

  Future<void> _leave(BuildContext context, ChatChannel channel) async {
    final error = await chat.updateChannelFollowing(siteUrl, channel, false);
    if (!context.mounted) return;
    if (error != null) {
      _notice(context, error);
      return;
    }
    PluginUiScope.require(context, chatShellService).openBrowseChannels();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null) {
          return const Center(
            child: Text('This channel is no longer available.'),
          );
        }
        final canEdit = chat.canEditChannelMetadata(siteUrl, channelId);
        final canChangeStatus = chat.canChangeChannelStatus(siteUrl, channelId);
        final config = chat.siteConfigFor(siteUrl);

        return ListenableBuilder(
          listenable: chat,
          builder: (context, _) {
            final notificationBusy = chat.channelNotificationWriteInFlight(
              siteUrl,
              channelId,
            );
            final settingsBusy = chat.channelSettingsWriteInFlight(
              siteUrl,
              channelId,
            );
            final followingBusy = chat.channelFollowWriteInFlight(
              siteUrl,
              channelId,
            );
            final membership = channel.membership;

            return ContentReadingLane(
              basePadding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              builder: (context, lane) => ListView(
                key: const ValueKey('chat-channel-settings'),
                padding: lane.padding,
                children: [
                  Align(
                    alignment: lane.alignment,
                    child: ConstrainedBox(
                      key: const ValueKey('chat-channel-settings-lane-content'),
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ChannelSummary(
                            channel: channel,
                            onOpenChannel: channel.isCategoryChannel
                                ? () => PluginUiScope.require(
                                    context,
                                    chatShellService,
                                  ).openChannel(channel.id)
                                : null,
                            onEdit: canEdit
                                ? () => unawaited(
                                    showChatChannelDetailsEditor(
                                      context: context,
                                      chat: chat,
                                      siteUrl: siteUrl,
                                      channel: channel,
                                    ),
                                  )
                                : null,
                          ),
                          if (channel.status == ChatChannelStatus.open &&
                              membership.following)
                            _InfoSection(
                              title: 'Your notifications',
                              children: [
                                _InfoRow(
                                  label: 'Mute channel',
                                  description:
                                      'Hide unread indicators and stop channel notifications.',
                                  action: DSwitch(
                                    key: const ValueKey(
                                      'chat-channel-muted-setting',
                                    ),
                                    semanticLabel: 'Mute channel',
                                    value: membership.muted,
                                    onChanged: notificationBusy
                                        ? null
                                        : (muted) => unawaited(
                                            _changeNotifications(
                                              context,
                                              muted: muted,
                                            ),
                                          ),
                                  ),
                                ),
                                if (!membership.muted)
                                  _InfoRow(
                                    label: 'Push notifications',
                                    description:
                                        'Choose which activity should reach this device.',
                                    action: SizedBox(
                                      width: 170,
                                      child:
                                          DSelect<
                                            ChatChannelNotificationLevel
                                          >.controlled(
                                            isExpanded: true,
                                            key: const ValueKey(
                                              'chat-channel-notification-setting',
                                            ),
                                            value: membership.notificationLevel,
                                            onChanged: notificationBusy
                                                ? null
                                                : (level) {
                                                    if (level != null) {
                                                      unawaited(
                                                        _changeNotifications(
                                                          context,
                                                          notificationLevel:
                                                              level,
                                                        ),
                                                      );
                                                    }
                                                  },
                                            entries: const [
                                              DSelectOption(
                                                value:
                                                    ChatChannelNotificationLevel
                                                        .never,
                                                label: 'Never',
                                                child: Text('Never'),
                                              ),
                                              DSelectOption(
                                                value:
                                                    ChatChannelNotificationLevel
                                                        .mention,
                                                label: 'Mentions only',
                                                child: Text('Mentions only'),
                                              ),
                                              DSelectOption(
                                                value:
                                                    ChatChannelNotificationLevel
                                                        .always,
                                                label: 'All activity',
                                                child: Text('All activity'),
                                              ),
                                            ],
                                            initialValue:
                                                membership.notificationLevel,
                                            enabled: !notificationBusy,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          if (channel.status == ChatChannelStatus.open &&
                              canEdit)
                            _InfoSection(
                              title: 'Conversation',
                              children: [
                                _InfoRow(
                                  label: 'Threaded replies',
                                  description:
                                      'Replies open as separate conversations alongside the main channel.',
                                  action: DSwitch(
                                    key: const ValueKey(
                                      'chat-channel-threading-switch',
                                    ),
                                    semanticLabel: 'Enable threads',
                                    value: channel.threadingEnabled,
                                    onChanged: settingsBusy
                                        ? null
                                        : (enabled) => unawaited(
                                            _toggleThreading(context, enabled),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          _InfoSection(
                            title: 'Channel information',
                            children: [
                              if (channel.isCategoryChannel)
                                _InfoRow(
                                  label: 'Category',
                                  description:
                                      'Controls visibility and membership rules.',
                                  action: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (channel.categoryColor
                                          case final color?) ...[
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: color,
                                            borderRadius: BorderRadius.circular(
                                              3,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      if (channel.readRestricted) ...[
                                        const DIcon(DIcons.lock, size: 14),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        channel.categoryName ??
                                            channel.slug ??
                                            'Category',
                                      ),
                                    ],
                                  ),
                                ),
                              _InfoRow(
                                label: 'Message history',
                                description:
                                    'Messages are removed after the retention period.',
                                action: Text(
                                  _retentionLabel(
                                    channel.isDirectMessage
                                        ? config
                                              .chatSettings
                                              .directMessageRetentionDays
                                        : config
                                              .chatSettings
                                              .channelRetentionDays,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (canChangeStatus)
                            _InfoSection(
                              title: 'Channel management',
                              children: [
                                _InfoRow(
                                  label:
                                      channel.status == ChatChannelStatus.closed
                                      ? 'Channel is closed.'
                                      : 'Channel is open.',
                                  description:
                                      channel.status == ChatChannelStatus.closed
                                      ? 'Opening lets members post in this channel again.'
                                      : 'Closing prevents non-staff members from posting.',
                                  action: DButton(
                                    key: const ValueKey(
                                      'chat-channel-toggle-status',
                                    ),
                                    label: Text(
                                      channel.status == ChatChannelStatus.closed
                                          ? 'Open channel'
                                          : 'Close channel',
                                    ),
                                    onPressed: () => unawaited(
                                      showChatChannelStatusDialog(
                                        context: context,
                                        chat: chat,
                                        siteUrl: siteUrl,
                                        channel: channel,
                                      ),
                                    ),
                                    variant: DButtonVariant.outline,
                                    size: DButtonSize.small,
                                  ),
                                ),
                              ],
                            ),
                          if (membership.following && channel.isCategoryChannel)
                            _InfoSection(
                              title: 'Leave this channel',
                              children: [
                                _InfoRow(
                                  value: Text(
                                    'Remove ${channel.title} from your sidebar and stop following its conversations.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  action: DButton(
                                    key: const ValueKey('chat-channel-leave'),
                                    label: const Text('Leave channel'),
                                    onPressed: () =>
                                        unawaited(_leave(context, channel)),
                                    icon: const DIcon(DIcons.rightFromBracket),
                                    variant: DButtonVariant.destructive,
                                    size: DButtonSize.small,
                                    loading: followingBusy,
                                    loadingLabel: const Text('Leaving…'),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static String _retentionLabel(int days) =>
      days > 0 ? '$days days' : 'Forever';
}

class _ChannelSummary extends StatelessWidget {
  const _ChannelSummary({
    required this.channel,
    this.onOpenChannel,
    this.onEdit,
  });

  final ChatChannel channel;
  final VoidCallback? onOpenChannel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = Row(
      key: const ValueKey('chat-channel-summary-identity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: DIcon(
              DIcons.comment,
              size: 18,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DText(
                channel.title,
                variant: DTextVariant.h4,
                headingLevel: 1,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              if (channel.isCategoryChannel) ...[
                const SizedBox(height: 2),
                DText(
                  channel.description ??
                      'Tell people what this channel is about.',
                  variant: DTextVariant.muted,
                ),
                const SizedBox(height: 4),
                InkWell(
                  key: const ValueKey('chat-channel-settings-channel-link'),
                  onTap: onOpenChannel,
                  child: Text(
                    '/chat/c/${channel.slug ?? '-'}/${channel.id}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    Widget editButton() => DButton(
      key: const ValueKey('chat-channel-edit-details'),
      label: const Text('Edit details'),
      onPressed: onEdit,
      icon: const DIcon(DIcons.pencil),
      variant: DButtonVariant.outline,
      size: DButtonSize.small,
    );

    return Padding(
      key: const ValueKey('chat-channel-summary'),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (onEdit == null) return identity;
          final width = ContentReadingLane.breakpointWidthOf(
            context,
            constraints.maxWidth,
          );
          if (width < 480) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: editButton()),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              editButton(),
            ],
          );
        },
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) DSeparator(space: 1, color: theme.dividerColor),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({this.label, this.description, this.value, this.action})
    : assert(label != null || value != null);

  final String? label;
  final String? description;
  final Widget? value;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child:
                  value ??
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (description case final description?) ...[
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
            ),
            if (action case final action?) ...[
              const SizedBox(width: 16),
              action,
            ],
          ],
        ),
      ),
    );
  }
}

class _ChannelMembers extends StatefulWidget {
  const _ChannelMembers({
    required this.siteUrl,
    required this.channelId,
    required this.membershipsCount,
    required this.chat,
  });

  final String siteUrl;
  final int channelId;
  final int membershipsCount;
  final ChatController chat;

  @override
  State<_ChannelMembers> createState() => _ChannelMembersState();
}

class _ChannelMembersState extends State<_ChannelMembers> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final _members = <ChatUser>[];
  Timer? _searchTimer;
  Object _generation = Object();
  String _filter = '';
  String? _error;
  int _nextOffset = 0;
  bool _loading = false;
  bool _loaded = false;
  bool _canLoadMore = true;
  VoidCallback? _unregisterRefresher;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unregisterRefresher?.call();
    _unregisterRefresher = PluginUiScope.require(context, chatShellService)
        .registerRouteRefresher(
          widget.siteUrl,
          ChatRoute.info(
            channelId: widget.channelId,
            tab: ChatChannelInfoTab.members,
          ).routeId,
          () => _load(reset: true),
        );
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(reset: true));
    });
  }

  @override
  void didUpdateWidget(covariant _ChannelMembers oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membershipsCount != widget.membershipsCount) {
      _generation = Object();
      unawaited(_load(reset: true));
    }
  }

  @override
  void dispose() {
    _unregisterRefresher?.call();
    _generation = Object();
    _searchTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter <
            paginationPrefetchDistance(_scroll.position) &&
        _canLoadMore &&
        _error == null &&
        !_loading) {
      unawaited(_load());
    }
  }

  void _filterChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || value.trim() == _filter) return;
      _filter = value.trim();
      _generation = Object();
      unawaited(_load(reset: true));
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_canLoadMore)) return;
    final generation = reset ? Object() : _generation;
    if (reset) {
      _generation = generation;
      setState(() {
        _members.clear();
        _nextOffset = 0;
        _loaded = false;
        _canLoadMore = true;
        _error = null;
      });
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final offset = _nextOffset;
    final result = await widget.chat.fetchChannelMembers(
      widget.siteUrl,
      widget.channelId,
      username: _filter,
      offset: offset,
      limit: _pageSize,
    );
    if (!mounted || !identical(_generation, generation)) return;
    final page = result.page;
    setState(() {
      _loading = false;
      _loaded = true;
      _error = result.error;
      if (page != null) {
        // Server progress includes duplicate and malformed rows.
        _nextOffset = offset + page.rowCount;
        final ids = _members.map((member) => member.id).toSet();
        _members.addAll(page.members.where((member) => ids.add(member.id)));
        _canLoadMore = page.canLoadMore && page.rowCount > 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ContentReadingLane(
      basePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      builder: (context, lane) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: lane.padding.left,
              top: lane.padding.top,
              right: lane.padding.right,
            ),
            child: Align(
              alignment: lane.alignment,
              child: ConstrainedBox(
                key: const ValueKey('chat-channel-member-filter-lane-content'),
                constraints: const BoxConstraints(maxWidth: 760),
                child: TextField(
                  style: Theme.of(context).textTheme.bodyMedium,
                  key: const ValueKey('chat-channel-member-filter'),
                  autofocus: true,
                  onChanged: _filterChanged,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Filter members',
                    prefixIcon: DIcon(DIcons.magnifyingGlass),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _memberList(lane)),
        ],
      ),
    );
  }

  Widget _memberList(ContentReadingLaneGeometry lane) {
    if (!_loaded && _loading) {
      return const Center(child: DSpinner(size: DSpacing.xl));
    }
    if (_error case final error? when _members.isEmpty && _nextOffset == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            DButton(
              label: const Text('Retry'),
              onPressed: () => unawaited(_load(reset: true)),
            ),
          ],
        ),
      );
    }
    final hasFooter = _loading || _canLoadMore || _error != null;
    if (_members.isEmpty && !hasFooter) {
      return Center(
        child: Text(_filter.isEmpty ? 'No members.' : 'No members found.'),
      );
    }
    return ListView.builder(
      key: const ValueKey('chat-channel-member-list'),
      controller: _scroll,
      padding: EdgeInsets.only(
        left: lane.padding.left,
        right: lane.padding.right,
      ),
      itemCount: _members.length + (hasFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _members.length) {
          return Align(
            alignment: lane.alignment,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _loading
                    ? const Center(child: DSpinner(size: DSpacing.xl))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_error case final error?) ...[
                            Text(error, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                          ],
                          DButton(
                            label: Text(_error == null ? 'Load more' : 'Retry'),
                            onPressed: () => unawaited(_load()),
                          ),
                        ],
                      ),
              ),
            ),
          );
        }
        final member = _members[index];
        return Align(
          alignment: lane.alignment,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: UserCardTarget(
              username: member.username,
              siteUrl: widget.siteUrl,
              child: ListTile(
                key: ValueKey('chat-channel-member-${member.id}'),
                contentPadding: EdgeInsets.zero,
                leading: ChatUserAvatar(
                  siteUrl: widget.siteUrl,
                  userId: member.id,
                  url: member.avatarUrl,
                  size: 36,
                  fallback: const DIcon(DIcons.user),
                ),
                title: Text(member.displayName),
                subtitle: member.name == null
                    ? null
                    : Text('@${member.username}'),
                trailing: UserStatusMessage(
                  siteUrl: widget.siteUrl,
                  userId: member.id,
                  status: member.status,
                  showDescription: true,
                  size: 16,
                  style: Theme.of(context).textTheme.bodySmall,
                  descriptionMaxWidth: 120,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
