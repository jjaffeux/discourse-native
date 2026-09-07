import 'package:flutter/foundation.dart';

import 'user_draft.dart';

@immutable
class DraftFeed {
  const DraftFeed({
    this.drafts = const [],
    this.loading = false,
    this.loaded = false,
    this.hasMore = true,
    this.nextOffset = 0,
    this.totalCount,
    this.error,
  });

  const DraftFeed.loading() : this(loading: true);

  const DraftFeed.failed(String message)
    : this(loaded: true, hasMore: false, error: message);

  final List<UserDraft> drafts;
  final bool loading;
  final bool loaded;
  final bool hasMore;
  final int nextOffset;
  final int? totalCount;
  final String? error;

  bool get isEmpty => loaded && !hasMore && error == null && drafts.isEmpty;

  DraftFeed loadingMore() => DraftFeed(
    drafts: drafts,
    loading: true,
    loaded: loaded,
    hasMore: hasMore,
    nextOffset: nextOffset,
    totalCount: totalCount,
  );

  DraftFeed withPage(
    UserDraftPage page, {
    required int limit,
    required int? reportedCount,
    int deletedCount = 0,
  }) {
    final byKey = <String, UserDraft>{
      for (final draft in drafts) draft.key: draft,
    };
    for (final draft in page.drafts) {
      byKey[draft.key] = _mergeDraft(byKey[draft.key], draft);
    }
    final combined = List<UserDraft>.unmodifiable(byKey.values);
    // Invalid or overlapping rows consume server positions. Actual deletions
    // shift those positions back, including deleted rows in a stale response.
    final consumed = (page.rawItemCount - deletedCount).clamp(
      0,
      page.rawItemCount,
    );
    final more = page.rawItemCount >= limit && consumed > 0;
    return DraftFeed(
      drafts: combined,
      loaded: true,
      hasMore: more,
      nextOffset: nextOffset + consumed,
      totalCount: more
          ? (reportedCount == null || reportedCount < combined.length
                ? combined.length
                : reportedCount)
          : combined.length,
    );
  }

  DraftFeed without(String key, {bool knownToExist = false}) {
    final contained = drafts.any((draft) => draft.key == key);
    final updated = List<UserDraft>.unmodifiable(
      drafts.where((draft) => draft.key != key),
    );
    final decrement = contained || knownToExist;
    return DraftFeed(
      drafts: updated,
      loading: loading,
      loaded: loaded,
      hasMore: hasMore,
      nextOffset: contained
          ? (nextOffset - 1).clamp(0, nextOffset)
          : nextOffset,
      totalCount: totalCount == null
          ? null
          : !decrement
          ? totalCount
          : (totalCount! - 1).clamp(0, totalCount!),
    );
  }

  DraftFeed withError(String message) => DraftFeed(
    drafts: drafts,
    loaded: true,
    hasMore: hasMore,
    nextOffset: nextOffset,
    totalCount: totalCount,
    error: message,
  );

  DraftFeed withoutTotalCount() => DraftFeed(
    drafts: drafts,
    loading: loading,
    loaded: loaded,
    hasMore: hasMore,
    nextOffset: nextOffset,
    error: error,
  );

  static UserDraft _mergeDraft(UserDraft? held, UserDraft incoming) {
    if (held == null || incoming.sequence > held.sequence) return incoming;
    if (incoming.sequence < held.sequence) return held;
    return UserDraft(
      key: incoming.key,
      sequence: incoming.sequence,
      data: incoming.data ?? held.data,
      createdAt: incoming.createdAt ?? held.createdAt,
      topicId: incoming.topicId ?? held.topicId,
      title: incoming.title ?? held.title,
      slug: incoming.slug ?? held.slug,
      categoryId: incoming.categoryId ?? held.categoryId,
      archetype: incoming.archetype ?? held.archetype,
    );
  }
}
