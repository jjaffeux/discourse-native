import 'dart:async';

import 'package:flutter/material.dart';

import '../../shell/shell_sheet.dart';
import '../../shell/user_card.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import 'chat_channel.dart';
import 'chat_channel_editor.dart';
import 'chat_channel_status.dart';
import 'chat_controller.dart';
import 'chat_user_avatar.dart';

/// Opens the channel description and privacy-safe member directory.
class ChatChannelInfoButton extends StatelessWidget {
  const ChatChannelInfoButton({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final chat = PluginScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel == null || !channel.membership.following) {
          return const SizedBox.shrink();
        }
        return DButton.iconOnly(
          key: const ValueKey('chat-channel-info-button'),
          tooltip: 'Channel info',
          variant: DButtonVariant.flat,
          onPressed: () => unawaited(
            showShellSheet<void>(
              context: context,
              title: channel.title,
              dialogOnDesktop: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              builder: (context) => _ChannelInfo(
                chat: chat,
                siteUrl: siteUrl,
                channelId: channelId,
              ),
            ),
          ),
          icon: const DIcon(DIcons.circleInfo, size: 18),
        );
      },
    );
  }
}

class _ChannelInfo extends StatefulWidget {
  const _ChannelInfo({
    required this.chat,
    required this.siteUrl,
    required this.channelId,
  });

  final ChatController chat;
  final String siteUrl;
  final int channelId;

  @override
  State<_ChannelInfo> createState() => _ChannelInfoState();
}

class _ChannelInfoState extends State<_ChannelInfo> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final _members = <ChatUser>[];
  Timer? _searchTimer;
  Object _generation = Object();
  String _filter = '';
  String? _error;
  int _totalRows = 0;
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
        _totalRows = page.totalRows;
        _canLoadMore = page.canLoadMore && page.members.isNotEmpty;
      } else {
        _canLoadMore = false;
      }
    });
  }

  Future<void> _toggleThreading(bool enabled) async {
    final error = await widget.chat.updateChannelThreading(
      widget.siteUrl,
      widget.channelId,
      enabled,
    );
    if (!mounted || error == null) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: widget.chat.channelRef(widget.siteUrl, widget.channelId),
      builder: (context, channel, _) {
        if (channel == null) {
          return const Text('This channel is no longer available.');
        }
        final canEdit = widget.chat.canEditChannelMetadata(
          widget.siteUrl,
          widget.channelId,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canEdit) ...[
              _ChannelDetailRow(
                actionKey: const ValueKey('chat-channel-edit-title'),
                label: 'Title',
                value: channel.title,
                actionLabel: 'Edit',
                onAction: () => unawaited(
                  showChatChannelTitleEditor(
                    context: context,
                    chat: widget.chat,
                    siteUrl: widget.siteUrl,
                    channel: channel,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ChannelDetailRow(
                actionKey: const ValueKey('chat-channel-edit-description'),
                label: 'Description',
                value: channel.description ?? 'No description.',
                actionLabel: channel.description == null ? 'Add' : 'Edit',
                onAction: () => unawaited(
                  showChatChannelDescriptionEditor(
                    context: context,
                    chat: widget.chat,
                    siteUrl: widget.siteUrl,
                    channel: channel,
                  ),
                ),
              ),
              if (widget.chat.canChangeChannelStatus(
                widget.siteUrl,
                widget.channelId,
              )) ...[
                const SizedBox(height: 12),
                _ChannelDetailRow(
                  actionKey: const ValueKey('chat-channel-toggle-status'),
                  label: 'Status',
                  value: channel.status == ChatChannelStatus.closed
                      ? 'Closed'
                      : 'Open',
                  actionLabel: channel.status == ChatChannelStatus.closed
                      ? 'Open channel'
                      : 'Close channel',
                  onAction: () => unawaited(
                    showChatChannelStatusDialog(
                      context: context,
                      chat: widget.chat,
                      siteUrl: widget.siteUrl,
                      channel: channel,
                    ),
                  ),
                ),
              ],
              if (channel.status == ChatChannelStatus.open) ...[
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  key: const ValueKey('chat-channel-threading-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Threading'),
                  subtitle: const Text(
                    'Replies create separate conversations alongside the main channel.',
                  ),
                  value: channel.threadingEnabled,
                  onChanged:
                      widget.chat.channelSettingsWriteInFlight(
                        widget.siteUrl,
                        widget.channelId,
                      )
                      ? null
                      : (enabled) => unawaited(_toggleThreading(enabled)),
                ),
              ],
              const SizedBox(height: 16),
            ] else if (channel.description case final description?) ...[
              Text(description),
              const SizedBox(height: 16),
            ],
            Text(
              _loaded ? 'Members ($_totalRows)' : 'Members',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('chat-channel-member-filter'),
              onChanged: _filterChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Filter members',
                prefixIcon: DIcon(DIcons.magnifyingGlass),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(height: 330, child: _memberList()),
          ],
        );
      },
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
          ),
        );
      },
    );
  }
}

class _ChannelDetailRow extends StatelessWidget {
  const _ChannelDetailRow({
    required this.actionKey,
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onAction,
  });

  final Key actionKey;
  final String label;
  final String value;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 3),
            Text(value),
          ],
        ),
      ),
      TextButton(key: actionKey, onPressed: onAction, child: Text(actionLabel)),
    ],
  );
}
