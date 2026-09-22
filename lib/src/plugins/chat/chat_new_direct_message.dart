import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_direct_message_search.dart';
import 'chat_plugin_data.dart';
import 'chat_shell_service.dart';
import 'chat_shortcuts.dart';

Future<void> showChatNewDirectMessageDialog({
  required BuildContext context,
  required String siteUrl,
  required ChatController chat,
  required ChatShellService shell,
}) => showDDialog<void>(
  context: context,
  builder: (context, dialog) => _ChatNewDirectMessageDialog(
    siteUrl: siteUrl,
    chat: chat,
    shell: shell,
    dialog: dialog,
  ),
);

class _ChatNewDirectMessageDialog extends StatefulWidget {
  const _ChatNewDirectMessageDialog({
    required this.siteUrl,
    required this.chat,
    required this.shell,
    required this.dialog,
  });

  final String siteUrl;
  final ChatController chat;
  final ChatShellService shell;
  final DDialogController<void> dialog;

  @override
  State<_ChatNewDirectMessageDialog> createState() =>
      _ChatNewDirectMessageDialogState();
}

class _ChatNewDirectMessageDialogState
    extends State<_ChatNewDirectMessageDialog> {
  static const _newGroupValue = 'new-group';
  final _searchFocus = FocusNode(debugLabel: 'Start chatting search');
  final _command = DCommandController<String>();
  final _search = TextEditingController();
  bool _resettingSearch = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocus.dispose();
    _command.dispose();
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
    final channels = widget.chat.directChannels(widget.siteUrl);
    final positions = {
      for (final (i, channel) in channels.indexed) channel.id: i,
    };
    channels.sort((a, b) {
      final activity = (b.lastMessageAt?.millisecondsSinceEpoch ?? 0).compareTo(
        a.lastMessageAt?.millisecondsSinceEpoch ?? 0,
      );
      return activity != 0
          ? activity
          : positions[a.id]!.compareTo(positions[b.id]!);
    });
    _results = [
      for (final channel in channels)
        ChatDirectMessageChannel(
          identifier: 'c-${channel.id}',
          matchQuality: 3,
          enabled: true,
          channel: channel,
        ),
    ];
  }

  void _scheduleSearch(String value) {
    if (_resettingSearch || _opening) return;
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
        widget.dialog.close();
      } else if (mounted) {
        setState(() => _error = 'This conversation is no longer available.');
      }
      return;
    }

    final user = item as ChatDirectMessageUser;
    _debounce?.cancel();
    _generation++;
    setState(() {
      _searching = false;
      _opening = true;
      _error = null;
    });
    try {
      final channel = await widget.chat.upsertDirectMessageChannel(
        widget.siteUrl,
        user.username,
      );
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (channel != null && widget.shell.openChannel(channel.id)) {
        widget.dialog.close();
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

  void _clearSearch() {
    _resettingSearch = true;
    _command.updateQuery('');
    _search.clear();
    _command.highlight(null);
    _resettingSearch = false;
    _searchFocus.requestFocus();
  }

  void _startGroup([
    List<ChatDirectMessageSearchItem> initialMembers = const [],
  ]) {
    if (!_canUseGroupChat || _opening) return;
    if (initialMembers.any((member) => !_canAddMember(member))) {
      setState(() {
        _error = 'A group chat can include up to $_maximumGroupMembers people.';
      });
      return;
    }
    _debounce?.cancel();
    _generation++;
    _clearSearch();
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
    _clearSearch();
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
    _clearSearch();
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
    if (_opening || _members.isEmpty || _membersCount > _maximumGroupMembers) {
      return;
    }
    _debounce?.cancel();
    _generation++;
    setState(() {
      _searching = false;
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
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (channel != null && widget.shell.openChannel(channel.id)) {
        widget.dialog.close();
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
    final tokens = DTokens.of(context);
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => false,
      _ => true,
    };
    return CallbackShortcuts(
      bindings: {
        newDirectMessageShortcutForPlatform(Theme.of(context).platform):
            widget.dialog.close,
      },
      child: DDialogContent(
        key: const ValueKey('chat-new-direct-message-dialog'),
        maxWidth: 520,
        showCloseButton: false,
        contentPadding: EdgeInsets.zero,
        verticalPadding: 0,
        spacing: 0,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(DSpacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DDialogHeader(
                        children: [
                          DDialogTitle(
                            child: Text(
                              _composingGroup
                                  ? 'New group chat'
                                  : 'Start chatting',
                            ),
                          ),
                          DDialogDescription(
                            child: Text(
                              _composingGroup
                                  ? 'Bring a few people into the conversation.'
                                  : 'Pick up a conversation or find someone new.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: DSpacing.sm),
                    DButton.iconOnly(
                      icon: const DIcon(DIcons.xmark),
                      variant: DButtonVariant.transparentBackground,
                      onPressed: widget.dialog.close,
                      tooltip: 'Close',
                      semanticLabel: 'Close start chatting',
                    ),
                  ],
                ),
              ),
              if (_composingGroup)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DSpacing.lg,
                    0,
                    DSpacing.lg,
                    DSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DInput(
                        key: const ValueKey('chat-new-group-name'),
                        controller: _groupName,
                        enabled: !_opening,
                        hintText: 'Group name (optional)',
                        semanticLabel: 'Group name (optional)',
                      ),
                      const SizedBox(height: DSpacing.sm),
                      _buildMembers(),
                    ],
                  ),
                ),
              DCommand<String>(
                key: const ValueKey('chat-destination-command'),
                controller: _command,
                shouldFilter: false,
                loop: true,
                vimBindings: false,
                loading: _searching || _opening,
                semanticLabel: 'Chat destinations',
                onQueryChanged: _scheduleSearch,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DSpacing.md,
                      ),
                      child: DCommandInput<String>(
                        key: const ValueKey('chat-new-direct-message-search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        enabled: !_opening,
                        semanticLabel: 'Search chat recipients',
                        placeholder: _composingGroup
                            ? 'Search users or groups'
                            : 'Search users, groups, or conversations',
                      ),
                    ),
                    _buildResults(),
                  ],
                ),
              ),
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.all(DSpacing.md),
                  child: DAlert(
                    key: const ValueKey('chat-new-direct-message-error'),
                    variant: DAlertVariant.destructive,
                    description: DAlertDescription(child: Text(error)),
                  ),
                ),
              DCardFooter(
                backgroundColor: tokens.footerBackground,
                borderColor: tokens.footerBorder,
                padding: const EdgeInsets.symmetric(
                  horizontal: DSpacing.lg,
                  vertical: DSpacing.sm,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showHints =
                        desktop &&
                        constraints.maxWidth >=
                            MediaQuery.textScalerOf(
                              context,
                            ).scale(_composingGroup ? 420 : 280);
                    return Row(
                      children: [
                        if (showHints) Expanded(child: _keyboardHints()),
                        if (_composingGroup)
                          Expanded(
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: DSpacing.controlGap,
                              runSpacing: DSpacing.sm,
                              children: [
                                DButton(
                                  label: const Text('Back'),
                                  variant: DButtonVariant.outline,
                                  onPressed: _opening ? null : _cancelGroup,
                                ),
                                DButton(
                                  key: const ValueKey(
                                    'chat-create-group-direct-message',
                                  ),
                                  label: const Text('Start group chat'),
                                  variant: DButtonVariant.primary,
                                  loading: _opening,
                                  onPressed: _opening || _members.isEmpty
                                      ? null
                                      : () => unawaited(_createGroup()),
                                ),
                              ],
                            ),
                          )
                        else if (showHints)
                          _keyHint(const [DKbd('Esc')], 'close')
                        else
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: DButton(
                                label: const Text('Cancel'),
                                variant: DButtonVariant.outline,
                                onPressed: widget.dialog.close,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyboardHints() => Wrap(
    spacing: DSpacing.md,
    runSpacing: DSpacing.xs,
    children: [
      _keyHint(const [DKbd('↑'), DKbd('↓')], 'navigate'),
      _keyHint(const [DKbd('↵')], _composingGroup ? 'add' : 'open'),
    ],
  );

  Widget _keyHint(List<Widget> keys, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: DSpacing.xs,
    children: [
      ...keys,
      Text(
        label,
        style: TextStyle(
          fontSize: DiscourseTypography.xs,
          color: DTokens.of(context).mutedForeground,
        ),
      ),
    ],
  );

  Widget _buildMembers() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_members.isNotEmpty) ...[
        Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.controlGap,
          children: [
            for (final member in _members)
              DButton(
                key: ValueKey('chat-new-group-member-${member.identifier}'),
                label: Text(_memberLabel(member)),
                icon: const DIcon(DIcons.xmark),
                iconPosition: DButtonIconPosition.end,
                size: DButtonSize.small,
                variant: DButtonVariant.outline,
                semanticLabel: 'Remove ${_memberLabel(member)}',
                onPressed: _opening
                    ? null
                    : () {
                        _removeMember(member);
                        _searchFocus.requestFocus();
                      },
              ),
          ],
        ),
        const SizedBox(height: DSpacing.xs),
      ],
      Semantics(
        liveRegion: true,
        child: Text(
          '$_membersCount of $_maximumGroupMembers people selected',
          style: TextStyle(
            fontSize: DiscourseTypography.xs,
            color: DTokens.of(context).mutedForeground,
          ),
        ),
      ),
    ],
  );

  static String _memberLabel(ChatDirectMessageSearchItem member) =>
      switch (member) {
        ChatDirectMessageUser(:final username) => '@$username',
        ChatDirectMessageGroup(:final name) => '@$name',
        ChatDirectMessageChannel(:final channel) => channel.title,
      };

  Widget _buildResults() {
    final query = _search.text.trim();
    final results = [
      if (!_opening && !_searching)
        for (final item in _results)
          if (!_composingGroup ||
              (item is! ChatDirectMessageChannel &&
                  !_members.any(
                    (member) => member.identifier == item.identifier,
                  )))
            item,
    ];
    final showNewGroup =
        !_composingGroup && query.isEmpty && _canUseGroupChat && !_opening;
    // Keep the server's relevance order, including across result types.
    final groups = <({String heading, List<DCommandItem<String>> items})>[];
    for (final item in results) {
      final heading = switch (item) {
        ChatDirectMessageUser() => 'People',
        ChatDirectMessageGroup() => 'Groups',
        ChatDirectMessageChannel() =>
          query.isEmpty ? 'Recent conversations' : 'Conversations',
      };
      if (groups.isEmpty || groups.last.heading != heading) {
        groups.add((heading: heading, items: []));
      }
      groups.last.items.add(_result(item));
    }
    return DCommandList<String>(
      key: const ValueKey('chat-new-direct-message-results'),
      semanticLabel: 'Chat recipients and conversations',
      children: [
        DCommandLoading(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: DSpacing.sm,
            children: [
              const DSpinner(size: 16),
              Text(_opening ? 'Opening conversation…' : 'Searching…'),
            ],
          ),
        ),
        DCommandEmpty(
          child: Text(
            _error != null
                ? 'Try searching again.'
                : query.isEmpty
                ? _composingGroup
                      ? 'Search for people or groups to add.'
                      : 'Search for a user to start a direct message.'
                : 'No matches found. Try another name or username.',
            textAlign: TextAlign.center,
          ),
        ),
        if (showNewGroup) ...[
          DCommandGroup<String>(
            items: [
              DCommandItem<String>(
                value: _newGroupValue,
                leading: const DIcon(DIcons.plus),
                child: const Text(
                  'Create a group chat',
                  key: ValueKey('chat-new-group-direct-message'),
                ),
                onSelected: (_) => _startGroup(),
              ),
            ],
          ),
          if (groups.isNotEmpty) const DCommandSeparator<String>(),
        ],
        for (final group in groups)
          DCommandGroup<String>(
            heading: Text(group.heading),
            items: group.items,
          ),
      ],
    );
  }

  DCommandItem<String> _result(ChatDirectMessageSearchItem item) {
    final (key, title, detail, leading) = switch (item) {
      final ChatDirectMessageUser user => (
        'chat-new-direct-message-user-${user.username}',
        user.name ?? user.username,
        !user.enabled ? 'Chat is disabled for this user.' : '@${user.username}',
        _ChatAvatar(username: user.username, url: user.avatarUrl),
      ),
      final ChatDirectMessageGroup group => (
        'chat-new-direct-message-group-${group.name}',
        group.fullName ?? group.name,
        !group.enabled
            ? 'This group cannot be added to Chat.'
            : '${group.memberCount} people',
        const DIcon(DIcons.users),
      ),
      ChatDirectMessageChannel(:final channel) => (
        'chat-new-direct-message-channel-${channel.id}',
        channel.title,
        channel.isGroup
            ? channel.users.map((user) => user.displayName).join(', ')
            : '',
        _channelAvatar(channel),
      ),
    };
    final enabled =
        !_opening && (_composingGroup ? _canAddMember(item) : item.enabled);
    return DCommandItem<String>(
      value: item.identifier,
      enabled: enabled,
      semanticLabel: [
        title,
        detail,
        if (_composingGroup && item.enabled && !enabled)
          'Group member limit reached',
      ].where((part) => part.isNotEmpty).join('. '),
      // Command owns its surface key; keep the app's interaction key on content.
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: DSpacing.xs),
        child: leading,
      ),
      trailing: AnimatedBuilder(
        animation: _command,
        builder: (context, _) => DCommandShortcut(
          Text(
            _command.value == item.identifier && enabled
                ? _composingGroup
                      ? '+'
                      : '↵'
                : switch (item) {
                    ChatDirectMessageChannel(:final channel)
                        when channel.lastMessageAt != null =>
                      relativeTime(channel.lastMessageAt!),
                    _ => '',
                  },
          ),
        ),
      ),
      onSelected: (_) => unawaited(_select(item)),
      child: Padding(
        key: ValueKey(key),
        padding: const EdgeInsets.symmetric(vertical: DSpacing.xs),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: title),
              if (detail.isNotEmpty)
                TextSpan(
                  text: '  $detail',
                  style: TextStyle(
                    color: DTokens.of(context).mutedForeground,
                    fontSize: DiscourseTypography.xs,
                  ),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _channelAvatar(ChatChannel channel) {
    final currentUser = widget.chat.currentUserFor(widget.siteUrl)?.id;
    final others = channel.users.where((user) => user.id != currentUser);
    if (!channel.isGroup && others.length == 1) {
      final user = others.single;
      return _ChatAvatar(username: user.username, url: user.avatarUrl);
    }
    return const DIcon(DIcons.users);
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.username, this.url});

  final String username;
  final String? url;

  @override
  Widget build(BuildContext context) => DAvatar(
    size: DAvatarSize.sm,
    decorative: true,
    child: AvatarImage(
      url: url,
      size: DAvatarSize.sm.dimension,
      fallback: DAvatarFallback(
        child: Text(
          username.isEmpty ? '?' : username.characters.first.toUpperCase(),
        ),
      ),
    ),
  );
}
