import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../plugin_api/plugin_scope.dart';
import '../../shell/adaptive_dialog_action.dart';
import '../../shell/content_reading_lane.dart';
import '../../shell/list_boundary_shortcuts.dart';
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

class ChatChannelView extends StatelessWidget {
  const ChatChannelView({
    super.key,
    required this.channelId,
    this.autofocusMessageStream = true,
  });

  final int channelId;
  final bool autofocusMessageStream;

  /// About one screen before the reversed list's oldest edge.
  static const double _loadOlderThreshold = 900;

  /// Future pages wait at the edge so backlogs cannot advance without the reader.
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
          autofocusMessageStream: autofocusMessageStream,
        );
      },
    );
  }
}

class _ChatChannelBody extends StatefulWidget {
  const _ChatChannelBody({
    super.key,
    required this.siteUrl,
    required this.channelId,
    required this.showTimeGapDays,
    required this.chat,
    required this.autofocusMessageStream,
  });

  final String siteUrl;
  final int channelId;
  final int showTimeGapDays;
  final ChatController chat;
  final bool autofocusMessageStream;

  @override
  State<_ChatChannelBody> createState() => _ChatChannelBodyState();
}

class _ChatChannelBodyState extends State<_ChatChannelBody> {
  Object? _viewToken;
  bool _viewStartScheduled = false;
  bool _tickerEnabled = true;
  ChatShellService? _shell;
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

  bool get _viewerActive => _tickerEnabled && (_shell?.forumActive ?? false);

  void _handleShellChanged() => _syncViewing();

  void _syncViewing() {
    if (!_viewerActive) {
      final viewToken = _viewToken;
      _viewToken = null;
      if (viewToken != null) {
        widget.chat.endViewingChannel(
          widget.siteUrl,
          widget.channelId,
          viewToken,
        );
      }
      return;
    }
    if (_viewToken != null || _viewStartScheduled) return;
    _viewStartScheduled = true;
    // The sibling header may still be building when beginViewing advances the
    // channel record, so register after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewStartScheduled = false;
      if (!mounted || !_viewerActive || _viewToken != null) return;
      _viewToken = widget.chat.beginViewingChannel(
        widget.siteUrl,
        widget.channelId,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = PluginUiScope.require(context, chatShellService);
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_handleShellChanged);
      _shell = shell..addListener(_handleShellChanged);
    }
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncViewing();

    final navigation = shell.navigation;
    if (!identical(navigation, _navigation)) {
      _navigation?.removeListener(_consumeNavigation);
      _navigation = navigation;
      navigation.addListener(_consumeNavigation);
      if (!_consumeNavigation() && !_opened) {
        _opened = true;
        unawaited(widget.chat.openChannel(widget.siteUrl, widget.channelId));
      }
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
    _shell?.removeListener(_handleShellChanged);
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
      // Local sends remain visible while the first page loads or has failed.
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
        autofocus: widget.autofocusMessageStream,
      );
    } else if (stream.loading) {
      content = const ContentReadingLaneBox(
        child: _ChatLoadingSkeleton(key: ValueKey('chat-loading-skeleton')),
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
    // Paging changes flags without changing immutable ids; avoid regrouping all
    // accumulated history for those states.
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
      // Use the opening snapshot so read receipts cannot move the divider.
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

  /// Reprojects a past-page prefix through the first old non-deleted seam;
  /// other changes take the full fallback.
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
    this.autofocus = true,
  });

  final String siteUrl;
  final ChatStreamTarget target;
  final List<ChatStreamItem> items;
  final ChatStreamState stream;
  final int? highlightMessageId;

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
  final bool autofocus;

  int get channelId => target.channelId;

  @override
  State<ChatMessageStream> createState() => _StreamState();
}

