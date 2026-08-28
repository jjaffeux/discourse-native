import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/adaptive_dialog_action.dart';
import '../../shell/loading_skeleton.dart';
import '../../shell/shell_sheet.dart';
import '../../shell/stream_day_separator.dart';
import '../../shell/time_gap.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_channel.dart';
import 'chat_channel_search.dart';
import 'chat_composer.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_message_tile.dart';
import 'chat_pinned_bar.dart';
import 'chat_route.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_stream.dart';
import 'chat_stream_target.dart';

/// One channel's messages, newest at the bottom.
class ChatChannelView extends StatelessWidget {
  const ChatChannelView({super.key, required this.channelId});

  final int channelId;

  /// Start fetching the page before this one about a screen from the end of
  /// what is held — the number [TopicView] already settled on, for the same
  /// reason. Under a reversed list this is the distance to the *oldest*
  /// message, which is where the reader is heading.
  static const double _loadOlderThreshold = 900;

  /// Forwards, the reader has to actually reach the end.
  ///
  /// Deliberately not a screen's worth, and the asymmetry is the whole point.
  /// Reading goes backwards, so fetching a screen early is fetching what the
  /// reader is about to want. Forwards is a backlog they have not read yet:
  /// pulling it in early would walk the window to the present on its own and
  /// undo the anchor `ChatController.openChannel` just placed. Discourse draws
  /// the same line — its fill-pane safety net only ever asks for the past, and
  /// the future is fetched from `state.atBottom`.
  static const double _loadNewerThreshold = 50;

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final siteUrl = shell.currentSiteUrl;
        if (siteUrl == null) return const SizedBox.shrink();
        final chat = PluginUiScope.require(context, chatControllerService);
        return _ChatChannelBody(
          key: ValueKey((siteUrl, channelId, chat)),
          siteUrl: siteUrl,
          channelId: channelId,
          showTimeGapDays: shell.showTimeGapDaysFor(siteUrl),
          chat: chat,
        );
      },
    );
  }
}

/// One mounted visit to one channel on one site.
///
/// Keeping the open request here makes returning to a channel refresh it while
/// a shell notification that changes neither site nor controller leaves the
/// message tree alone.
class _ChatChannelBody extends StatefulWidget {
  const _ChatChannelBody({
    super.key,
    required this.siteUrl,
    required this.channelId,
    required this.showTimeGapDays,
    required this.chat,
  });

  final String siteUrl;
  final int channelId;
  final int showTimeGapDays;
  final ChatController chat;

  @override
  State<_ChatChannelBody> createState() => _ChatChannelBodyState();
}

class _ChatChannelBodyState extends State<_ChatChannelBody> {
  Object? _viewToken;
  Listenable? _navigation;
  bool _opened = false;
  List<int>? _projectedMessageIds;
  List<int>? _projectedLocalMessageIds;
  int? _projectedLastRead;
  int? _projectedRevision;
  int? _projectedShowTimeGapDays;
  List<ChatStreamItem> _items = const [];
  int? _highlightMessageId;
  int _highlightRequest = 0;
  bool _selectingMessages = false;
  final Set<int> _selectedMessageIds = {};
  ChatMessage? _editingMessage;
  final ChatUploadDropController _uploadDropController =
      ChatUploadDropController();

  @override
  void initState() {
    super.initState();
    // In the expanded thread workspace the channel header is an earlier
    // sibling and already listens to this channel record. Starting the visit
    // synchronously would advance lastViewedAt while that sibling is still
    // building. Register the visible visit after the first frame so every
    // channel-record listener sees that change at a legal frame boundary.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _viewToken = widget.chat.beginViewingChannel(
        widget.siteUrl,
        widget.channelId,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final navigation = PluginUiScope.require(
      context,
      chatShellService,
    ).navigation;
    if (identical(navigation, _navigation)) return;
    _navigation?.removeListener(_consumeNavigation);
    _navigation = navigation;
    navigation.addListener(_consumeNavigation);
    if (!_consumeNavigation() && !_opened) {
      _opened = true;
      unawaited(widget.chat.openChannel(widget.siteUrl, widget.channelId));
    }
  }

  bool _consumeNavigation() {
    if (!mounted) return false;
    final pending = PluginUiScope.require(context, chatShellService).navigation
        .take(
          siteUrl: widget.siteUrl,
          route: ChatRoute.channel(widget.channelId),
        );
    if (pending == null) return false;

    _opened = true;
    if (pending.messageId case final messageId?) {
      setState(() {
        _highlightMessageId = messageId;
        _highlightRequest++;
      });
    }
    unawaited(
      widget.chat.openChannel(
        widget.siteUrl,
        widget.channelId,
        targetMessageId: pending.messageId,
        force: true,
      ),
    );
    return true;
  }

