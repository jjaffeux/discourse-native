import '../models/sidebar_tag.dart';
import '../models/tag_notification.dart';

abstract interface class TagNotificationsApi {
  /// [tag] is what `/tag/:tag/notifications` resolves: an id or a name.
  Future<TagNotificationLevel> tagNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required String tag,
    String? clientId,
  });

  /// Returns every tag the account now mutes, when the response lists them.
  Future<List<int>?> updateTagNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required String tag,
    required TagNotificationLevel notificationLevel,
    String? clientId,
  });
}

abstract interface class TagQueriesApi {
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });
}
