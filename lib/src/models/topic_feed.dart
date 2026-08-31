import 'package:flutter/foundation.dart';

import 'topic.dart';
import 'topic_filter.dart';

@immutable
class TopicFeed {
  const TopicFeed({
    this.topicIds = const [],
    this.loading = false,
    this.loadingMore = false,
    this.loadingIncoming = false,
    this.error,
    this.pageError = false,
    this.loaded = false,
    this.nextPagePath,
    this.canCreateTopic = false,
    this.filterOptions = const [],
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

  TopicFeed refreshing() => TopicFeed(
    topicIds: topicIds,
    loading: true,
    loaded: loaded,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  TopicFeed loadingNextPage() => TopicFeed(
    topicIds: topicIds,
    loadingMore: true,
    loadingIncoming: loadingIncoming,
    loaded: loaded,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  TopicFeed withError(String message, {bool page = false}) => TopicFeed(
    topicIds: topicIds,
    loadingIncoming: loadingIncoming,
    error: message,
    pageError: page,
    loaded: true,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  final List<int> topicIds;
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

  bool get isEmpty => loaded && error == null && topicIds.isEmpty;
}
