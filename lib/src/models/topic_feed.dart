import 'package:flutter/foundation.dart';

import 'topic.dart';

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
    this.loaded = false,
    this.nextPagePath,
  });

  const TopicFeed.loading() : this(loading: true);

  const TopicFeed.failed(String message) : this(error: message, loaded: true);

  TopicFeed.of(TopicList list)
    : this(
        topicIds: [for (final topic in list.topics) topic.id],
        loaded: true,
        nextPagePath: list.nextPagePath,
      );

  TopicFeed copyWith({
    List<int>? topicIds,
    bool? loading,
    bool? loadingMore,
    bool? loadingIncoming,
    String? nextPagePath,
    bool clearNextPage = false,
  }) {
    return TopicFeed(
      topicIds: topicIds ?? this.topicIds,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      loadingIncoming: loadingIncoming ?? this.loadingIncoming,
      error: error,
      loaded: loaded,
      nextPagePath: clearNextPage ? null : (nextPagePath ?? this.nextPagePath),
    );
  }

  final List<int> topicIds;
  final bool loading;

  /// True while a further page is in flight, so the list can show a footer
  /// without replacing what is already on screen.
  final bool loadingMore;

  /// True while the topics announced by the banner are being fetched, so it can
  /// spin in place rather than vanishing before they arrive.
  final bool loadingIncoming;

  final String? error;

  /// Null once the last page has been reached.
  final String? nextPagePath;

  bool get hasMore => nextPagePath != null;

  /// True once a request has finished, so an empty list can be told apart from
  /// one that has not been fetched.
  final bool loaded;

  bool get isEmpty => loaded && error == null && topicIds.isEmpty;
}
