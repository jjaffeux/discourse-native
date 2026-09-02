import 'package:http/http.dart' as http;

import '../diagnostics/diagnostics_redactor.dart';
import '../models/bookmark.dart';
import '../models/composer_draft.dart';
import '../models/composer_upload.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_user.dart';
import '../models/do_not_disturb.dart';
import '../models/found_group.dart';
import '../models/found_hashtag.dart';
import '../models/found_user.dart';
import '../models/json.dart';
import '../models/notification.dart';
import '../models/notification_totals.dart';
import '../models/post.dart';
import '../models/post_creation.dart';
import '../models/post_flag.dart';
import '../models/post_likers.dart';
import '../models/post_revision.dart';
import '../models/search_results.dart';
import '../models/sidebar.dart';
import '../models/sidebar_tag.dart';
import '../models/site_appearance.dart';
import '../models/site_config.dart';
import '../models/site_emoji.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../models/topic_tracking_state.dart';
import '../models/user_activity.dart';
import '../models/user_card.dart';
import '../models/user_draft.dart';
import '../models/user_preferences.dart';
import '../models/user_summary.dart';
import '../plugin_api/discourse_model_codec.dart';
import 'discourse_api_contracts.dart';
import 'discourse_transport.dart';
import 'http_transport.dart';
import 'json_decode.dart';

export 'discourse_api_contracts.dart';
export 'plugin_transport.dart';
export 'shell_api_ports.dart';

part 'discourse_account_api.dart';
part 'discourse_composer_api.dart';
part 'discourse_search_api.dart';
part 'discourse_site_api.dart';
part 'discourse_topic_api.dart';

class DiscourseApi implements ShellApiCapabilities, DiscourseApiConfiguration {
  DiscourseApi({
    http.Client? client,
    DiscourseTransport? transport,
    this.models = const DiscourseModelCodec.core(),
    this.timeout = const Duration(seconds: 10),
    int maxResponseBytes = 16 * 1024 * 1024,
  }) : assert(timeout > Duration.zero),
       assert(maxResponseBytes > 0),
       assert(
         client == null || transport == null,
         'Provide either client or transport, not both.',
       ),
       _transport =
           transport ??
           DiscourseTransport.create(
             client: client,
             timeout: timeout,
             maxResponseBytes: maxResponseBytes,
           );

  static const int minimumApiVersion = DiscourseSiteApi.minimumApiVersion;
  static const int maximumSearchTermLength = maximumDiscourseSearchTermLength;
  static const int maximumAutocompleteResults = TopicTagSearch.maximumResults;
  static const int maximumCategorySearchTermLength =
      DiscourseSiteApi.maximumCategorySearchTermLength;
  static const int maximumCategorySearchResults =
      DiscourseSiteApi.maximumCategorySearchResults;
  static const int maximumRecentNotifications =
      DiscourseAccountApi.maximumRecentNotifications;
  static const int maximumUserMenuBookmarkRows =
      DiscourseAccountApi.maximumUserMenuBookmarkRows;
  static const int maximumUserActivityPageSize =
      DiscourseAccountApi.maximumUserActivityPageSize;
  static const int maximumUserDraftPageSize =
      DiscourseAccountApi.maximumUserDraftPageSize;
  @override
  final DiscourseModelCodec models;
  @override
  final Duration timeout;

  final DiscourseTransport _transport;

  late final DiscourseAccountApi _account = DiscourseAccountApi(
    _transport,
    models,
  );
  late final DiscourseComposerApi _composer = DiscourseComposerApi(
    _transport,
    models,
  );
  late final DiscourseSearchApi _search = DiscourseSearchApi(_transport);
  late final DiscourseSiteApi _site = DiscourseSiteApi(_transport, models);
  late final DiscourseTopicApi _topic = DiscourseTopicApi(_transport, models);

  static const int maximumForumAddressLength =
      DiscourseSiteApi.maximumForumAddressLength;

  static Uri normalize(String term) => DiscourseSiteApi.normalize(term);