  @override
  void dispose() {
    _navigation?.removeListener(_consumeNavigation);
    final viewToken = _viewToken;
    if (viewToken != null) {
      widget.chat.endViewingChannel(
        widget.siteUrl,
        widget.channelId,
        viewToken,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.chat.channelRef(widget.siteUrl, widget.channelId),
      builder: (context, channel, _) => ValueListenableBuilder<ChatStreamState>(
        valueListenable: widget.chat.streamListenable(
          widget.siteUrl,
          widget.channelId,
        ),
        builder: (context, stream, _) => _buildChannel(
          stream,
          channel: channel,
          channelTitle: channel?.title ?? 'Chat',
          canCreateThread:
              channel?.threadingEnabled == true &&
              widget.chat.canSendMessageTo(
                widget.siteUrl,
                ChatChannelTarget(widget.channelId),
              ),
        ),
      ),
    );
  }

  Widget _buildChannel(
    ChatStreamState stream, {
    required ChatChannel? channel,
    required String channelTitle,
    required bool canCreateThread,
  }) {
    late final Widget content;
    final hasMessages =
        stream.messageIds.isNotEmpty || stream.localMessageIds.isNotEmpty;
    if (hasMessages) {
      // A send can be staged while the first page is still loading, or after
      // that page failed. The local row is useful state in either case and
      // must not be hidden behind the page-level loading/error state.
      _syncProjection(stream);
      content = ChatMessageStream(
        siteUrl: widget.siteUrl,
        target: ChatChannelTarget(widget.channelId),
        items: _items,
        stream: stream,
        highlightMessageId: _highlightMessageId,
        highlightRequest: _highlightRequest,
        onHighlightComplete: _clearHighlight,
        onOpenThread: (preview) =>
            _openThread(context, widget.siteUrl, widget.channelId, preview),
        onJumpToMessage: _jumpToMessage,
        canCreateThread: canCreateThread,
        onReplyInThread: (message) => _replyInThread(context, message),
        onEdit: _editMessage,
        selectingMessages: _selectingMessages,
        selectedMessageIds: _selectedMessageIds,
        onStartSelecting: _startSelecting,
        onSelectionChanged: _setMessageSelected,
      );
    } else if (stream.loading) {
      content = const _ChatLoadingSkeleton(
        key: ValueKey('chat-loading-skeleton'),
      );
    } else if (stream.error case final error?) {
      content = _Message(icon: DIcons.triangleExclamation, text: error);
    } else if (stream.isEmpty) {
      content = const _Message(
        icon: DIcons.comment,
        text: 'No messages here yet.',
      );
    } else {
      content = const SizedBox.shrink();
    }

    return ChatUploadDropRegion(
      controller: _uploadDropController,
      title: 'Drop images to upload to #$channelTitle',
      child: Column(
        children: [
          ChatChannelSearchBar(
            siteUrl: widget.siteUrl,
            channelId: widget.channelId,
          ),
          if (channel?.hasPinnedMessages == true)
            ChatPinnedBar(
              siteUrl: widget.siteUrl,
              channel: channel!,
              chat: widget.chat,
              onJumpToMessage: _jumpToMessage,
            ),
          Expanded(child: content),
          if (_selectingMessages)
            ChatMessageSelectionBar(
              siteUrl: widget.siteUrl,
              channelId: widget.channelId,
              messageIds: _selectedMessageIds,
              chat: widget.chat,
              onCancel: _cancelSelecting,
            )
          else if (stream.error == null || hasMessages)
            ChatComposer(
              key: ValueKey((widget.siteUrl, widget.channelId, 'composer')),
              siteUrl: widget.siteUrl,
              channelId: widget.channelId,
              uploadDropController: _uploadDropController,
              editingMessage: _editingMessage,
              onEditFinished: _finishEditing,
            ),
        ],
      ),
    );
  }

  void _startSelecting(int messageId) {
    setState(() {
      _selectingMessages = true;
      _selectedMessageIds.add(messageId);
    });
  }

  void _editMessage(ChatMessage message) {
    setState(() => _editingMessage = message);
  }

  void _finishEditing() {
    if (_editingMessage != null) setState(() => _editingMessage = null);
  }

  void _setMessageSelected(int messageId, bool selected) {
    setState(() {
      if (selected) {
        _selectedMessageIds.add(messageId);
      } else {
        _selectedMessageIds.remove(messageId);
      }
    });
  }

  void _cancelSelecting() {
    setState(() {
      _selectingMessages = false;
      _selectedMessageIds.clear();
    });
  }

  void _clearHighlight(int request) {
    if (!mounted || request != _highlightRequest) return;
    setState(() => _highlightMessageId = null);
  }

  void _jumpToMessage(int messageId) {
    setState(() {
      _highlightMessageId = messageId;
      _highlightRequest++;
    });
    unawaited(
      widget.chat.openChannel(
        widget.siteUrl,
        widget.channelId,
        targetMessageId: messageId,
        force: true,
      ),
    );
  }

  Future<void> _replyInThread(BuildContext context, ChatMessage message) async {
    final shell = PluginUiScope.require(context, chatShellService);
    final existing = message.thread;
    if (existing != null) {
      shell.openThread(
        siteUrl: widget.siteUrl,
        channelId: widget.channelId,
        threadId: existing.threadId,
        messageId: existing.lastReplyId,
        focusComposer: true,
      );
      return;
    }

    final channel = widget.chat.channel(widget.siteUrl, widget.channelId);
    if (channel?.threadingEnabled != true ||
        !widget.chat.canSendMessageTo(
          widget.siteUrl,
          ChatChannelTarget(widget.channelId),
        )) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('You cannot start a thread here.')),
        );
      }
      return;
    }

    final created = await widget.chat.createThread(
      widget.siteUrl,
      channelId: widget.channelId,
      originalMessageId: message.id,
    );
    if (!mounted || !context.mounted) return;
    if (created == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not start this thread. Try again.'),
        ),
      );
      return;
    }
    shell.openThread(
      siteUrl: widget.siteUrl,
      channelId: widget.channelId,
      threadId: created.id,
      focusComposer: true,
    );
  }

  void _openThread(
    BuildContext context,
    String siteUrl,
    int channelId,
    ChatThreadPreview preview,
  ) {
    final shell = PluginUiScope.require(context, chatShellService);
    shell.openThread(
      siteUrl: siteUrl,
      channelId: channelId,
      threadId: preview.threadId,
      messageId: preview.lastReplyId,
    );
  }

  void _syncProjection(ChatStreamState stream) {
    // Paging toggles loading flags before and after each request while keeping
    // the same immutable id list. Deriving every grouped row again for those
    // flag-only states turns each page into repeated work over the whole
    // history accumulated so far.
    if (identical(_projectedMessageIds, stream.messageIds) &&
        identical(_projectedLocalMessageIds, stream.localMessageIds) &&
        _projectedLastRead == stream.lastReadOnOpen &&
        _projectedRevision == stream.revision &&
        _projectedShowTimeGapDays == widget.showTimeGapDays) {
      return;
    }

    final extended = _extendProjectionIntoPast(stream);
    if (!extended) {
      final messages = widget.chat.messages(widget.siteUrl, widget.channelId);
      // The stream's snapshot rather than the membership's live answer:
      // reading moves the membership under the reader, and a divider that
      // followed it would slide away as they scrolled. See
      // `ChatStreamState.lastReadOnOpen`.
      _items = buildChatStream(
        messages,
        lastReadMessageId: stream.lastReadOnOpen,
        showTimeGapDays: widget.showTimeGapDays,
      );
    }

    _projectedMessageIds = stream.messageIds;
    _projectedLocalMessageIds = stream.localMessageIds;
    _projectedLastRead = stream.lastReadOnOpen;
    _projectedRevision = stream.revision;
    _projectedShowTimeGapDays = widget.showTimeGapDays;
  }

  /// Projects an older page without walking the accumulated history again.
  ///
  /// A past page is a prefix of the canonical id list. Grouping only needs the
  /// page and the first old non-deleted message: that row closes a deleted run
  /// and gives the projection a stable seam. Other changes (a fresh window,
  /// live message, forward page, or optimistic row) take the full fallback in
  /// [_syncProjection].
  bool _extendProjectionIntoPast(ChatStreamState stream) {
    final previous = _projectedMessageIds;
    if (previous == null || previous.isEmpty) return false;
    if (!identical(_projectedLocalMessageIds, stream.localMessageIds) ||
        _projectedLastRead != stream.lastReadOnOpen ||
        _projectedRevision != stream.revision ||
        _projectedShowTimeGapDays != widget.showTimeGapDays) {
      return false;
    }

    final added = stream.messageIds.length - previous.length;
    if (added <= 0 ||
        stream.messageIds[added] != previous.first ||
        stream.messageIds.last != previous.last) {
      return false;
    }

    final prepended = <ChatMessage>[];
    for (var index = 0; index < added; index++) {
      final message = _message(stream.messageIds[index]);
      if (message == null) return false;
      prepended.add(message);
    }

    final existingLeading = <ChatMessage>[];
    for (final id in previous) {
      final message = _message(id);
      if (message == null) return false;
      existingLeading.add(message);
      if (!message.isDeleted) break;
    }

    final projected = prependChatStream(
      existingItems: _items,
      prepended: prepended,
      existingLeading: existingLeading,
      lastReadMessageId: stream.lastReadOnOpen,
      newestMessageId:
          stream.localMessageIds.lastOrNull ?? stream.messageIds.lastOrNull,
      showTimeGapDays: widget.showTimeGapDays,
    );
    if (projected == null) return false;
    _items = projected;
    return true;
  }

  ChatMessage? _message(int id) =>
      widget.chat.messageRef(widget.siteUrl, id).value;
}

/// The list itself.
///
/// Split from the state above so that the arithmetic of a reversed viewport
/// sits in one place with the comment explaining it, rather than inside a
/// build method that is also deciding between four screens.
///
/// Stateful for one reason: reading is a thing the viewport does, so "what has
/// the reader seen" can only be answered from here. That answer, debounced, is
/// what `ChatController.markRead` is given.
class ChatMessageStream extends StatefulWidget {
  const ChatMessageStream({
    super.key,
    required this.siteUrl,
    required this.target,
    required this.items,
    required this.stream,
    this.highlightMessageId,
    this.highlightRequest = 0,
    this.onHighlightComplete,
    this.onOpenThread,
    this.onJumpToMessage,
    this.onReplyInThread,
    this.onEdit,
    this.canCreateThread = false,
    this.showThreadSummaries = true,
    this.selectingMessages = false,
    this.selectedMessageIds = const {},
    this.onStartSelecting,
    this.onSelectionChanged,
  });

