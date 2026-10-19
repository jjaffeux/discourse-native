import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/topic.dart';
import '../models/topic_feed.dart';
import 'shell_controller.dart';
import 'topic_feed_controller.dart';

typedef TopicListCursor = ({int topicId, int index, bool keyboard});

final class TopicListCursorCoordinator {
  TopicListCursorCoordinator({
    required ShellTabContext tab,
    required this._feed,
    TopicListCursor? savedCursor,
    required this._keyboardAvailable,
    required this._afterFrame,
    required this._onCursorChanged,
    required this._onKeyboardSelection,
    required this._revealRow,
    required this._openTopic,
  }) : _tab = tab,
       _destination = tab.currentFeedId ?? 'latest',
       _cursor = ValueNotifier(savedCursor);

  final ShellTabContext _tab;
  final String _destination;
  TopicFeed _feed;
  final ValueNotifier<TopicListCursor?> _cursor;
  final bool Function() _keyboardAvailable;
  final void Function(void Function()) _afterFrame;
  final void Function(TopicListCursor) _onCursorChanged;
  final void Function(Topic?) _onKeyboardSelection;
  final void Function(int) _revealRow;
  final void Function(Topic) _openTopic;
  Object? _keyboardMoveToken;
  Object? _selectionRestoreToken;
  bool _retired = false;

  ValueListenable<TopicListCursor?> get cursor => _cursor;

  bool get _isCurrent =>
      !_retired &&
      _tab.isCurrent &&
      (_tab.currentFeedId ?? 'latest') == _destination;

  TopicFeed _latestFeed() => _tab.currentFeed ?? _feed;

  Topic? _readTopic(int id) => _tab.siteUrl == null
      ? null
      : _tab.shell.store.read<Topic>(_tab.siteUrl!, id);

  Future<void> _ensureSourceRange(int first, int last) async {
    if (!_isCurrent) return;
    await _tab.ensureFeedRange(_destination, firstRow: first, lastRow: last);
  }

  void updateFeed(TopicFeed next) {
    final previous = _feed;
    _feed = next;
    final cursor = _cursor.value;
    if (cursor == null) return;
    var index = next.indexOfTopic(cursor.topicId);
    if (index < 0) {
      var source = previous.sourceRowFor(cursor.index);
      if (previous.loadingIncoming && !next.loadingIncoming) {
        source +=
            (next.totalRows ?? next.rowCount) -
            (previous.totalRows ?? previous.rowCount);
      }
      index = next.visibleRowForSource(source);
    }
    if (index != cursor.index) {
      _saveCursor((
        topicId: cursor.topicId,
        index: index,
        keyboard: cursor.keyboard,
      ));
    }
  }

  void cancelSelectionRestore() => _selectionRestoreToken = null;

  void retire() {
    _retired = true;
    _keyboardMoveToken = null;
    _selectionRestoreToken = null;
  }

  void dispose() {
    retire();
    _cursor.dispose();
  }

  void remember(int topicId, {bool? keyboard}) {
    final index = _latestFeed().indexOfTopic(topicId);
    if (index < 0) return;
    final previous = _cursor.value;
    final cursor = (
      topicId: topicId,
      index: index,
      keyboard:
          keyboard ?? (previous?.topicId == topicId && previous!.keyboard),
    );
    _saveCursor(cursor);
  }

  void _saveCursor(TopicListCursor cursor) {
    _cursor.value = cursor;
    _onCursorChanged(cursor);
  }

  bool move(int direction, {required int firstVisibleRow}) {
    _selectionRestoreToken = null;
    if (_feed.rowCount == 0) return false;
    if (_keyboardMoveToken != null) return true;
    unawaited(_moveSelectionTo(direction, firstVisibleRow));
    return true;
  }

