import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
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
}) {
  final session = chat.captureSession(siteUrl);
  final searchFocus = FocusNode(debugLabel: 'Start chatting search');
  Widget content(DDialogController<void> dialog, {required bool sheet}) =>
      _ChatNewDirectMessageDialog(
        siteUrl: siteUrl,
        chat: chat,
        shell: shell,
        session: session,
        dialog: dialog,
        searchFocus: searchFocus,
        sheet: sheet,
      );
  // Touch keeps the search focused, so the picker takes the whole height above
  // the keyboard the same way the emoji picker does.
  if (context.isTouch) {
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      inset: true,
      fillAvailableHeight: true,
      initialFocusNode: searchFocus,
      barrierLabel: appL10n.dismissStartChatting,
      builder: (context, sheet) => DSheetContent(
        key: const ValueKey('chat-new-direct-message-sheet'),
        side: DSheetSide.bottom,
        semanticLabel: appL10n.startChatting,
        topBottomMaxHeightFactor: 1,
        scrollWholeSheet: false,
        showCloseButton: false,
        children: [Expanded(child: content(sheet, sheet: true))],
      ),
    );
  }
  return showDDialog<void>(
    context: context,
    builder: (context, dialog) => content(dialog, sheet: false),
  );
}

class _ChatNewDirectMessageDialog extends StatefulWidget {
  const _ChatNewDirectMessageDialog({
    required this.siteUrl,
    required this.chat,
    required this.shell,
    required this.session,
    required this.dialog,
    required this.searchFocus,
    required this.sheet,
  });

  final String siteUrl;
  final ChatController chat;
  final ChatShellService shell;
  final PluginSiteLease session;
  final DDialogController<void> dialog;

  /// Owned by this state: the route holds it as its initial focus until the
  /// route, and with it this state, is disposed.
  final FocusNode searchFocus;
  final bool sheet;

  @override
  State<_ChatNewDirectMessageDialog> createState() =>
      _ChatNewDirectMessageDialogState();
}

