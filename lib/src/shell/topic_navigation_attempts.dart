import 'dart:async';
import 'dart:math' as math;

import '../data/site_lifecycle.dart';
import '../data/store.dart';
import '../models/content_route.dart';
import '../models/post.dart';
import 'topic_data_owner.dart';

abstract interface class TopicNavigationTab {
  String? get siteUrl;
  String? get tabId;
  ContentRoute? get currentContent;
  TopicDetail? get currentTopic;
  List<int> get currentTopicStreamIds;
  bool get currentTopicSummary;
}

final class _TopicJumpAttempt {
  _TopicJumpAttempt({
    required this.key,
    required this.tabId,
    required this.revision,
    required this.lease,
  });

  final ({String siteUrl, int topicId}) key;
  final String tabId;
  final int revision;
  final SiteLease lease;
  final _retired = Completer<void>();

  Future<T?> waitFor<T>(Future<T?> operation) async {
    final detach = lease.onRetire(retire);
    try {
      return await Future.any<T?>([
        operation,
        _retired.future.then<T?>((_) => null),
      ]);
    } finally {
      detach();
    }
  }

  void retire() {
    if (!_retired.isCompleted) _retired.complete();
  }
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

final class TopicNavigationAttempts {
  TopicNavigationAttempts({
    required this._focusedContext,
    required this._store,
    required this._topicData,
    required this._lifecycle,
    required this._openPost,
    required this._openScrubbedPost,
    required this._changed,
    required this._loadTimeout,
  });

  final TopicNavigationTab Function() _focusedContext;
  final Store _store;
  final TopicDataOwner _topicData;
  final SiteLifecycle _lifecycle;
  final void Function(int postNumber, {bool loadAroundPost}) _openPost;
  final void Function(int postNumber) _openScrubbedPost;
  final void Function() _changed;
  final Duration _loadTimeout;
  final _revisions = <String, int>{};
  final _jumps = <({String siteUrl, int topicId}), _TopicJumpAttempt>{};
  _TopicPostHighlight? _highlight;
  void Function()? _detachHighlight;
  Timer? _highlightTimer;
  bool _disposed = false;

  static const _highlightDuration = Duration(milliseconds: 2200);

  /// Enough posts below a drag's position to fill any screen it stops on.
  static const _scrubChunk = 20;

  int revisionFor(String? tabId) => _revisions[tabId] ?? 0;