  Future<void> _moveSelectionTo(int direction, int firstVisibleRow) async {
    final token = Object();
    _keyboardMoveToken = token;
    final route = _tab.currentContent;
    bool isCurrent() =>
        _isCurrent &&
        identical(_keyboardMoveToken, token) &&
        _tab.currentContent == route &&
        _keyboardAvailable();
    try {
      var feed = _feed;
      final cursor = _cursor.value;
      final anchor = cursor?.topicId ?? _tab.readingTopicId;
      var index = anchor == null ? -1 : feed.indexOfTopic(anchor);
      TopicFeed sourceFeed() =>
          _tab.shell.topicFeeds.feedFor(_tab.siteUrl!, _destination) ?? feed;
      if (index < 0 &&
          cursor != null &&
          sourceFeed().rowCount > sourceFeed().topicIds.length) {
        final hint = feed.sourceRowFor(cursor.index);
        await _ensureSourceRange(
          hint - TopicFeedController.incomingPageSize,
          hint + TopicFeedController.incomingPageSize,
        );
        if (!isCurrent()) return;
        feed = _latestFeed();
        if (feed.error != null) return;
        for (
          var row = 0;
          sourceFeed().indexOfTopic(cursor.topicId) < 0 &&
              row < sourceFeed().rowCount;
          row += TopicFeedController.incomingPageSize
        ) {
          await _ensureSourceRange(
            row,
            row + TopicFeedController.incomingPageSize - 1,
          );
          if (!isCurrent()) return;
          feed = _latestFeed();
          if (feed.error != null) return;
        }
        if (sourceFeed().indexOfTopic(cursor.topicId) < 0) return;
        index = feed.indexOfTopic(cursor.topicId);
      }
      final sourceIndex = anchor == null
          ? -1
          : sourceFeed().indexOfTopic(anchor);
      final removedIndex = sourceIndex < 0
          ? null
          : feed.visibleRowForSource(sourceIndex);
      var target = index >= 0
          ? index + direction
          : removedIndex != null
          ? removedIndex + (direction < 0 ? -1 : 0)
          : cursor != null
          ? cursor.index +
                (feed.topicIdAt(cursor.index) == null
                    ? direction
                    : direction < 0
                    ? -1
                    : 0)
          : firstVisibleRow;
      if (target >= feed.rowCount && feed.hasMore) {
        await _tab.loadMoreFeed(_destination);
        if (!isCurrent()) return;
      }
      var current = _latestFeed();
      if (!isCurrent() || current.rowCount == 0) return;
      target = target.clamp(0, current.rowCount - 1);
      final candidate = current.topicIdAt(target);
      if (candidate == null ||
          !_tab.shell.store.containsRecord<Topic>(_tab.siteUrl!, candidate)) {
        await _ensureSourceRange(
          current.sourceRowFor(target),
          current.sourceRowFor(target),
        );
        if (!isCurrent()) return;
        current = _latestFeed();
      }
      final topicId = current.topicIdAt(target);
      if (topicId == null) return;
      remember(topicId, keyboard: true);
      _onKeyboardSelection(_readTopic(topicId));
      _afterFrame(() {
        if (isCurrent()) _revealRow(target);
      });
    } finally {
      _afterFrame(() {
        if (identical(_keyboardMoveToken, token)) _keyboardMoveToken = null;
      });
    }
  }

  void opened(int topicId, {required bool keyboard}) {
    _keyboardMoveToken = null;
    _selectionRestoreToken = null;
    remember(topicId, keyboard: keyboard);
  }

  bool openSelection() {
    final cursor = _cursor.value;
    final siteUrl = _tab.siteUrl;
    if (cursor == null || siteUrl == null) return false;
    final topic = _readTopic(cursor.topicId);
    if (topic != null && _feed.topicIds.contains(cursor.topicId)) {
      _openTopic(topic);
    } else {
      unawaited(_restoreSelection(cursor));
    }
    return true;
  }

  Future<void> _restoreSelection(TopicListCursor cursor) async {
    final token = Object();
    _selectionRestoreToken = token;
    final route = _tab.currentContent;
    bool isCurrent() =>
        _isCurrent &&
        identical(_selectionRestoreToken, token) &&
        _cursor.value?.topicId == cursor.topicId &&
        _tab.currentContent == route &&
        _keyboardAvailable();
    try {
      if (!isCurrent()) return;
      var topic = _readTopic(cursor.topicId);
      topic ??= await _tab.restoreFeedTopic(_destination, cursor.topicId);
      if (isCurrent() && topic != null) _openTopic(topic);
    } finally {
      if (identical(_selectionRestoreToken, token)) {
        _selectionRestoreToken = null;
      }
    }
  }
}
