import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/discourse_api_contracts.dart';
import '../../shell/avatar_image.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_controller.dart';
import 'chat_direct_message_search.dart';
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
  Timer? _debounce;
  int _generation = 0;
  List<ChatDirectMessageSearchItem> _results = const [];
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
    super.dispose();
  }

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
        _showExistingChannels();
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
      title: const Text('Start a chat'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('chat-new-direct-message-search'),
              controller: _search,
              autofocus: true,
              enabled: !_opening,
              onChanged: _scheduleSearch,
              decoration: const InputDecoration(
                hintText: 'Search users',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
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
        TextButton(
          onPressed: _opening ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildResults(String query) {
    if (_searching) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_opening) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          query.isEmpty
              ? 'Search for a user to start a direct message.'
              : 'No users or conversations found.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('chat-new-direct-message-results'),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return switch (item) {
          final ChatDirectMessageUser user => ListTile(
            key: ValueKey('chat-new-direct-message-user-${user.username}'),
            enabled: user.enabled,
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
        };
      },
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
