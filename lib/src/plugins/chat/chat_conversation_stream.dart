part of 'chat_controller.dart';

final class _ChatWindowGeneration {}

final class _ChatPageRequest {
  _ChatPageRequest(this.generation);

  final _ChatWindowGeneration generation;
}

final class _ChatConversationStream {
  _ChatConversationStream(this._controller, this.siteUrl, this.target)
    : key = ChatController._targetKey(siteUrl, target);

  final ChatController _controller;
  final String siteUrl;
  final ChatStreamTarget target;
  final String key;
  ChatStreamState? _window;
  FrameSafeValueNotifier<ChatStreamState>? _ref;
  _ChatMessagePinSet? _messagePins;
  ({List<int> messageIds, List<int> localMessageIds, bool viewing})?
  _completePinInputs;
  _ChatWindowGeneration? _generation;
  _ChatPageRequest? _olderRequest;
  _ChatPageRequest? _newerRequest;
  bool _loading = false;
  DateTime? _attemptedAt;
  final Set<int> _pendingLiveMessageIds = {};
  Timer? _noticeTimer;
  ChatReadReceiptOwner? _readReceipts;
  bool _retired = false;

  bool get isCurrent =>
      !_retired && identical(_controller._conversations[key], this);

  ChatStreamState get snapshot => _window ?? const ChatStreamState();

  ValueListenable<ChatStreamState> get listenable =>
      _ref ??= FrameSafeValueNotifier(snapshot);

  bool get attemptedRecently {
    final attemptedAt = _attemptedAt;
    return attemptedAt != null &&
        _controller._clock().difference(attemptedAt) <
            _controller.minimumWindowRefreshInterval;
  }

  bool get preventsEviction =>
      (_window?.localMessageIds.isNotEmpty ?? false) ||
      _pendingLiveMessageIds.isNotEmpty ||
      _loading ||
      _olderRequest != null ||
      _newerRequest != null ||
      _noticeTimer != null ||
      (_readReceipts?.preventsEviction ?? false) ||
      (_messagePins?.length ?? 0) > 0;

  void publish(ChatStreamState stream, {_ChatWindowGrowth? growth}) {
    if (!isCurrent) return;
    final previous = _window;
    final retained = growth == null
        ? stream
        : _retainCanonicalWindow(stream, growth);
    _window = retained;
    _controller._rememberConversation(this);
    syncMessagePins();
    if (previous != null && previous.localMessageIds.isNotEmpty) {
      final remaining = retained.localMessageIds.toSet();
      for (final id in previous.localMessageIds) {
        if (!remaining.contains(id)) {
          _controller._store.remove<ChatMessage>(siteUrl, id);
        }
      }
    }
    if (!isCurrent) return;
    _ref?.value = retained;
    if (isCurrent) _controller._enforceSiteRetention(siteUrl, keep: key);
  }

  void syncMessagePins() {
    if (!isCurrent) return;
    final stream = snapshot;
    final viewing = _controller._liveSync.isViewingTarget(siteUrl, target);
    final previous = _completePinInputs;
    if (previous != null &&
        identical(previous.messageIds, stream.messageIds) &&
        identical(previous.localMessageIds, stream.localMessageIds) &&
        previous.viewing == viewing) {
      return;
    }
    _completePinInputs = null;
    final inputs = (
      messageIds: stream.messageIds,
      localMessageIds: stream.localMessageIds,
      viewing: viewing,
    );
    final desired = <int>{...stream.localMessageIds};
    if (viewing) {
      desired.addAll(stream.messageIds);
    }
    if (desired.isEmpty) {
      _messagePins?.release();
      _messagePins = null;
      _completePinInputs = inputs;
      return;
    }
    (_messagePins ??= _ChatMessagePinSet(
      _controller._store,
      siteUrl,
    )).retain(desired);
    if (_messagePins!.length == desired.length) {
      _completePinInputs = inputs;
    }
  }

