import 'package:flutter/foundation.dart';

import '../data/store.dart';
import '../models/bookmark.dart';

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

/// Opening ownership for a bookmark UI flow, including its nested dialogs.
/// This exposes neither credentials nor authority over another target type.
abstract interface class BookmarkSession {
  bool get isCurrent;

  /// The reader context captured when this session was opened.
  BookmarkSiteContext get siteContext;
}

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

/// The target type is deliberately absent from every mutation. A plugin gets
/// one of these only after binding its registered target, so it cannot turn a
/// Chat-message affordance into an arbitrary post/topic bookmark write.
abstract interface class BookmarkTargetHost {
  BookmarkSession captureSession(String siteUrl);

  BookmarkSiteContext siteContextFor(String siteUrl);

  bool bookmarkWriteInFlight({
    required String siteUrl,
    required int topicId,
    required int targetId,
  });

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

/// A plugin bookmark has no topic/post context. The owning strategy is the
/// opaque context used to project the write back into feature state, so this
/// contract deliberately has no `topicId` parameter. Core's topic-aware host
/// remains a separate interface rather than asking plugins to pass a sentinel.
abstract interface class PluginBookmarkHost {
  BookmarkSession captureSession(String siteUrl);

  BookmarkSiteContext siteContextFor(String siteUrl);

  bool bookmarkWriteInFlight({required String siteUrl, required int targetId});

  ValueListenable<bool> bookmarkWriteInFlightListenable({
    required String siteUrl,
    required int targetId,
  });

  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
  });

  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  });

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  });

  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  });
}

abstract interface class PluginBookmarkHostFactory {
  PluginBookmarkHost forTarget(BookmarkTargetType targetType);
}