  void explicitTarget(String siteUrl, String tabId) {
    _revisions[tabId] = revisionFor(tabId) + 1;
    _retireJumps(
      (attempt) => attempt.key.siteUrl == siteUrl && attempt.tabId == tabId,
    );
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
    final postId = stream[boundedIndex - 1];
    final attempt = _TopicJumpAttempt(
      key: (siteUrl: siteUrl, topicId: topic.id),
      tabId: tabId,
      revision: revision,
      lease: _lifecycle.capture(siteUrl),
    );
    _replaceJump(attempt);

    try {
      var target = _store.read<Post>(siteUrl, postId);
      final loadAroundPost = target == null;
      if (target == null) {
        final request = _topicData
            .forLease(siteUrl, attempt.lease)
            ?.ensurePost(
              topic.id,
              postId,
              isInterested: () => _isCurrent(attempt),
            );
        if (request == null) return false;
        target = await attempt.waitFor(request);
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

  /// Takes the reader to progress [index] for a timeline drag.
  ///
  /// Unlike a jump, the posts arrive before the route changes. A route that
  /// names a post not yet loaded drops the list for a skeleton, and a drag
  /// would flash one at every position it stopped at. It also means a load the
  /// drag has moved on from has nothing to undo: the reader goes nowhere once
  /// [isWanted] answers false, and its posts wait in the store for a return.
  Future<bool> scrubCurrentTopicTo(
    int index, {
    required bool Function() isWanted,
  }) async {
    final document = _focusedContext();
    final siteUrl = document.siteUrl;
    final route = document.currentContent;
    final topic = document.currentTopic;
    final tabId = document.tabId;
    final stream = document.currentTopicStreamIds;
    if (siteUrl == null ||
        route?.topicId == null ||
        topic == null ||
        tabId == null ||
        stream.isEmpty) {
      return false;
    }
    final attempt = _TopicJumpAttempt(
      key: (siteUrl: siteUrl, topicId: topic.id),
      tabId: tabId,
      revision: revisionFor(tabId),
      lease: _lifecycle.capture(siteUrl),
    );
    _replaceJump(attempt);
    bool wanted() => _isCurrent(attempt) && isWanted();

    try {
      final data = _topicData.forLease(siteUrl, attempt.lease);
      if (data == null) return false;
      final int? postNumber;
      if (topic.isMegaTopic && !document.currentTopicSummary) {
        final requested = math.max(index, 1);
        postNumber = await attempt.waitFor(
          data.ensureMegaRun(
            topic.id,
            slug: route!.slug ?? '',
            postNumber: requested,
            isInterested: wanted,
          ),
        );
      } else {
        final target = index.clamp(1, stream.length) - 1;
        final end = math.min(target + _scrubChunk, stream.length);
        final held = await attempt.waitFor(
          data.ensurePosts(
            topic.id,
            stream.sublist(math.max(0, end - _scrubChunk), end),
            shouldFetch: wanted,
            shouldPublish: () => _isCurrent(attempt),
          ),
        );
        if (held != true) return false;
        postNumber = _store.read<Post>(siteUrl, stream[target])?.postNumber;
      }
      if (postNumber == null || !wanted()) return false;
      _openScrubbedPost(postNumber);
      return true;
    } catch (error) {
      return false;
    } finally {
      if (identical(_jumps[attempt.key], attempt)) {
        final _ = _jumps.remove(attempt.key);
      }
    }
  }

  /// Drops a jump still waiting for its post, so it cannot land under a drag
  /// that started after it.
  void abandonJump() {
    final document = _focusedContext();
    final siteUrl = document.siteUrl;
    final topicId = document.currentTopic?.id;
    if (siteUrl == null || topicId == null) return;
    _jumps.remove((siteUrl: siteUrl, topicId: topicId))?.retire();
  }

  void _replaceJump(_TopicJumpAttempt attempt) {
    _jumps[attempt.key]?.retire();
    _jumps[attempt.key] = attempt;
  }

  void _retireJumps(bool Function(_TopicJumpAttempt) matches) {
    _jumps.removeWhere((_, attempt) {
      if (!matches(attempt)) return false;
      attempt.retire();
      return true;
    });
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
    if (_disposed) return;
    clearHighlight(notify: false);
    final lease = _lifecycle.capture(siteUrl);
    if (!lease.isCurrent) return;
    final highlight = _highlight = _TopicPostHighlight(
      siteUrl: siteUrl,
      topicId: topicId,
      postNumber: postNumber,
      tabId: _focusedContext().tabId,
    );
    _detachHighlight = lease.onRetire(() {
      if (identical(_highlight, highlight)) clearHighlight(notify: false);
    });
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
    _detachHighlight?.call();
    _detachHighlight = null;
    _highlightTimer?.cancel();
    _highlightTimer = null;
    _highlight = null;
    if (changed && notify && !_disposed) _changed();
  }

  void forgetSite(String siteUrl) {
    _retireJumps((attempt) => attempt.key.siteUrl == siteUrl);
    if (_highlight?.siteUrl == siteUrl) clearHighlight(notify: false);
  }

  void closeTab(String siteUrl, String tabId) {
    explicitTarget(siteUrl, tabId);
    final highlight = _highlight;
    if (highlight?.siteUrl == siteUrl && highlight?.tabId == tabId) {
      clearHighlight(notify: false);
    }
  }

  void dispose() {
    _disposed = true;
    clearHighlight(notify: false);
    _retireJumps((_) => true);
    _revisions.clear();
  }
}