  final String siteUrl;
  final ChatStreamTarget target;
  final List<ChatStreamItem> items;
  final ChatStreamState stream;
  final int? highlightMessageId;

  /// A new explicit navigation request, even when it targets the same message.
  final int highlightRequest;
  final ValueChanged<int>? onHighlightComplete;
  final ValueChanged<ChatThreadPreview>? onOpenThread;
  final ValueChanged<int>? onJumpToMessage;
  final ValueChanged<ChatMessage>? onReplyInThread;
  final ValueChanged<ChatMessage>? onEdit;
  final bool canCreateThread;
  final bool showThreadSummaries;
  final bool selectingMessages;
  final Set<int> selectedMessageIds;
  final ValueChanged<int>? onStartSelecting;
  final void Function(int messageId, bool selected)? onSelectionChanged;

  int get channelId => target.channelId;

  @override
  State<ChatMessageStream> createState() => _StreamState();
}

class _StreamState extends State<ChatMessageStream>
    with WidgetsBindingObserver {
  /// How long the viewport has to hold still before the reader is credited
  /// with what is on it. Discourse's own `READ_INTERVAL_MS`, and the number
  /// matters in both directions: a scroll that fires a write per frame would
  /// be a request per frame, and one that waited for the scroll to *end* would
  /// never credit a reader who keeps a channel open and idle.
  static const Duration _readInterval = Duration(milliseconds: 500);
  static const EdgeInsets _streamPadding = EdgeInsets.symmetric(vertical: 8);

  /// Asked for the visible range, and the reason the list is measured at all.
  final ListController _list = ListController();

  /// Needed alongside it because landing on a message is a scroll, and
  /// `jumpToItem` translates one into the other.
  final ScrollController _scroll = ScrollController();

  Timer? _readTimer;
  DateTime? _readTimerStartedAt;
  Duration _readTimeRemaining = _readInterval;
  bool _readDwellPending = false;

  /// The newest message the reader has had on screen since the last write,
  /// with the channel it belongs to — which the reader can leave before the
  /// timer fires, and a message id means nothing without it.
  ({String siteUrl, ChatStreamTarget target, int messageId})? _seen;

  /// The window this has already positioned itself against, as
  /// `(site, channel, ChatStreamState.fetches)`. Null means the next frame has
  /// to land somewhere deliberate.
  ({String siteUrl, ChatStreamTarget target, int fetches})? _anchored;

  /// Whether the reader has scrolled away from the present, which is what puts
  /// the jump-to-now button on screen. Held rather than read from the position
  /// on every build because it changes far less often than a scroll does.
  bool _awayFromPresent = false;
  int _unseenLiveMessages = 0;
  DateTime? _floatingDay;
  double _floatingDayOffset = 0;
  int? _highlightMessageId;
  int? _pendingHighlightMessageId;
  int? _handledHighlightRequest;
  Timer? _highlightTimer;

  /// True from the moment an anchor starts moving the list until the frame
  /// that lays the result out.
  ///
  /// Load-bearing, not tidiness. `jumpTo` dispatches its scroll notification
  /// *synchronously*, before anything is laid out, so the range the list can
  /// report while this is set still describes where the reader was — which,
  /// on an open, is the live edge the anchor is moving them away from. Reading
  /// it would credit them with the whole backlog in the one frame before the
  /// anchor takes effect. Discourse guards the same window with
  /// `_ignoreNextScroll`.
  bool _anchoring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _list.addListener(_noteExtentsChanged);
    _acceptHighlightRequest();
    _scheduleLook();
  }

  @override
  void didUpdateWidget(ChatMessageStream oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changedStream =
        oldWidget.target != widget.target ||
        oldWidget.siteUrl != widget.siteUrl;

    // A route/pane transition before the dwell completes is not a read. Clear
    // the old target rather than flushing it during teardown.
    if (changedStream) {
      _cancelReadDwell();
      _seen = null;
      _anchored = null;
      _filled = null;
      _anchoring = false;
      _awayFromPresent = false;
      _unseenLiveMessages = 0;
      _floatingDay = null;
      _floatingDayOffset = 0;
      _clearHighlight(notify: false);
    }

    if (changedStream ||
        oldWidget.highlightRequest != widget.highlightRequest) {
      _acceptHighlightRequest();
    }

    if (!changedStream &&
        _awayFromPresent &&
        oldWidget.stream.fetches == widget.stream.fetches &&
        oldWidget.stream.atPresent &&
        widget.stream.atPresent &&
        oldWidget.stream.newestId != widget.stream.newestId) {
      // Within one fetch generation an at-present window only ever gains
      // ids, so the growth is the count of live arrivals — no need to build
      // an O(n) set difference per incoming message.
      _unseenLiveMessages +=
          widget.stream.messageIds.length - oldWidget.stream.messageIds.length;
    }

    _holdStillThroughForwardPage(oldWidget);
    _scheduleLook();
  }

  /// Keeps the reader on the message they were reading when a page towards the
  /// present lands.
  ///
  /// The one direction that moves the ground under them. Older messages take
  /// higher offsets in a reversed viewport, so a page of history lands beyond
  /// where the reader is and moves nothing; a page of newer ones lands *under*
  /// the whole list and pushes it up by its own height, carrying the reader
  /// forward past messages they have not read. Discourse pins the same way —
  /// it remembers the last message it held and scrolls back to it with
  /// `position: "end"` once the page is in.
  void _holdStillThroughForwardPage(ChatMessageStream oldWidget) {
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.target != widget.target) {
      return;
    }
    // A forward page can only land when the old window had more future to
    // load. A window already at the present grows its newest id by live
    // appends instead, and those must not move the reader: the reversed
    // viewport keeps a scrolled-up reader in place on its own, and a reader
    // at the bottom edge sticks to it naturally.
    if (!oldWidget.stream.canLoadMoreFuture) return;
    final was = oldWidget.stream.newestId;
    // A replaced window is not a page, and positions itself: see
    // [_anchorIfFresh].
    if (oldWidget.stream.fetches != widget.stream.fetches) return;
    if (was == null || widget.stream.newestId == was) return;

    final row = _rowOf(was);
    if (row == null) return;

    final identity = (siteUrl: widget.siteUrl, target: widget.target);
    final stream = widget.stream;
    _anchoring = true;
    // After the frame that lays the new rows out, because until then they have
    // no heights for the jump to measure against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.siteUrl != identity.siteUrl ||
          widget.target != identity.target ||
          !identical(widget.stream, stream)) {
        return;
      }
      // At the bottom edge, so the messages that just arrived sit below it
      // waiting to be read rather than above it already missed.
      _landOn(row, alignment: 0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelReadDwell();
    _highlightTimer?.cancel();
    _list.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _acceptHighlightRequest() {
    if (widget.highlightMessageId case final messageId?) {
      _pendingHighlightMessageId = messageId;
    }
  }

  void _startHighlightIfReady() {
    final messageId = _pendingHighlightMessageId;
    if (messageId == null ||
        _handledHighlightRequest == widget.highlightRequest ||
        _rowOf(messageId) == null) {
      return;
    }
    _highlightTimer?.cancel();
    _pendingHighlightMessageId = null;
    _handledHighlightRequest = widget.highlightRequest;
    _highlightMessageId = messageId;
    _highlightTimer = Timer(const Duration(seconds: 2), _clearHighlight);
  }

  void _clearHighlight({bool notify = true}) {
    _highlightTimer?.cancel();
    _highlightTimer = null;
    if (_highlightMessageId == null) return;
    _highlightMessageId = null;
    if (notify && mounted) {
      setState(() {});
      widget.onHighlightComplete?.call(widget.highlightRequest);
    }
  }

  /// Positions and then measures, once the frame that laid the list out is
  /// done.
  ///
  /// Scrolling is not enough on its own to measure: a channel with four
  /// messages in it never scrolls, and a reader who opens one and reads it has
  /// still read it. This is Discourse's `didResizePane`, arriving by the one
  /// route Flutter offers — the frame in which the list has extents to report.
  void _scheduleLook() {
    if (_lookScheduled) return;
    _lookScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lookScheduled = false;
      if (!mounted) return;
      if (_anchorIfFresh()) return;
      _syncFloatingDay();
      _fillTowardsPresent();
      _noteWhatIsOnScreen();
    });
  }

  bool _lookScheduled = false;

  /// Asks for the page towards the present when the window is too short to
  /// scroll to it.
  ///
  /// The forward twin of the fill-pane net in the builder, and it has to be a
  /// position check rather than a row-built one: a list that fits inside the
  /// viewport has no scroll activity, so it never dispatches the notification
  /// the forward fetch normally rides. Bounded by the same rule that path uses
  /// — the reader has to already be at the present end of what is held — so it
  /// fills the screen and stops, rather than walking the window forward past
  /// messages nobody has read.
  void _fillTowardsPresent() {
    final stream = widget.stream;
    if (!stream.canLoadMoreFuture || !_scroll.hasClients) return;
    if (_scroll.position.pixels > ChatChannelView._loadNewerThreshold) return;

    // Once per state of the window. A page that arrives moves the newest id
    // and earns another ask; one that fails moves nothing, and this runs after
    // every frame — which against a site that is refusing would be a request
    // per frame for as long as the channel is open.
    final asked = (
      siteUrl: widget.siteUrl,
      target: widget.target,
      fetches: stream.fetches,
      newestId: stream.newestId,
    );
    if (_filled == asked) return;
    _filled = asked;

    unawaited(_chat?.loadNewerFor(widget.siteUrl, widget.target));
  }

  ({String siteUrl, ChatStreamTarget target, int fetches, int? newestId})?
  _filled;

  /// Lands the reader where a freshly fetched window says they should be, and
  /// answers whether it did.
  ///
  /// A new window is the one time the scroll offset means nothing: it is a
  /// distance measured against messages that may no longer be in the list. So
  /// an open lands on the last-read message — Discourse's
  /// `scrollToMessageId(lastReadMessageId)`, centred, so the unread messages
  /// fill the screen below it and the read ones give it context above — and a
  /// jump to the present lands at the bottom.
  bool _anchorIfFresh() {
    final stream = widget.stream;
    final token = (
      siteUrl: widget.siteUrl,
      target: widget.target,
      fetches: stream.fetches,
    );
    if (_anchored == token) return false;
    if (!_list.isAttached || !_scroll.hasClients) return false;
    _anchored = token;

    final target = stream.anchorMessageId ?? stream.lastReadOnOpen;
    final index = target == null || target == stream.newestId
        ? null
        : _rowOf(target);

    _anchoring = true;

    if (index == null) {
      // The present, which under a reversed viewport is offset zero. Worth
      // doing rather than assuming: a jump to now replaces the list under a
      // reader who was scrolled into last week, and the offset they were
      // holding would survive into a window that does not go back that far.
      _scroll.jumpTo(0);
      _settleAnchor();
    } else {
      // Centred, which is what `scrollIntoView` falls back to in the helper
      // Discourse routes this through: the messages the reader has not seen
      // fill the screen below the line, and the ones they have give it
      // context above.
      _landOn(index, alignment: 0.5);
    }

    // Seeded rather than measured, for the reason [_anchoring] gives. Landing
    // is the one moment the honest answer is known without looking: the reader
    // is at the message they were put on.
    final canonicalId = target ?? stream.newestId;
    _cancelReadDwell();
    _seen = canonicalId == null
        ? null
        : (
            siteUrl: widget.siteUrl,
            target: widget.target,
            messageId: canonicalId,
          );
    _syncAwayFromPresent();
    return true;
  }

  /// Puts a row where [alignment] says, and lets go once it is there.
  ///
  /// Twice, because the first jump is measured against estimated heights for
  /// rows that have never been built; once the real ones are laid out it lands
  /// on the same row again. `TopicListView` restores a remembered row the same
  /// way, for the same reason.
  void _landOn(int row, {required double alignment}) {
    final token = _anchored;
    _anchoring = true;
    _jumpToRow(row, alignment);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchored != token) return;
      _jumpToRow(row, alignment);
      _settleAnchor();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// Lets go once the landing has been laid out, and starts the dwell for what
  /// it put in front of the reader.
  ///
  /// Discourse does the same at the end of its own `fetchMessages` — a window
  /// opened half a screen from the end has been read to the bottom of that
  /// screen, and the reader should not have to nudge it to say so.
  void _settleAnchor() {
    final token = _anchored;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchored != token) return;
      _anchoring = false;
      _syncFloatingDay();
      _fillTowardsPresent();
      if (_seen != null) _startReadDwell(_readInterval);
      _noteWhatIsOnScreen();
    });
    // Asked for rather than assumed. A post-frame callback does not schedule a
    // frame, and a jump that landed exactly where the list already was does
    // not either — which would leave [_anchoring] set for good, and reading
    // never credited again in this channel.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// [alignment] is measured from the leading edge, which under `reverse: true`
  /// is the bottom: zero puts the row against the newest end, one against the
  /// oldest, and a half centres it either way.
  void _jumpToRow(int row, double alignment) {
    if (!_list.isAttached || !_scroll.hasClients) return;
    _list.jumpToItem(
      index: row,
      scrollController: _scroll,
      alignment: alignment,
    );
  }

  /// Remembers the newest message on screen, and starts the clock.
  ///
  /// The clock restarts only when what is on screen has *changed*, which is
  /// the difference between debouncing the reader and debouncing the app: this
  /// runs after every frame the shell redraws, and a timer reset by each of
  /// those would be a timer that never fired on a busy site.
  void _noteWhatIsOnScreen() {
    if (_anchoring) return;

    final messageId = _newestVisibleMessageId();
    if (messageId == null) return;

    final seen = (
      siteUrl: widget.siteUrl,
      target: widget.target,
      messageId: messageId,
    );
    if (seen == _seen) return;
    _seen = seen;
    _startReadDwell(_readInterval);
  }

  void _startReadDwell(Duration duration) {
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readTimeRemaining = duration;
    _readDwellPending = true;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    _readTimerStartedAt = DateTime.now();
    _readTimer = Timer(duration, _creditReaderNow);
  }

  void _pauseReadDwell() {
    final timer = _readTimer;
    final startedAt = _readTimerStartedAt;
    if (timer == null || startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = _readTimeRemaining - elapsed;
    _readTimeRemaining = remaining > Duration.zero ? remaining : Duration.zero;
    timer.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
  }

  void _cancelReadDwell() {
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readTimeRemaining = _readInterval;
    _readDwellPending = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_readDwellPending && _seen != null && _readTimer == null) {
        _startReadDwell(_readTimeRemaining);
      }
      return;
    }
    _pauseReadDwell();
  }

  /// Tells the controller what the reader has seen, now rather than on the
  /// timer. Everything about *whether* that turns into a write is
  /// [ChatController.markRead]'s to decide.
  void _creditReaderNow() {
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readDwellPending = false;

    final seen = _seen;
    if (seen == null) return;

    // Discourse asks three questions before crediting anybody — the tab is
    // visible, the window has focus, the reader is present. A phone asks one,
    // and this is it: a timer that lands after the app has gone away would
    // credit a reader who is not looking at anything. Null is a launch that
    // has had no lifecycle message yet, and a test, and both mean "in front".
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _readTimeRemaining = _readInterval;
      return;
    }

    _readTimeRemaining = _readInterval;
    unawaited(_chat?.markReadFor(seen.siteUrl, widget.target, seen.messageId));
  }

  /// How many rows sit before the newest item. The forward-paging skeleton,
  /// when there is one, and this is the only place that number is decided —
  /// everything that turns a row number into an item goes through [_itemAt].
  int get _leadingRows => widget.stream.loadingNewer ? 1 : 0;

  /// The item a row draws, or null for the two pagination-skeleton rows.
  ///
  /// The reversal lives here and nowhere else: row `_leadingRows` is the
  /// *newest* item, and rows count backwards into the past from there.
  ChatStreamItem? _itemAt(int row) {
    final index = row - _leadingRows;
    if (index < 0 || index >= widget.items.length) return null;
    return widget.items[widget.items.length - 1 - index];
  }

  /// The day separators in the current projection, newest-last by row.
  ///
  /// Derived per projection rather than per frame: [_syncFloatingDay] runs on
  /// every scroll notification, and the items list is replaced — never
  /// mutated — so its identity is an exact cache key.
  List<({DateTime day, int row})> _daySeparatorRows() {
    if (identical(_daySeparatorsFor, widget.items) &&
        _daySeparatorsLeadingRows == _leadingRows) {
      return _daySeparators;
    }
    final days = <({DateTime day, int row})>[];
    for (var index = 0; index < widget.items.length; index++) {
      if (widget.items[index] case ChatStreamDay(:final day)) {
        days.add((
          day: day,
          row: _leadingRows + widget.items.length - 1 - index,
        ));
      }
    }
    _daySeparators = days;
    _daySeparatorsFor = widget.items;
    _daySeparatorsLeadingRows = _leadingRows;
    _dayExtentSums = null;
    return days;
  }

  List<({DateTime day, int row})> _daySeparators = const [];
  List<ChatStreamItem>? _daySeparatorsFor;
  int _daySeparatorsLeadingRows = 0;

  /// Cumulative extent through each separator row, valid until the list
  /// re-measures something. The list controller notifies exactly when an
  /// extent is modified during layout, so scroll frames over already-measured
  /// rows — every frame of a steady reading scroll, and every live-message
  /// tick while parked — reuse the sums instead of re-walking the window.
  Map<int, double>? _dayExtentSums;

  void _noteExtentsChanged() => _dayExtentSums = null;

  /// Pins the date whose messages currently cross the top of the viewport.
  ///
  /// Chat's list is reversed: row zero is at the bottom and larger rows head
  /// into the past. A separator's normal top is therefore measured from the
  /// bottom of the viewport. Once that top has passed above zero, its date
  /// floats until the next (newer) separator pushes it out.
  void _syncFloatingDay() {
    if (!_list.isAttached || !_scroll.hasClients) return;

    final days = _daySeparatorRows();
    if (days.isEmpty) {
      _setFloatingDay(null, 0);
      return;
    }

    var sums = _dayExtentSums;
    if (sums == null) {
      sums = <int, double>{};
      final dayRows = {for (final entry in days) entry.row};
      var extentThroughRow = 0.0;
      for (var row = 0; row <= days.first.row; row++) {
        extentThroughRow += _list.extentForIndex(row).$1;
        if (dayRows.contains(row)) sums[row] = extentThroughRow;
      }
      _dayExtentSums = sums;
    }
    // Every separator's top is the same scalar minus its own cached sum, so
    // the scroll position enters the arithmetic once rather than through a
    // rebuilt map on each of these — one runs per scroll frame.
    final fromBottom =
        _scroll.position.viewportDimension -
        _streamPadding.bottom +
        _scroll.position.pixels;

    double topOf(int row) => fromBottom - sums![row]!;

    var candidateIndex = -1;
    for (var index = 0; index < days.length; index++) {
      if (topOf(days[index].row) > 0) break;
      candidateIndex = index;
    }
    if (candidateIndex < 0) {
      _setFloatingDay(null, 0);
      return;
    }

    var offset = 0.0;
    final nextIndex = candidateIndex + 1;
    if (nextIndex < days.length) {
      final nextTop = topOf(days[nextIndex].row);
      if (nextTop < StreamDaySeparator.height) {
        offset = nextTop - StreamDaySeparator.height;
      }
    }
    _setFloatingDay(days[candidateIndex].day, offset);
  }

  void _setFloatingDay(DateTime? day, double offset) {
    if (_floatingDay == day && (_floatingDayOffset - offset).abs() < 0.1) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _floatingDay = day;
      _floatingDayOffset = offset;
    });
  }

  /// The row a message is drawn on, or null when it is not in the list — a
  /// last-read message the reader has since deleted, or one that fell outside
  /// the window the site answered with.
  int? _rowOf(int messageId) {
    final items = widget.items;
    for (var index = 0; index < items.length; index++) {
      final item = items[items.length - 1 - index];
      if (item is ChatStreamMessage && item.id == messageId) {
        return index + _leadingRows;
      }
    }
    return null;
  }

  /// The newest message the reader can see, or null before the list has been
  /// laid out.
  ///
  /// Under `reverse: true` the range's low end is the row at the bottom edge of
  /// the viewport, so this walks *up* — into the past — until it finds a row
  /// that is a message at all, a day separator and the unread divider being
  /// rows too.
  ///
  /// Discourse additionally requires the row's *bottom* to be on screen, and
  /// so takes the next one up when it is clipped. The difference is at most one
  /// message, and it is the message immediately below the one the reader is
  /// looking at — which they have either just scrolled past or are about to.
  int? _newestVisibleMessageId() {
    if (!_list.isAttached) return null;
    final range = _list.visibleRange;
    if (range == null) return null;

    for (var row = range.$1; row <= range.$2; row++) {
      if (_itemAt(row) case final ChatStreamMessage message
          when message.id > 0) {
        return message.id;
      }
    }
    return null;
  }

  /// Keeps the jump-to-now button in step with where the reader is.
  ///
  /// Two ways to be away from the present: scrolled up inside the window, or
  /// anchored behind it with messages the site has not been asked for yet.
  void _syncAwayFromPresent() {
    final away =
        !widget.stream.atPresent ||
        (_scroll.hasClients && _scroll.position.pixels > _presentSlack);
    if (away == _awayFromPresent) return;
    _awayFromPresent = away;
    if (!away) _unseenLiveMessages = 0;

    // Deferred when it lands mid-frame, which is the deferral
    // `ChatController._notify` explains: a viewport correcting an overshoot
    // dispatches its scroll notification from inside its own `performLayout`,
    // and marking the tree dirty there is an error rather than a rebuild.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// How far from the bottom still counts as being at the present. A message
  /// tall enough to sit under the reader's thumb should not put a button on
  /// screen.
  static const double _presentSlack = 120;

  /// Held rather than looked up, because [dispose] cannot ask for it: reaching
  /// for an inherited widget from there is an error, and the last write is the
  /// one that happens as the reader leaves.
  ChatController? _chat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chat = PluginUiScope.require(context, chatControllerService);
  }

  @override
  Widget build(BuildContext context) {
    final siteUrl = widget.siteUrl;
    final channelId = widget.channelId;
    final items = widget.items;
    final stream = widget.stream;
    final chat = PluginUiScope.require(context, chatControllerService);
    _startHighlightIfReady();

    final leading = _leadingRows;
    final lastRow = leading + items.length - 1;

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth != 0) return false;

            // Under `reverse: true` the scroll axis points at the past: offset
            // 0 is the newest message and `maxScrollExtent` is the oldest one
            // held. So `extentAfter` — which in a topic means "posts further
            // down, later" — here means "messages further up, earlier", and
            // `extentBefore` is the distance back to the present. Easy to
            // write backwards, hence the note.
            if (notification.metrics.extentAfter <
                ChatChannelView._loadOlderThreshold) {
              unawaited(chat.loadOlderFor(siteUrl, widget.target));
            }
            if (notification.metrics.extentBefore <
                ChatChannelView._loadNewerThreshold) {
              unawaited(chat.loadNewerFor(siteUrl, widget.target));
            }
            _noteWhatIsOnScreen();
            _syncAwayFromPresent();
            _scheduleLook();
            return false;
          },
          // Reversed rather than reversing the list, which is what makes
          // prepending history free: older messages take higher scroll offsets,
          // the viewport lays out from offset 0 outward and holds `pixels`
          // across a change in content extent, so a page landing at the far end
          // moves nothing the reader is looking at. Rendering forwards and
          // inserting at index 0 would throw them into the past on every page.
          //
          // The array stays oldest-first and the builder does the arithmetic:
          // the grouping and the day separators all want a *previous* message
          // in chronological order, and a reversed copy per build would put the
          // two permanently at odds.
          //
          // SuperListView for the reason `TopicView` gives — message heights
          // swing from one word to a screenful of quotes, and a plain
          // ListView's running average makes the scrollbar thumb lurch. Under
          // `reverse: true` that estimate applies to the older end, which is
          // where the reader is going.
          child: SuperListView.builder(
            reverse: true,
            controller: _scroll,
            listController: _list,
            padding: _streamPadding,
            itemCount: leading + items.length + (stream.loadingOlder ? 1 : 0),
            itemBuilder: (context, row) {
              // The two ends. Newest first, because under a reversed list that
              // is row zero.
              if (row < leading) return const _LoadingNewerRow();
              if (row > lastRow) return const _LoadingOlderRow();

              // Building the oldest row means the top of the stream is in view.
              // Scrolling alone is not enough: fifty one-line messages may not
              // fill the pane, leaving nothing to scroll and the rest never
              // fetched. Discourse calls this its fill-pane safety net and
              // debounces it; here the controller's in-flight guard is the
              // debounce.
              //
              // Past only, which is Discourse's rule too. See
              // [ChatChannelView._loadNewerThreshold] for why the other end
              // must be reached rather than approached — and note that a window
              // too short to scroll sits at offset zero, which *is* the end, so
              // the forward case is covered without a net of its own.
              if (row == lastRow && stream.canLoadMorePast) {
                _scheduleOlderPage(chat, siteUrl, channelId, stream);
              }

              return switch (_itemAt(row)) {
                ChatStreamMessage(:final id, :final chained) => ConstrainedBox(
                  // Only a genuinely short live-edge row needs room for
                  // its hover actions. Reserving their worst-case overflow
                  // in the list padding leaves the same large gap after a
                  // tall message, where the toolbar already fits.
                  constraints: BoxConstraints(
                    minHeight: row == 0
                        ? ChatMessageTile.minimumHoverActionsHeight
                        : 0,
                  ),
                  child: _HighlightedChatMessage(
                    highlighted: id == _highlightMessageId,
                    child: ValueListenableBuilder<ChatMessage?>(
                      valueListenable: chat.messageRef(siteUrl, id),
                      builder: (context, message, _) => ChatMessageTile(
                        siteUrl: siteUrl,
                        messageId: id,
                        chained: chained,
                        contextThreadId: widget.target.threadId,
                        onOpenThread: widget.onOpenThread,
                        onJumpToMessage: widget.onJumpToMessage,
                        onReplyInThread:
                            message?.thread != null || widget.canCreateThread
                            ? widget.onReplyInThread
                            : null,
                        onEdit: widget.onEdit,
                        showThreadSummary: widget.showThreadSummaries,
                        onSelect: id > 0 && widget.onStartSelecting != null
                            ? () => widget.onStartSelecting!(id)
                            : null,
                        selecting: widget.selectingMessages,
                        selected: widget.selectedMessageIds.contains(id),
                        onSelectedChanged: (selected) =>
                            widget.onSelectionChanged?.call(id, selected),
                      ),
                    ),
                  ),
                ),
                ChatStreamDay(:final day) => IgnorePointer(
                  ignoring: day == _floatingDay,
                  child: Opacity(
                    opacity: day == _floatingDay ? 0 : 1,
                    child: StreamDaySeparator(
                      key: ValueKey(('chat-day', day)),
                      day: day,
                    ),
                  ),
                ),
                ChatStreamTimeGap(:final messageId, :final daysSince) =>
                  TimeGapNotice(
                    key: ValueKey(('chat-time-gap', messageId)),
                    daysSince: daysSince,
                  ),
                ChatStreamDeleted(:final messageIds) => _DeletedRun(
                  siteUrl: siteUrl,
                  messageIds: messageIds,
                ),
                ChatStreamNewDivider() => const _NewDivider(),
                null => const SizedBox.shrink(),
              };
            },
          ),
        ),
        if (_floatingDay case final day?)
          Positioned(
            left: 0,
            right: 0,
            top: _floatingDayOffset,
            child: StreamDaySeparator(
              key: ValueKey(('chat-floating-day', day)),
              day: day,
              floating: true,
            ),
          ),
        if (_awayFromPresent)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: _JumpToPresent(
                pendingCount:
                    widget.stream.pendingNewMessages + _unseenLiveMessages,
                onTap: () => _jumpToPresent(chat, siteUrl, channelId),
              ),
            ),
          ),
      ],
    );
  }

  void _scheduleOlderPage(
    ChatController chat,
    String siteUrl,
    int channelId,
    ChatStreamState stream,
  ) {
    if (identical(_olderPageScheduledFor, stream)) return;
    _olderPageScheduledFor = stream;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_olderPageScheduledFor, stream)) {
        _olderPageScheduledFor = null;
      }
      if (!mounted ||
          widget.siteUrl != siteUrl ||
          widget.channelId != channelId ||
          !identical(widget.stream, stream) ||
          !identical(chat.streamFor(siteUrl, widget.target), stream)) {
        return;
      }
      unawaited(chat.loadOlderFor(siteUrl, widget.target));
    });
  }

  ChatStreamState? _olderPageScheduledFor;

  /// Takes the reader back to the newest message.
  ///
  /// Discourse's two-step: when the window already runs to the present this is
  /// a scroll, and when it does not the messages have to be fetched first —
  /// which replaces the window, and the anchor that follows lands at the
  /// bottom because a fetched-at-the-edge window has nothing to anchor to.
  Future<void> _jumpToPresent(
    ChatController chat,
    String siteUrl,
    int channelId,
  ) async {
    if (!widget.stream.atPresent) {
      await chat.showLatestFor(siteUrl, widget.target);
      _unseenLiveMessages = 0;
      return;
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _syncAwayFromPresent();
    _noteWhatIsOnScreen();
  }
}

