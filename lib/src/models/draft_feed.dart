import 'package:flutter/foundation.dart';

import 'user_draft.dart';

@immutable
class DraftFeed {
  const DraftFeed({
    this.drafts = const [],
    this.loading = false,
    this.loaded = false,
    this.hasMore = true,
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
  final int? totalCount;
  final String? error;

  bool get isEmpty => loaded && error == null && drafts.isEmpty;

  DraftFeed loadingMore() => DraftFeed(
    drafts: drafts,
    loading: true,
    loaded: loaded,
    hasMore: hasMore,
    totalCount: totalCount,
  );

  DraftFeed withPage(
    List<UserDraft> page, {
    required int limit,
    required int? reportedCount,
  }) {
    final byKey = <String, UserDraft>{
      for (final draft in drafts) draft.key: draft,
      for (final draft in page) draft.key: draft,
    };
    final combined = List<UserDraft>.unmodifiable(byKey.values);
    final more = page.length >= limit;
    return DraftFeed(
      drafts: combined,
      loaded: true,
      hasMore: more,
      totalCount: more
          ? (reportedCount == null || reportedCount < combined.length
                ? combined.length
                : reportedCount)
          : combined.length,
    );
  }

  DraftFeed without(String key) {
    final updated = List<UserDraft>.unmodifiable(
      drafts.where((draft) => draft.key != key),
    );
    return DraftFeed(
      drafts: updated,
      loaded: loaded,
      hasMore: hasMore,
      totalCount: totalCount == null
          ? null
          : (totalCount! - 1).clamp(0, totalCount!),
    );
  }

  DraftFeed withError(String message) => DraftFeed(
    drafts: drafts,
    loaded: true,
    hasMore: hasMore,
    totalCount: totalCount,
    error: message,
  );
}