class _StreamState extends State<ChatMessageStream>
    with WidgetsBindingObserver {
  /// Matches Discourse's `READ_INTERVAL_MS`.
  static const Duration _readInterval = Duration(milliseconds: 500);
  static const EdgeInsets _streamPadding = EdgeInsets.symmetric(vertical: 8);

  final ListController _list = ListController();

  final ScrollController _scroll = ScrollController();

  Timer? _readTimer;
  DateTime? _readTimerStartedAt;
  Duration _readTimeRemaining = _readInterval;
  bool _readDwellPending = false;
  bool _tickerEnabled = true;

  /// Includes target identity because the dwell timer may outlive the route.
  ({String siteUrl, ChatStreamTarget target, int messageId})? _seen;

  /// Null requires the next frame to choose a deliberate landing point.
  ({String siteUrl, ChatStreamTarget target, int fetches})? _anchored;

  bool _awayFromPresent = false;
  int _boundaryJumpRevision = 0;
  int _unseenLiveMessages = 0;
  DateTime? _floatingDay;
  double _floatingDayOffset = 0;
  int? _highlightMessageId;
  int? _pendingHighlightMessageId;
  int? _handledHighlightRequest;
  Timer? _highlightTimer;

  bool get _readerActive => _tickerEnabled && (_shell?.forumActive ?? false);

  /// Suppresses pre-layout visibility while an anchor moves.
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
      // Within one fetch generation, present-window growth is live arrivals.
      _unseenLiveMessages +=
          widget.stream.messageIds.length - oldWidget.stream.messageIds.length;
    }

    _holdStillThroughForwardPage(oldWidget);
    _scheduleLook();
  }

  void _holdStillThroughForwardPage(ChatMessageStream oldWidget) {
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.target != widget.target) {
      return;
    }
    if (!oldWidget.stream.canLoadMoreFuture) return;
    final was = oldWidget.stream.newestId;
    if (oldWidget.stream.fetches != widget.stream.fetches) return;
    if (was == null || widget.stream.newestId == was) return;

    final row = _rowOf(was);
    if (row == null) return;

    final identity = (siteUrl: widget.siteUrl, target: widget.target);
    final stream = widget.stream;
    _anchoring = true;
    // New row heights exist only after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.siteUrl != identity.siteUrl ||
          widget.target != identity.target ||
          !identical(widget.stream, stream)) {
        return;
      }
      _landOn(row, alignment: 0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shell?.removeListener(_handleShellChanged);
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

  void _fillTowardsPresent() {
    final stream = widget.stream;
    if (!stream.canLoadMoreFuture || !_scroll.hasClients) return;
    if (_scroll.position.pixels > ChatChannelView._loadNewerThreshold) return;

    // Ask once per window state so a failed request cannot retry every frame.
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
      // Reversed offset zero is the present; discard offsets from replaced history.
      _scroll.jumpTo(0);
      _settleAnchor();
    } else {
      _landOn(index, alignment: 0.5);
    }

    // Seed from the known landing point; layout still reports the old range.
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

  /// The second jump uses measured rather than estimated row heights.
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
    // Post-frame callbacks and no-op jumps do not themselves schedule a frame.
    WidgetsBinding.instance.scheduleFrame();
  }

  /// In a reversed list, zero aligns to the newest edge and one to the oldest.
  void _jumpToRow(int row, double alignment) {
    if (!_list.isAttached || !_scroll.hasClients) return;
    _list.jumpToItem(
      index: row,
      scrollController: _scroll,
      alignment: alignment,
    );
  }

  void _jumpToOldestLoadedMessage() {
    final revision = ++_boundaryJumpRevision;
    if (!_list.isAttached || !_scroll.hasClients || _list.numberOfItems == 0) {
      return;
    }

    final target = _list.numberOfItems - 1;
    void correctToOldestEdge({bool repeat = true}) {
      if (!mounted ||
          revision != _boundaryJumpRevision ||
          !_list.isAttached ||
          !_scroll.hasClients) {
        return;
      }
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
      if (!repeat) return;

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => correctToOldestEdge(repeat: false),
      );
      WidgetsBinding.instance.scheduleFrame();
    }

    // Reveal and measure the oldest row before including trailing padding.
    _jumpToRow(target, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => correctToOldestEdge());
    WidgetsBinding.instance.scheduleFrame();
  }

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
    if (!_readerActive) return;
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

  void _creditReaderNow() {
    _readTimer?.cancel();
    _readTimer = null;
    _readTimerStartedAt = null;
    _readDwellPending = false;

    final seen = _seen;
    if (seen == null) return;

    if (!_readerActive) {
      _readDwellPending = true;
      _readTimeRemaining = _readInterval;
      return;
    }

    // A dwell timer firing in the background must not mark messages read. Null
    // covers launch before the first lifecycle event and tests.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      _readTimeRemaining = _readInterval;
      return;
    }

    _readTimeRemaining = _readInterval;
    unawaited(_chat?.markReadFor(seen.siteUrl, widget.target, seen.messageId));
  }

  int get _leadingRows => widget.stream.loadingNewer ? 1 : 0;

  /// Centralizes reversal: `_leadingRows` is newest and indices count backward.
  ChatStreamItem? _itemAt(int row) {
    final index = row - _leadingRows;
    if (index < 0 || index >= widget.items.length) return null;
    return widget.items[widget.items.length - 1 - index];
  }

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

  Map<int, double>? _dayExtentSums;

  void _noteExtentsChanged() => _dayExtentSums = null;

  /// In the reversed list, a separator floats after its bottom-relative top
  /// crosses zero until the next newer separator pushes it out.
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

  /// Counts partially visible rows, unlike Discourse.
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

  void _syncAwayFromPresent() {
    final away =
        !widget.stream.atPresent ||
        (_scroll.hasClients && _scroll.position.pixels > _presentSlack);
    if (away == _awayFromPresent) return;
    _awayFromPresent = away;
    if (!away) _unseenLiveMessages = 0;

    // Overshoot correction can notify during performLayout, where setState is illegal.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  static const double _presentSlack = 120;

  /// Held because dispose cannot depend on an inherited-widget lookup.
  ChatController? _chat;
  ChatShellService? _shell;

  void _handleShellChanged() => _syncReadDwellVisibility();

  void _syncReadDwellVisibility() {
    if (_readerActive) {
      if (_readDwellPending && _seen != null && _readTimer == null) {
        _startReadDwell(_readTimeRemaining);
      }
    } else {
      _pauseReadDwell();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    if (!identical(_shell, shell)) {
      _shell?.removeListener(_handleShellChanged);
      _shell = shell..addListener(_handleShellChanged);
    }
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncReadDwellVisibility();
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

    return ContentReadingLane(
      basePadding: _streamPadding,
      builder: (context, lane) => Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth != 0) return false;
              // In the reversed list, extentAfter points toward older messages
              // and extentBefore back toward the present.
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
            // Reversal preserves position as older, variably sized rows are
            // added.
            child: ListBoundaryShortcuts(
              key: const ValueKey('chat-message-stream-keyboard-focus'),
              debugLabel: 'chat message stream',
              initiallyActive: widget.autofocus,
              onStart: _jumpToOldestLoadedMessage,
              onEnd: () {
                _boundaryJumpRevision++;
                if (_chat case final chat?) {
                  unawaited(
                    _jumpToPresent(
                      chat,
                      widget.siteUrl,
                      widget.target.channelId,
                    ),
                  );
                }
              },
              child: SuperListView.builder(
                reverse: true,
                controller: _scroll,
                listController: _list,
                padding: lane.padding,
                itemCount:
                    leading + items.length + (stream.loadingOlder ? 1 : 0),
                itemBuilder: (context, row) {
                  if (row < leading) return const _LoadingNewerRow();
                  if (row > lastRow) return const _LoadingOlderRow();

                  // The oldest row drives fill-pane fallback when no scroll fires.
                  if (row == lastRow && stream.canLoadMorePast) {
                    _scheduleOlderPage(chat, siteUrl, channelId, stream);
                  }

                  return switch (_itemAt(row)) {
                    ChatStreamMessage(:final id, :final chained) =>
                      ConstrainedBox(
                        // Reserve hover overflow only when the live-edge row is short.
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
                                  message?.thread != null ||
                                      widget.canCreateThread
                                  ? widget.onReplyInThread
                                  : null,
                              onEdit: widget.onEdit,
                              showThreadSummary: widget.showThreadSummaries,
                              onSelect:
                                  id > 0 && widget.onStartSelecting != null
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
          ),
          if (_floatingDay case final day?)
            Positioned(
              left: lane.leftInset,
              right: lane.rightInset,
              top: _floatingDayOffset,
              child: StreamDaySeparator(
                key: ValueKey(('chat-floating-day', day)),
                day: day,
                floating: true,
              ),
            ),
          if (_awayFromPresent)
            Positioned(
              left: lane.leftInset,
              right: lane.rightInset,
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
      ),
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
