import 'package:flutter/foundation.dart';

import 'topic.dart';
import 'user_activity.dart';

/// What the connected account's default Activity destination currently knows.
@immutable
class UserActivityFeed {
  const UserActivityFeed({
    this.items = const [],
    this.categoriesById = const {},
    this.loading = false,
    this.loaded = false,
    this.hasMore = true,
    this.nextOffset = 0,
    this.retryFromStart = false,
    this.error,
  });

  final List<UserActivityItem> items;
  final Map<int, TopicCategory> categoriesById;
  final bool loading;
  final bool loaded;
  final bool hasMore;
  final int nextOffset;
  final bool retryFromStart;
  final String? error;

  bool get isEmpty => loaded && error == null && items.isEmpty;

  TopicCategory? categoryFor(int? id) => id == null ? null : categoriesById[id];

  UserActivityFeed loadingPage({required bool replace}) => UserActivityFeed(
    // Pull-to-refresh keeps confirmed rows mounted until their replacement
    // arrives. This preserves scroll context and gives a failed refresh useful
    // content to fall back to; [withPage] still replaces them atomically.
    items: items,
    categoriesById: categoriesById,
    loading: true,
    loaded: loaded,
    hasMore: hasMore,
    nextOffset: nextOffset,
  );

  UserActivityFeed withPage(
    UserActivityPage page, {
    required int limit,
    required bool replace,
  }) {
    final heldItems = replace ? const <UserActivityItem>[] : items;
    final byIdentity = <String, UserActivityItem>{
      for (final item in heldItems) item.identity: item,
      for (final item in page.items) item.identity: item,
    };
    final categories = <int, TopicCategory>{
      if (!replace) ...categoriesById,
      for (final category in page.categories) category.id: category,
    };
    return UserActivityFeed(
      items: List.unmodifiable(byIdentity.values),
      categoriesById: Map.unmodifiable(categories),
      loaded: true,
      hasMore: page.rawItemCount >= limit,
      nextOffset: (replace ? 0 : nextOffset) + page.rawItemCount,
    );
  }

  UserActivityFeed withError(String message, {required bool retryFromStart}) =>
      UserActivityFeed(
        items: items,
        categoriesById: categoriesById,
        loaded: true,
        hasMore: hasMore,
        nextOffset: nextOffset,
        retryFromStart: retryFromStart,
        error: message,
      );
}