/// Replaces the composer while one pane is selecting persisted messages.
class ChatMessageSelectionBar extends StatefulWidget {
  const ChatMessageSelectionBar({
    super.key,
    required this.siteUrl,
    required this.channelId,
    required this.messageIds,
    required this.chat,
    required this.onCancel,
  });

  final String siteUrl;
  final int channelId;
  final Set<int> messageIds;
  final ChatController chat;
  final VoidCallback onCancel;

  @override
  State<ChatMessageSelectionBar> createState() =>
      _ChatMessageSelectionBarState();
}

class _ChatMessageSelectionBarState extends State<ChatMessageSelectionBar> {
  bool _copying = false;
  bool _deleting = false;
  bool _moving = false;
  bool _quoting = false;

  Future<void> _copy() async {
    if (_copying ||
        _deleting ||
        _moving ||
        _quoting ||
        widget.messageIds.isEmpty) {
      return;
    }
    setState(() => _copying = true);
    final result = await widget.chat.generateMessageQuote(
      widget.siteUrl,
      widget.channelId,
      widget.messageIds,
    );
    var notice = result.error;
    if (result.markdown case final markdown?) {
      try {
        await Clipboard.setData(ClipboardData(text: markdown));
        notice = 'Messages copied!';
      } catch (_) {
        notice = "Couldn't copy messages.";
      }
    }
    if (!mounted) return;
    setState(() => _copying = false);
    if (notice != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _quote() async {
    if (_copying ||
        _deleting ||
        _moving ||
        _quoting ||
        widget.messageIds.isEmpty) {
      return;
    }
    final shell = PluginUiScope.require(context, chatShellService);
    setState(() => _quoting = true);
    final result = await widget.chat.generateMessageQuote(
      widget.siteUrl,
      widget.channelId,
      widget.messageIds,
    );
    var notice = result.error;
    if (result.markdown case final markdown?) {
      notice = await shell.openQuote(
        widget.siteUrl,
        widget.channelId,
        markdown,
      );
    }
    if (!mounted) return;
    setState(() => _quoting = false);
    if (notice != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(notice)));
    }
  }