  void _clearNoticeTimer() {
    _noticeTimer?.cancel();
    _noticeTimer = null;
  }

  void abandonWindowWork() {
    _generation = null;
    _loading = false;
    _attemptedAt = null;
    _olderRequest = null;
    _newerRequest = null;
    _pendingLiveMessageIds.clear();
    _clearNoticeTimer();
  }

  void retire() {
    _retired = true;
    _completePinInputs = null;
    abandonWindowWork();
    _window = null;
    _readReceipts?.retire();
    _readReceipts = null;
    _messagePins?.release();
    _messagePins = null;
  }

  void resetReference({bool dispose = false}) {
    final ref = _ref;
    _ref = null;
    if (ref == null) return;
    ref.value = const ChatStreamState();
    if (dispose) ref.dispose();
  }

  void disposeReference() {
    _ref?.dispose();
    _ref = null;
  }

  void showNotice(String notice) {
    if (!isCurrent) return;
    _clearNoticeTimer();
    final lease = _controller._requests.capture(siteUrl);
    late final Timer timer;
    timer = Timer(const Duration(seconds: 4), () {
      if (!isCurrent || !identical(_noticeTimer, timer)) return;
      _noticeTimer = null;
      if (!lease.isCurrent) return;
      final current = _window;
      if (current?.notice == notice) {
        publish(current!.copyWith(clearNotice: true));
      }
    });
    _noticeTimer = timer;
    publish(snapshot.copyWith(notice: notice));
  }

  void admitLive(ChatMessage message) {
    if (!isCurrent) return;
    final window = snapshot;
    if (!window.fetchedOnce) {
      // Only a page establishes a window: subscriptions resume from an older
      // snapshot cursor, so a replayed arrival would stand in for the present
      // and let a read receipt skip the unread backlog. The record is already
      // stored; a page in flight settles the parked id at its edge, and any
      // later page is requested after the arrival was published.
      if (_loading) {
        _pendingLiveMessageIds.add(message.id);
      }
      return;
    }
    if (window.canLoadMoreFuture) {
      final pending = _pendingLiveMessageIds;
      if (!pending.add(message.id)) return;
      publish(
        window.copyWith(pendingNewMessages: pending.length, clearError: true),
      );
      return;
    }
    _pendingLiveMessageIds.remove(message.id);
    publish(
      window.copyWith(
        messageIds: ChatMessageTimeline.admitLive(
          held: _controller._timelineSnapshot(siteUrl, window.messageIds),
          message: message,
        ),
        localMessageIds: _controller._retireCanonicalLocals(siteUrl, window, [
          message,
        ]),
        clearError: true,
      ),
      growth: _ChatWindowGrowth.future,
    );
  }

  ChatStreamState _retainCanonicalWindow(
    ChatStreamState stream,
    _ChatWindowGrowth growth,
  ) {
    final original = stream.messageIds;
    var ids = original;
    var droppedPast = false;
    var droppedFuture = false;
    final limit = _controller._maxRetainedCanonicalMessageIdsPerSite;
    if (limit != null && ids.length > limit) {
      if (growth == _ChatWindowGrowth.replacement) {
        final anchor = stream.anchorMessageId ?? stream.lastReadOnOpen;
        final anchorIndex = anchor == null ? -1 : ids.indexOf(anchor);
        var start = anchorIndex < 0
            ? ids.length - limit
            : anchorIndex - (limit ~/ 2);
        final latestStart = ids.length - limit;
        if (start < 0) start = 0;
        if (start > latestStart) start = latestStart;
        droppedPast = start > 0;
        droppedFuture = start + limit < ids.length;
        ids = List.unmodifiable(ids.sublist(start, start + limit));
      } else {
        final retained = ChatMessageTimeline.retain(
          ids: ids,
          maxLength: limit,
          edge: growth == _ChatWindowGrowth.past
              ? ChatTimelineRetainedEdge.past
              : ChatTimelineRetainedEdge.future,
        );
        ids = retained.ids;
        droppedPast = retained.droppedPast;
        droppedFuture = retained.droppedFuture;
      }
    }

    final backed = _backedRange(ids, growth, stream);
    if (backed == null) {
      if (ids.isNotEmpty) {
        ids = const [];
        droppedPast = true;
        droppedFuture = true;
      }
    } else if (backed.start != 0 || backed.end != ids.length) {
      droppedPast = droppedPast || backed.start > 0;
      droppedFuture = droppedFuture || backed.end < ids.length;
      ids = List.unmodifiable(ids.sublist(backed.start, backed.end));
    }

    if (identical(ids, original) && !droppedPast && !droppedFuture) {
      return stream;
    }
    return stream.copyWith(
      messageIds: ids,
      canLoadMorePast: stream.canLoadMorePast || droppedPast,
      canLoadMoreFuture: stream.canLoadMoreFuture || droppedFuture,
      fetchedOnce: ids.isNotEmpty || original.isEmpty
          ? stream.fetchedOnce
          : false,
    );
  }

