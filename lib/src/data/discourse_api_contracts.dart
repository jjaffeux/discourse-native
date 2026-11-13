import 'package:discourse_native/l10n/strings.dart';

import '../models/bookmark.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_model_codec.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/forum_about.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/pending_post.dart';
import '../models/post.dart';
import '../models/post_checklist.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/post_revision.dart';
import '../models/sidebar_tag.dart';
import '../models/site_appearance.dart';
import '../models/site_basic_info.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/tag_notification.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../models/topic_tracking_state.dart';
import '../models/user_activity.dart';
import '../models/user_card.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../models/user_summary.dart';
import 'discourse_search_contract.dart';
import 'dsa_notice_contracts.dart';
import 'http_basic_auth.dart';
import 'plugin_transport.dart';
import 'sidebar_sections_api.dart';
import 'site_lookup_failure.dart';
import 'site_message_bus_bootstrap.dart';
import 'write_failure.dart';

export 'discourse_search_contract.dart';
export 'dsa_notice_contracts.dart';
export 'site_lookup_failure.dart';
export 'write_failure.dart';

/// The sentence a user is shown for a failed request.
///
/// A [WriteException] carries the site's own words or a localized category
/// message. A [SiteLookupException] carries a message naming the site, which
/// holds only when nothing answered. A status other than a basic-auth
/// challenge means the site was reached, so its "couldn't reach" message would
/// be false and [fallback], which names what failed, is shown instead. A 401 or
/// 403 answer to a read of a feature on a forum that is already connected is
/// the forum refusing this account, so the lookup message would call it
/// something other than a forum. Anything else, or no recorded failure at all,
/// is not a message to show, so [fallback] stands in for it rather than a type
/// name or a developer string.
String failureText(Object? error, {required String fallback}) =>
    switch (error) {
      WriteException(:final message) => message,
      HttpBasicAuthenticationRequired(:final message) => message,
      SiteLookupException(
        failure: SiteLookupFailure.notDiscourse,
        statusCode: 401 || 403,
      ) =>
        appL10n.thisAccountCanTAccessThat,
      SiteLookupException(
        failure: SiteLookupFailure.unreachable,
        statusCode: _?,
      ) =>
        fallback,
      SiteLookupException(:final message) => message,
      _ => fallback,
    };

/// A category-list response plus whether its page-one site metadata also
/// arrived. A partial list is still useful for badges/navigation, but callers
/// should leave it retryable so lazy-loaded navigation choices can be filled
/// in.
final class CategoryLoadResult {
  factory CategoryLoadResult(
    Iterable<TopicCategory> categories, {
    bool complete = true,
    Iterable<int>? rootCategoryIds,
    bool canCreateTopic = false,
    SitePostActionCatalog? postActionCatalog,
    TopicComposerCapabilities? composerCapabilities,
    Iterable<NotificationWireType> notificationTypes = const [],
    Iterable<SidebarTag>? siteTopTags,
    Iterable<SidebarTag>? anonymousDefaultTags,
    bool? anonymousSearchAllowed,
  }) {
    final immutableCategories = List<TopicCategory>.unmodifiable(categories);
    return CategoryLoadResult._(
      immutableCategories,
      List<int>.unmodifiable(
        rootCategoryIds ??
            immutableCategories
                .where((category) => category.parentCategoryId == null)
                .map((category) => category.id),
      ),
      complete,
      canCreateTopic,
      postActionCatalog,
      composerCapabilities,
      List<NotificationWireType>.unmodifiable(notificationTypes),
      siteTopTags == null ? null : List<SidebarTag>.unmodifiable(siteTopTags),
      anonymousDefaultTags == null
          ? null
          : List<SidebarTag>.unmodifiable(anonymousDefaultTags),
      anonymousSearchAllowed,
    );
  }

  CategoryLoadResult._(
    this.categories,
    this.rootCategoryIds,
    this.complete,
    this.canCreateTopic,
    this.postActionCatalog,
    this.composerCapabilities,
    this.notificationTypes,
    this.siteTopTags,
    this.anonymousDefaultTags,
    this.anonymousSearchAllowed,
  );

  final List<TopicCategory> categories;

