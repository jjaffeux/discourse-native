part of 'chat_controller.dart';

/// One document's contiguous chat window; message records and writes stay shared.
final class ChatConversationReader {
  ChatConversationReader._(this._controller, this._owner);

  final ChatController _controller;
  final _ChatConversationStream _owner;
  bool _disposed = false;

  String get siteUrl => _owner.siteUrl;
  ChatStreamTarget get target => _owner.target;
  bool get isCurrent => !_disposed && _owner.isCurrent;
  ChatStreamState get stream => _owner.snapshot;
  List<ChatMessage> get messages => [
    for (final id in [...stream.messageIds, ...stream.localMessageIds])
      ?_controller._store.read<ChatMessage>(siteUrl, id),
  ];
  ValueListenable<ChatStreamState> get changes => _owner.listenable;

  Object beginViewing() =>
      isCurrent ? _controller._beginViewing(_owner) : Object();
  void endViewing(Object token) => _controller._endViewing(_owner, token);

  Future<void> open({int? targetMessageId, bool force = false}) async {
    if (!isCurrent) return;
    final held = stream;
    final backed = _controller._canonicalWindowIsBacked(siteUrl, held);
    if (!force &&
        targetMessageId == null &&
        _owner.attemptedRecently &&
        (_owner._openIntent != null ||
            _owner._loading ||
            held.fetchedOnce && backed)) {
      return;
    }
    final intent = Object();
    _owner._openIntent = intent;
    _owner._attemptedAt = _controller._clock();
    try {
      if (!backed) {
        _owner.publish(
          held.copyWith(
            messageIds: const [],
            loadingOlder: false,
            loadingNewer: false,
            fetchedOnce: false,
            revision: held.revision + 1,
          ),
        );
      }
      if (target case final ChatThreadTarget thread) {
        final detail = await _controller.refreshThreadDetail(siteUrl, thread);
        if (detail == null ||
            !isCurrent ||
            !identical(_owner._openIntent, intent)) {
          return;
        }
        _controller._liveSync.ensureThreadSubscription(siteUrl, thread);
      } else {
        _controller._lastOpenedChannelIds[siteUrl] = target.channelId;
      }
      final result = await _owner.fetchWindow(
        fromLastRead: target is ChatChannelTarget && targetMessageId == null,
        targetMessageId: targetMessageId,
      );
      if (result == _ChatWindowFetchResult.missingTarget &&
          targetMessageId != null &&
          target is ChatThreadTarget &&
          isCurrent &&
          identical(_owner._openIntent, intent)) {
        final fallback = await _owner.fetchWindow(fromLastRead: false);
        if (fallback == _ChatWindowFetchResult.loaded) {
          _owner.showNotice(
            appL10n.thatMessageIsUnavailableShowingTheThreadInstead,
          );
        }
      }
    } finally {
      if (identical(_owner._openIntent, intent)) _owner._openIntent = null;
    }
  }

  Future<void> loadOlder() => isCurrent ? _owner.loadOlder() : Future.value();
  Future<void> loadNewer() => isCurrent ? _owner.loadNewer() : Future.value();
  Future<void> showLatest() async {
    if (!isCurrent || stream.atPresent) return;
    await _owner.fetchWindow(fromLastRead: false, anchorAtEnd: true);
  }

  Future<void> markRead(int messageId) => isCurrent
      ? _controller._markReadInWindow(siteUrl, target, messageId, stream)
      : Future.value();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (--_owner._readers != 0 || !_owner.isCurrent) return;
    _owner._openIntent = null;
    for (final token in _owner._viewTokens.toList()) {
      _controller._endViewing(_owner, token);
    }
    if (_owner._readers == 0 && _owner.isCurrent) {
      _owner.syncMessagePins();
      _owner.disposeReference();
      _controller._enforceSiteRetention(siteUrl);
    }
  }
}