class _ChatNewDirectMessageDialogState
    extends State<_ChatNewDirectMessageDialog> {
  static const _newGroupValue = 'new-group';
  late final _searchFocus = widget.searchFocus;
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
  bool _retired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _showExistingChannels();
    widget.chat.addListener(_sessionChanged);
    _sessionChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sessionIsCurrent) _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    widget.chat.removeListener(_sessionChanged);
    _debounce?.cancel();
    _searchFocus.dispose();
    _command.dispose();
    _search.dispose();
    _groupName.dispose();
    super.dispose();
  }

  bool get _sessionIsCurrent => widget.session.isCurrent;

  void _sessionChanged() {
    if (_sessionIsCurrent || _retired || !mounted) return;
    _debounce?.cancel();
    _generation++;
    setState(() {
      _retired = true;
      _searching = false;
      _opening = false;
      _error = appL10n.yourConnectionChangedReopenTheActionAndTryAgain;
    });
  }

  bool _checkSession() {
    if (!mounted) return false;
    if (_sessionIsCurrent) return true;
    _sessionChanged();
    return false;
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
    final channels = [
      ...widget.chat.directChannels(widget.siteUrl),
      ...widget.chat.publicChannels(widget.siteUrl),
    ];
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
    if (_resettingSearch || !_checkSession() || _opening) return;
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
      if (!_checkSession()) return;
      try {
        final answer = await widget.chat.searchDirectMessages(
          widget.siteUrl,
          query,
          includeGroups: _canUseGroupChat,
          includeDirectMessageChannels: !_composingGroup,
          includeCategoryChannels: !_composingGroup,
        );
        if (!mounted || !_sessionIsCurrent || generation != _generation) return;
        setState(() {
          _searching = false;
          _results = answer.items;
        });
      } catch (error) {
        if (!mounted || !_sessionIsCurrent || generation != _generation) return;
        setState(() {
          _searching = false;
          _error = _messageFor(error, fallback: appL10n.couldNotSearchChat);
        });
      }
    });
  }

  bool _acceptsResult(int generation) =>
      _checkSession() && !_opening && !_searching && generation == _generation;

  Future<void> _select(ChatDirectMessageSearchItem item, int generation) async {
    if (!_acceptsResult(generation) || !item.enabled) return;
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
        setState(() => _error = appL10n.thisConversationIsNoLongerAvailable);
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
      if (!mounted ||
          !_sessionIsCurrent ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (channel != null && widget.shell.openChannel(channel.id)) {
        widget.dialog.close();
      } else {
        setState(() {
          _opening = false;
          _error = appL10n.thisConversationIsNoLongerAvailable;
        });
      }
    } catch (error) {
      if (!mounted || !_sessionIsCurrent) return;
      setState(() {
        _opening = false;
        _error = _messageFor(error, fallback: appL10n.couldNotStartThisChat);
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
    if (!_checkSession() || !_canUseGroupChat || _opening) return;
    if (initialMembers.any((member) => !_canAddMember(member))) {
      setState(() {
        _error = appL10n.aGroupChatCanIncludeUpToPeople(
          (_maximumGroupMembers).toString(),
        );
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
    if (!_checkSession()) return;
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
    if (!_checkSession() ||
        item is ChatDirectMessageChannel ||
        _members.any((member) => member.identifier == item.identifier)) {
      return;
    }
    if (!_canAddMember(item)) {
      setState(() {
        _error = appL10n.aGroupChatCanIncludeUpToPeople(
          (_maximumGroupMembers).toString(),
        );
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
    if (!_checkSession()) return;
    setState(() {
      _members.removeWhere((member) => member.identifier == item.identifier);
      _error = null;
    });
  }

  Future<void> _createGroup() async {
    if (!_checkSession() ||
        _opening ||
        _members.isEmpty ||
        _membersCount > _maximumGroupMembers) {
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
      if (!mounted ||
          !_sessionIsCurrent ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (channel != null && widget.shell.openChannel(channel.id)) {
        widget.dialog.close();
      } else {
        setState(() {
          _opening = false;
          _error = appL10n.thisConversationIsNoLongerAvailable;
        });
      }
    } catch (error) {
      if (!mounted || !_sessionIsCurrent) return;
      setState(() {
        _opening = false;
        _error = _messageFor(error, fallback: appL10n.couldNotCreateThisGroup);
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
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      newDirectMessageShortcutForPlatform(Theme.of(context).platform):
          widget.dialog.close,
    },
    child: widget.sheet ? _buildSheet() : _buildDialog(),
  );

  Widget _buildSheet() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DSpacing.lg,
          vertical: DSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(child: DSheetTitle(child: Text(_title))),
            _closeButton(),
          ],
        ),
      ),
      if (_composingGroup) _buildGroupFields(),
      // Keyed so the group fields appearing above do not remount the command.
      Expanded(
        key: const ValueKey('chat-destination-command-slot'),
        child: _buildCommand(fill: true),
      ),
      ?_buildError(),
      if (_composingGroup)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DSpacing.lg,
            DSpacing.sm,
            DSpacing.lg,
            0,
          ),
          child: _groupActions(),
        ),
    ],
  );

  Widget _buildDialog() {
    final tokens = DTokens.of(context);
    final desktop = !context.isTouch;
    return DDialogContent(
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
                        DDialogTitle(child: Text(_title)),
                        DDialogDescription(
                          child: Text(
                            _composingGroup
                                ? appL10n.bringAFewPeopleIntoTheConversation
                                : appL10n.pickUpAConversationOrFindSomeoneNew,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DSpacing.sm),
                  _closeButton(),
                ],
              ),
            ),
            if (_composingGroup) _buildGroupFields(),
            _buildCommand(fill: false),
            ?_buildError(),
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
                        Expanded(child: _groupActions())
                      else if (showHints)
                        _keyHint([DKbd(appL10n.esc)], 'close')
                      else
                        Expanded(
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: DButton(
                              label: Text(appL10n.cancel),
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
    );
  }

  String get _title =>
      _composingGroup ? appL10n.newGroupChat : appL10n.startChatting;

  Widget _closeButton() => DButton.iconOnly(
    icon: const DIcon(DIcons.xmark),
    variant: DButtonVariant.transparentBackground,
    onPressed: widget.dialog.close,
    tooltip: appL10n.close,
    semanticLabel: appL10n.closeStartChatting,
  );

  Widget _buildGroupFields() => Padding(
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
          enabled: !_opening && _sessionIsCurrent,
          hintText: appL10n.groupNameOptional,
          semanticLabel: appL10n.groupNameOptional,
        ),
        const SizedBox(height: DSpacing.sm),
        _buildMembers(),
      ],
    ),
  );

  Widget _buildCommand({required bool fill}) {
    final results = _buildResults(fill: fill);
    return DCommand<String>(
      key: const ValueKey('chat-destination-command'),
      controller: _command,
      backgroundColor: widget.sheet
          ? DTokens.of(context).background.withValues(alpha: 1)
          : null,
      shouldFilter: false,
      loop: true,
      vimBindings: false,
      loading: _searching || _opening,
      semanticLabel: appL10n.chatDestinations,
      onQueryChanged: _scheduleSearch,
      child: Column(
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: DSpacing.md),
            child: DCommandInput<String>(
              key: const ValueKey('chat-new-direct-message-search'),
              controller: _search,
              focusNode: _searchFocus,
              enabled: !_opening && _sessionIsCurrent,
              semanticLabel: appL10n.searchChatRecipients,
              placeholder: _composingGroup
                  ? appL10n.searchUsersOrGroups
                  : appL10n.searchUsersGroupsOrChannels,
            ),
          ),
          if (fill) Expanded(child: results) else results,
        ],
      ),
    );
  }

  Widget? _buildError() => switch (_error) {
    final error? => Padding(
      padding: const EdgeInsets.all(DSpacing.md),
      child: DAlert(
        key: const ValueKey('chat-new-direct-message-error'),
        variant: DAlertVariant.destructive,
        description: DAlertDescription(child: Text(error)),
      ),
    ),
    null => null,
  };

  Widget _groupActions() => Wrap(
    alignment: WrapAlignment.end,
    spacing: DSpacing.controlGap,
    runSpacing: DSpacing.sm,
    children: [
      DButton(
        label: Text(appL10n.back),
        variant: DButtonVariant.outline,
        onPressed: _opening || !_sessionIsCurrent ? null : _cancelGroup,
      ),
      DButton(
        key: const ValueKey('chat-create-group-direct-message'),
        label: Text(appL10n.startGroupChat),
        variant: DButtonVariant.primary,
        loading: _opening,
        onPressed: _opening || !_sessionIsCurrent || _members.isEmpty
            ? null
            : () => unawaited(_createGroup()),
      ),
    ],
  );

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
                semanticLabel: appL10n.removeChatnewdirectmessage(
                  (_memberLabel(member)).toString(),
                ),
                onPressed: _opening || !_sessionIsCurrent
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
          appL10n.ofPeopleSelected(
            (_membersCount).toString(),
            (_maximumGroupMembers).toString(),
          ),
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

  Widget _buildResults({required bool fill}) {
    final generation = _generation;
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
        !_composingGroup &&
        query.isEmpty &&
        _canUseGroupChat &&
        !_opening &&
        _sessionIsCurrent;
    // Keep the server's relevance order, including across result types.
    final groups = <({String heading, List<DCommandItem<String>> items})>[];
    for (final item in results) {
      final heading = switch (item) {
        ChatDirectMessageUser() => appL10n.people,
        ChatDirectMessageGroup() => appL10n.groups,
        ChatDirectMessageChannel() when query.isEmpty =>
          appL10n.recentConversations,
        ChatDirectMessageChannel(:final channel) =>
          channel.isDirectMessage ? appL10n.conversations : appL10n.channels,
      };
      if (groups.isEmpty || groups.last.heading != heading) {
        groups.add((heading: heading, items: []));
      }
      groups.last.items.add(_result(item));
    }
    return DCommandList<String>(
      key: const ValueKey('chat-new-direct-message-results'),
      // Results are replaced on every keystroke; a fixed height keeps the
      // dialog, its input and its footer from moving while typing. A third of
      // the window keeps the group footer on screen in short windows. The
      // sheet is already fixed by the keyboard, so its list takes what is left.
      height: fill
          ? double.infinity
          : math.min(288, MediaQuery.sizeOf(context).height / 3),
      semanticLabel: appL10n.chatRecipientsAndConversations,
      children: [
        DCommandLoading(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: DSpacing.sm,
            children: [
              Text(_opening ? appL10n.openingConversation : appL10n.searching),
            ],
          ),
        ),
        DCommandEmpty(
          child: Text(
            _error != null
                ? appL10n.trySearchingAgain
                : query.isEmpty
                ? _composingGroup
                      ? appL10n.searchForPeopleOrGroupsToAdd
                      : appL10n.searchForAUserToStartADirectMessage
                : appL10n.noMatchesFoundTryAnotherNameOrUsername,
            textAlign: TextAlign.center,
          ),
        ),
        if (showNewGroup) ...[
          DCommandGroup<String>(
            items: [
              DCommandItem<String>(
                value: _newGroupValue,
                leading: const DIcon(DIcons.plus),
                child: Text(
                  appL10n.createAGroupChat,
                  key: const ValueKey('chat-new-group-direct-message'),
                ),
                onSelected: (_) {
                  if (_acceptsResult(generation)) _startGroup();
                },
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
    final generation = _generation;
    final (key, title, detail, leading) = switch (item) {
      final ChatDirectMessageUser user => (
        'chat-new-direct-message-user-${user.username}',
        user.name ?? user.username,
        !user.enabled ? appL10n.chatIsDisabledForThisUser : '@${user.username}',
        _ChatAvatar(username: user.username, url: user.avatarUrl),
      ),
      final ChatDirectMessageGroup group => (
        'chat-new-direct-message-group-${group.name}',
        group.fullName ?? group.name,
        !group.enabled
            ? appL10n.thisGroupCannotBeAddedToChat
            : countLabel(group.memberCount, CountNoun.person),
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
        !_opening &&
        _sessionIsCurrent &&
        (_composingGroup ? _canAddMember(item) : item.enabled);
    return DCommandItem<String>(
      value: item.identifier,
      enabled: enabled,
      semanticLabel: [
        title,
        detail,
        if (_composingGroup && item.enabled && !enabled)
          appL10n.groupMemberLimitReached,
      ].where((part) => part.isNotEmpty).join('. '),
      // Command owns its surface key; keep the app's interaction key on content.
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: DSpacing.xs),
        child: leading,
      ),
      trailing: AnimatedBuilder(
        animation: _command,
        builder: (context, _) =>
            !DControlStyle.isTouch(context) &&
                _command.value == item.identifier &&
                enabled
            ? DCommandShortcut(Text(_composingGroup ? '+' : '↵'))
            : switch (item) {
                ChatDirectMessageChannel(:final channel)
                    when channel.lastMessageAt != null =>
                  RelativeTimeText(channel.lastMessageAt!),
                _ => const Text(''),
              },
      ),
      onSelected: (_) => unawaited(_select(item, generation)),
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
    if (!channel.isDirectMessage) {
      return DIcon(
        channel.readRestricted ? DIcons.lock : DIcons.comment,
        color: channel.categoryColor,
      );
    }
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
