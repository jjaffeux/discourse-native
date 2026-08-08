import '../diagnostics/diagnostic_error_cause.dart';
import '../models/bookmark.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../plugins/chat/chat_channel.dart';
import '../plugins/chat/chat_message.dart';
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
