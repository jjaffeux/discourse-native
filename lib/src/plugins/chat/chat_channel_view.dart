import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../shell/loading_skeleton.dart';
import '../../shell/shell_scope.dart';
import '../../theme/app_theme.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_composer.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_message_tile.dart';
import 'chat_stream.dart';

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
    return ShellSelector<_ChatSource?>(
      select: (controller) {
        final siteUrl = controller.currentInstance?.url;
        return siteUrl == null
            ? null
            : (siteUrl: siteUrl, chat: controller.chat);
      },
      builder: (context, source, _) => source == null
          ? const SizedBox.shrink()
          : _ChatChannelBody(
              key: ValueKey((source.siteUrl, channelId, source.chat)),
              siteUrl: source.siteUrl,
              channelId: channelId,
              chat: source.chat,
            ),
    );
  }
}

typedef _ChatSource = ({String siteUrl, ChatController chat});

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
    required this.chat,
  });

  final String siteUrl;
  final int channelId;
  final ChatController chat;

  @override
  State<_ChatChannelBody> createState() => _ChatChannelBodyState();
}

class _ChatChannelBodyState extends State<_ChatChannelBody> {
  late final Object _viewToken;
  List<int>? _projectedMessageIds;
  List<int>? _projectedLocalMessageIds;
  int? _projectedLastRead;
  List<ChatStreamItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _viewToken = widget.chat.beginViewingChannel(
      widget.siteUrl,
      widget.channelId,
    );
    unawaited(widget.chat.openChannel(widget.siteUrl, widget.channelId));
  }

  @override
  void dispose() {
    widget.chat.endViewingChannel(widget.siteUrl, widget.channelId, _viewToken);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatStreamState>(
      valueListenable: widget.chat.streamListenable(
        widget.siteUrl,
        widget.channelId,
      ),
      builder: (context, stream, _) => _buildChannel(stream),
    );
  }

  Widget _buildChannel(ChatStreamState stream) {
    late final Widget content;
    final hasMessages =
        stream.messageIds.isNotEmpty || stream.localMessageIds.isNotEmpty;
    if (hasMessages) {
      // A send can be staged while the first page is still loading, or after
      // that page failed. The local row is useful state in either case and
      // must not be hidden behind the page-level loading/error state.
      _syncProjection(stream);
      content = _Stream(
        siteUrl: widget.siteUrl,
        channelId: widget.channelId,
        items: _items,
        stream: stream,
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

    return Column(
      children: [
        Expanded(child: content),
        ChatComposer(
          key: ValueKey((widget.siteUrl, widget.channelId, 'composer')),
          siteUrl: widget.siteUrl,
          channelId: widget.channelId,
        ),
      ],
    );
  }

  void _syncProjection(ChatStreamState stream) {
    // Paging toggles loading flags before and after each request while keeping
    // the same immutable id list. Deriving every grouped row again for those
    // flag-only states turns each page into repeated work over the whole
    // history accumulated so far.
    if (identical(_projectedMessageIds, stream.messageIds) &&
        identical(_projectedLocalMessageIds, stream.localMessageIds) &&
        _projectedLastRead == stream.lastReadOnOpen) {
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
      );
    }

    _projectedMessageIds = stream.messageIds;
    _projectedLocalMessageIds = stream.localMessageIds;
    _projectedLastRead = stream.lastReadOnOpen;
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
        _projectedLastRead != stream.lastReadOnOpen) {
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
class _Stream extends StatefulWidget {
  const _Stream({
    required this.siteUrl,
    required this.channelId,
    required this.items,
    required this.stream,
  });

  final String siteUrl;
  final int channelId;
  final List<ChatStreamItem> items;
  final ChatStreamState stream;

  @override
  State<_Stream> createState() => _StreamState();
}

class _StreamState extends State<_Stream> {
  /// How long the viewport has to hold still before the reader is credited
  /// with what is on it. Discourse's own `READ_INTERVAL_MS`, and the number
  /// matters in both directions: a scroll that fires a write per frame would
  /// be a request per frame, and one that waited for the scroll to *end* would
  /// never credit a reader who keeps a channel open and idle.
  static const Duration _readInterval = Duration(milliseconds: 500);

  /// Asked for the visible range, and the reason the list is measured at all.
  final ListController _list = ListController();

  /// Needed alongside it because landing on a message is a scroll, and
  /// `jumpToItem` translates one into the other.
  final ScrollController _scroll = ScrollController();

  Timer? _readTimer;

  /// The newest message the reader has had on screen since the last write,
  /// with the channel it belongs to — which the reader can leave before the
  /// timer fires, and a message id means nothing without it.
  ({String siteUrl, int channelId, int messageId})? _seen;

  /// The window this has already positioned itself against, as
  /// `(site, channel, ChatStreamState.fetches)`. Null means the next frame has
  /// to land somewhere deliberate.
  ({String siteUrl, int channelId, int fetches})? _anchored;

  /// Whether the reader has scrolled away from the present, which is what puts
  /// the jump-to-now button on screen. Held rather than read from the position
  /// on every build because it changes far less often than a scroll does.
  bool _awayFromPresent = false;

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
    _scheduleLook();
  }

  @override
  void didUpdateWidget(_Stream oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changedStream =
        oldWidget.channelId != widget.channelId ||
        oldWidget.siteUrl != widget.siteUrl;

    // Leaving a channel is Discourse's `teardown`, which credits the reader
    // before it goes. The pending id already names the channel being left, so
    // it is the old one that gets the write.
    if (changedStream) {
      _creditReaderNow();
      _seen = null;
      _anchored = null;
      _filled = null;
      _anchoring = false;
      _awayFromPresent = false;
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
  void _holdStillThroughForwardPage(_Stream oldWidget) {
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.channelId != widget.channelId) {
      return;
    }
    final was = oldWidget.stream.newestId;
    // A replaced window is not a page, and positions itself: see
    // [_anchorIfFresh].
    if (oldWidget.stream.fetches != widget.stream.fetches) return;
    if (was == null || widget.stream.newestId == was) return;

    final row = _rowOf(was);
    if (row == null) return;

    final identity = (siteUrl: widget.siteUrl, channelId: widget.channelId);
    final stream = widget.stream;
    _anchoring = true;
    // After the frame that lays the new rows out, because until then they have
    // no heights for the jump to measure against.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.siteUrl != identity.siteUrl ||
          widget.channelId != identity.channelId ||
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
    _creditReaderNow();
    _list.dispose();
    _scroll.dispose();
    super.dispose();
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
      channelId: widget.channelId,
      fetches: stream.fetches,
      newestId: stream.newestId,
    );
    if (_filled == asked) return;
    _filled = asked;

    unawaited(_chat?.loadNewer(widget.siteUrl, widget.channelId));
  }

  ({String siteUrl, int channelId, int fetches, int? newestId})? _filled;

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
      channelId: widget.channelId,
      fetches: stream.fetches,
    );
    if (_anchored == token) return false;
    if (!_list.isAttached || !_scroll.hasClients) return false;
    _anchored = token;

    final target = stream.lastReadOnOpen;
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
    _seen = canonicalId == null
        ? null
        : (
            siteUrl: widget.siteUrl,
            channelId: widget.channelId,
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

  /// Lets go once the landing has been laid out, and credits the reader with
  /// what it put in front of them.
  ///
  /// Discourse does the same at the end of its own `fetchMessages` — a window
  /// opened half a screen from the end has been read to the bottom of that
  /// screen, and the reader should not have to nudge it to say so.
  void _settleAnchor() {
    final token = _anchored;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchored != token) return;
      _anchoring = false;
      _fillTowardsPresent();
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
      channelId: widget.channelId,
      messageId: messageId,
    );
    if (seen == _seen) return;
    _seen = seen;

    _readTimer?.cancel();
    _readTimer = Timer(_readInterval, _creditReaderNow);
  }

  /// Tells the controller what the reader has seen, now rather than on the
  /// timer. Everything about *whether* that turns into a write is
  /// [ChatController.markRead]'s to decide.
  void _creditReaderNow() {
    _readTimer?.cancel();
    _readTimer = null;

    final seen = _seen;
    if (seen == null) return;

    // Discourse asks three questions before crediting anybody — the tab is
    // visible, the window has focus, the reader is present. A phone asks one,
    // and this is it: a timer that lands after the app has gone away would
    // credit a reader who is not looking at anything. Null is a launch that
    // has had no lifecycle message yet, and a test, and both mean "in front".
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    unawaited(_chat?.markRead(seen.siteUrl, seen.channelId, seen.messageId));
  }

  /// How many rows sit before the newest item. The forward-paging spinner,
  /// when there is one, and this is the only place that number is decided —
  /// everything that turns a row number into an item goes through [_itemAt].
  int get _leadingRows => widget.stream.loadingNewer ? 1 : 0;

  /// The item a row draws, or null for the two spinner rows.
  ///
  /// The reversal lives here and nowhere else: row `_leadingRows` is the
  /// *newest* item, and rows count backwards into the past from there.
  ChatStreamItem? _itemAt(int row) {
    final index = row - _leadingRows;
    if (index < 0 || index >= widget.items.length) return null;
    return widget.items[widget.items.length - 1 - index];
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
        widget.stream.canLoadMoreFuture ||
        (_scroll.hasClients && _scroll.position.pixels > _presentSlack);
    if (away == _awayFromPresent) return;
    _awayFromPresent = away;

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
    _chat = ShellScope.read(context).chat;
  }

  @override
  Widget build(BuildContext context) {
    final siteUrl = widget.siteUrl;
    final channelId = widget.channelId;
    final items = widget.items;
    final stream = widget.stream;
    final chat = ShellScope.read(context).chat;

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
              unawaited(chat.loadOlder(siteUrl, channelId));
            }
            if (notification.metrics.extentBefore <
                ChatChannelView._loadNewerThreshold) {
              unawaited(chat.loadNewer(siteUrl, channelId));
            }
            _noteWhatIsOnScreen();
            _syncAwayFromPresent();
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
            padding: const EdgeInsets.symmetric(vertical: 8),
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
                ChatStreamMessage(:final id, :final chained) => ChatMessageTile(
                  siteUrl: siteUrl,
                  messageId: id,
                  chained: chained,
                ),
                ChatStreamDay(:final day) => _DaySeparator(day: day),
                ChatStreamDeleted(:final count) => _DeletedRun(count: count),
                ChatStreamNewDivider() => const _NewDivider(),
                null => const SizedBox.shrink(),
              };
            },
          ),
        ),
        if (_awayFromPresent)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: _JumpToPresent(
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
          !identical(chat.stream(siteUrl, channelId), stream)) {
        return;
      }
      unawaited(chat.loadOlder(siteUrl, channelId));
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
    if (widget.stream.canLoadMoreFuture) {
      await chat.showLatest(siteUrl, channelId);
      return;
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _syncAwayFromPresent();
    _noteWhatIsOnScreen();
  }
}

