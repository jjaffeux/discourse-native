import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

typedef TopicReaderCommandSnapshot = ({
  List<int> postIds,
  List<int> streamIds,
  bool progressByPostNumber,
  bool hasEarlier,
});
typedef TopicReaderCommandIdentity = ({
  Object owner,
  Object? session,
  String siteUrl,
  int topicId,
  String? tabId,
  int navigationRevision,
});
typedef TopicReaderCommandScroll = ({
  double pixels,
  double minScrollExtent,
  double maxScrollExtent,
  double viewportExtent,
});
typedef TopicReaderCommandPost = ({
  double top,
  double bottom,
  bool? bodyComplete,
});

abstract interface class TopicReaderNavigation {
  TopicReaderCommandIdentity get identity;
  bool get isCurrent;
  TopicReaderCommandSnapshot get snapshot;
  int? get progressPosition;
  bool get restored;
  bool get restoring;
  Future<bool> hydrateIndex(int index);
  Future<void> loadEarlier();
  DateTime? dayForPost(int postId);
  void beginDayJump();
  void finishDayJump();
}

abstract interface class TopicReaderCommandGeometry {
  TopicReaderCommandScroll? get commandScroll;
  TopicReaderCommandPost? commandPost(int postId);
  int get leadingItems;
  void jumpToPixels(double pixels);
  void jumpToPost(int itemIndex);
  TopicReaderCommandBoundary? captureBoundary();
}

abstract interface class TopicReaderCommandBoundary {
  bool get isCurrent;
  bool get hasItems;
  void revealLastItem();
  void jumpToEdge({required bool end});
}

/// Explicit commands share a reader lifetime, but keep their admission rules.
final class TopicReaderInteraction {
  TopicReaderInteraction({
    required this._geometry,
    required this._postFrame,
    required this._scheduleFrame,
    required this._focus,
    required this._scheduleLook,
  });

  final TopicReaderCommandGeometry _geometry;
  final void Function(VoidCallback) _postFrame;
  final VoidCallback _scheduleFrame;
  final VoidCallback _focus;
  final VoidCallback _scheduleLook;
  final _selection = ValueNotifier<int?>(null);
  ValueListenable<int?> get selection => _selection;
  TopicReaderNavigation? _navigation;
  Object? _postLoad;
  int? _postEndTarget;
  Object? _dayJump;
  int _boundaryRevision = 0;
  bool _disposed = false;

  void bind(TopicReaderNavigation navigation) {
    final previous = _navigation;
    final before = previous?.identity;
    final after = navigation.identity;
    final sameReader =
        before != null &&
        identical(before.owner, after.owner) &&
        identical(before.session, after.session) &&
        before.siteUrl == after.siteUrl &&
        before.topicId == after.topicId &&
        before.tabId == after.tabId;
    _navigation = navigation;
    if (!sameReader) {
      _postLoad = null;
      clearSelection();
      _dayJump = null;
      _boundaryRevision++;
    } else if (before.navigationRevision != after.navigationRevision) {
      _dayJump = null;
    }
  }

  void clearSelection() {
    _selection.value = null;
    _postEndTarget = null;
  }

  bool navigatePost({
    required TopicReaderCommandSnapshot snapshot,
    required int direction,
    required int? visiblePostId,
    required void Function(int postId) selectVisiblePost,
  }) {
    final navigation = _navigation;
    if (navigation == null || _disposed) return false;
    if (_postLoad != null) return true;
    if (_postEndTarget != null && _postEndTarget == _selection.value) {
      return true;
    }
    final posts = snapshot.progressByPostNumber
        ? snapshot.postIds
        : snapshot.streamIds;
    final current = _selection.value ?? visiblePostId;
    if (current != null && _scrollWithinPost(current, direction)) return true;
    final currentIndex = current == null
        ? (navigation.progressPosition ?? 1) - 1
        : posts.indexOf(current);
    final nextIndex = currentIndex + direction;
    if (nextIndex < 0 || nextIndex >= posts.length) return false;
    final nextId = posts[nextIndex];
    _selection.value = nextId;
    _postEndTarget = direction < 0 ? nextId : null;
    _focus();
    final loadedIndex = snapshot.postIds.indexOf(nextId);
    if (loadedIndex >= 0) {
      selectVisiblePost(nextId);
      _geometry.jumpToPost(loadedIndex + (snapshot.hasEarlier ? 1 : 0));
      _scheduleLook();
    } else {
      final token = Object();
      _postLoad = token;
      unawaited(() async {
        try {
          final loaded = await navigation.hydrateIndex(nextIndex + 1);
          if (_disposed || !identical(_postLoad, token)) return;
          if (!loaded) clearSelection();
        } finally {
          if (identical(_postLoad, token)) _postLoad = null;
        }
      }());
    }
    return true;
  }