  @override
  Future<DiscourseInstance> lookup(String term) async => _site.lookup(term);

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _account.currentUser(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => _account.topicTrackingState(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    clientId: clientId,
  );

  @override
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => _account.loadUserPreferences(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    clientId: clientId,
  );

  @override
  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  }) async => _account.updateUserPreferences(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    fallback: fallback,
    values: values,
    clientId: clientId,
  );

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _account.customSidebarSections(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) => _site.siteAppearance(
    siteUrl: siteUrl,
    username: username,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _account.notificationTotals(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async => _account.notifications(
    siteUrl: siteUrl,
    apiKey: apiKey,
    limit: limit,
    filterByTypes: filterByTypes,
    clientId: clientId,
  );

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => _account.bookmarks(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    clientId: clientId,
  );

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async => _account.userActivity(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    offset: offset,
    limit: limit,
    clientId: clientId,
  );

  @override
  Future<int> createBookmark({
    required String siteUrl,
    required String apiKey,
    required BookmarkTargetType targetType,
    required int targetId,
    String? name,
    DateTime? reminderAt,
    BookmarkAutoDeletePreference? autoDeletePreference,
    String? clientId,
  }) async => _account.createBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    targetType: targetType,
    targetId: targetId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
    clientId: clientId,
  );

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async => _account.updateBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    bookmarkId: bookmarkId,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
    clientId: clientId,
  );

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async => _account.deleteBookmark(
    siteUrl: siteUrl,
    apiKey: apiKey,
    bookmarkId: bookmarkId,
    targetType: targetType,
    clientId: clientId,
  );

  @override
  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async => _account.deleteTopicBookmarks(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    clientId: clientId,
  );

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async => _account.markNotificationRead(
    siteUrl: siteUrl,
    apiKey: apiKey,
    id: id,
    clientId: clientId,
  );

  @override
  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async => _account.markNotificationsRead(
    siteUrl: siteUrl,
    apiKey: apiKey,
    types: types,
    clientId: clientId,
  );

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async => _topic.topicList(
    siteUrl: siteUrl,
    path: path,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    int? topicId,
    bool searchForId = false,
    String? restrictToArchetype,
    String? apiKey,
    String? clientId,
  }) async => _search.searchPosts(
    siteUrl: siteUrl,
    term: term,
    typeFilter: typeFilter,
    topicId: topicId,
    searchForId: searchForId,
    restrictToArchetype: restrictToArchetype,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async => _search.searchUsersAndGroups(
    siteUrl: siteUrl,
    term: term,
    limit: limit,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _search.recentSearches(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> resetRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _search.resetRecentSearches(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> logSearchClick({
    required String siteUrl,
    required String apiKey,
    required int searchLogId,
    required Object resultId,
    required SearchResultKind resultKind,
    String? clientId,
  }) async => _search.logSearchClick(
    siteUrl: siteUrl,
    apiKey: apiKey,
    searchLogId: searchLogId,
    resultId: resultId,
    resultKind: resultKind,
    clientId: clientId,
  );

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async => _topic.topic(
    siteUrl: siteUrl,
    slug: slug,
    id: id,
    postNumber: postNumber,
    summary: summary,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> recordTopicRead({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postNumber,
    int milliseconds = 500,
    String? clientId,
  }) async => _topic.recordTopicRead(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    postNumber: postNumber,
    milliseconds: milliseconds,
    clientId: clientId,
  );

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async => _topic.updateTopicNotificationLevel(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    notificationLevel: notificationLevel,
    clientId: clientId,
  );

  @override
  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) async => _topic.updateTopicPinForUser(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    pinned: pinned,
    clientId: clientId,
  );

  @override
  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) async => _topic.updateTopicStatus(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    status: status,
    enabled: enabled,
    clientId: clientId,
  );

  @override
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async => _topic.deleteTopic(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    clientId: clientId,
  );

  @override
  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async => _topic.permanentlyDeleteTopic(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    clientId: clientId,
  );

  @override
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async => _topic.recoverTopic(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    clientId: clientId,
  );

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async => _topic.posts(
    siteUrl: siteUrl,
    topicId: topicId,
    ids: ids,
    includeRaw: includeRaw,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  }) => _topic.topicPosts(
    siteUrl: siteUrl,
    topicId: topicId,
    ids: ids,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  }) async => _topic.postRevision(
    siteUrl: siteUrl,
    postId: postId,
    revision: revision,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async => _account.userCard(
    siteUrl: siteUrl,
    username: username,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) async => _account.setUserStatus(
    siteUrl: siteUrl,
    apiKey: apiKey,
    description: description,
    emoji: emoji,
    endsAt: endsAt,
    clientId: clientId,
  );

  @override
  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _account.clearUserStatus(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) async => _account.enterDoNotDisturb(
    siteUrl: siteUrl,
    apiKey: apiKey,
    duration: duration,
    clientId: clientId,
  );

  @override
  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _account.leaveDoNotDisturb(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  }) async => _account.updateHidePresence(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    hidePresence: hidePresence,
    clientId: clientId,
  );

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async =>
      _site.siteConfig(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async =>
      _site.customEmojis(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  @override
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async => _search.searchUsers(
    siteUrl: siteUrl,
    term: term,
    topicId: topicId,
    limit: limit,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async => _search.searchFilterTags(
    siteUrl: siteUrl,
    term: term,
    limit: limit,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async => _search.searchFilterTagGroups(
    siteUrl: siteUrl,
    term: term,
    limit: limit,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async => _search.searchFilterGroups(
    siteUrl: siteUrl,
    term: term,
    limit: limit,
    apiKey: apiKey,
    clientId: clientId,
  );

  static const int hashtagsPerRequest = DiscourseSearchApi.hashtagsPerRequest;

  static const List<String> hashtagOrder = DiscourseSearchApi.hashtagOrder;

  @override
  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async => _search.searchHashtags(
    siteUrl: siteUrl,
    term: term,
    order: order,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    List<String> order = hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async => _search.lookupHashtags(
    siteUrl: siteUrl,
    refs: refs,
    order: order,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<Set<String>> checkMentions({
    required String siteUrl,
    required Iterable<String> names,
    int? topicId,
    String? apiKey,
    String? clientId,
  }) async => _search.checkMentions(
    siteUrl: siteUrl,
    names: names,
    topicId: topicId,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async =>
      _site.emojiCatalog(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  @override
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => _site.emojiSearchAliases(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => _site.categories(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
    page: page,
  );

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async => _site.loadCategories(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
    page: page,
  );

  @override
  Future<void> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) async => _site.updateCategoryNotificationLevel(
    siteUrl: siteUrl,
    apiKey: apiKey,
    categoryId: categoryId,
    notificationLevel: notificationLevel,
    clientId: clientId,
  );

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async => _site.tags(siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async => _site.findCategories(
    siteUrl: siteUrl,
    ids: ids,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    String? clientId,
  }) async => _site.searchCategories(
    siteUrl: siteUrl,
    term: term,
    apiKey: apiKey,
    includeUncategorized: includeUncategorized,
    clientId: clientId,
  );

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _composer.topicComposerCapabilities(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) async => _composer.searchTopicTags(
    siteUrl: siteUrl,
    apiKey: apiKey,
    term: term,
    categoryId: categoryId,
    selectedTagIds: selectedTagIds,
    limit: limit,
    clientId: clientId,
  );

  @override
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
  }) async => _composer.createPost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    raw: raw,
    typingDuration: typingDuration,
    composerOpenDuration: composerOpenDuration,
    replyToPostNumber: replyToPostNumber,
    whisper: whisper,
    draftKey: draftKey,
    clientId: clientId,
  );

  @override
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
  }) async => _composer.createTopic(
    siteUrl: siteUrl,
    apiKey: apiKey,
    title: title,
    raw: raw,
    typingDuration: typingDuration,
    composerOpenDuration: composerOpenDuration,
    categoryId: categoryId,
    tags: tags,
    targetRecipients: targetRecipients,
    draftKey: draftKey,
    clientId: clientId,
  );

  @override
  Future<void> updateTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required String title,
    required String originalTitle,
    required Iterable<TopicTag> tags,
    required Iterable<TopicTag> originalTags,
    int? categoryId,
    String? clientId,
  }) async => _topic.updateTopic(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    title: title,
    originalTitle: originalTitle,
    tags: tags,
    originalTags: originalTags,
    categoryId: categoryId,
    clientId: clientId,
  );

  @override
  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  }) async => _topic.updateTopicTags(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    tags: tags,
    clientId: clientId,
  );

  @override
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  }) async => _composer.updatePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    raw: raw,
    originalText: originalText,
    editReason: editReason,
    clientId: clientId,
  );

  @override
  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _topic.deletePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<({bool allowed, String? reason})> checkPermanentPostDeletion({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _topic.checkPermanentPostDeletion(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<void> permanentlyDeletePost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postId,
    String? clientId,
  }) async => _topic.permanentlyDeletePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async => _topic.deletePosts(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postIds: postIds,
    clientId: clientId,
  );

  @override
  Future<void> mergePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async => _topic.mergePosts(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postIds: postIds,
    clientId: clientId,
  );

  @override
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
    String? clientId,
  }) async => _topic.movePosts(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    postIds: postIds,
    destinationTopicId: destinationTopicId,
    title: title,
    categoryId: categoryId,
    tagIds: tagIds,
    chronologicalOrder: chronologicalOrder,
    clientId: clientId,
  );

  @override
  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  }) async => _topic.changePostOwners(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    postIds: postIds,
    username: username,
    clientId: clientId,
  );

  @override
  Future<void> updatePostWiki({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool wiki,
    String? clientId,
  }) async => _topic.updatePostWiki(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    wiki: wiki,
    clientId: clientId,
  );

  @override
  Future<void> updatePostLocked({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool locked,
    String? clientId,
  }) async => _topic.updatePostLocked(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    locked: locked,
    clientId: clientId,
  );

  @override
  Future<void> unhidePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _topic.unhidePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<void> updatePostType({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postType,
    String? clientId,
  }) async => _topic.updatePostType(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    postType: postType,
    clientId: clientId,
  );

  @override
  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  }) async => _topic.updatePostNotice(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    notice: notice,
    clientId: clientId,
  );

  @override
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _topic.likePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async => _topic.createPostFlag(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    postActionTypeId: postActionTypeId,
    message: message,
    clientId: clientId,
  );

  @override
  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async => _topic.createTopicFlag(
    siteUrl: siteUrl,
    apiKey: apiKey,
    topicId: topicId,
    postActionTypeId: postActionTypeId,
    message: message,
    clientId: clientId,
  );

  @override
  Future<Post?> unlikePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _topic.unlikePost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) async => _topic.postLikers(
    siteUrl: siteUrl,
    postId: postId,
    limit: limit,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async => _topic.recoverPost(
    siteUrl: siteUrl,
    apiKey: apiKey,
    postId: postId,
    clientId: clientId,
  );

  @override
  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  }) async => _composer.saveDraft(
    siteUrl: siteUrl,
    apiKey: apiKey,
    draftKey: draftKey,
    sequence: sequence,
    data: data,
    owner: owner,
    clientId: clientId,
  );

  @override
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    String? clientId,
  }) async => _composer.uploadComposerImage(
    siteUrl: siteUrl,
    apiKey: apiKey,
    file: file,
    onProgress: onProgress,
    abortTrigger: abortTrigger,
    uploadType: uploadType,
    clientId: clientId,
  );

  @override
  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  }) async => _composer.lookupUploadUrls(
    siteUrl: siteUrl,
    apiKey: apiKey,
    shortUrls: shortUrls,
    clientId: clientId,
  );

  @override
  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  }) async => _composer.draft(
    siteUrl: siteUrl,
    apiKey: apiKey,
    draftKey: draftKey,
    clientId: clientId,
  );

  @override
  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async => _account.userDrafts(
    siteUrl: siteUrl,
    apiKey: apiKey,
    offset: offset,
    limit: limit,
    clientId: clientId,
  );

  @override
  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  }) async => _account.deleteUserDraft(
    siteUrl: siteUrl,
    apiKey: apiKey,
    draftKey: draftKey,
    sequence: sequence,
    clientId: clientId,
  );

  @override
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async => _account.userSummary(
    siteUrl: siteUrl,
    apiKey: apiKey,
    username: username,
    clientId: clientId,
  );

  Future<Map<String, dynamic>> _write(
    Uri url, {
    required String siteUrl,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) => _transport.write(
    url,
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    body: body,
    clientId: clientId,
  );

  Future<http.Response> _get(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) =>
      _transport.get(url, siteUrl: siteUrl, apiKey: apiKey, clientId: clientId);

  Future<Map<String, dynamic>> _getObject(
    Uri url, {
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) => _transport.getObject(
    url,
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async => _getObject(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final response = await _get(
      _resolvePluginPath(siteUrl, path),
      siteUrl: siteUrl,
      apiKey: apiKey,
      clientId: clientId,
    );
    try {
      final decoded = await decodeJsonHttpResponse(response);
      if (decoded is! List) throw const FormatException('Expected a JSON list');
      return List.unmodifiable([
        for (final value in decoded)
          if (value is Map<String, dynamic>) value,
      ]);
    } catch (error, stackTrace) {
      throw SiteLookupException(
        SiteLookupFailure.unreachable,
        siteUrl,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async => _write(
    _resolvePluginPath(siteUrl, path),
    siteUrl: siteUrl,
    method: method,
    apiKey: apiKey,
    clientId: clientId,
    body: body,
  );

  static Uri _resolvePluginPath(String siteUrl, String path) {
    final site = Uri.parse(siteUrl);
    final target = site.resolve(path);
    if (target.origin != site.origin) {
      throw ArgumentError.value(
        path,
        'path',
        'Plugin API paths must stay on the connected site origin.',
      );
    }
    return target;
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => _account.revokeApiKey(
    siteUrl: siteUrl,
    apiKey: apiKey,
    clientId: clientId,
  );

  static const String userAgent = DiscourseTransport.userAgent;

  static Map<String, String> authHeaders(String apiKey, {String? clientId}) =>
      DiscourseTransport.authHeaders(apiKey, clientId: clientId);

  @override
  void close() => _transport.close();
}