  Future<void> _move(List<ChatChannel> destinations) async {
    if (_copying ||
        _deleting ||
        _moving ||
        _quoting ||
        widget.messageIds.isEmpty ||
        destinations.isEmpty) {
      return;
    }
    final count = widget.messageIds.length;
    final destinationId = await showDiscourseDialog<int>(
      context: context,
      builder: (dialogContext) {
        int? selected;
        return StatefulBuilder(
          builder: (context, setDialogState) => DiscourseAlertDialog(
            title: const Text('Move messages'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Move $count selected '
                    '${count == 1 ? 'message' : 'messages'} to:',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('chat-move-destination'),
                    initialValue: selected,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Destination channel',
                    ),
                    items: [
                      for (final channel in destinations)
                        DropdownMenuItem(
                          value: channel.id,
                          child: Text(
                            channel.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selected = value),
                  ),
                ],
              ),
            ),
            actions: [
              AdaptiveDialogAction(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              AdaptiveDialogAction(
                key: const ValueKey('confirm-move-chat-messages'),
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(dialogContext, selected),
                kind: AdaptiveDialogActionKind.primary,
                child: const Text('Move'),
              ),
            ],
          ),
        );
      },
    );
    if (destinationId == null || !mounted) return;

    final ids = widget.messageIds.toSet();
    final shell = PluginUiScope.require(context, chatShellService);
    setState(() => _moving = true);
    final result = await widget.chat.moveMessages(
      widget.siteUrl,
      widget.channelId,
      destinationId,
      ids,
    );
    if (!mounted) return;
    setState(() => _moving = false);
    if (result.error case final error?) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (result.move case final move?) {
      widget.onCancel();
      shell.openChannel(
        move.destinationChannelId,
        messageId: move.firstMovedMessageId,
      );
    }
  }

  Future<void> _delete() async {
    if (_copying ||
        _deleting ||
        _moving ||
        _quoting ||
        widget.messageIds.isEmpty) {
      return;
    }
    final ids = widget.messageIds.toSet();
    final count = ids.length;
    final confirmed = await showDiscourseDialog<bool>(
      context: context,
      builder: (dialogContext) => DiscourseAlertDialog(
        title: const Text('Delete selected messages?'),
        content: Text(
          'Are you sure you want to delete $count '
          '${count == 1 ? 'message' : 'messages'}?',
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            key: const ValueKey('confirm-delete-chat-messages'),
            onPressed: () => Navigator.pop(dialogContext, true),
            kind: AdaptiveDialogActionKind.destructive,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final error = await widget.chat.deleteMessages(
      widget.siteUrl,
      widget.channelId,
      ids,
    );
    if (!mounted) return;
    setState(() => _deleting = false);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error ?? 'Messages deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.messageIds.length;
    final canDelete = widget.chat.canDeleteMessages(
      widget.siteUrl,
      widget.channelId,
      widget.messageIds,
    );
    final source = widget.chat.channel(widget.siteUrl, widget.channelId);
    final moveDestinations = widget.chat.messageMoveDestinations(
      widget.siteUrl,
      widget.channelId,
    );
    final offersMove =
        source?.isCategoryChannel == true &&
        source?.canModerate == true &&
        moveDestinations.isNotEmpty;
    final canMove = widget.chat.canMoveMessages(
      widget.siteUrl,
      widget.channelId,
      widget.messageIds,
    );
    final busy = _copying || _deleting || _moving || _quoting;
    return Material(
      key: const ValueKey('chat-message-selection-bar'),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'message' : 'messages'} selected',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                key: const ValueKey('chat-quote-selection'),
                tooltip: 'Quote selected messages',
                onPressed: count == 0 || busy ? null : _quote,
                icon: _quoting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const DIcon(DIcons.quoteLeft, size: 18),
              ),
              FilledButton.icon(
                key: const ValueKey('chat-copy-selection'),
                onPressed: count == 0 || busy ? null : _copy,
                icon: _copying
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const DIcon(DIcons.copy, size: 16),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 4),
              if (offersMove)
                IconButton(
                  key: const ValueKey('chat-move-selection'),
                  tooltip: 'Move selected messages to another channel',
                  onPressed: canMove && !busy
                      ? () => _move(moveDestinations)
                      : null,
                  icon: _moving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        )
                      : const DIcon(DIcons.rightFromBracket, size: 18),
                ),
              IconButton(
                key: const ValueKey('chat-delete-selection'),
                tooltip: count > ChatController.maximumBulkDeleteMessages
                    ? 'Select no more than '
                          '${ChatController.maximumBulkDeleteMessages} messages'
                    : 'Delete selected messages',
                onPressed: canDelete && !busy ? _delete : null,
                icon: _deleting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const DIcon(DIcons.trashCan, size: 18),
              ),
              IconButton(
                key: const ValueKey('chat-cancel-selection'),
                tooltip: 'Cancel selection',
                onPressed: busy ? null : widget.onCancel,
                icon: const DIcon(DIcons.xmark, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedChatMessage extends StatelessWidget {
  const _HighlightedChatMessage({
    required this.highlighted,
    required this.child,
  });

  final bool highlighted;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    key: highlighted ? const ValueKey('chat-message-highlight') : null,
    duration: const Duration(milliseconds: 180),
    color: highlighted
        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45)
        : Colors.transparent,
    child: child,
  );
}

/// The button back to the present.
class _JumpToPresent extends StatelessWidget {
  const _JumpToPresent({required this.onTap, this.pendingCount = 0});

  static const double _targetSize = 44;
  static const double _visualSize = 36;

  final VoidCallback onTap;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final label = pendingCount > 0
        ? 'Jump to latest messages, $pendingCount new'
        : 'Jump to latest messages';
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: _targetSize,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Material(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: SizedBox.square(
                      dimension: _visualSize,
                      child: Center(
                        child: ExcludeSemantics(
                          child: DIcon(
                            DIcons.chevronDown,
                            size: 16,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      key: const ValueKey('chat-jump-pending-count'),
                      right: 0,
                      top: 0,
                      child: ExcludeSemantics(
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            pendingCount > 99 ? '99+' : '$pendingCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontSize: DiscourseTypography.fontDown3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the messages the reader has not seen begin.
class _NewDivider extends StatelessWidget {
  const _NewDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: theme.colorScheme.error)),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'New',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A run of deleted messages, which only a moderator is ever shown.
class _DeletedRun extends StatelessWidget {
  const _DeletedRun({required this.siteUrl, required this.messageIds});

  final String siteUrl;
  final List<int> messageIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final chat = PluginUiScope.require(context, chatControllerService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final restorable = [
          for (final id in messageIds)
            if (chat.messageRef(siteUrl, id).value case final message?
                when chat.canRestoreMessage(siteUrl, message))
              message,
        ];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  messageIds.length == 1
                      ? '1 message deleted'
                      : '${messageIds.length} messages deleted',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              if (restorable.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _restore(context, chat, restorable),
                  icon: const DIcon(DIcons.arrowRotateLeft, size: 14),
                  label: Text(restorable.length == 1 ? 'Restore' : 'Restore…'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _restore(
    BuildContext context,
    ChatController chat,
    List<ChatMessage> messages,
  ) async {
    if (messages.length > 1) {
      await showShellSheet<void>(
        context: context,
        title: 'Restore deleted message',
        padding: EdgeInsets.zero,
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final message in messages)
              ListTile(
                leading: const DIcon(DIcons.arrowRotateLeft, size: 18),
                title: Text('Message by ${message.author.displayName}'),
                subtitle: Text('Message ${message.id}'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_restoreOne(context, chat, message.id));
                },
              ),
          ],
        ),
      );
      return;
    }
    await _restoreOne(context, chat, messages.single.id);
  }

  Future<void> _restoreOne(
    BuildContext context,
    ChatController chat,
    int messageId,
  ) async {
    final error = await chat.restoreMessage(siteUrl, messageId);
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(error)));
  }
}

/// Its mirror at the newest end, for a stream anchored behind the present.
class _LoadingNewerRow extends StatelessWidget {
  const _LoadingNewerRow();

  @override
  Widget build(BuildContext context) => const _ChatPaginationSkeleton(
    key: ValueKey('chat-loading-newer-skeleton'),
    semanticsLabel: 'Loading newer messages',
    nameWidth: 0.28,
    lineWidth: 0.58,
    chainedLineWidth: 0.34,
  );
}

class _LoadingOlderRow extends StatelessWidget {
  const _LoadingOlderRow();

  @override
  Widget build(BuildContext context) => const _ChatPaginationSkeleton(
    key: ValueKey('chat-loading-older-skeleton'),
    semanticsLabel: 'Loading older messages',
    nameWidth: 0.22,
    lineWidth: 0.66,
    chainedLineWidth: 0.40,
  );
}

/// A compact continuation of the conversation while one adjacent page loads.
///
/// Keeping the avatar, header, and chained follow-up makes either edge read as
/// incoming chat content without inserting enough speculative height to move
/// the reader noticeably when the real page replaces it.
class _ChatPaginationSkeleton extends StatelessWidget {
  const _ChatPaginationSkeleton({
    super.key,
    required this.semanticsLabel,
    required this.nameWidth,
    required this.lineWidth,
    required this.chainedLineWidth,
  });

  final String semanticsLabel;
  final double nameWidth;
  final double lineWidth;
  final double chainedLineWidth;

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      semanticsLabel: semanticsLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChatSkeletonMessage(nameWidth: nameWidth, lineWidths: [lineWidth]),
            _ChatSkeletonChainedMessage(lineWidth: chainedLineWidth),
          ],
        ),
      ),
    );
  }
}

