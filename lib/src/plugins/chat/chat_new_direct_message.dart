import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../shell/avatar_image.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_controller.dart';
import 'chat_direct_message_search.dart';
import 'chat_plugin_data.dart';
import 'chat_shell_service.dart';

Future<void> showChatNewDirectMessageDialog({
  required BuildContext context,
  required String siteUrl,
  required ChatController chat,
  required ChatShellService shell,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _ChatNewDirectMessageDialog(siteUrl: siteUrl, chat: chat, shell: shell),
);

class _ChatNewDirectMessageDialog extends StatefulWidget {
  const _ChatNewDirectMessageDialog({
    required this.siteUrl,
    required this.chat,
    required this.shell,
  });

  final String siteUrl;
  final ChatController chat;
  final ChatShellService shell;

  @override
  State<_ChatNewDirectMessageDialog> createState() =>
      _ChatNewDirectMessageDialogState();
}

class _ChatNewDirectMessageDialogState
    extends State<_ChatNewDirectMessageDialog> {
  final _search = TextEditingController();
  final _groupName = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  List<ChatDirectMessageSearchItem> _results = const [];
  final List<ChatDirectMessageSearchItem> _members = [];
  bool _composingGroup = false;
  bool _searching = false;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _showExistingChannels();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _groupName.dispose();
    super.dispose();
  }

  int get _maximumGroupMembers =>
      widget.chat.siteConfigFor(widget.siteUrl).chatMaximumDirectMessageUsers;

  bool get _canUseGroupChat =>
      widget.chat.currentUserFor(widget.siteUrl)?.staff == true ||
      _maximumGroupMembers > 1;

  int get _membersCount => _members.fold(0, (count, member) {
    return count +
        switch (member) {
          ChatDirectMessageUser() => 1,
          ChatDirectMessageGroup(:final memberCount) => memberCount,
          ChatDirectMessageChannel() => 0,
        };
  });

  void _showExistingChannels() {
    _results = [
      for (final channel in widget.chat.directChannels(widget.siteUrl))
        ChatDirectMessageChannel(
          identifier: 'c-${channel.id}',
          matchQuality: 3,
          enabled: true,
          channel: channel,
        ),
    ];
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final generation = ++_generation;
    setState(() {
      _error = null;
      if (query.isEmpty) {
        _searching = false;
        if (_composingGroup) {
          _results = const [];
        } else {
          _showExistingChannels();
        }
      } else {
        _searching = true;
        _results = const [];
      }
    });
    if (query.isEmpty) return;

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final answer = await widget.chat.searchDirectMessages(
          widget.siteUrl,
          query,
          includeGroups: _canUseGroupChat,
          includeDirectMessageChannels: !_composingGroup,
        );
        if (!mounted || generation != _generation) return;
        setState(() {
          _searching = false;
          _results = answer.items;
        });
      } catch (error) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _searching = false;
          _error = _messageFor(error, fallback: 'Could not search Chat.');
        });
      }
    });
  }

  Future<void> _select(ChatDirectMessageSearchItem item) async {
    if (_opening || !item.enabled) return;
    if (_composingGroup) {
      _addMember(item);
      return;
    }
    if (item case ChatDirectMessageGroup()) {
      _startGroup([item]);
      return;
    }
    if (item case ChatDirectMessageChannel(:final channel)) {
      if (widget.shell.openChannel(channel.id) && mounted) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(() => _error = 'This conversation is no longer available.');
      }
      return;
    }

    final user = item as ChatDirectMessageUser;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final channel = await widget.chat.upsertDirectMessageChannel(
        widget.siteUrl,
        user.username,
      );
      if (!mounted) return;
      if (channel != null && widget.shell.openChannel(channel.id)) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _opening = false;
          _error = 'This conversation is no longer available.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = _messageFor(error, fallback: 'Could not start this chat.');
      });
    }
  }

  void _startGroup([
    List<ChatDirectMessageSearchItem> initialMembers = const [],
  ]) {
    if (!_canUseGroupChat) return;
    _debounce?.cancel();
    _generation++;
    _search.clear();
    setState(() {
      _composingGroup = true;
      _members
        ..clear()
        ..addAll(initialMembers);
      _results = const [];
      _searching = false;
      _error = null;
    });
  }

  void _cancelGroup() {
    _debounce?.cancel();
    _generation++;
    _search.clear();
    _groupName.clear();
    setState(() {
      _composingGroup = false;
      _members.clear();
      _searching = false;
      _error = null;
      _showExistingChannels();
    });
  }

  int _memberCount(ChatDirectMessageSearchItem item) => switch (item) {
    ChatDirectMessageUser() => 1,
    ChatDirectMessageGroup(:final memberCount) => memberCount,
    ChatDirectMessageChannel() => 0,
  };

  bool _canAddMember(ChatDirectMessageSearchItem item) =>
      item is! ChatDirectMessageChannel &&
      item.enabled &&
      _membersCount + _memberCount(item) <= _maximumGroupMembers;

  void _addMember(ChatDirectMessageSearchItem item) {
    if (item is ChatDirectMessageChannel ||
        _members.any((member) => member.identifier == item.identifier)) {
      return;
    }
    if (!_canAddMember(item)) {
      setState(() {
        _error = 'A group chat can include up to $_maximumGroupMembers people.';
      });
      return;
    }
    _debounce?.cancel();
    _generation++;
    _search.clear();
    setState(() {
      _members.add(item);
      _results = const [];
      _searching = false;
      _error = null;
    });
  }

  void _removeMember(ChatDirectMessageSearchItem item) {
    setState(() {
      _members.removeWhere((member) => member.identifier == item.identifier);
      _error = null;
    });
  }

  Future<void> _createGroup() async {
    if (_opening || _members.isEmpty) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final channel = await widget.chat.createDirectMessageChannel(
        widget.siteUrl,
        usernames: [
          for (final member in _members)
            if (member case ChatDirectMessageUser(:final username)) username,
        ],
        groups: [
          for (final member in _members)
            if (member case ChatDirectMessageGroup(:final name)) name,
        ],
        name: _groupName.text,
      );
      if (!mounted) return;
      if (channel != null && widget.shell.openChannel(channel.id)) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _opening = false;
          _error = 'This conversation is no longer available.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = _messageFor(error, fallback: 'Could not create this group.');
      });
    }
  }

  static String _messageFor(Object error, {required String fallback}) =>
      switch (error) {
        WriteException(errors: final errors) when errors.isNotEmpty =>
          errors.join('\n'),
        final WriteException error => error.message,
        _ => fallback,
      };

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    return AlertDialog(
      key: const ValueKey('chat-new-direct-message-dialog'),
      title: Text(_composingGroup ? 'New group chat' : 'Start a chat'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_composingGroup) ...[
              TextField(
                key: const ValueKey('chat-new-group-name'),
                controller: _groupName,
                enabled: !_opening,
                decoration: const InputDecoration(
                  hintText: 'Group name (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _buildMembers(),
              const SizedBox(height: 8),
            ],
            TextField(
              key: const ValueKey('chat-new-direct-message-search'),
              controller: _search,
              autofocus: true,
              enabled: !_opening,
              onChanged: _scheduleSearch,
              decoration: InputDecoration(
                hintText: _composingGroup
                    ? 'Search users or groups'
                    : 'Search users, groups, or conversations',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildResults(query)),
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  error,
                  key: const ValueKey('chat-new-direct-message-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (_composingGroup) ...[
          TextButton(
            onPressed: _opening ? null : _cancelGroup,
            child: const Text('Back'),
          ),
          FilledButton(
            key: const ValueKey('chat-create-group-direct-message'),
            onPressed: _opening || _members.isEmpty
                ? null
                : () => unawaited(_createGroup()),
            child: const Text('Create group chat'),
          ),
        ] else
          TextButton(
            onPressed: _opening ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
      ],
    );
  }

  Widget _buildMembers() {
    if (_members.isEmpty) {
      return Text('0 of $_maximumGroupMembers people selected');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$_membersCount of $_maximumGroupMembers people selected'),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final member in _members) ...[
                InputChip(
                  key: ValueKey('chat-new-group-member-${member.identifier}'),
                  label: Text(_memberLabel(member)),
                  onDeleted: _opening ? null : () => _removeMember(member),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _memberLabel(ChatDirectMessageSearchItem member) =>
      switch (member) {
        ChatDirectMessageUser(:final username) => '@$username',
        ChatDirectMessageGroup(:final name) => '@$name',
        ChatDirectMessageChannel(:final channel) => channel.title,
      };

  Widget _buildResults(String query) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_opening) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    final results = [
      for (final item in _results)
        if (!_composingGroup ||
            !_members.any((member) => member.identifier == item.identifier))
          item,
    ];
    final showNewGroup = !_composingGroup && query.isEmpty && _canUseGroupChat;
    if (results.isEmpty && !showNewGroup) {
      return Center(
        child: Text(
          query.isEmpty
              ? _composingGroup
                    ? 'Search for people or groups to add.'
                    : 'Search for a user to start a direct message.'
              : _composingGroup
              ? 'No users or groups found.'
              : 'No users, groups, or conversations found.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      key: const ValueKey('chat-new-direct-message-results'),
      children: [
        if (showNewGroup)
          ListTile(
            key: const ValueKey('chat-new-group-direct-message'),
            leading: const DIcon(DIcons.users, size: 20),
            title: const Text('New group chat'),
            onTap: _startGroup,
          ),
        for (final item in results)
          switch (item) {
            final ChatDirectMessageUser user => ListTile(
              key: ValueKey('chat-new-direct-message-user-${user.username}'),
              enabled: _composingGroup ? _canAddMember(user) : user.enabled,
              leading: _UserAvatar(user: user),
              title: Text(user.name ?? user.username),
              subtitle: !user.enabled
                  ? const Text('Chat is disabled for this user.')
                  : user.name == null
                  ? null
                  : Text('@${user.username}'),
              onTap: () => unawaited(_select(user)),
            ),
            final ChatDirectMessageChannel result => ListTile(
              key: ValueKey(
                'chat-new-direct-message-channel-${result.channel.id}',
              ),
              enabled: result.enabled,
              leading: const DIcon(DIcons.comment, size: 20),
              title: Text(result.channel.title),
              subtitle: const Text('Existing conversation'),
              onTap: () => unawaited(_select(result)),
            ),
            final ChatDirectMessageGroup group => ListTile(
              key: ValueKey('chat-new-direct-message-group-${group.name}'),
              enabled: _composingGroup ? _canAddMember(group) : group.enabled,
              leading: const DIcon(DIcons.users, size: 20),
              title: Text(group.fullName ?? group.name),
              subtitle: !group.enabled
                  ? const Text('This group cannot be added to Chat.')
                  : Text('@${group.name} · ${group.memberCount} people'),
              onTap: () => unawaited(_select(group)),
            ),
          },
      ],
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final ChatDirectMessageUser user;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: 36,
      child: AvatarImage(
        url: user.avatarUrl,
        size: 36,
        fallback: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Center(
            child: Text(user.username.characters.first.toUpperCase()),
          ),
        ),
      ),
    ),
  );
}
