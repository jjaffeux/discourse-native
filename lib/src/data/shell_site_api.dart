import '../models/forum_about.dart';
import '../models/notification.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/topic_tracking_state.dart';
import '../models/user_card.dart';
import 'account_session_api.dart';
import 'sidebar_sections_api.dart';
import 'site_message_bus_bootstrap.dart';

abstract interface class ShellSiteApi
    implements AccountSessionApi, SidebarSectionsApi {
  Future<ForumAbout> forumAbout({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<SiteMessageBusBootstrap?> messageBusBootstrap({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });

  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  });

  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<List<NotificationWireType>> siteNotificationTypes({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  });

  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  });

  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  });

  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  });
}
