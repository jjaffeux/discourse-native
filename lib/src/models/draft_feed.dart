import 'package:flutter/foundation.dart';

import 'account_feed_window.dart';
import 'topic_tag.dart';
import 'user_draft.dart';

@immutable
class DraftFeed {
  const DraftFeed({
    this.drafts = const [],
    this.loading = false,
    this.loadingPrevious = false,
    this.loaded = false,
    this.hasMore = true,
    this.nextOffset = 0,
    this.totalCount,
    this.error,
    this.retryPrevious = false,
    this.requiresRefresh = false,
    this.retainedAllRows = true,
    this.window = const AccountFeedWindow(),
  });

  const DraftFeed.loading() : this(loading: true);

  const DraftFeed.failed(String message)
    : this(loaded: true, hasMore: false, error: message);

  final List<UserDraft> drafts;
  final bool loading;
  final bool loadingPrevious;
  final bool loaded;
  final bool hasMore;
  final int nextOffset;
  final int? totalCount;
  final String? error;
  final bool retryPrevious;
  final bool requiresRefresh;
  final bool retainedAllRows;
  final AccountFeedWindow<UserDraft> window;

  int get firstOffset => window.start;
  bool get hasPrevious => firstOffset > 0;
  int previousOffset(int limit) => (firstOffset - limit).clamp(0, firstOffset);
  int get retainedPageCount => window.packets.length;
  int get estimatedRetainedBytes => window.estimatedBytes(_estimate);
  bool get isEmpty =>
      loaded && !hasPrevious && !hasMore && error == null && drafts.isEmpty;

  DraftFeed loadingMore({bool prepend = false}) => DraftFeed(
    drafts: drafts,
    loading: true,
    loadingPrevious: prepend,
    loaded: loaded,
    hasMore: hasMore,
    nextOffset: nextOffset,
    totalCount: totalCount,
    requiresRefresh: requiresRefresh,
    retainedAllRows: retainedAllRows,
    window: window,
  );

  DraftFeed withPage(
    UserDraftPage page, {
    required int limit,
    required int? reportedCount,
    int deletedCount = 0,
    bool prepend = false,
    int? requestOffset,
  }) {
    final consumed = (page.rawItemCount - deletedCount).clamp(
      0,
      page.rawItemCount,
    );
    final start = requestOffset ?? nextOffset;
    final updated = _heldWindow.withPage(
      incoming: page.drafts,
      start: start,
      end: start + consumed,
      prepend: prepend,
      identity: (draft) => draft.key,
      merge: _mergeDraft,
      estimate: _estimate,
    );
    final rows = updated.items;
    final retainedAll =
        retainedAllRows &&
        updated.packets.length == _heldWindow.packets.length + 1;
    final more = prepend
        ? hasMore || updated.end < nextOffset
        : page.rawItemCount >= limit;
    return DraftFeed(
      drafts: rows,
      loaded: true,
      hasMore: more,
      nextOffset: updated.end,
      totalCount: !more && retainedAll
          ? rows.length
          : reportedCount != null && reportedCount >= rows.length
          ? reportedCount
          : retainedAll
          ? rows.length
          : null,
      requiresRefresh: requiresRefresh,
      retainedAllRows: retainedAll,
      window: updated,
    );
  }

  AccountFeedWindow<UserDraft> get _heldWindow =>
      window.packets.isNotEmpty || drafts.isEmpty
      ? window
      : AccountFeedWindow(
          packets: [
            AccountFeedPacket(start: 0, end: nextOffset, items: drafts),
          ],
        );

  DraftFeed without(String key, {bool knownToExist = false}) {
    final contained = drafts.any((draft) => draft.key == key);
    final updated = _heldWindow.without(key, (draft) => draft.key);
    final decrement = contained || knownToExist;
    return DraftFeed(
      drafts: updated.items,
      loading: loading,
      loadingPrevious: loadingPrevious,
      loaded: loaded,
      hasMore: hasMore,
      nextOffset: contained ? updated.end : nextOffset,
      totalCount: totalCount == null
          ? null
          : !decrement
          ? totalCount
          : (totalCount! - 1).clamp(0, totalCount!),
      requiresRefresh:
          requiresRefresh || (knownToExist && !contained && hasPrevious),
      retainedAllRows: retainedAllRows,
      retryPrevious: retryPrevious,
      window: updated,
    );
  }

  DraftFeed withError(String message) => DraftFeed(
    drafts: drafts,
    loaded: true,
    hasMore: hasMore,
    nextOffset: nextOffset,
    totalCount: totalCount,
    error: message,
    retryPrevious: loadingPrevious,
    requiresRefresh: requiresRefresh,
    retainedAllRows: retainedAllRows,
    window: window,
  );

  DraftFeed requiringRefresh() => DraftFeed(
    drafts: drafts,
    loading: loading,
    loadingPrevious: loadingPrevious,
    loaded: loaded,
    hasMore: hasMore,
    nextOffset: nextOffset,
    totalCount: totalCount,
    error: error,
    retryPrevious: retryPrevious,
    requiresRefresh: true,
    retainedAllRows: retainedAllRows,
    window: window,
  );

  DraftFeed withoutTotalCount() => DraftFeed(
    drafts: drafts,
    loading: loading,
    loadingPrevious: loadingPrevious,
    loaded: loaded,
    hasMore: hasMore,
    nextOffset: nextOffset,
    error: error,
    retryPrevious: retryPrevious,
    requiresRefresh: requiresRefresh,
    retainedAllRows: retainedAllRows,
    window: window,
  );

  static int _estimate(UserDraft draft) {
    final cachedExcerptAllowance = (draft.data?.reply.length ?? 0) * 2;
    return cachedExcerptAllowance +
        accountFeedStringBytes([
          draft.key,
          draft.title,
          draft.slug,
          draft.archetype,
          draft.data?.reply,
          draft.data?.title,
          draft.data?.action,
          draft.data?.archetypeId,
          draft.data?.recipients,
          draft.data?.replyToUsername,
          for (final tag in draft.data?.tags ?? const <TopicTag>[]) ...[
            tag.name,
            tag.slug,
            tag.disabledReason,
          ],
        ]);
  }

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