  /// Category ids represented as roots by this page's category-list response.
  ///
  /// Nested categories and the page-one `site.json` supplement remain in
  /// [categories] for identity lookup, but must not become category cards.
  final List<int> rootCategoryIds;
  final bool complete;
  final bool canCreateTopic;

  /// Navigation metadata carried by the page-one `/site.json` supplement.
  ///
  /// Null means that optional request failed or was not made (later pages),
  /// while an empty list is the server-confirmed absence of fallback tags.
  final List<SidebarTag>? siteTopTags;
  final List<SidebarTag>? anonymousDefaultTags;

  /// Authenticated post-action metadata from the page-one `/site.json` read.
  /// Null means that metadata was not requested or did not arrive.
  final SitePostActionCatalog? postActionCatalog;

  /// What the signed-in user may do in the composer, from the authenticated
  /// page-one `/site.json` read. Null means that read was not made or did not
  /// arrive; an anonymous document would understate the account's permissions.
  final TopicComposerCapabilities? composerCapabilities;

  /// The site's notification catalog from the authenticated page-one
  /// `/site.json` read. Empty when that read was not made, failed, or named no
  /// types, which settles nothing about the catalog.
  final List<NotificationWireType> notificationTypes;

  /// Core's `allow_anonymous_search`, as the anonymous page-one `/site.json`
  /// read reports it through `can_search`. Null means that read was
  /// authenticated, failed, or was not made.
  final bool? anonymousSearchAllowed;
}

/// Compile-time aggregate accepted only at the shell composition boundary.
///
/// Consumers below that boundary receive one workflow port. Adding an
/// unrelated public method to the production HTTP adapter therefore cannot
/// widen this contract or its test doubles.
abstract interface class ShellApiCapabilities
    implements
        DiscourseApiLifecycle,
        DiscourseApiModels,
        DsaNoticesApi,
        SiteLookupApi,
        PluginApiTransport,
        PluginJsonListTransport,
        ShellSiteApi,
        ShellSearchApi,
        ShellLookupApi,
        CategoryQueriesApi,
        CategoryMutationsApi,
        TagQueriesApi,
        TagNotificationsApi,
        TopicComposerQueriesApi,
        TopicContentApi,
        TopicMutationsApi,
        PostMutationsApi,
        ComposerPersistenceApi,
        AccountActivityApi,
        BookmarksWriteApi,
        DoNotDisturbApi,
        DraftsApi,
        UserSummariesApi,
        TopicFeedsApi,
        TopicReadsApi,
        UserPreferencesApi {}

abstract interface class DiscourseApiLifecycle {
  void close();
}

abstract interface class DiscourseApiModels {
  DiscourseModelCodec get models;
}

abstract interface class DiscourseApiConfiguration {
  Duration get timeout;
}

abstract interface class SiteLookupApi {
  Future<DiscourseInstance> lookup(
    String term, {
    HttpBasicAuthentication? authentication,
  });

  Future<SiteBasicInfo> basicInfo(String siteUrl);
}

abstract interface class ShellSiteApi implements SidebarSectionsApi {
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

  Future<DiscourseUser> currentUser({
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

  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });
}

abstract interface class CategoryQueriesApi {
  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  });

  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  });

  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  });

  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    bool includeAncestors = false,
    String? clientId,
  });
}

abstract interface class CategoryMutationsApi {
  /// Returns server-resolved inherited mute preferences when available.
  Future<List<int>?> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  });
}

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

abstract interface class ShellLookupApi {
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  });

  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int? categoryId,
    int limit = 5,
    String? apiKey,
    String? clientId,
  });

  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  });

  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  });

  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    List<String> order = defaultDiscourseHashtagOrder,
    String? apiKey,
    String? clientId,
  });

  Future<Set<String>> checkMentions({
    required String siteUrl,
    required Iterable<String> names,
    int? topicId,
    String? apiKey,
    String? clientId,
  });
}

abstract interface class TopicComposerQueriesApi {
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  });
}

abstract interface class TopicContentApi {
  /// Fetches the post window around [postNumber]. Completing [abortTrigger]
  /// cancels this request, including while it waits for a network slot.
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  });

  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  });

  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  });

  /// Reads a page of posts after [postNumber], or before it unless
  /// [ascending], answered in topic order. This is how a mega topic pages
  /// (TopicDetail.isMegaTopic): it has no stream of ids to ask for.
  Future<List<Post>> postsFromNumber({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    required bool ascending,
    String? apiKey,
    String? clientId,
  });

  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  });

  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  });
}