/// The button back to the present.
class _JumpToPresent extends StatelessWidget {
  const _JumpToPresent({required this.onTap});

  static const double _targetSize = 44;
  static const double _visualSize = 36;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    const label = 'Jump to latest messages';
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
              child: Center(
                child: Material(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line between two days of conversation.
class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day});

  final DateTime day;

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Today and yesterday by name, everything else by date. The reader's days,
  /// not the site's — [day] is already local midnight.
  String get _label {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final delta = today.difference(day).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    return '${day.day} ${_months[day.month - 1]} ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: theme.shell.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Divider(height: 1, color: theme.shell.divider)),
        ],
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
  const _DeletedRun({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Text(
        count == 1 ? '1 message deleted' : '$count messages deleted',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.error,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// Its mirror at the newest end, for a stream anchored behind the present.
class _LoadingNewerRow extends StatelessWidget {
  const _LoadingNewerRow();

  @override
  Widget build(BuildContext context) => const _LoadingOlderRow();
}

class _LoadingOlderRow extends StatelessWidget {
  const _LoadingOlderRow();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
    ),
  );
}

/// A quiet stand-in for the bottom of a conversation while its first window
/// is on the way.
///
/// The rows mirror the real chat gutter and grouping closely enough that the
/// loaded messages do not make the pane jump from an unrelated shape. The
/// oversized column is clipped from the top on exceptionally short panes,
/// keeping the newest-looking rows attached to the composer without making
/// this loading state scrollable.
class _ChatLoadingSkeleton extends StatelessWidget {
  const _ChatLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return LoadingSkeleton(
      semanticsLabel: 'Loading chat channel',
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: SizedBox(
            width: double.infinity,
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatSkeletonMessage(nameWidth: 0.22, lineWidths: [0.68, 0.42]),
                _ChatSkeletonChainedMessage(lineWidth: 0.26),
                _ChatSkeletonMessage(nameWidth: 0.30, lineWidths: [0.90]),
                _ChatSkeletonChainedMessage(lineWidth: 0.44),
                _ChatSkeletonChainedMessage(lineWidth: 0.64),
                _ChatSkeletonMessage(nameWidth: 0.24, lineWidths: [0.66, 0.30]),
              ],
            ),
          ),
        ),
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
    return Padding(
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
    return Padding(
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
