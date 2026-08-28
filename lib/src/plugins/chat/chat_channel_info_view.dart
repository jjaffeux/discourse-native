import 'dart:async';

import 'package:flutter/material.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/user_card.dart';
import '../../shell/user_status.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel.dart';
import 'chat_channel_editor.dart';
import 'chat_channel_status.dart';
import 'chat_controller.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_shell_extension.dart';
import 'chat_user_avatar.dart';

/// Core Discourse's routed channel information surface.
///
/// Settings and members are sibling routes rather than unrelated header
/// sheets. The shell owns Back, while this view owns the route-local tabs and
/// the same channel controls core groups together under `/info`.
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
          return const Center(child: CircularProgressIndicator.adaptive());
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
      child: Row(
        key: const ValueKey('chat-channel-info-tabs'),
        children: [
          const SizedBox(width: 16),
          _tab(context, ChatChannelInfoTab.settings, 'Settings'),
          _tab(
            context,
            ChatChannelInfoTab.members,
            channel.isCategoryChannel
                ? 'Members (${channel.membershipsCount})'
                : 'Members',
          ),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, ChatChannelInfoTab tab, String label) {
    final theme = Theme.of(context);
    final active = selected == tab;
    return InkWell(
      key: ValueKey('chat-channel-info-${tab.name}-tab'),
      onTap: active
          ? null
          : () => PluginUiScope.require(context, chatShellService)
                .openChannelInfo(
                  siteUrl: siteUrl,
                  channelId: channel.id,
                  tab: tab,
                ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 3,
              color: active ? theme.colorScheme.primary : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
            fontWeight: active ? FontWeight.w600 : null,
          ),
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
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
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

            return ListView(
              key: const ValueKey('chat-channel-settings'),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _InfoSection(
                          title: 'Title',
                          children: [
                            _InfoRow(
                              value: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(channel.title),
                                  if (channel.isCategoryChannel)
                                    InkWell(
                                      key: const ValueKey(
                                        'chat-channel-settings-channel-link',
                                      ),
                                      onTap: () => PluginUiScope.require(
                                        context,
                                        chatShellService,
                                      ).openChannel(channel.id),
                                      child: Text(
                                        '/chat/c/${channel.slug ?? '-'}/${channel.id}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              action: canEdit
                                  ? TextButton(
                                      key: const ValueKey(
                                        'chat-channel-edit-title',
                                      ),
                                      onPressed: () => unawaited(
                                        showChatChannelTitleEditor(
                                          context: context,
                                          chat: chat,
                                          siteUrl: siteUrl,
                                          channel: channel,
                                        ),
                                      ),
                                      child: const Text('Edit'),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                        if (channel.isCategoryChannel)
                          _InfoSection(
                            title: 'Description',
                            children: [
                              _InfoRow(
                                value: Text(
                                  channel.description ??
                                      'Tell people what this channel is about.',
                                ),
                                action: canEdit
                                    ? TextButton(
                                        key: const ValueKey(
                                          'chat-channel-edit-description',
                                        ),
                                        onPressed: () => unawaited(
                                          showChatChannelDescriptionEditor(
                                            context: context,
                                            chat: chat,
                                            siteUrl: siteUrl,
                                            channel: channel,
                                          ),
                                        ),
                                        child: Text(
                                          channel.description == null
                                              ? 'Add'
                                              : 'Edit',
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        if (channel.status == ChatChannelStatus.open &&
                            (membership.following || canEdit))
                          _InfoSection(
                            title: 'Settings',
                            children: [
                              if (membership.following)
                                _InfoRow(
                                  label: 'Mute channel',
                                  action: Switch.adaptive(
                                    key: const ValueKey(
                                      'chat-channel-muted-setting',
                                    ),
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
                              if (membership.following && !membership.muted)
                                _InfoRow(
                                  label: 'Push notifications',
                                  action:
                                      DropdownButton<
                                        ChatChannelNotificationLevel
                                      >(
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
                                                      notificationLevel: level,
                                                    ),
                                                  );
                                                }
                                              },
                                        items: const [
                                          DropdownMenuItem(
                                            value: ChatChannelNotificationLevel
                                                .never,
                                            child: Text('Never'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChatChannelNotificationLevel
                                                .mention,
                                            child: Text('Mentions only'),
                                          ),
                                          DropdownMenuItem(
                                            value: ChatChannelNotificationLevel
                                                .always,
                                            child: Text('All activity'),
                                          ),
                                        ],
                                      ),
                                ),
                              if (canEdit)
                                _InfoRow(
                                  label: 'Threading',
                                  description:
                                      'Replies create separate conversations alongside the main channel.',
                                  action: Switch.adaptive(
                                    key: const ValueKey(
                                      'chat-channel-threading-switch',
                                    ),
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
                              label: 'History',
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
                            if (canChangeStatus)
                              _InfoRow(
                                label: 'Status',
                                action: TextButton(
                                  key: const ValueKey(
                                    'chat-channel-toggle-status',
                                  ),
                                  onPressed: () => unawaited(
                                    showChatChannelStatusDialog(
                                      context: context,
                                      chat: chat,
                                      siteUrl: siteUrl,
                                      channel: channel,
                                    ),
                                  ),
                                  child: Text(
                                    channel.status == ChatChannelStatus.closed
                                        ? 'Open channel'
                                        : 'Close channel',
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (membership.following &&
                            channel.isCategoryChannel) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              key: const ValueKey('chat-channel-leave'),
                              onPressed: followingBusy
                                  ? null
                                  : () => unawaited(_leave(context, channel)),
                              style: FilledButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onError,
                              ),
                              icon: const DIcon(DIcons.rightFromBracket),
                              label: Text(
                                followingBusy ? 'Leaving…' : 'Leave channel',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static String _retentionLabel(int days) =>
      days > 0 ? '$days days' : 'Forever';
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({this.label, this.description, this.value, this.action})
    : assert(label != null || value != null);

  final String? label;
  final String? description;
  final Widget? value;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child:
              value ??
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label!),
                  if (description case final description?)
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
        ),
        if (action case final action?) ...[const SizedBox(width: 16), action],
      ],
    ),
  );
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
  bool _loading = false;
  bool _loaded = false;
  bool _canLoadMore = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(reset: true));
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
    _generation = Object();
    _searchTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 160 &&
        _canLoadMore &&
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
    if (_loading && !reset) return;
    final generation = reset ? Object() : _generation;
    if (reset) {
      _generation = generation;
      setState(() {
        _members.clear();
        _loaded = false;
        _canLoadMore = true;
        _error = null;
      });
    }
    setState(() => _loading = true);
    final result = await widget.chat.fetchChannelMembers(
      widget.siteUrl,
      widget.channelId,
      username: _filter,
      offset: reset ? 0 : _members.length,
      limit: _pageSize,
    );
    if (!mounted || !identical(_generation, generation)) return;
    final page = result.page;
    setState(() {
      _loading = false;
      _loaded = true;
      _error = result.error;
      if (page != null) {
        final ids = _members.map((member) => member.id).toSet();
        _members.addAll(page.members.where((member) => ids.add(member.id)));
        _canLoadMore = page.canLoadMore && page.members.isNotEmpty;
      } else {
        _canLoadMore = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
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
              const SizedBox(height: 12),
              Expanded(child: _memberList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _memberList() {
    if (!_loaded && _loading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_error case final error? when _members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => unawaited(_load(reset: true)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_members.isEmpty) {
      return Center(
        child: Text(_filter.isEmpty ? 'No members.' : 'No members found.'),
      );
    }
    return ListView.builder(
      key: const ValueKey('chat-channel-member-list'),
      controller: _scroll,
      itemCount: _members.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _members.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final member = _members[index];
        return UserCardTarget(
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
            subtitle: member.name == null ? null : Text('@${member.username}'),
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
        );
      },
    );
  }
}
