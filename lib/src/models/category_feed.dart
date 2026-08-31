import 'package:flutter/foundation.dart';

@immutable
class CategoryFeed {
  const CategoryFeed({
    this.categoryIds = const [],
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.nextPage,
    this.canCreateTopic = false,
    this.error,
    this.pageError = false,
  });

  const CategoryFeed.loading() : this(loading: true);

  final List<int> categoryIds;
  final bool loading;
  final bool loadingMore;
  final bool loaded;

  final int? nextPage;

  final bool canCreateTopic;
  final String? error;
  final bool pageError;

  bool get hasMore => nextPage != null;
  bool get isEmpty => loaded && error == null && categoryIds.isEmpty;

  CategoryFeed refreshing() => CategoryFeed(
    categoryIds: categoryIds,
    loading: true,
    loaded: loaded,
    nextPage: nextPage,
    canCreateTopic: canCreateTopic,
  );

  CategoryFeed withFirstPage(
    Iterable<int> ids, {
    required bool hasMore,
    required bool canCreateTopic,
  }) => CategoryFeed(
    categoryIds: List.unmodifiable(ids),
    loaded: true,
    nextPage: hasMore ? 2 : null,
    canCreateTopic: canCreateTopic,
  );

  CategoryFeed loadingNextPage() => CategoryFeed(
    categoryIds: categoryIds,
    loadingMore: true,
    loaded: loaded,
    nextPage: nextPage,
    canCreateTopic: canCreateTopic,
  );

  CategoryFeed withPage(Iterable<int> ids, {required bool hasMore}) {
    final combined = <int>{...categoryIds, ...ids};
    return CategoryFeed(
      categoryIds: List.unmodifiable(combined),
      loaded: true,
      nextPage: hasMore ? (nextPage ?? 1) + 1 : null,
      canCreateTopic: canCreateTopic,
    );
  }

  CategoryFeed withError(String message, {bool page = false}) => CategoryFeed(
    categoryIds: categoryIds,
    loaded: true,
    nextPage: nextPage,
    canCreateTopic: canCreateTopic,
    error: message,
    pageError: page,
  );
}
