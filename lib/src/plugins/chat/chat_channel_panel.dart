import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_browse_session.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_inbox_filters.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';

/// What the channel panel is open for.
sealed class ChatChannelPanelMode {
  const ChatChannelPanelMode();
}

/// Every channel the forum lists, each joined or left from its row and
/// narrowed by the chips at the panel's foot. Pressing one opens it.
final class ChatChannelBrowsing extends ChatChannelPanelMode {
  const ChatChannelBrowsing({this.words = ''});

  /// What the field opens holding.
  final String words;
}

/// The channels something is narrowed to, by name alone. The one pressed is
/// the choice.
final class ChatChannelPicking extends ChatChannelPanelMode {
  const ChatChannelPicking({required this.channels, required this.pickedId});

  final List<ChatChannel> channels;

  /// Null while every channel is shown.
  final int? pickedId;
}

/// What a reader picked in the panel: one channel, or every one of them.
@immutable
final class ChatChannelChoice {
  const ChatChannelChoice(this.channel);

  final ChatChannel? channel;
}

/// Opens the panel over [context] to browse every channel.
Future<void> showChatChannelBrowser(
  BuildContext context, {
  required String siteUrl,
  String words = '',
}) => _showPanel<void>(
  context,
  siteUrl: siteUrl,
  title: context.l10n.channels,
  mode: ChatChannelBrowsing(words: words),
);

/// Opens the panel over [context] to pick one of [channels]. Answers null
/// when it is put away with nothing picked.
Future<ChatChannelChoice?> showChatChannelPicker(
  BuildContext context, {
  required String siteUrl,
  required List<ChatChannel> channels,
  required int? pickedId,
}) => _showPanel<ChatChannelChoice>(
  context,
  siteUrl: siteUrl,
  title: context.l10n.channel,
  mode: ChatChannelPicking(channels: channels, pickedId: pickedId),
);

/// What a row's highlight reaches past its words on each side.
const double _rowInset = 9;

Future<T?> _showPanel<T>(
  BuildContext context, {
  required String siteUrl,
  required String title,
  required ChatChannelPanelMode mode,
}) {
  final chat = PluginUiScope.require(context, chatControllerService);
  final shell = PluginUiScope.require(context, chatShellService);
  final touch = context.isTouch;
  return showShellSheet<T>(
    context: context,
    title: title,
    search: true,
    scrollBody: false,
    dialogOnDesktop: true,
    desktopDialogConstraints: const BoxConstraints(
      maxWidth: 380,
      maxHeight: 560,
    ),
    // The rows' words start on the sheet's own edge, their highlight reaching
    // past it, so the sheet stands in by that much less.
    padding: touch
        ? const EdgeInsets.symmetric(horizontal: 15 - _rowInset)
        : const EdgeInsets.fromLTRB(17 - _rowInset, 0, 17 - _rowInset, 8),
    builder: (context) => ChatChannelPanel(
      chat: chat,
      shell: shell,
      siteUrl: siteUrl,
      mode: mode,
    ),
  );
}

/// Shows the channel panel over the Chats page for what could not show it
/// itself: [ChatShellService.openBrowseChannels], and a tab kept from when
/// channels were browsed on a page of their own.
class ChatChannelPanelRequests extends StatefulWidget {
  const ChatChannelPanelRequests({
    super.key,
    required this.siteUrl,
    required this.child,
    this.asked = false,
  });

  final String siteUrl;

  /// Whether the page itself stands for a request, made once.
  final bool asked;
  final Widget child;

  @override
  State<ChatChannelPanelRequests> createState() =>
      _ChatChannelPanelRequestsState();
}