abstract interface class TopicMutationsApi {
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  });

  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  });

  Future<void> updateMessageArchived({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool archived,
    String? clientId,
  });

  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  });

  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  });

  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  });

  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  });

  /// Omitted taxonomy fields are preserved; an empty [tags] clears tags.
  Future<TopicUpdate> updateTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String title,
    required String originalTitle,
    Iterable<TopicTag>? tags,
    Iterable<TopicTag>? originalTags,
    int? categoryId,
    String? clientId,
  });

  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  });
}

abstract interface class PostMutationsApi {
  Future<PostChecklistUpdate> togglePostChecklist({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required List<Map<String, Object?>> toggles,
    required String expectedRaw,
    required DateTime expectedUpdatedAt,
    required String mutationId,
    String? clientId,
  });

  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  });

  Future<({bool allowed, String? reason})> checkPermanentPostDeletion({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  });

  Future<void> permanentlyDeletePost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postId,
    String? clientId,
  });

  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  });

  Future<void> mergePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  });

  Future<String> movePosts({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    int? destinationTopicId,
    String? title,
    int? categoryId,
    List<int> tagIds = const [],
    bool chronologicalOrder = false,
    bool privateMessage = false,
    String? clientId,
  });

  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  });

  Future<void> updatePostWiki({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool wiki,
    String? clientId,
  });

  Future<void> updatePostLocked({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool locked,
    String? clientId,
  });

  Future<void> unhidePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  });

  Future<void> updatePostType({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postType,
    String? clientId,
  });

  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  });

  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  });

  Future<Post?> unlikePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  });

  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  });

  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  });

  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  });
}

abstract interface class ComposerPersistenceApi {
  Future<PostCreation> createPost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? replyToPostNumber,
    bool whisper = false,
    String? draftKey,
    String? clientId,
  });

  Future<PostCreation> createTopic({
    required String siteUrl,
    required String apiKey,
    required String title,
    required String raw,
    required Duration typingDuration,
    required Duration composerOpenDuration,
    int? categoryId,
    Iterable<TopicTag> tags = const [],
    String? targetRecipients,
    String draftKey = ComposerDraft.newTopicDraftKey,
    String? clientId,
    Map<String, Object?> extraFields = const {},
  });

  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  });

  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  });

  /// [forPrivateMessage] marks a new message or a post in one, where the site
  /// may let staff attach any file. An enforced [sizeLimit] refuses a larger
  /// file before any request, and any limit names the ceiling when the site
  /// answers 413.
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    bool forPrivateMessage = false,
    ComposerUploadSizeLimit? sizeLimit,
    String? clientId,
  });

  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  });

  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  });

  /// Every post of [username]'s still waiting for review, newest first.
  Future<List<PendingPost>> pendingPosts({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });
}

abstract interface class DoNotDisturbApi {
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  });

  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });
}

abstract interface class AccountActivityApi {
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  });

  /// A [background] read is one nobody is looking at.
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    bool background = false,
    String? clientId,
  });

  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });

  Future<BookmarkListPage> bookmarkListPage({
    required String siteUrl,
    required String apiKey,
    required String username,
    int page = 0,
    String? clientId,
  });

  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  });

  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  });

  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  });
}

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
    DateTime? originalReminderAt,
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

abstract interface class DraftsApi {
  Future<UserDraftPage> userDrafts({
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

abstract interface class UserSummariesApi {
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  });
}

abstract interface class TopicFeedsApi {
  Future<Topic> topicSummary({
    required String siteUrl,
    required int id,
    String? apiKey,
    String? clientId,
  });

  Future<List<int>> dismissNewTopics({
    required String siteUrl,
    required String apiKey,
    required bool dismissTopics,
    required bool dismissPosts,
    bool tracked = false,
    int? categoryId,
    String? tagName,
    List<int>? topicIds,
    String? clientId,
  });

  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  });
}

abstract interface class TopicReadsApi {
  static const maximumPostsPerRequest = 100;

  Future<void> recordTopicReads({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postNumbers,
    int milliseconds = 500,
    String? clientId,
  });
}
