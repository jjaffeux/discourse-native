import '../diagnostics/diagnostic_error_cause.dart';
import '../models/bookmark.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/topic.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';

enum SiteLookupFailure { notDiscourse, unreachable }

class SiteLookupException implements Exception, DiagnosticErrorCause {
  const SiteLookupException(
    this.failure,
    this.term, {
    this.statusCode,
    this.cause,
    this.causeStackTrace,
  });

  final SiteLookupFailure failure;
  final String term;
  final int? statusCode;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  Object get diagnosticCause => cause ?? this;

  @override
  StackTrace? get diagnosticCauseStackTrace => causeStackTrace;

  String get message => switch (failure) {
    SiteLookupFailure.notDiscourse =>
      '$term is not a Discourse forum, or is running a version too old to '
          'support apps.',
    SiteLookupFailure.unreachable => "Couldn't reach $term.",
  };

  @override
  String toString() => [
    'SiteLookupException($failure',
    if (statusCode != null) ', statusCode: $statusCode',
    ')',
  ].join();
}

/// Why a write did not go through.
///
/// Reads collapse into "couldn't reach it" because there is nothing the reader
/// can do either way. A write is the opposite: the user typed something, it was
/// refused, and the reason decides what they do next — fix the text, wait,
/// reconnect, or reload.
enum WriteFailure {
  /// The site refused the content. [WriteException.errors] says why, in words
  /// Discourse already wrote for a reader.
  validation,

  /// Too fast. [WriteException.retryAfter] says how long to wait, when the
  /// site said.
  rateLimited,

  /// Not allowed here — or the key is gone. The two are indistinguishable from
  /// the status alone, since Discourse answers 403 to both.
  forbidden,

  /// Someone changed it first. Only edits can hit this.
  conflict,

  /// Nothing answered, or what answered made no sense.
  unreachable,
}

class WriteException implements Exception, DiagnosticErrorCause {
  const WriteException(
    this.failure, {
    this.errors = const [],
    this.statusCode,
    this.retryAfter,
    this.cause,
    this.causeStackTrace,
  });

  final WriteFailure failure;

  /// Discourse's own messages. Already written for a reader, so they are shown
  /// as they arrive rather than translated into something of ours.
  final List<String> errors;

  final int? statusCode;

  /// How long to wait before trying again, on a [WriteFailure.rateLimited].
  final Duration? retryAfter;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  Object get diagnosticCause => cause ?? this;

  @override
  StackTrace? get diagnosticCauseStackTrace => causeStackTrace;

  String get message {
    if (errors.isNotEmpty) return errors.join('\n');
    return switch (failure) {
      WriteFailure.validation => "That wasn't accepted.",
      WriteFailure.rateLimited => switch (retryAfter) {
        final wait? => 'Too fast — try again in ${wait.inSeconds}s.',
        null => 'Too fast — try again in a moment.',
      },
      WriteFailure.forbidden =>
        "You can't post that here — or the connection to this site has "
            'expired.',
      WriteFailure.conflict => 'Someone else changed that first.',
      WriteFailure.unreachable => "Couldn't reach the site.",
    };
  }

  @override
  String toString() =>
      'WriteException($failure, statusCode: $statusCode, '
      'retryAfter: $retryAfter)';
}

abstract interface class AccountActivityApi {
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  });

  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });

  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  });
}

/// The authenticated user record used by the native Preferences destination.
abstract interface class UserPreferencesApi {
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });

  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  });
}

/// Bookmark writes shared by the shell and its independently tested fakes.
abstract interface class BookmarksWriteApi {
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  });

  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  });

  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  });

  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  });
}

/// The authenticated list behind the Drafts destination.
abstract interface class DraftsApi {
  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  });

  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  });
}

/// Topic-list pages consumed by the shell's feed state machine.
abstract interface class TopicFeedsApi {
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  });
}

/// Read receipts emitted from native topic viewport observations.
abstract interface class TopicReadsApi {
  Future<void> recordTopicRead({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postNumber,
    int milliseconds = 500,
    String? clientId,
  });
}