/// A quiet stand-in for the bottom of a conversation while its first window
/// is on the way.
///
/// The rows mirror the real chat gutter and grouping closely enough that the
/// loaded messages do not make the pane jump from an unrelated shape. The
/// pattern repeats until it covers the viewport, then is clipped from the top
/// to keep the newest-looking rows attached to the composer without making
/// this loading state scrollable.
class _ChatLoadingSkeleton extends StatelessWidget {
  const _ChatLoadingSkeleton({super.key});

  static const _patternHeight =
      (ChatMessageTile.minimumUnchainedHeight * 3) +
      (ChatMessageTile.minimumChainedHeight * 3);

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      semanticsLabel: 'Loading chat channel',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final patternCount = constraints.hasBoundedHeight
              ? (constraints.maxHeight / _patternHeight).ceil()
              : 1;

          return ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  key: const ValueKey('chat-loading-skeleton-content'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (
                      var index = 0;
                      index < patternCount;
                      index++
                    ) ...const [
                      _ChatSkeletonMessage(
                        nameWidth: 0.22,
                        lineWidths: [0.68, 0.42],
                      ),
                      _ChatSkeletonChainedMessage(lineWidth: 0.26),
                      _ChatSkeletonMessage(nameWidth: 0.30, lineWidths: [0.90]),
                      _ChatSkeletonChainedMessage(lineWidth: 0.44),
                      _ChatSkeletonChainedMessage(lineWidth: 0.64),
                      _ChatSkeletonMessage(
                        nameWidth: 0.24,
                        lineWidths: [0.66, 0.30],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatSkeletonMessage extends StatelessWidget {
  const _ChatSkeletonMessage({
    required this.nameWidth,
    required this.lineWidths,
  });

  final double nameWidth;
  final List<double> lineWidths;

  @override
  Widget build(BuildContext context) {
    final message = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutterWidth = constraints.maxWidth < ChatMessageTile.gutter
              ? constraints.maxWidth
              : ChatMessageTile.gutter;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gutterWidth,
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: LoadingSkeletonBlock.circle(diameter: 28),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ChatSkeletonHeader(nameWidth: nameWidth),
                    for (final width in lineWidths) ...[
                      const SizedBox(height: 7),
                      _ChatSkeletonLine(width: width),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ChatMessageTile.minimumUnchainedHeight,
      ),
      child: message,
    );
  }
}

class _ChatSkeletonHeader extends StatelessWidget {
  const _ChatSkeletonHeader({required this.nameWidth});

  final double nameWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 10,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: nameWidth,
              child: const LoadingSkeletonBlock(height: 10),
            ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: LoadingSkeletonBlock(width: 36, height: 7),
          ),
        ],
      ),
    );
  }
}

class _ChatSkeletonChainedMessage extends StatelessWidget {
  const _ChatSkeletonChainedMessage({required this.lineWidth});

  final double lineWidth;

  @override
  Widget build(BuildContext context) {
    final message = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gutterWidth = constraints.maxWidth < ChatMessageTile.gutter
              ? constraints.maxWidth
              : ChatMessageTile.gutter;
          return Padding(
            padding: EdgeInsets.only(left: gutterWidth),
            child: _ChatSkeletonLine(width: lineWidth),
          );
        },
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ChatMessageTile.minimumChainedHeight,
      ),
      child: message,
    );
  }
}

class _ChatSkeletonLine extends StatelessWidget {
  const _ChatSkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: width,
        child: const LoadingSkeletonBlock(height: 9),
      ),
    );
  }
}

/// Local to this screen, the way `TopicListView` keeps its own: an empty
/// channel and an unreachable one are two sentences, not a shared widget.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final DIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DIcon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