  ({int start, int end})? _backedRange(
    List<int> ids,
    _ChatWindowGrowth growth,
    ChatStreamState stream,
  ) {
    if (ids.isEmpty) return (start: 0, end: 0);
    final runs = <({int start, int end})>[];
    var index = 0;
    while (index < ids.length) {
      while (index < ids.length &&
          !_controller._holdsMessageSlot(siteUrl, ids[index])) {
        index++;
      }
      if (index == ids.length) break;
      final start = index;
      while (index < ids.length &&
          _controller._holdsMessageSlot(siteUrl, ids[index])) {
        index++;
      }
      runs.add((start: start, end: index));
    }
    if (runs.isEmpty) return null;
    if (growth == _ChatWindowGrowth.past) return runs.first;
    if (growth == _ChatWindowGrowth.future) return runs.last;

    final anchor = stream.anchorMessageId ?? stream.lastReadOnOpen;
    final anchorIndex = anchor == null ? -1 : ids.indexOf(anchor);
    if (anchorIndex >= 0) {
      for (final run in runs) {
        if (run.start <= anchorIndex && anchorIndex < run.end) return run;
      }
    }
    var longest = runs.last;
    for (final run in runs) {
      if (run.end - run.start > longest.end - longest.start) longest = run;
    }
    return longest;
  }

