import 'package:flutter/foundation.dart';

import 'topic.dart';
import 'topic_filter.dart';

/// What the main region knows about one list, at one moment.
///
/// The list is ids, not topics. Which topics are in a list, and in what order,
/// is the only thing that belongs to the list — everything about a topic itself
/// belongs to the topic, and lives once in the store under its id. That is
/// what makes the same topic in `/latest` and in `/unread` one row rather than
/// two copies that drift apart.
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

  /// Starts a first-page request without throwing away readable cached rows.
  ///
  /// An initial load still has no rows and therefore renders as a blocking
  /// wait. A refresh keeps the previous page, pagination cursor and
  /// capabilities available until the replacement arrives.
  TopicFeed refreshing() => TopicFeed(
    topicIds: topicIds,
    loading: true,
    loaded: loaded,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  /// Starts pagination while keeping the current page visible.
  TopicFeed loadingNextPage() => TopicFeed(
    topicIds: topicIds,
    loadingMore: true,
    loadingIncoming: loadingIncoming,
    loaded: loaded,
    nextPagePath: nextPagePath,
    canCreateTopic: canCreateTopic,
    filterOptions: filterOptions,
  );

  /// Keeps the last useful snapshot and adds a retryable failure to it.
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

  /// True while a further page is in flight, so the list can show a footer
  /// without replacing what is already on screen.
  final bool loadingMore;

  /// True while the topics announced by the banner are being fetched, so it can
  /// spin in place rather than vanishing before they arrive.
  final bool loadingIncoming;

  final String? error;

  /// Whether [error] belongs to the next-page request rather than a refresh.
  ///
  /// The distinction keeps a failed page at the end of the list, where the
  /// user encountered it, while a failed refresh is shown above stale rows.
  final bool pageError;

  /// Null once the last page has been reached.
  final String? nextPagePath;

  bool get hasMore => nextPagePath != null;

  /// True once a request has finished, so an empty list can be told apart from
  /// one that has not been fetched.
  final bool loaded;
  final bool canCreateTopic;
  final List<TopicFilterOption> filterOptions;

  bool get isEmpty => loaded && error == null && topicIds.isEmpty;
}
