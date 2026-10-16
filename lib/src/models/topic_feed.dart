import 'package:flutter/foundation.dart';

import 'topic.dart';
import 'topic_filter.dart';

@immutable
class TopicFeed {
  const TopicFeed({
    this.topicIds = const [],
    this.topicRows = const [],
    this.totalRows,
    this.loading = false,
    this.loadingMore = false,
    this.loadingIncoming = false,
    this.error,
    this.pageError = false,
    this.loaded = false,
    this.nextPagePath,
    this.canCreateTopic = false,
    this.filterOptions = const [],
    this._hiddenRows = const [],
  });

  const TopicFeed.loading() : this(loading: true);

  const TopicFeed.failed(String message) : this(error: message, loaded: true);

  TopicFeed.of(TopicList list)
    : this(
        topicIds: [for (final topic in list.topics) topic.id],
        loaded: true,
        nextPagePath: list.nextPagePath,
        canCreateTopic: list.canCreateTopic,
        filterOptions: list.filterOptions,
      );

  TopicFeed copyWith({
    List<int>? topicIds,
    List<int>? topicRows,
    int? totalRows,
    bool? loading,
    bool? loadingMore,
    bool? loadingIncoming,
    String? error,
    bool clearError = false,
    bool? pageError,
    bool? loaded,
    String? nextPagePath,
    bool clearNextPage = false,
    bool? canCreateTopic,
    List<TopicFilterOption>? filterOptions,
  }) {
    return TopicFeed(
      topicIds: topicIds ?? this.topicIds,
      topicRows: topicRows ?? this.topicRows,
      totalRows: totalRows ?? this.totalRows,
      hiddenRows: _hiddenRows,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      loadingIncoming: loadingIncoming ?? this.loadingIncoming,
      error: clearError ? null : (error ?? this.error),
      pageError: clearError ? false : (pageError ?? this.pageError),
      loaded: loaded ?? this.loaded,
      nextPagePath: clearNextPage ? null : (nextPagePath ?? this.nextPagePath),
      canCreateTopic: canCreateTopic ?? this.canCreateTopic,
      filterOptions: filterOptions ?? this.filterOptions,
    );
  }

  TopicFeed withVisibleTopics(List<int> ids) {
    final kept = ids.toSet();
    final hidden = [..._hiddenRows];
    final rows = <int>[];
    for (var index = 0; index < topicIds.length; index++) {
      final row = topicRows.isEmpty ? index : topicRows[index];
      if (kept.contains(topicIds[index])) {
        rows.add(row);
      } else {
        hidden.add(row);
      }
    }
    hidden.sort();
    return TopicFeed(
      topicIds: ids,
      topicRows: rows,
      totalRows: totalRows ?? topicIds.length,
      hiddenRows: hidden,
      loading: loading,
      loadingMore: loadingMore,
      loadingIncoming: loadingIncoming,
      error: error,
      pageError: pageError,
      loaded: loaded,
      nextPagePath: nextPagePath,
      canCreateTopic: canCreateTopic,
      filterOptions: filterOptions,
    );
  }

  TopicFeed refreshing() => TopicFeed(
    topicIds: topicIds,
    topicRows: topicRows,
    totalRows: totalRows,
    hiddenRows: _hiddenRows,
    loading: true,
    loaded: loaded,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  TopicFeed loadingNextPage() => TopicFeed(
    topicIds: topicIds,
    topicRows: topicRows,
    totalRows: totalRows,
    hiddenRows: _hiddenRows,
    loadingMore: true,
    loadingIncoming: loadingIncoming,
    loaded: loaded,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  TopicFeed withError(String message, {bool page = false}) => TopicFeed(
    topicIds: topicIds,
    topicRows: topicRows,
    totalRows: totalRows,
    hiddenRows: _hiddenRows,
    loadingIncoming: loadingIncoming,
    error: message,
    pageError: page,
    loaded: true,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  final List<int> topicIds;

  /// Source row positions for resident IDs. Empty means a dense first page.
  final List<int> topicRows;
  final int? totalRows;
  final List<int> _hiddenRows;

  int get rowCount => (totalRows ?? topicIds.length) - _hiddenRows.length;

  /// Maps the unread projection's row back to the server page positions.
  int sourceRowFor(int row) {
    var source = row;
    for (final hidden in _hiddenRows) {
      if (hidden > source) break;
      source++;
    }
    return source;
  }

  int? topicIdAt(int row) {
    if (row < 0 || row >= rowCount) return null;
    final source = sourceRowFor(row);
    if (topicRows.isEmpty) {
      return source < topicIds.length ? topicIds[source] : null;
    }
    var low = 0;
    var high = topicRows.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (topicRows[middle] < source) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low < topicRows.length && topicRows[low] == source
        ? topicIds[low]
        : null;
  }

  int indexOfTopic(int id) {
    final index = topicIds.indexOf(id);
    if (index < 0) return -1;
    final source = topicRows.isEmpty ? index : topicRows[index];
    return visibleRowForSource(source);
  }

  int visibleRowForSource(int row) =>
      row - _hiddenRows.where((hidden) => hidden < row).length;

  final bool loading;

  final bool loadingMore;

  final bool loadingIncoming;

  final String? error;

  final bool pageError;

  final String? nextPagePath;

  bool get hasMore => nextPagePath != null;

  final bool loaded;
  final bool canCreateTopic;
  final List<TopicFilterOption> filterOptions;

  bool get isEmpty => loaded && error == null && rowCount == 0;
}