class _ChatChannelPanelRequestsState extends State<ChatChannelPanelRequests> {
  ChatShellService? _shell;
  bool _scheduled = false;
  late bool _asked = widget.asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = PluginUiScope.require(context, chatShellService);
    if (!identical(shell, _shell)) {
      _shell?.channelPanelRequest.removeListener(_take);
      _shell = shell;
      shell.channelPanelRequest.addListener(_take);
    }
    _take();
  }

  @override
  void dispose() {
    _shell?.channelPanelRequest.removeListener(_take);
    super.dispose();
  }

  void _take() {
    final requests = _shell!.channelPanelRequest;
    final request = requests.value;
    final String words;
    if (request != null && request.siteUrl == widget.siteUrl) {
      words = request.words;
    } else if (_asked) {
      words = '';
    } else {
      return;
    }
    if (_scheduled) return;
    _scheduled = true;
    // A request can arrive while this page is being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      _asked = false;
      if (request != null) {
        // Two Chats pages can be on screen. The first to look takes it.
        if (requests.value != request) return;
        requests.value = null;
        if (!request.lease.isCurrent) return;
      }
      unawaited(
        showChatChannelBrowser(context, siteUrl: widget.siteUrl, words: words),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A channel's mark where names are listed to pick from: its # in its colour
/// on nothing, in the slot every row of a menu keeps for a mark. A filled
/// tile is for where it stands among faces.
class ChatChannelMark extends StatelessWidget {
  const ChatChannelMark({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14,
    child: Center(child: DIcon(DIcons.hashtag, size: 13, color: color)),
  );
}

/// Finding a channel, as a panel over wherever it was asked for: by name
/// along its field, then the channels under it.
class ChatChannelPanel extends StatefulWidget {
  const ChatChannelPanel({
    super.key,
    required this.chat,
    required this.shell,
    required this.siteUrl,
    required this.mode,
  });

  final ChatController chat;
  final ChatShellService shell;
  final String siteUrl;
  final ChatChannelPanelMode mode;

  @override
  State<ChatChannelPanel> createState() => _ChatChannelPanelState();
}

class _ChatChannelPanelState extends State<ChatChannelPanel> {
  final _field = FocusNode();
  late final TextEditingController _words;
  ChatBrowseSession? _browse;

  /// The channels whose join or leave is still being answered. Their chips
  /// wait, so a second press cannot ask for the opposite ahead of the answer.
  final _writing = <int>{};

  @override
  void initState() {
    super.initState();
    final mode = widget.mode;
    _words = TextEditingController(
      text: mode is ChatChannelBrowsing ? mode.words : '',
    );
    if (mode is ChatChannelBrowsing) {
      _browse = ChatBrowseSession(
        chat: widget.chat,
        siteUrl: widget.siteUrl,
        query: mode.words,
      )..addListener(_changed);
      unawaited(_browse!.refresh());
    }
    // The dialog takes the focus as it opens, so the field asks for it after.
    // A phone keeps its keyboard down until the field is pressed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !context.isTouch) _field.requestFocus();
    });
  }

  @override
  void dispose() {
    _browse?.dispose();
    _words.dispose();
    _field.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _typed(String words) {
    if (_browse case final browse?) {
      browse.changeQuery(words);
    } else {
      setState(() {});
    }
  }

  /// A size as a page's list has it. A phone's sheet draws all it holds
  /// larger, so there the size is given smaller by as much.
  double _size(double px) => DMenuContentScale.isActiveOf(context)
      ? px / DMenuContentScale.factor
      : px;

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final list = switch (mode) {
      ChatChannelBrowsing() => _browsing(context, _browse!),
      ChatChannelPicking() => _picking(context, mode),
    };
    return Column(
      // A phone's sheet keeps its height as rows come and go. A desktop's
      // dialog is as tall as what it lists.
      mainAxisSize: context.isTouch ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _rowInset),
          child: SheetSearch(
            inputKey: const ValueKey('chat-channel-panel-field'),
            focusNode: _field,
            controller: _words,
            hintText: context.l10n.findAChannel,
            onChanged: _typed,
          ),
        ),
        Flexible(
          child: SheetSearchHold(
            focusNode: _field,
            child: DSheetScrollBody(
              fill: context.isTouch,
              footer: switch (_browse) {
                final browse? => _ChatChannelPanelChips(session: browse),
                null => null,
              },
              child: list,
            ),
          ),
        ),
      ],
    );
  }

  Widget _note(BuildContext context, String text) => Padding(
    key: const ValueKey('chat-channel-panel-note'),
    padding: const EdgeInsets.symmetric(horizontal: _rowInset, vertical: 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: DiscourseTypography.preview,
        height: 1.5,
        color: DTokens.of(context).mutedForeground,
      ),
    ),
  );

  Widget _scroll(List<Widget> rows) => ListView(
    key: const ValueKey('chat-channel-panel-list'),
    shrinkWrap: !context.isTouch,
    padding: const EdgeInsets.only(top: 6),
    children: rows,
  );

  Widget _browsing(BuildContext context, ChatBrowseSession browse) {
    final channels = browse.visibleChannels;
    final words = browse.query.trim();
    if (browse.loading && channels.isEmpty) {
      return _scroll(const [_ChatChannelPanelSkeleton(rows: 4)]);
    }
    final error = browse.error;
    final trailing = <Widget>[
      if (channels.isEmpty && error == null)
        _note(
          context,
          browse.hasMore
              ? context.l10n.noMatchingChannelsLoadedYet
              : words.isEmpty
              ? context.l10n.noChannelsMatchTheseFilters
              : context.l10n.chatNoChannelsMatch(words),
        ),
      if (browse.loadingMore)
        const _ChatChannelPanelSkeleton(rows: 1)
      else if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _rowInset,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text(error),
              DButton(
                key: const ValueKey('chat-channel-panel-retry'),
                label: Text(context.l10n.tryAgain),
                onPressed: () => unawaited(
                  channels.isEmpty && !browse.hasMore
                      ? browse.refresh()
                      : browse.loadMore(retry: true),
                ),
              ),
            ],
          ),
        )
      else
        ScrollPageTrigger(
          enabled: browse.hasMore && !browse.loading,
          onLoad: () => unawaited(browse.loadMore()),
          child: const SizedBox.shrink(),
        ),
    ];
    late final indices = {
      for (var index = 0; index < channels.length; index++)
        channels[index].id: index,
    };
    return ListView.builder(
      key: const ValueKey('chat-channel-panel-list'),
      shrinkWrap: !context.isTouch,
      padding: const EdgeInsets.only(top: 6),
      itemCount: channels.length + trailing.length,
      findChildIndexCallback: (key) =>
          key is ValueKey<int> ? indices[key.value] : null,
      itemBuilder: (context, index) {
        if (index >= channels.length) return trailing[index - channels.length];
        final channel = channels[index];
        return ValueListenableBuilder<ChatChannel?>(
          key: ValueKey(channel.id),
          valueListenable: widget.chat.channelRef(widget.siteUrl, channel.id),
          builder: (context, current, _) => _ChatChannelBrowseRow(
            channel: current ?? channel,
            busy: _writing.contains(channel.id),
            nameSize: _size(DiscourseTypography.rowTitle),
            countSize: _size(DiscourseTypography.xs),
            aboutSize: _size(DiscourseTypography.preview),
            onOpen: () => unawaited(_open(current ?? channel)),
            onFollow: (following) =>
                unawaited(_follow(current ?? channel, following)),
          ),
        );
      },
    );
  }

  Widget _picking(BuildContext context, ChatChannelPicking mode) {
    final tokens = DTokens.of(context);
    final words = _words.text.trim();
    final query = words.toLowerCase();
    final channels = [
      for (final channel in mode.channels)
        if (query.isEmpty || channel.title.toLowerCase().contains(query))
          channel,
    ];
    final nameSize = _size(DiscourseTypography.rowTitle);
    return _scroll([
      if (query.isEmpty)
        _ChatChannelPickRow(
          key: const ValueKey('chat-channel-panel-all'),
          name: context.l10n.allChannels,
          color: tokens.mutedForeground,
          picked: mode.pickedId == null,
          nameSize: nameSize,
          onPressed: () => DDialogClose.close<ChatChannelChoice>(
            context,
            const ChatChannelChoice(null),
          ),
        ),
      for (final channel in channels)
        _ChatChannelPickRow(
          key: ValueKey(('chat-channel-panel-pick', channel.id)),
          name: channel.title,
          color: channel.categoryColor ?? tokens.mutedForeground,
          picked: mode.pickedId == channel.id,
          nameSize: nameSize,
          onPressed: () => DDialogClose.close<ChatChannelChoice>(
            context,
            ChatChannelChoice(channel),
          ),
        ),
      if (channels.isEmpty && query.isNotEmpty)
        _note(context, context.l10n.chatNoChannelsMatch(words)),
    ]);
  }

  Future<void> _open(ChatChannel channel) async {
    final toast = DToast.maybeOf(context);
    final lease = widget.chat.captureSession(widget.siteUrl);
    ChatChannel? resolved;
    try {
      resolved = await widget.chat.ensureChannel(widget.siteUrl, channel.id);
    } catch (_) {
      resolved = null;
    }
    if (!lease.isCurrent) return;
    if (resolved == null) {
      if (toast?.isDisposed == false) {
        toast!.add(
          DToastOptions(
            description: appL10n.couldNotOpenThisChannel,
            type: DToastType.error,
          ),
        );
      }
      return;
    }
    if (mounted) DDialogClose.close<void>(context);
    widget.shell.openChannel(channel.id);
  }

  Future<void> _follow(ChatChannel channel, bool following) async {
    if (!_writing.add(channel.id)) return;
    setState(() {});
    final toast = DToast.maybeOf(context);
    final error = await widget.chat.updateChannelFollowing(
      widget.siteUrl,
      channel,
      following,
    );
    _writing.remove(channel.id);
    if (mounted) setState(() {});
    if (error != null && toast?.isDisposed == false) {
      toast!.add(DToastOptions(description: error, type: DToastType.error));
    }
  }
}

