import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../models/bookmark.dart';

/// The small slice of site/account policy bookmark reminder UI needs.
@immutable
final class BookmarkSiteContext {
  const BookmarkSiteContext({
    this.username,
    this.timezone,
    required this.suggestWeekendsInDatePickers,
  });

  final String? username;
  final String? timezone;
  final bool suggestWeekendsInDatePickers;
}

/// The confirmed result of a bookmark mutation, or why it was not applied.
final class BookmarkWriteResult {
  const BookmarkWriteResult.saved([this.bookmark])
    : message = null,
      reconciled = false;

  const BookmarkWriteResult.refused(this.message)
    : bookmark = null,
      reconciled = false;

  const BookmarkWriteResult.reconciled(this.message)
    : bookmark = null,
      reconciled = true;

  final Bookmark? bookmark;
  final String? message;
  final bool reconciled;

  bool get saved => message == null;
}

/// Site-scoped actions for one already-authorized bookmark target type.
///
/// The target type is deliberately absent from every mutation. A plugin gets
/// one of these only after binding its registered target, so it cannot turn a
/// Chat-message affordance into an arbitrary post/topic bookmark write.
abstract interface class BookmarkTargetHost {
  BookmarkSiteContext siteContextFor(String siteUrl);

  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required int targetId,
  });

  /// Changes only when this exact bookmark target enters or leaves a write.
  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int topicId,
    required int targetId,
  });

  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int topicId,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  });

  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  });

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  });

  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required int topicId,
    required Bookmark bookmark,
  });
}

/// Core bookmark UI, including topic-wide reads and actions.
///
/// This contract is never handed to a plugin session. Plugins receive the
/// narrower [PluginBookmarkHost] returned by [PluginBookmarkHostFactory].
abstract interface class BookmarkHost {
  Store get store;

  BookmarkTargetHost bookmarkTarget(BookmarkTargetType targetType);

  Future<BookmarkWriteResult> deleteAllTopicBookmarks({
    required String siteUrl,
    required int topicId,
  });

  void openTopicPost({
    required String siteUrl,
    required int topicId,
    required int postNumber,
  });
}

/// Target-bound bookmark actions exposed to plugin-owned widgets.
abstract interface class PluginBookmarkHost implements BookmarkTargetHost {}

/// Creates a least-privilege facade for one plugin-owned target strategy.
abstract interface class PluginBookmarkHostFactory {
  PluginBookmarkHost forTarget(BookmarkTargetType targetType);
}
