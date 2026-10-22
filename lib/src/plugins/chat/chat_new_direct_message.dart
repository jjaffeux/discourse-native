import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_direct_message_search.dart';
import 'chat_new_direct_message_session.dart';
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
  // Use the same adaptive presentation as Native dropdown menus. Reserve the
  // opening height so asynchronous search results cannot move the input.
  if (context.isTouch) {
    return showDSheet<void>(
      context: context,
      side: DSheetSide.bottom,
      variant: DSheetVariant.adaptiveMenu,
      sizeToContent: false,
      initialFocusNode: searchFocus,
      barrierLabel: appL10n.dismissStartChatting,
      builder: (context, sheet) => DSheetContent(
        key: const ValueKey('chat-new-direct-message-sheet'),
        side: DSheetSide.bottom,
        variant: DSheetVariant.adaptiveMenu,
        sizeToContent: false,
        semanticLabel: appL10n.startChatting,
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
  late final _editing = ChatNewDirectMessageSession(
    chat: widget.chat,
    siteUrl: widget.siteUrl,
    lease: widget.session,
  );

  bool get _sessionIsCurrent => widget.session.isCurrent;

  @override
  void initState() {
    super.initState();
    _editing.addListener(_editingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _sessionIsCurrent) _searchFocus.requestFocus();
    });
  }

  void _editingChanged() {
    if (_search.text != _editing.searchText) _clearSearch();
    setState(() {});
  }

  @override
  void dispose() {
    _editing.removeListener(_editingChanged);
    _editing.dispose();
    _searchFocus.dispose();
    _command.dispose();
    _search.dispose();
    _groupName.dispose();
    super.dispose();
  }

  void _scheduleSearch(String value) {
    if (!_resettingSearch) _editing.changeQuery(value);
  }

  Future<void> _select(ChatDirectMessageSearchItem item, int revision) async {
    _navigate(await _editing.select(item, revision));
  }

  void _clearSearch() {
    _resettingSearch = true;
    _command.updateQuery('');
    _search.clear();
    _command.highlight(null);
    _resettingSearch = false;
    _searchFocus.requestFocus();
  }

  void _startGroup(int revision) {
    if (_editing.startGroup(revision)) _clearSearch();
  }

  void _cancelGroup() {
    if (!_editing.cancelGroup()) return;
    _clearSearch();
    _groupName.clear();
  }

  Future<void> _createGroup() async {
    _navigate(await _editing.createGroup(_groupName.text));
  }

  void _navigate(ChatNewConversationDestination? destination) {
    if (destination == null ||
        !mounted ||
        !_sessionIsCurrent ||
        (destination.requiresCurrentRoute &&
            ModalRoute.of(context)?.isCurrent != true)) {
      return;
    }
    if (destination.channelId case final channelId?
        when widget.shell.openChannel(channelId)) {
      widget.dialog.close();
    } else {
      _editing.navigationFailed(destination);
    }
  }

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
      if (_editing.composingGroup)
        Flexible(child: DScrollArea(child: _buildGroupFields())),
      // Keyed so the group fields appearing above do not remount the command.
      Expanded(
        key: const ValueKey('chat-destination-command-slot'),
        flex: 2,
        child: _buildCommand(fill: true),
      ),
      ?_buildError(),
      if (_editing.composingGroup)
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
                            _editing.composingGroup
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
            if (_editing.composingGroup) _buildGroupFields(),
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
                          ).scale(_editing.composingGroup ? 420 : 280);
                  return Row(
                    children: [
                      if (showHints) Expanded(child: _keyboardHints()),
                      if (_editing.composingGroup)
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
      _editing.composingGroup ? appL10n.newGroupChat : appL10n.startChatting;

  Widget _closeButton() => DButton.iconOnly(
    icon: const DIcon(DIcons.xmark),
    variant: DButtonVariant.ghost,
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
          enabled: !_editing.opening && _sessionIsCurrent,
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
      backgroundColor: Colors.transparent,
      shouldFilter: false,
      loop: true,
      vimBindings: false,
      loading: _editing.searching || _editing.opening,
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
              enabled: !_editing.opening && _sessionIsCurrent,
              semanticLabel: appL10n.searchChatRecipients,
              placeholder: _editing.composingGroup
                  ? appL10n.searchUsersOrGroups
                  : appL10n.searchUsersGroupsOrChannels,
            ),
          ),
          if (fill) Expanded(child: results) else results,
        ],
      ),
    );
  }

  Widget? _buildError() => switch (_editing.error) {
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
        onPressed: _editing.opening || !_sessionIsCurrent ? null : _cancelGroup,
      ),
      DButton(
        key: const ValueKey('chat-create-group-direct-message'),
        label: Text(appL10n.startGroupChat),
        variant: DButtonVariant.primary,
        loading: _editing.opening,
        onPressed:
            _editing.opening || !_sessionIsCurrent || _editing.members.isEmpty
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
      _keyHint(const [DKbd('↵')], _editing.composingGroup ? 'add' : 'open'),
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
      if (_editing.members.isNotEmpty) ...[
        Wrap(
          spacing: DSpacing.controlGap,
          runSpacing: DSpacing.controlGap,
          children: [
            for (final member in _editing.members)
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
                onPressed: _editing.opening || !_sessionIsCurrent
                    ? null
                    : () {
                        _editing.removeMember(member);
                        _searchFocus.requestFocus();
                      },
              ),
          ],
        ),
        const SizedBox(height: DSpacing.xs),
      ],
      // Core's DM member policy exempts staff, so its bounded hint applies
      // only to people whose selections are actually capped.
      if (!_editing.staff)
        Semantics(
          liveRegion: true,
          child: Text(
            appL10n.ofPeopleSelected(
              (_editing.membersCount).toString(),
              (_editing.maximumGroupMembers).toString(),
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
    final generation = _editing.revision;
    final query = _search.text.trim();
    final results = [
      if (!_editing.opening && !_editing.searching)
        for (final item in _editing.results)
          if (!_editing.composingGroup ||
              (item is! ChatDirectMessageChannel &&
                  !_editing.members.any(
                    (member) => member.identifier == item.identifier,
                  )))
            item,
    ];
    final showNewGroup =
        !_editing.composingGroup &&
        query.isEmpty &&
        _editing.canUseGroupChat &&
        !_editing.opening &&
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
      // adaptive sheet owns its viewport, so its list takes what is left.
      height: fill
          ? double.infinity
          : math.min(288, MediaQuery.sizeOf(context).height / 3),
      semanticLabel: appL10n.chatRecipientsAndConversations,
      children: [
        DCommandLoading(
          child: DSkeletonRegion(
            semanticsLabel: _editing.opening
                ? appL10n.openingConversation
                : appL10n.searching,
            color: skeletonFill(context, on: SkeletonSurface.floating),
            child: Column(
              children: [
                for (var index = 0; index < 3; index++)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: DSpacing.sm,
                      vertical: DSpacing.sm,
                    ),
                    child: Row(
                      spacing: DSpacing.sm,
                      children: [
                        DSkeleton.circle(diameter: 32),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: DSpacing.xs,
                            children: [
                              DSkeleton(height: 16),
                              DSkeleton(width: 100, height: 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        DCommandEmpty(
          child: Text(
            _editing.error != null
                ? appL10n.trySearchingAgain
                : query.isEmpty
                ? _editing.composingGroup
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
                  _startGroup(generation);
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
    final generation = _editing.revision;
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
        !_editing.opening &&
        _sessionIsCurrent &&
        (_editing.composingGroup ? _editing.canAddMember(item) : item.enabled);
    return DCommandItem<String>(
      value: item.identifier,
      enabled: enabled,
      semanticLabel: [
        title,
        detail,
        if (_editing.composingGroup && item.enabled && !enabled)
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
            ? DCommandShortcut(Text(_editing.composingGroup ? '+' : '↵'))
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
