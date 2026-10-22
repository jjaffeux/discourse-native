part of 'shell_controller.dart';

final class _TopicJumpAttempt {
  const _TopicJumpAttempt({
    required this.key,
    required this.tabId,
    required this.revision,
    required this.lease,
    required this.postId,
  });

  final ({String siteUrl, int topicId}) key;
  final String tabId;
  final int revision;
  final SiteLease lease;
  final int postId;
}

final class _TopicPostHighlight {
  _TopicPostHighlight({
    required this.siteUrl,
    required this.topicId,
    required this.postNumber,
    required this.tabId,
  });

  final String siteUrl;
  final int topicId;
  final int postNumber;
  final String? tabId;
  bool visible = false;
}

final class _TopicNavigationAttempts {
  _TopicNavigationAttempts({
    required this._focusedContext,
    required this._store,
    required this._topicData,
    required this._lifecycle,
    required this._openPost,
    required this._changed,
    required this._loadTimeout,
  });

  final ShellTabContext Function() _focusedContext;
  final Store _store;
  final TopicDataOwner _topicData;
  final SiteLifecycle _lifecycle;
  final void Function(int postNumber, {bool loadAroundPost}) _openPost;
  final void Function() _changed;
  final Duration _loadTimeout;
  final _revisions = <String, int>{};
  final _jumps = <({String siteUrl, int topicId}), _TopicJumpAttempt>{};
  _TopicPostHighlight? _highlight;
  Timer? _highlightTimer;
  bool _disposed = false;

  static const _highlightDuration = Duration(milliseconds: 2200);

  int revisionFor(String? tabId) => _revisions[tabId] ?? 0;

  void explicitTarget(String tabId) {
    _revisions[tabId] = revisionFor(tabId) + 1;
  }

  Future<bool> jumpToCurrentTopicIndex(int index) async {
    final document = _focusedContext();
    final siteUrl = document.siteUrl;
    final route = document.currentContent;
    final topic = document.currentTopic;
    final tabId = document.tabId;
    final revision = revisionFor(tabId);
    if (siteUrl == null ||
        route?.topicId == null ||
        topic == null ||
        tabId == null ||
        document.currentTopicStreamIds.isEmpty) {
      return false;
    }
    if (topic.isMegaTopic && !document.currentTopicSummary) {
      _openPost(math.max(index, 1));
      return true;
    }

    final stream = document.currentTopicStreamIds;
    final boundedIndex = index.clamp(1, stream.length);
    final attempt = _TopicJumpAttempt(
      key: (siteUrl: siteUrl, topicId: topic.id),
      tabId: tabId,
      revision: revision,
      lease: _lifecycle.capture(siteUrl),
      postId: stream[boundedIndex - 1],
    );
    _jumps[attempt.key] = attempt;

    try {
      var target = _store.read<Post>(siteUrl, attempt.postId);
      final loadAroundPost = target == null;
      if (target == null) {
        target = await _topicData
            .forLease(siteUrl, attempt.lease)
            ?.ensurePost(
              topic.id,
              attempt.postId,
              isInterested: () => _isCurrent(attempt),
            );
        if (target == null) return false;
      }
      if (!_isCurrent(attempt)) return false;
      _openPost(target.postNumber, loadAroundPost: loadAroundPost);
      return true;
    } catch (error) {
      return false;
    } finally {
      if (identical(_jumps[attempt.key], attempt)) {
        final _ = _jumps.remove(attempt.key);
      }
    }
  }

  bool _isCurrent(_TopicJumpAttempt attempt) {
    if (_disposed ||
        !identical(_jumps[attempt.key], attempt) ||
        !attempt.lease.isCurrent) {
      return false;
    }
    final focused = _focusedContext();
    return focused.tabId == attempt.tabId &&
        focused.siteUrl == attempt.key.siteUrl &&
        revisionFor(focused.tabId) == attempt.revision &&
        focused.currentContent?.topicId == attempt.key.topicId;
  }

  bool isPostHighlighted(String siteUrl, int topicId, int postNumber) {
    final highlight = _highlight;
    return highlight != null &&
        highlight.visible &&
        highlight.tabId == _focusedContext().tabId &&
        highlight.siteUrl == siteUrl &&
        highlight.topicId == topicId &&
        highlight.postNumber == postNumber;
  }

  void requestHighlight({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  }) {
    _highlightTimer?.cancel();
    _highlight = _TopicPostHighlight(
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      tabId: _focusedContext().tabId,
    );
    _highlightTimer = Timer(_loadTimeout, clearHighlight);
    armHighlightIfLoaded();
  }

  void armHighlightIfLoaded() {
    final highlight = _highlight;
    if (highlight == null || highlight.visible) return;
    final topic = _store.read<TopicDetail>(
      highlight.siteUrl,
      highlight.topicId,
    );
    final targetLoaded = topic?.stream.any(
      (postId) =>
          _store.read<Post>(highlight.siteUrl, postId)?.postNumber ==
          highlight.postNumber,
    );
    if (targetLoaded != true) return;

    highlight.visible = true;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(_highlightDuration, clearHighlight);
  }

  void clearHighlight({bool notify = true}) {
    final changed = _highlight != null;
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _highlight = null;
    if (changed && notify && !_disposed) _changed();
  }

  void forgetSite(String siteUrl) {
    _jumps.removeWhere((key, _) => key.siteUrl == siteUrl);
  }

  void dispose() {
    _disposed = true;
    clearHighlight(notify: false);
    _jumps.clear();
    _revisions.clear();
  }
}