  bool _scrollWithinPost(int postId, int direction) {
    final position = _geometry.commandScroll;
    final bounds = _geometry.commandPost(postId);
    if (position == null || bounds == null) return false;
    final height = position.viewportExtent;
    if (height <= 0 || bounds.bottom <= 0 || bounds.top >= height) return false;
    if (bounds.bodyComplete == false) {
      _selection.value = postId;
      _focus();
      return true;
    }
    final remaining = direction > 0 ? bounds.bottom - height : -bounds.top;
    if (remaining <= 0.5) return false;
    final delta = math.min(height * 0.9, remaining) * direction;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() <= 0.5) return false;
    _selection.value = postId;
    _focus();
    _geometry.jumpToPixels(target);
    return true;
  }

  bool revealPostEnd() {
    final postId = _postEndTarget;
    if (postId == null) return false;
    if (_selection.value != postId) {
      _postEndTarget = null;
      return false;
    }
    final navigation = _navigation;
    if (navigation == null || !navigation.restored || navigation.restoring) {
      return false;
    }
    final bounds = _geometry.commandPost(postId);
    final position = _geometry.commandScroll;
    if (bounds == null || bounds.bodyComplete != true || position == null) {
      return false;
    }
    _postEndTarget = null;
    if (bounds.bottom - bounds.top <= position.viewportExtent) return false;
    final target = (position.pixels + bounds.bottom - position.viewportExtent)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() <= 0.5) return false;
    _geometry.jumpToPixels(target);
    return true;
  }

  void jumpToBoundary({required bool end}) {
    final revision = ++_boundaryRevision;
    final boundary = _geometry.captureBoundary();
    if (boundary == null) return;
    if (!end || !boundary.hasItems) {
      boundary.jumpToEdge(end: end);
      return;
    }
    void correctToEnd({bool repeat = true}) {
      if (_disposed || revision != _boundaryRevision || !boundary.isCurrent) {
        return;
      }
      boundary.jumpToEdge(end: true);
      if (!repeat) return;
      _postFrame(() => correctToEnd(repeat: false));
      _scheduleFrame();
    }

    boundary.revealLastItem();
    _postFrame(() => correctToEnd());
    _scheduleFrame();
  }

  Future<void> jumpToDayStart(DateTime day) async {
    final navigation = _navigation;
    if (navigation == null || _disposed) return;
    final token = Object();
    _dayJump = token;
    navigation.beginDayJump();
    bool isCurrent() =>
        !_disposed && identical(_dayJump, token) && navigation.isCurrent;
    while (isCurrent()) {
      final snapshot = navigation.snapshot;
      if (!snapshot.hasEarlier || snapshot.postIds.isEmpty) break;
      if (navigation.dayForPost(snapshot.postIds.first) != day) break;
      final before = List<int>.of(snapshot.postIds);
      await navigation.loadEarlier();
      if (!isCurrent()) return;
      if (listEquals(before, navigation.snapshot.postIds)) break;
    }
    if (!isCurrent()) return;
    void jump() {
      if (!isCurrent()) return;
      final index = navigation.snapshot.postIds.indexWhere(
        (id) => navigation.dayForPost(id) == day,
      );
      if (index >= 0) _geometry.jumpToPost(index + _geometry.leadingItems);
    }

    _postFrame(() {
      if (!isCurrent()) return;
      jump();
      _postFrame(() {
        if (!isCurrent()) return;
        jump();
        if (!isCurrent()) return;
        _dayJump = null;
        navigation.finishDayJump();
      });
    });
  }

  void dispose() {
    _disposed = true;
    _postLoad = null;
    _dayJump = null;
    _navigation = null;
    _selection.dispose();
  }
}
