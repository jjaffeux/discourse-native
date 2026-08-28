import '../models/bookmark.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/json.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../models/user_card.dart';
import '../models/user_status.dart';
import 'notification_counters.dart';
import 'plugin_data.dart';
import 'plugin_icon_catalog.dart';

/// Constructs core wire models with one explicitly installed extension decoder.
///
/// Keeping this object at the composition boundary lets core-only builds use an
/// empty decoder and prevents model factories from reaching a process-global
/// plugin registry.
final class DiscourseModelCodec {
  const DiscourseModelCodec({
    required this.extensions,
    this.recommendationSources = const EmptyTopicRecommendationSourceDecoder(),
    this.icons = const CoreIconNameDecoder(),
  });

  const DiscourseModelCodec.core()
    : extensions = const EmptyPluginDataDecoder(),
      recommendationSources = const EmptyTopicRecommendationSourceDecoder(),
      icons = const CoreIconNameDecoder();

  final PluginDataDecoder extensions;
  final TopicRecommendationSourceDecoder recommendationSources;
  final IconNameDecoder icons;

  PluginNotificationCounterCodec get _notificationCounterCodec =>
      extensions is PluginNotificationCounterCodec
      ? extensions as PluginNotificationCounterCodec
      : const EmptyPluginNotificationCounterCodec();

  Post post(Map<String, dynamic> json, String siteUrl) =>
      Post.fromJson(json, siteUrl, extensions: extensions);

  TopicList topicList(Map<String, dynamic> json, String siteUrl) =>
      TopicList.fromJson(json, siteUrl, extensions: extensions);

  TopicPayload topic(Map<String, dynamic> json, String siteUrl) =>
      TopicDetail.parse(
        json,
        siteUrl,
        extensions: extensions,
        recommendationSources: recommendationSources,
      );

  TopicRecommendations? topicRecommendations(
    Map<String, dynamic> json,
    String siteUrl,
  ) => TopicRecommendations.fromJson(
    json,
    siteUrl,
    extensions: extensions,
    recommendationSources: recommendationSources,
  );

  UserCard userCard(Map<String, dynamic> json, String siteUrl) =>
      UserCard.fromJson(json, siteUrl, extensions: extensions);

  SiteConfig siteConfig(Map<String, dynamic> json, String siteUrl) =>
      SiteConfig.fromSettings(json, siteUrl: siteUrl, extensions: extensions);

  NotificationTotals notificationTotals(Map<String, dynamic> json) =>
      NotificationTotals.fromJson(
        json,
        counterCodec: _notificationCounterCodec,
      );

  DiscourseUser currentUser(Map<String, dynamic> json, String siteUrl) {
    final userOption = jsonObject(json['user_option']);
    return DiscourseUser(
      username: jsonText(json['username'])!,
      id: jsonIntOrNull(json['id']),
      name: jsonText(json['name']),
      avatarUrl: resolveAvatarUrl(
        jsonText(json['avatar_template']),
        siteUrl,
        size: 120,
      ),
      status: UserStatus.fromJson(json['status']),
      draftCount: jsonInt(json['draft_count']),
      canChangePostOwner: json['can_change_post_owner'] == true,
      staff:
          json['staff'] == true ||
          json['admin'] == true ||
          json['moderator'] == true,
      groups: List.unmodifiable([
        for (final group in jsonObjects(json['groups']))
          ?jsonText(group['name']),
      ]),
      sidebarCategoryIds: List.unmodifiable([
        for (final value in jsonArray(json['sidebar_category_ids']))
          ?jsonIntOrNull(value),
      ]),
      trackedCategoryIds: _categoryIds(json['tracked_category_ids']),
      watchedCategoryIds: _categoryIds(json['watched_category_ids']),
      watchedFirstPostCategoryIds: _categoryIds(
        json['watched_first_post_category_ids'],
      ),
      timezone: jsonText(userOption['timezone']),
      hidePresence: userOption['hide_presence'] is bool
          ? userOption['hide_presence'] as bool
          : null,
      bookmarkAutoDeletePreference: BookmarkAutoDeletePreference.read(
        userOption['bookmark_auto_delete_preference'],
      ),
      doNotDisturbUntil: jsonDate(json['do_not_disturb_until']),
      doNotDisturbChannelPosition: jsonIntOrNull(
        json['do_not_disturb_channel_position'],
      ),
      plugins: extensions.readCurrentUser(json, siteUrl),
    );
  }

  DiscourseInstance storedInstance(Map<String, dynamic> json) =>
      DiscourseInstance.fromJson(
        json,
        extensions: extensions,
        counterCodec: _notificationCounterCodec,
      );

  Map<String, dynamic> storeInstance(DiscourseInstance instance) => instance
      .toJson(extensions: extensions, counterCodec: _notificationCounterCodec);

  SiteConfig preserveUnknownSiteSettings(
    SiteConfig held,
    SiteConfig incoming,
  ) => incoming.withPlugins(
    incoming.plugins.preservingUnknownFrom(held.plugins),
  );

  DiscourseUser preserveUnknownCurrentUser(
    DiscourseUser? held,
    DiscourseUser incoming,
  ) {
    if (held == null) return incoming;
    if (!sameCurrentUserAccount(held, incoming)) {
      return incoming;
    }
    return incoming.withPlugins(
      incoming.plugins.preservingUnknownFrom(held.plugins),
    );
  }

  /// Whether two current-user snapshots belong to the same account.
  ///
  /// The stable numeric id wins whenever the stored snapshot has one. Older
  /// snapshots without an id fall back to Discourse's case-insensitive
  /// username identity.
  bool sameCurrentUserAccount(DiscourseUser held, DiscourseUser incoming) =>
      held.id != null
      ? incoming.id != null && held.id == incoming.id
      : held.username.toLowerCase() == incoming.username.toLowerCase();

  PostCreation postCreation(Map<String, dynamic> json, String siteUrl) =>
      PostCreation.fromJson(json, siteUrl, extensions: extensions);

  PluginData mergeAfterPostEdit({
    required PluginData held,
    required PluginData incoming,
  }) => extensions.mergeAfterPostEdit(held: held, incoming: incoming);
}

List<int> _categoryIds(Object? value) => List.unmodifiable([
  for (final item in jsonArray(value)) ?jsonIntOrNull(item),
]);
