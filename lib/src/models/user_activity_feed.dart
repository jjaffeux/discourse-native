import 'package:flutter/foundation.dart';

import 'account_feed_window.dart';
import 'topic.dart';
import 'user_activity.dart';

@immutable
class UserActivityFeed {
  const UserActivityFeed({
    this.items = const [],
    this.categoriesById = const {},
    this.loading = false,
    this.loadingPrevious = false,
    this.loaded = false,
    this.hasMore = true,
    this.nextOffset = 0,
    this.retryFromStart = false,
    this.retryPrevious = false,
    this.error,
    this.window = const AccountFeedWindow(),
  });

  final List<UserActivityItem> items;
  final Map<int, TopicCategory> categoriesById;
  final bool loading;
  final bool loadingPrevious;
  final bool loaded;
  final bool hasMore;
  final int nextOffset;
  final bool retryFromStart;
  final bool retryPrevious;
  final String? error;
  final AccountFeedWindow<UserActivityItem> window;

  int get firstOffset => window.start;
  bool get hasPrevious => firstOffset > 0;
  int previousOffset(int limit) => (firstOffset - limit).clamp(0, firstOffset);
  int get retainedPageCount => window.packets.length;
  int get estimatedRetainedBytes => window.estimatedBytes(
    (row) => _estimate(row) + _categoryBytes(categoriesById[row.categoryId]),
  );
  bool get isEmpty =>
      loaded && !hasPrevious && !hasMore && error == null && items.isEmpty;

  TopicCategory? categoryFor(int? id) => id == null ? null : categoriesById[id];

  UserActivityFeed loadingPage({required bool replace, bool prepend = false}) =>
      UserActivityFeed(
        items: items,
        categoriesById: categoriesById,
        loading: true,
        loadingPrevious: prepend,
        loaded: loaded,
        hasMore: hasMore,
        nextOffset: nextOffset,
        window: window,
      );

  UserActivityFeed withPage(
    UserActivityPage page, {
    required int limit,
    required bool replace,
    bool prepend = false,
    int? requestOffset,
  }) {
    final start = requestOffset ?? (replace ? 0 : nextOffset);
    final base = replace
        ? const AccountFeedWindow<UserActivityItem>()
        : _heldWindow;
    final categories = <int, TopicCategory>{
      if (!replace) ...categoriesById,
      for (final category in page.categories) category.id: category,
    };
    final updated = base.withPage(
      incoming: page.items,
      start: start,
      end: start + page.rawItemCount,
      prepend: prepend,
      identity: (item) => item.identity,
      merge: (_, incoming) => incoming,
      estimate: (row) =>
          _estimate(row) + _categoryBytes(categories[row.categoryId]),
    );
    final rows = updated.items;
    final usedCategories = {for (final row in rows) row.categoryId};
    categories.removeWhere((id, _) => !usedCategories.contains(id));
    return UserActivityFeed(
      items: rows,
      categoriesById: Map.unmodifiable(categories),
      loaded: true,
      hasMore: prepend
          ? hasMore || updated.end < nextOffset
          : page.rawItemCount >= limit,
      nextOffset: updated.end,
      window: updated,
    );
  }

  AccountFeedWindow<UserActivityItem> get _heldWindow =>
      window.packets.isNotEmpty || items.isEmpty
      ? window
      : AccountFeedWindow(
          packets: [AccountFeedPacket(start: 0, end: nextOffset, items: items)],
        );

  UserActivityFeed withError(String message, {required bool retryFromStart}) =>
      UserActivityFeed(
        items: items,
        categoriesById: categoriesById,
        loaded: true,
        hasMore: hasMore,
        nextOffset: nextOffset,
        retryFromStart: retryFromStart,
        retryPrevious: loadingPrevious,
        error: message,
        window: window,
      );

  static int _categoryBytes(TopicCategory? category) => category == null
      ? 0
      : accountFeedStringBytes([
          category.name,
          category.color,
          category.slug,
          category.styleType,
          category.icon,
          category.emoji,
          category.descriptionExcerpt,
          category.topicTemplate,
          for (final topic in category.featuredTopics) ...[
            topic.title,
            topic.slug,
          ],
        ]);

  static int _estimate(UserActivityItem item) => accountFeedStringBytes([
    item.title,
    item.slug,
    item.username,
    item.excerpt,
    item.avatarUrl,
  ]);
}