  Future<_ChatWindowFetchResult> fetchWindow({
    required bool fromLastRead,
    int? targetMessageId,
    bool anchorAtEnd = false,
  }) async {
    if (!isCurrent) return _ChatWindowFetchResult.cancelled;
    _loading = true;
    _clearNoticeTimer();
    _attemptedAt = _controller._clock();

    final lease = _controller._requests.capture(siteUrl);
    final generation = _ChatWindowGeneration();
    _generation = generation;
    bool ownsRequest() => isCurrent && identical(_generation, generation);
    _olderRequest = null;
    _newerRequest = null;
    final held = snapshot;
    publish(
      held.copyWith(
        loading: held.messageIds.isEmpty,
        loadingOlder: false,
        loadingNewer: false,
        clearError: true,
        clearNotice: true,
      ),
    );

    try {
      final requestCredentials = await _controller._requests.credentialsFor(
        siteUrl,
      );
      final apiKey = requestCredentials.apiKey;
      if (!_controller._requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }
      final clientId = requestCredentials.clientId;
      if (!_controller._requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }

      final bookmarkVersion = _controller._bookmarkVersion(siteUrl);
      final page = target.threadId == null
          ? await requestCredentials.run(
              () => _controller.api.chatMessages(
                siteUrl: siteUrl,
                channelId: target.channelId,
                targetMessageId: targetMessageId,
                fromLastRead: fromLastRead,
                pageSize: ChatController.pageSize,
                apiKey: apiKey,
                clientId: clientId,
              ),
            )
          : await requestCredentials.run(
              () => _controller.api.chatThreadMessages(
                siteUrl: siteUrl,
                channelId: target.channelId,
                threadId: target.threadId!,
                targetMessageId: targetMessageId,
                pageSize: ChatController.pageSize,
                apiKey: apiKey,
                clientId: clientId,
              ),
            );
      if (!_controller._requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }
      lease.commit(() {
        if (!ownsRequest()) return;
        final current = _window ?? held;
        final heldIds = held.messageIds.toSet();
        final pageIds = {for (final message in page.messages) message.id};
        final arrivedWhileLoading = [
          for (final id in current.messageIds)
            if (!heldIds.contains(id) && !pageIds.contains(id))
              ?_controller._store.read<ChatMessage>(siteUrl, id),
        ];
        _controller._putMessages(
          siteUrl,
          page.messages,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        final pendingIds = _pendingLiveMessageIds;
        final List<int> messageIds;
        var retired = page.messages;
        if (page.canLoadMoreFuture) {
          messageIds = ChatMessageTimeline.merge(
            held: _controller._timelineSnapshot(siteUrl, const []),
            arrived: page.messages,
            mode: ChatTimelineMergeMode.sortedUnion,
          );
          pendingIds
            ..removeAll(pageIds)
            ..addAll(arrivedWhileLoading.map((message) => message.id));
        } else {
          final seam = _controller._withSeamStragglers(
            siteUrl,
            pendingIds,
            ChatMessageTimeline.merge(
              held: _controller._timelineSnapshot(siteUrl, const []),
              arrived: [...page.messages, ...arrivedWhileLoading],
              mode: ChatTimelineMergeMode.sortedUnion,
            ),
          );
          messageIds = seam.ids;
          retired = [...page.messages, ...seam.stragglers];
        }
        final lastReadOnOpen = target.threadId == null
            ? _controller
                  .channel(siteUrl, target.channelId)
                  ?.membership
                  .lastReadMessageId
            : _controller
                  .thread(siteUrl, target.threadId!)
                  ?.membership
                  ?.lastReadMessageId;
        publish(
          ChatStreamState(
            messageIds: messageIds,
            localMessageIds: _controller._retireCanonicalLocals(
              siteUrl,
              current,
              retired,
            ),
            canLoadMorePast: page.canLoadMorePast,
            canLoadMoreFuture: page.canLoadMoreFuture,
            pendingNewMessages: pendingIds.length,
            fetchedOnce: true,
            fetches: held.fetches + 1,
            lastReadOnOpen: lastReadOnOpen,
            anchorMessageId: anchorAtEnd
                ? messageIds.lastOrNull
                : targetMessageId ?? page.targetMessageId ?? lastReadOnOpen,
          ),
          growth: _ChatWindowGrowth.replacement,
        );
        _controller._sendCoordinator.releaseReconciliationIfSettled(
          siteUrl,
          target,
        );
      });
      return _ChatWindowFetchResult.loaded;
    } catch (error) {
      if (!_controller._requestIsCurrent(lease, ownsRequest)) {
        return _ChatWindowFetchResult.cancelled;
      }

      lease.commit(() {
        if (!ownsRequest()) return;
        final current = _window ?? const ChatStreamState();
        if (!current.fetchedOnce) _pendingLiveMessageIds.clear();
        final replacesDestination =
            current.messageIds.isEmpty && current.localMessageIds.isEmpty;
        publish(
          current.copyWith(
            fetchedOnce: true,
            error: replacesDestination
                ? target.threadId == null
                      ? appL10n.couldNotLoadThisChannel
                      : appL10n.couldNotLoadThisThread
                : null,
          ),
        );
        final siteDidNotAnswer =
            error is SiteLookupException &&
            error.failure == SiteLookupFailure.unreachable &&
            error.statusCode == null;
        if (replacesDestination && siteDidNotAnswer) {
          _controller.onSiteUnreachable?.call(siteUrl);
        }
      });
      return targetMessageId != null &&
              error is SiteLookupException &&
              error.statusCode == 404
          ? _ChatWindowFetchResult.missingTarget
          : _ChatWindowFetchResult.failed;
    } finally {
      if (_controller._requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          if (!ownsRequest()) return;
          final current = _window;
          if (current != null && current.loading) {
            publish(current.copyWith(loading: false));
          }
          if (ownsRequest()) _loading = false;
        });
      }
    }
  }

  Future<void> loadOlder() async {
    if (!isCurrent || target.channelId <= 0) return;
    final held = snapshot;
    final before = held.oldestId;
    if (!held.canLoadMorePast || before == null) return;

    if (_loading || _olderRequest != null) return;

    final lease = _controller._requests.capture(siteUrl);
    final generation = _generation ??= _ChatWindowGeneration();
    final request = _ChatPageRequest(generation);
    _olderRequest = request;
    bool ownsRequest() =>
        isCurrent &&
        identical(_generation, request.generation) &&
        identical(_olderRequest, request);
    publish(held.copyWith(loadingOlder: true));

    try {
      final requestCredentials = await _controller._requests.credentialsFor(
        siteUrl,
      );
      final apiKey = requestCredentials.apiKey;
      if (!_controller._requestIsCurrent(lease, ownsRequest)) return;
      final clientId = requestCredentials.clientId;
      if (!_controller._requestIsCurrent(lease, ownsRequest)) return;

      final bookmarkVersion = _controller._bookmarkVersion(siteUrl);
      final page = target.threadId == null
          ? await requestCredentials.run(
              () => _controller.api.chatMessages(
                siteUrl: siteUrl,
                channelId: target.channelId,
                before: before,
                pageSize: ChatController.pageSize,
                apiKey: apiKey,
                clientId: clientId,
              ),
            )
          : await requestCredentials.run(
              () => _controller.api.chatThreadMessages(
                siteUrl: siteUrl,
                channelId: target.channelId,
                threadId: target.threadId!,
                before: before,
                pageSize: ChatController.pageSize,
                apiKey: apiKey,
                clientId: clientId,
              ),
            );
      if (!_controller._requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        if (!ownsRequest()) {
          return;
        }
        _controller._putMessages(
          siteUrl,
          page.messages,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        final current = _window ?? const ChatStreamState();
        final merged = ChatMessageTimeline.merge(
          held: _controller._timelineSnapshot(siteUrl, current.messageIds),
          arrived: page.messages,
          mode: ChatTimelineMergeMode.prependPage,
        );
        publish(
          current.copyWith(
            messageIds: merged,
            localMessageIds: _controller._retireCanonicalLocals(
              siteUrl,
              current,
              page.messages,
            ),
            canLoadMorePast:
                merged.length > current.messageIds.length &&
                page.canLoadMorePast,
            fetchedOnce: true,
          ),
          growth: _ChatWindowGrowth.past,
        );
        _controller._sendCoordinator.releaseReconciliationIfSettled(
          siteUrl,
          target,
        );
      });
    } catch (error) {
      if (!_controller._requestIsCurrent(lease, ownsRequest)) {
        return;
      }
    } finally {
      if (_controller._requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          if (!ownsRequest()) {
            return;
          }
          final current = _window;
          if (current != null) {
            publish(current.copyWith(loadingOlder: false));
          }
          if (ownsRequest()) _olderRequest = null;
        });
      }
    }
  }

  Future<void> loadNewer() async {
    if (!isCurrent || target.channelId <= 0) return;
    final held = snapshot;
    final after = held.newestId;
    if (!held.canLoadMoreFuture || after == null) return;

    if (_loading || _newerRequest != null) return;

    final lease = _controller._requests.capture(siteUrl);
    final generation = _generation ??= _ChatWindowGeneration();
    final request = _ChatPageRequest(generation);
    _newerRequest = request;
    bool ownsRequest() =>
        isCurrent &&
        identical(_generation, request.generation) &&
        identical(_newerRequest, request);
    publish(held.copyWith(loadingNewer: true));

    try {
      final requestCredentials = await _controller._requests.credentialsFor(
        siteUrl,
      );
      final apiKey = requestCredentials.apiKey;
      if (!_controller._requestIsCurrent(lease, ownsRequest)) return;
      final clientId = requestCredentials.clientId;
      if (!_controller._requestIsCurrent(lease, ownsRequest)) return;

      final bookmarkVersion = _controller._bookmarkVersion(siteUrl);
      final page = target.threadId == null
          ? await requestCredentials.run(
              () => _controller.api.chatMessages(
                siteUrl: siteUrl,
                channelId: target.channelId,
                after: after,
                pageSize: ChatController.pageSize,
                apiKey: apiKey,
                clientId: clientId,
              ),
            )
          : await requestCredentials.run(
              () => _controller.api.chatThreadMessages(
                siteUrl: siteUrl,
                channelId: target.channelId,
                threadId: target.threadId!,
                after: after,
                pageSize: ChatController.pageSize,
                apiKey: apiKey,
                clientId: clientId,
              ),
            );
      if (!_controller._requestIsCurrent(lease, ownsRequest)) return;
      lease.commit(() {
        if (!ownsRequest()) {
          return;
        }
        _controller._putMessages(
          siteUrl,
          page.messages,
          bookmarkVersionAtDispatch: bookmarkVersion,
        );
        final current = _window ?? const ChatStreamState();
        var merged = ChatMessageTimeline.merge(
          held: _controller._timelineSnapshot(siteUrl, current.messageIds),
          arrived: page.messages,
          mode: ChatTimelineMergeMode.appendPage,
        );
        final canLoadMoreFuture =
            merged.length > current.messageIds.length && page.canLoadMoreFuture;
        final pendingIds = _pendingLiveMessageIds;
        var retired = page.messages;
        pendingIds.removeAll(page.messages.map((message) => message.id));
        if (!canLoadMoreFuture) {
          final seam = _controller._withSeamStragglers(
            siteUrl,
            pendingIds,
            merged,
          );
          merged = seam.ids;
          retired = [...page.messages, ...seam.stragglers];
        }

        publish(
          current.copyWith(
            messageIds: merged,
            localMessageIds: _controller._retireCanonicalLocals(
              siteUrl,
              current,
              retired,
            ),
            canLoadMoreFuture: canLoadMoreFuture,
            pendingNewMessages: canLoadMoreFuture ? pendingIds.length : 0,
            fetchedOnce: true,
          ),
          growth: _ChatWindowGrowth.future,
        );
        _controller._sendCoordinator.releaseReconciliationIfSettled(
          siteUrl,
          target,
        );
      });
    } catch (error) {
      if (!_controller._requestIsCurrent(lease, ownsRequest)) {
        return;
      }
    } finally {
      if (_controller._requestIsCurrent(lease, ownsRequest)) {
        lease.commit(() {
          if (!ownsRequest()) {
            return;
          }
          final current = _window;
          if (current != null) {
            publish(current.copyWith(loadingNewer: false));
          }
          if (ownsRequest()) _newerRequest = null;
        });
      }
    }
  }

  ChatReadReceiptOwner get readReceipts =>
      _readReceipts ??= ChatReadReceiptOwner(
        siteUrl: siteUrl,
        target: target,
        api: _controller.api,
        requests: _controller._requests,
        retries: _controller._readReceiptRetries,
        clock: _controller._clock,
        isCurrent: () => isCurrent,
        publish: (admission, viewedAt) =>
            _controller._publishRead(siteUrl, target, admission, viewedAt),
      );
}
