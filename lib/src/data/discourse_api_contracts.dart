import '../diagnostics/diagnostic_error_cause.dart';
import '../models/bookmark.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/topic.dart';
import '../models/user_draft.dart';
import '../plugins/chat/chat_channel.dart';
import '../plugins/chat/chat_message.dart';
import '../plugins/gifs/gif.dart';
import '../plugins/poll/poll.dart';
import '../plugins/reactions/post_reactors.dart';

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

enum ChatReactionAction { add, remove }

abstract interface class ChatApi {
  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  });

  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  });

  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    String? apiKey,
    String? clientId,
  });

  Future<int?> sendChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required String message,
    int? threadId,
    String? stagedId,
    DateTime? clientCreatedAt,
    String? clientId,
  });

  Future<void> setChatMessageReaction({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String emoji,
    required ChatReactionAction action,
    String? clientId,
  });

  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  });
}

/// Authenticated reads behind Discourse core's GIF picker.
abstract interface class GifsApi {
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  });
}

/// Narrow authenticated JSON transport used by repository-owned plugins.
///
/// Keeping this boundary generic prevents every optional plugin from growing
/// the already-large core API contract while preserving the shared HTTP safety
/// and write-error mapping.
abstract interface class PluginApiTransport {
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String apiKey,
    String? clientId,
  });

  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  });
}

abstract interface class ReactionsApi {
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  });
}

/// Personalized writes owned by Discourse's bundled Poll plugin.
abstract interface class PollsApi {
  /// Casts or changes this reader's vote in one named poll.
  Future<PollVoteResponse> votePoll({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    required List<String> options,
    String? clientId,
  });

  /// Removes this reader's vote from one named poll.
  Future<PollVoteResponse> removePollVote({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    String? clientId,
  });
}
