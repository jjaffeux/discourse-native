import '../diagnostics/diagnostic_error_cause.dart';
import '../models/bookmark.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../plugins/chat/chat_channel.dart';
import '../plugins/chat/chat_message.dart';
import '../plugins/reactions/post_reactors.dart';

enum SiteLookupFailure { notDiscourse, unreachable }

class SiteLookupException implements Exception, DiagnosticErrorCause {
  const SiteLookupException(
    this.failure,
    this.term, {
    this.cause,
    this.causeStackTrace,
  });

  final SiteLookupFailure failure;
  final String term;
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
  String toString() => 'SiteLookupException($failure)';
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
