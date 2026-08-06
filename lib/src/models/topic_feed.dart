import 'package:flutter/foundation.dart';

import 'topic.dart';

/// What the main region knows about one list, at one moment.
@immutable
class TopicFeed {
  const TopicFeed({
    this.topics = const [],
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.loaded = false,
    this.nextPagePath,
  });

  const TopicFeed.loading() : this(loading: true);

  const TopicFeed.failed(String message) : this(error: message, loaded: true);

  TopicFeed.of(TopicList list)
    : this(topics: list.topics, loaded: true, nextPagePath: list.nextPagePath);

  TopicFeed copyWith({
    List<Topic>? topics,
    bool? loading,
    bool? loadingMore,
    String? nextPagePath,
    bool clearNextPage = false,
  }) {
    return TopicFeed(
      topics: topics ?? this.topics,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error,
      loaded: loaded,
      nextPagePath: clearNextPage ? null : (nextPagePath ?? this.nextPagePath),
    );
  }

  final List<Topic> topics;
  final bool loading;

  /// True while a further page is in flight, so the list can show a footer
  /// without replacing what is already on screen.
  final bool loadingMore;

  final String? error;

  /// Null once the last page has been reached.
  final String? nextPagePath;

  bool get hasMore => nextPagePath != null;

  /// True once a request has finished, so an empty list can be told apart from
  /// one that has not been fetched.
  final bool loaded;

  bool get isEmpty => loaded && error == null && topics.isEmpty;
}