/// As the web app's channel browser has each: beside its mark, its name and
/// how many are in it, and the way in or out of it; then what it is about, in
/// full, across the row.
class _ChatChannelBrowseRow extends StatelessWidget {
  const _ChatChannelBrowseRow({
    required this.channel,
    required this.busy,
    required this.nameSize,
    required this.countSize,
    required this.aboutSize,
    required this.onOpen,
    required this.onFollow,
  });

  final ChatChannel channel;
  final bool busy;
  final double nameSize;
  final double countSize;
  final double aboutSize;
  final VoidCallback onOpen;
  final ValueChanged<bool> onFollow;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final l10n = context.l10n;
    final following = channel.membership.following;
    final canJoin = channel.canJoin && channel.status == ChatChannelStatus.open;
    final status = switch (channel.status) {
      ChatChannelStatus.open => null,
      ChatChannelStatus.readOnly => l10n.readOnly,
      ChatChannelStatus.closed => l10n.closed,
      ChatChannelStatus.archived => l10n.archived,
    };
    final count = [
      countLabel(channel.membershipsCount, CountNoun.member),
      ?status,
    ].join(' · ');
    final about = channel.description?.trim() ?? '';
    return DItem(
      key: ValueKey('chat-channel-panel-channel-${channel.id}'),
      shape: DItemShape.menu,
      padding: const EdgeInsets.symmetric(horizontal: _rowInset, vertical: 8),
      semanticLabel: [
        channel.title,
        count,
        if (about.isNotEmpty) about,
      ].join(', '),
      onPressed: onOpen,
      children: [
        DItemContent(
          spacing: 6,
          alignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: 10,
              children: [
                ChatChannelMark(
                  color: channel.categoryColor ?? tokens.mutedForeground,
                ),
                // One line, the count after the name, so it is what gives
                // way where there is not room for both.
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: channel.title,
                          style: TextStyle(
                            fontSize: nameSize,
                            fontWeight: FontWeight.w600,
                            color: tokens.foreground,
                          ),
                        ),
                        TextSpan(
                          text: '  · $count',
                          style: TextStyle(
                            fontSize: countSize,
                            fontWeight: FontWeight.w400,
                            color: tokens.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // The chip every sheet has, chosen while it offers the way
                // in, as the chips at the foot are while they narrow.
                DToggle(
                  key: ValueKey(
                    following
                        ? 'chat-channel-panel-leave-${channel.id}'
                        : 'chat-channel-panel-join-${channel.id}',
                  ),
                  density: DToggleDensity.menuFilter,
                  variant: DToggleVariant.outline,
                  size: DToggleSize.filter,
                  pressed: !following,
                  enabled: following || canJoin,
                  readOnly: busy,
                  semanticLabel: following
                      ? l10n.chatLeaveChannelNamed(channel.title)
                      : l10n.chatJoinChannelNamed(channel.title),
                  onPressedChanged: (_) => onFollow(!following),
                  child: Text(following ? l10n.leave : l10n.join),
                ),
              ],
            ),
            if (about.isNotEmpty)
              Text(
                about,
                style: TextStyle(
                  fontSize: aboutSize,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                  color: tokens.mutedForeground,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Picking, the name alone is what is being chosen between.
class _ChatChannelPickRow extends StatelessWidget {
  const _ChatChannelPickRow({
    super.key,
    required this.name,
    required this.color,
    required this.picked,
    required this.nameSize,
    required this.onPressed,
  });

  final String name;
  final Color color;
  final bool picked;
  final double nameSize;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return DItem(
      shape: DItemShape.menu,
      padding: const EdgeInsets.symmetric(horizontal: _rowInset, vertical: 6),
      gap: 10,
      selected: picked,
      selectionStyle: DItemSelectionStyle.strongNeutral,
      showSelectionIndicator: false,
      semanticLabel: name,
      onPressed: onPressed,
      children: [
        DItemMedia(child: ChatChannelMark(color: color)),
        DItemContent(
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: nameSize, color: tokens.foreground),
            ),
          ],
        ),
        if (picked)
          DItemMedia(
            child: ExcludeSemantics(
              child: DIcon(DIcons.check, size: 11, color: tokens.primary),
            ),
          ),
      ],
    );
  }
}

/// What narrows the channels browsed, by the thumb at the panel's foot: which
/// of them you are in, then which are still open.
class _ChatChannelPanelChips extends StatelessWidget {
  const _ChatChannelPanelChips({required this.session});

  final ChatBrowseSession session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    DToggleGroup<T> chips<T extends Object>({
      required Key key,
      required String label,
      required T? value,
      required Map<T, String> items,
      required ValueChanged<T?> onChanged,
      required bool allowEmpty,
    }) => DToggleGroup<T>(
      key: key,
      values: [?value],
      onChanged: (values) => onChanged(values.firstOrNull),
      allowEmptySelection: allowEmpty,
      density: DToggleDensity.menuFilter,
      variant: DToggleVariant.outline,
      size: DToggleSize.filter,
      scrollable: false,
      spacing: 1.5,
      semanticLabel: label,
      items: [
        for (final item in items.entries)
          DToggleGroupItem(
            value: item.key,
            semanticLabel: item.value,
            child: Text(item.value),
          ),
      ],
    );

    // Scrolled across as one line. A chip brought into focus brings itself
    // into view, so the line is no stop of its own for the keyboard.
    return DScrollFadeScope(
      horizontalExtent: 28,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: _rowInset, vertical: 8),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              chips<ChatChannelJoinedFilter>(
                key: const ValueKey('chat-channel-panel-membership'),
                label: l10n.membership,
                value: session.membership,
                allowEmpty: false,
                items: {
                  ChatChannelJoinedFilter.all: l10n.all,
                  ChatChannelJoinedFilter.joined: l10n.joined,
                  ChatChannelJoinedFilter.notJoined: l10n.notJoined,
                },
                onChanged: (value) => session.changeMembership(value!),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: DTokens.of(context).border,
                ),
              ),
              // Pressing the one chosen lets every status back in.
              chips<ChatChannelBrowseStatus>(
                key: const ValueKey('chat-channel-panel-status'),
                label: l10n.status,
                value: session.status == ChatChannelBrowseStatus.all
                    ? null
                    : session.status,
                allowEmpty: true,
                items: {
                  ChatChannelBrowseStatus.open: l10n.open,
                  ChatChannelBrowseStatus.closed: l10n.closed,
                  ChatChannelBrowseStatus.archived: l10n.archived,
                },
                onChanged: (value) =>
                    session.changeStatus(value ?? ChatChannelBrowseStatus.all),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatChannelPanelSkeleton extends StatelessWidget {
  const _ChatChannelPanelSkeleton({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    key: const ValueKey('chat-channel-panel-skeleton'),
    semanticsLabel: context.l10n.loading,
    color: skeletonFill(context, on: SkeletonSurface.floating),
    child: Column(
      children: [
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _rowInset,
              vertical: 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                Row(
                  spacing: 10,
                  children: [
                    const DSkeleton(width: 14, height: 14),
                    Expanded(
                      child: FractionallySizedBox(
                        widthFactor: row.isEven ? .6 : .45,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 14),
                      ),
                    ),
                    const DSkeleton(width: 44, height: 22),
                  ],
                ),
                const DSkeleton(height: 12),
              ],
            ),
          ),
      ],
    ),
  );
}
