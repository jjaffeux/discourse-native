import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/data/update_store.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/do_not_disturb.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/found_group.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/post_revision.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/models/user_preferences.dart';
import 'package:discourse_native/src/models/user_summary.dart';
import 'package:discourse_native/src/plugin_api/core_plugin_host.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugin_api/live_channels.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_pin.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_api.dart';
import 'package:discourse_native/src/plugins/gifs/gifs_settings.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/polls_api.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_api.dart';

import 'bundled_plugins.dart';

class FakeInstanceStore implements InstanceStore {
  FakeInstanceStore([Iterable<DiscourseInstance> instances = const []])
    : _instances = List.of(instances);

  List<DiscourseInstance> _instances;
  int saveCount = 0;

  @override
  Future<List<DiscourseInstance>> load() async => List.of(_instances);

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    _instances = List.of(instances);
    saveCount++;
  }
}

class FakeForumTabStore implements ForumTabStore {
  FakeForumTabStore([Iterable<ForumWorkspace> workspaces = const []])
    : _workspaces = List.of(workspaces);

  List<ForumWorkspace> _workspaces;
  int saveCount = 0;

  List<ForumWorkspace> get workspaces => List.unmodifiable(_workspaces);

  @override
  Future<List<ForumWorkspace>> load() async => List.of(_workspaces);

  @override
  Future<void> save(Iterable<ForumWorkspace> workspaces) async {
    _workspaces = List.of(workspaces);
    saveCount++;
  }
}

/// Defaults to unsupported so unrelated shell tests do not expose update UI.
class FakeUpdater implements Updater {
  FakeUpdater({
    this.isSupported = false,
    this.releases = const {},
    this.checkFailure,
    this.downloadFailure,
    this.installFailure,
    this.progressSteps = const [0.25, 0.5, 1.0],
    this.gate,
    this.checkGates = const {},
    this.downloadGate,
  });

  @override
  final bool isSupported;

  final Map<UpdateChannel, UpdateRelease?> releases;

  final UpdateException? checkFailure;
  final UpdateException? downloadFailure;
  final UpdateException? installFailure;

  final List<double> progressSteps;

  final Completer<void>? gate;

  final Map<UpdateChannel, Completer<void>> checkGates;

  final Completer<void>? downloadGate;

  int checkCount = 0;
  int downloadCount = 0;
  int installCount = 0;
  int discardCount = 0;
  int _discardGeneration = 0;
  UpdateChannel? lastCheckedChannel;
  UpdateRelease? lastDownloaded;
  UpdateRelease? stagedRelease;

  @override
  Future<UpdateRelease?> check({required UpdateChannel channel}) async {
    checkCount++;
    lastCheckedChannel = channel;
    if (gate != null) await gate!.future;
    await checkGates[channel]?.future;
    if (checkFailure != null) throw checkFailure!;
    return releases[channel];
  }

  @override
  Future<void> download(
    UpdateRelease release, {
    void Function(double fraction)? onProgress,
  }) async {
    final discardGeneration = _discardGeneration;
    downloadCount++;
    lastDownloaded = release;
    for (final step in progressSteps) {
      onProgress?.call(step);
    }
    if (downloadGate != null) await downloadGate!.future;
    if (discardGeneration != _discardGeneration) return;
    if (downloadFailure != null) throw downloadFailure!;
    stagedRelease = release;
  }

  @override
  Future<void> installAndRestart() async {
    installCount++;
    if (installFailure != null) throw installFailure!;
  }

  @override
  Future<void> discard() async {
    discardCount++;
    _discardGeneration++;
    stagedRelease = null;
  }
}

class FakeUpdateStore implements UpdateStore {
  FakeUpdateStore({
    this.rawChannel,
    this.lastChecked,
    this.channelWriteGates = const {},
  });

  String? rawChannel;
  DateTime? lastChecked;
  final Map<UpdateChannel, Completer<void>> channelWriteGates;
  int writeCount = 0;

  @override
  Future<UpdateChannel?> readChannel() async =>
      UpdateChannel.byName(rawChannel);

  @override
  Future<void> writeChannel(UpdateChannel channel) async {
    writeCount++;
    await channelWriteGates[channel]?.future;
    rawChannel = channel.name;
  }

  @override
  Future<DateTime?> readLastChecked() async => lastChecked;

  @override
  Future<void> writeLastChecked(DateTime at) async => lastChecked = at;
}

class FakeDraftStore implements DraftStore {
  final Map<String, String> saved = {};
  final List<String> events = [];

  static String _key(String siteUrl, String draftKey) => '$siteUrl::$draftKey';

  @override
  Future<String?> read(String siteUrl, String draftKey) async =>
      saved[_key(siteUrl, draftKey)];

  @override
  Future<DraftStoreRead> readChecked(String siteUrl, String draftKey) async {
    try {
      return (value: await read(siteUrl, draftKey), succeeded: true);
    } catch (_) {
      return (value: null, succeeded: false);
    }
  }

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent != null && !ifCurrent()) return;
    saved[_key(siteUrl, draftKey)] = data;
    events.add('write:$data');
  }

  @override
  Future<void> clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent != null && !ifCurrent()) return;
    saved.remove(_key(siteUrl, draftKey));
    events.add('clear');
  }

  @override
  Future<bool> clearChecked(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    if (ifCurrent?.call() == false) return false;
    try {
      await clear(siteUrl, draftKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    if (ifCurrent != null && !ifCurrent()) return;
    saved.removeWhere((key, _) => key.startsWith('$siteUrl::'));
    events.add('clearSite:$siteUrl');
  }
}

/// Real long-poll backoff timers outlive widget-test trees.
class FakeSiteTracker implements SiteTracker, PluginLiveChannelHandle {
  FakeSiteTracker({
    required this.siteUrl,
    required this.onIncomingTopics,
    required this.onNotifications,
    required this.onReviewableCounts,
    this.userId,
    this.apiKey,
  });

  static final List<FakeSiteTracker> built = [];

  static SiteTrackerFactory reset() {
    built.clear();
    return factory;
  }

  static SiteTracker factory({
    required String siteUrl,
    required void Function() onIncomingTopics,
    required void Function(Object? data) onNotifications,
    required void Function(Object? data) onReviewableCounts,
    int? userId,
    String? apiKey,
    String? clientId,
    bool Function()? shouldLongPoll,
  }) {
    final tracker = FakeSiteTracker(
      siteUrl: siteUrl,
      onIncomingTopics: onIncomingTopics,
      onNotifications: onNotifications,
      onReviewableCounts: onReviewableCounts,
      userId: userId,
      apiKey: apiKey,
    );
    built.add(tracker);
    return tracker;
  }

  @override
  final String siteUrl;

  @override
  final void Function() onIncomingTopics;

  @override
  final void Function(Object? data) onNotifications;

  @override
  final void Function(Object? data) onReviewableCounts;

  @override
  final int? userId;

  final String? apiKey;

  @override
  final IncomingTopics incoming = IncomingTopics();
  void Function(Object? data)? _onTopicTrackingState;

  bool polling = true;
  int pollNowCalls = 0;
  bool disposed = false;

  void deliver(Object? message) {
    _onTopicTrackingState?.call(message);
    if (incoming.notify(message)) onIncomingTopics();
  }

  void deliverTopicTracking(Object? message) =>
      _onTopicTrackingState?.call(message);

  @override
  void watchTopicTrackingState(
    int accountId,
    void Function(Object? data) onMessage,
  ) {
    _onTopicTrackingState ??= onMessage;
  }

  void deliverNotification(Object? message) => onNotifications(message);

  void deliverReviewableCounts(Object? message) => onReviewableCounts(message);

  final List<String> watchedChannels = [];
  final Map<String, int?> watchedChannelLastIds = {};

  @override
  int? watchedTopic;

  void Function(String channel, Object? data)? _onTopicMessage;

  @override
  void watchTopic(
    int topicId,
    List<String> channels,
    void Function(String channel, Object? data) onMessage, {
    Map<String, int?> lastIds = const {},
  }) {
    if (watchedTopic == topicId) return;
    unwatchTopic();
    watchedTopic = topicId;
    watchedChannels.addAll(channels);
    for (final channel in channels) {
      watchedChannelLastIds[channel] = lastIds[channel];
    }
    _onTopicMessage = onMessage;
  }

  @override
  void unwatchTopic() {
    watchedTopic = null;
    watchedChannels.clear();
    watchedChannelLastIds.clear();
    _onTopicMessage = null;
  }

  void deliverTopicMessage(String channel, Object? data) =>
      _onTopicMessage?.call(channel, data);

  final Map<String, List<void Function(Object?)>> pluginChannelCallbacks = {};
  final Map<String, int?> pluginChannelLastIds = {};

  @override
  SiteMessageBusSubscription watchPluginChannel(
    String channel,
    void Function(Object? data) onMessage, {
    int? lastId,
  }) {
    pluginChannelLastIds[channel] = lastId;
    (pluginChannelCallbacks[channel] ??= []).add(onMessage);
    return _FakeSiteMessageBusSubscription(() {
      pluginChannelCallbacks[channel]?.remove(onMessage);
    });
  }

  int _deliveredPluginMessageId = 1;

  @override
  SiteMessageBusSubscription watchPluginChannelWithPosition(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) {
    pluginChannelLastIds[channel] = lastId;
    void callback(Object? data) => onMessage(data, _deliveredPluginMessageId);
    (pluginChannelCallbacks[channel] ??= []).add(callback);
    return _FakeSiteMessageBusSubscription(() {
      pluginChannelCallbacks[channel]?.remove(callback);
    });
  }

  @override
  PluginLiveChannelSubscription subscribe(
    String channel,
    void Function(Object? data, int messageId) onMessage, {
    int? lastId,
  }) =>
      watchPluginChannelWithPosition(channel, onMessage, lastId: lastId)
          as PluginLiveChannelSubscription;

  void deliverPluginMessage(String channel, Object? data, {int messageId = 1}) {
    _deliveredPluginMessageId = messageId;
    for (final callback in List.of(
      pluginChannelCallbacks[channel] ?? const <void Function(Object?)>[],
    )) {
      callback(data);
    }
    _deliveredPluginMessageId = 1;
  }

  @override
  void start() => polling = true;

  @override
  void stop() => polling = false;

  @override
  void pollNow() => pollNowCalls++;

  @override
  Future<void> dispose() async {
    polling = false;
    _onTopicTrackingState = null;
    unwatchTopic();
    for (final callbacks in pluginChannelCallbacks.values) {
      callbacks.clear();
    }
    disposed = true;
  }
}

final class _FakeSiteMessageBusSubscription
    implements SiteMessageBusSubscription, PluginLiveChannelSubscription {
  _FakeSiteMessageBusSubscription(this._cancel);
  final void Function() _cancel;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

class FakeDiscourseApi
    implements
        ShellApiCapabilities,
        DiscourseApiConfiguration,
        ChatApi,
        GifsApi,
        PollsApi,
        ReactionsApi,
        ReactionsWriteApi {
  FakeDiscourseApi({
    DiscourseModelCodec? models,
    this.results = const {},
    this.failure,
    this.user,
    this.trackingState,
    this.trackingStateGate,
    this.doNotDisturbUntil,
    this.totals,
    this.notificationList,
    this.replyNotificationList,
    this.chatNotificationList,
    this.bookmarkList,
    this.reminderList = const [],
    this.userPreferences,
    this.userPreferencesGate,
    this.userPreferencesWriteGate,
    this.feeds = const {},
    this.feedCategoriesByPath = const {},
    this.filterOptionsByPath = const {},
    this.creatableFeedPaths = const {},
    this.categoryList = const [],
    this.categoryPages = const {},
    this.categorySearches = const {},
    this.categoryLoadComplete = true,
    this.categoryPostActionCatalog,
    this.categorySiteTopTags = const [],
    this.categoryAnonymousDefaultTags = const [],
    this.tagList = const [],
    this.composerCapabilities = const TopicComposerCapabilities(),
    this.topicTagSearches = const {},
    this.userDraftList = const [],
    this.userDraftGate,
    this.summary,
    this.userSummaryGate,
    this.userActivityItems = const [],
    this.userActivityCategories = const [],
    this.userActivityGate,
    this.nextPages = const {},
    this.gate,
    this.feedGates = const {},
    this.topics = const {},
    this.summaryTopics = const {},
    this.topicGate,
    this.postsById = const {},
    this.postRecommendations = const {},
    this.postGate,
    this.cards = const {},
    this.creation,
    this.writeFailure,
    this.presenceGate,
    this.permanentDeletionAllowed = true,
    this.permanentDeletionReason,
    this.draftFailure,
    this.draftGate,
    this.draftDeleteFailure,
    this.draftDeleteGate,
    this.draftToRestore = const (draft: null, sequence: 0),
    this.draftRestoreGate,
    this.draftRestoreFailure,
    this.likeResponses = const {},
    this.likeFailure,
    this.likeGate,
    this.flagResponses = const {},
    this.flagFailure,
    this.flagGate,
    this.likersById = const {},
    this.likerGate,
    this.postRevisions = const {},
    this.siteAppearances = const {},
    this.appearanceGate,
    this.siteConfigs = const {},
    this.siteConfigGate,
    this.gifCategoriesBySite = const {},
    this.gifSearchPages = const {},
    this.gifFailure,
    this.searchResults = const {},
    this.customEmojisBySite = const {},
    this.customEmojiGate,
    this.userSearches = const {},
    this.filterTagSearches = const {},
    this.hashtagSearches = const {},
    this.hashtagSearchGate,
    this.realUsernames = const {},
    this.emojiCatalogsBySite = const {},
    this.emojisBySite = const {},
    this.reactorsById = const {},
    this.reactorGate,
    this.reactionResponses = const {},
    this.reactionFailure,
    this.reactionGate,
    this.pollVoteResponses = const {},
    this.pollRemovalResponses = const {},
    this.pollVoteFailure,
    this.pollVoteGate,
    this.directMessageChannelsByUsername = const {},
    this.directMessageGroupChannel,
    this.chatDirectMessageSearches = const {},
    this.chatChannelsBySite = const {},
    this.chatChannelsById = const {},
    this.chatChannelUpdateResponse,
    this.chatChannelUpdateGate,
    this.chatChannelUpdateFailure,
    this.chatChannelStatusResponse,
    this.chatChannelStatusGate,
    this.chatChannelStatusFailure,
    this.chatChannelGate,
    this.chatChannelStarGate,
    this.chatChannelStarFailure,
    this.chatChannelNotificationMembership = const ChatMembership(
      following: true,
    ),
    this.chatChannelNotificationGate,
    this.chatChannelNotificationFailure,
    this.chatChannelMemberPagesByKey = const {},
    this.chatChannelMemberGate,
    this.chatBrowsePagesByKey = const {},
    this.chatBrowseGate,
    this.chatChannelFollowMembership = const ChatMembership(following: true),
    this.chatChannelUnfollowMembership = const ChatMembership(),
    this.chatChannelFollowGate,
    this.chatChannelFollowFailure,
    this.chatSearchPagesByKey = const {},
    this.chatSearchGate,
    this.chatMessagesByKey = const {},
    this.chatThreadPagesByOffset = const {},
    this.chatChannelThreadPagesByKey = const {},
    this.chatThreadsByKey = const {},
    this.createdChatThreadsByKey = const {},
    this.chatMessageGate,
    this.chatReadFailure,
    this.chatSendFailure,
    this.chatSendGate,
    this.chatSentMessageId = 1,
    this.chatEditFailure,
    this.chatEditGate,
    this.chatMessageMutationFailure,
    this.chatMessageMutationGate,
    this.chatMoveFirstMessageId = 1000,
    this.chatRebakeFailure,
    this.chatRebakeGate,
    this.chatQuoteMarkdown = '[chat quote]',
    this.chatQuoteFailure,
    this.chatQuoteGate,
    this.chatPinFailure,
    this.chatPinGate,
    this.chatPinsByChannel = const {},
    this.chatFlagFailure,
    this.chatFlagGate,
    this.composerUploadResult,
    this.chatReactionFailure,
    this.chatReactionGate,
    this.chatReactorsById = const {},
    this.chatReactorGate,
    this.customSidebarSectionsBySite = const {},
    this.pluginResponses = const {},
    Map<String, WriteException>? pluginWriteFailures,
  }) : models =
           models ??
           DiscourseModelCodec(
             extensions: pluginRegistry,
             recommendationSources: pluginRegistry,
             icons: pluginRegistry,
           ),
       pluginWriteFailures = pluginWriteFailures ?? {};

  @override
  final DiscourseModelCodec models;

  final Map<String, DiscourseInstance> results;
  final Map<String, List<SidebarSection>> customSidebarSectionsBySite;
  final Map<String, Map<String, dynamic>> pluginResponses;
  final Map<String, WriteException> pluginWriteFailures;
  final List<
    ({String siteUrl, String method, String path, Map<String, Object?> body})
  >
  pluginWrites = [];
  final List<String> pluginReadPaths = [];
  final SiteLookupFailure? failure;

  final DiscourseUser? user;

  final TopicTrackingState? trackingState;
  final Completer<void>? trackingStateGate;
  final List<String> topicTrackingRequests = [];

  final DateTime? doNotDisturbUntil;

  final NotificationTotals? totals;

  final List<DiscourseNotification>? notificationList;

  final List<DiscourseNotification>? replyNotificationList;

  final List<DiscourseNotification>? chatNotificationList;

  final List<Bookmark>? bookmarkList;

  final List<DiscourseNotification> reminderList;

  UserPreferences? userPreferences;
  final Completer<void>? userPreferencesGate;
  final Completer<void>? userPreferencesWriteGate;
  final List<({String siteUrl, String username, String? clientId})>
  userPreferenceLoads = [];
  final List<
    ({
      String siteUrl,
      String username,
      String? clientId,
      Map<String, Object?> values,
    })
  >
  userPreferenceUpdates = [];

  final List<String> revoked = [];
  int totalsCalls = 0;
  int notificationCalls = 0;
  int replyNotificationCalls = 0;
  int chatNotificationCalls = 0;

  final List<List<NotificationTypeName>> notificationFilters = [];

  final List<String> bookmarksRequested = [];
  int _nextBookmarkId = 1000;
  final List<
    ({
      BookmarkTargetType targetType,
      int targetId,
      String? name,
      DateTime? reminderAt,
      BookmarkAutoDeletePreference? autoDeletePreference,
    })
  >
  createdBookmarks = [];
  final List<
    ({
      int bookmarkId,
      String? name,
      DateTime? reminderAt,
      BookmarkAutoDeletePreference autoDeletePreference,
    })
  >
  updatedBookmarks = [];
  final List<int> deletedBookmarks = [];

  final List<int> markedRead = [];
  final List<List<NotificationTypeName>> markedTypesRead = [];

  final Map<String, List<Topic>> feeds;
  final Map<String, List<TopicCategory>> feedCategoriesByPath;
  final Map<String, List<TopicFilterOption>> filterOptionsByPath;
  final Set<String> creatableFeedPaths;

  final List<TopicCategory> categoryList;
  final Map<int, List<TopicCategory>> categoryPages;
  final Map<String, List<TopicCategory>> categorySearches;
  final bool categoryLoadComplete;
  final SitePostActionCatalog? categoryPostActionCatalog;
  final List<SidebarTag> categorySiteTopTags;
  final List<SidebarTag> categoryAnonymousDefaultTags;
  final List<SidebarTag> tagList;
  final TopicComposerCapabilities composerCapabilities;
  final List<String> categoryRequests = [];
  final List<String> tagRequests = [];
  final List<int> categoryPagesRequested = [];
  final List<List<int>> categoryIdsRequested = [];
  final List<String> categorySearchTerms = [];
  final List<String> topicComposerCapabilityRequests = [];
  final Map<String, TopicTagSearch> topicTagSearches;

  final List<int> topicTagSearchLimits = [];
  List<UserDraft> userDraftList;
  final Completer<void>? userDraftGate;
  final List<({String siteUrl, int offset, int limit})> userDraftRequests = [];
  final List<({String siteUrl, String draftKey, int sequence})>
  userDraftsDeleted = [];
  final UserSummary? summary;
  final Completer<void>? userSummaryGate;
  final List<({String siteUrl, String username})> userSummaryRequests = [];
  final List<UserActivityItem> userActivityItems;
  final List<TopicCategory> userActivityCategories;
  final Completer<void>? userActivityGate;
  final List<({String siteUrl, String username, int offset, int limit})>
  userActivityRequests = [];

  final Map<String, String> nextPages;

  final Completer<void>? gate;

  final Map<String, Completer<void>> feedGates;

  final Map<int, TopicPayload> topics;

  final Map<int, TopicPayload> summaryTopics;

  final Completer<void>? topicGate;

  final Map<int, Post> postsById;

  final Map<int, TopicRecommendations> postRecommendations;

  final Completer<void>? postGate;

  final Map<String, UserCard> cards;

  final List<String> cardsRequested = [];

  final List<int> topicsOpened = [];
  final List<int?> topicPostNumbersOpened = [];
  final List<int> topicSummariesOpened = [];
  final List<({int topicId, int postNumber})> topicReadsRecorded = [];
  final List<({int topicId, TopicNotificationLevel notificationLevel})>
  topicNotificationLevelsUpdated = [];
  final List<({int topicId, TopicStatusProperty status, bool enabled})>
  topicStatusesUpdated = [];
  final List<int> topicsDeleted = [];
  final List<int> topicsRecovered = [];
  final List<int> topicsPermanentlyDeleted = [];
  final List<({int topicId, bool pinned})> topicPinPreferencesUpdated = [];
  final List<({String description, String emoji, DateTime? endsAt})>
  userStatusesSet = [];
  final List<String> userStatusesCleared = [];
  final List<DoNotDisturbDuration> doNotDisturbDurations = [];
  final List<String> doNotDisturbResumes = [];
  final List<({String siteUrl, String username, bool hidePresence})>
  presencePreferencesUpdated = [];
  final List<List<int>> postFetches = [];

  final List<String> feedPaths = [];

  final List<String> lookups = [];

  int closeCalls = 0;

  final PostCreation? creation;

  final WriteException? writeFailure;

  final Completer<void>? presenceGate;
  final bool permanentDeletionAllowed;
  final String? permanentDeletionReason;
  final List<int> permanentDeletionChecks = [];

  final List<Map<String, Object?>> created = [];
  final List<Map<String, Object?>> topicsCreated = [];

  final List<Map<String, Object?>> updated = [];
  final List<Map<String, Object?>> topicsUpdated = [];
  final List<Map<String, Object?>> topicTagsUpdated = [];

  final List<int> deleted = [];
  final List<int> recovered = [];
  final List<({int topicId, int postId})> postsPermanentlyDeleted = [];
  final List<List<int>> bulkDeleted = [];
  final List<List<int>> merged = [];
  final List<
    ({
      int topicId,
      List<int> postIds,
      int? destinationTopicId,
      String? title,
      int? categoryId,
      List<int> tagIds,
      bool chronologicalOrder,
    })
  >
  movedTopicPosts = [];
  String topicMoveUrl = '/t/moved-topic/99';
  final List<({int topicId, List<int> postIds, String username})>
  postOwnersChanged = [];

  final List<int> liked = [];
  final List<int> unliked = [];

  /// What a like route answers with, keyed by post id. Nothing for a post
  /// means the route answered without one — which real ones do, and which
  /// leaves the caller's own guess at the count standing.
  final Map<int, Post> likeResponses;

  final WriteException? likeFailure;

  final Completer<void>? likeGate;

  final Map<int, Post> flagResponses;
  final WriteException? flagFailure;
  final Completer<void>? flagGate;
  final List<({int postId, int postActionTypeId, String? message})>
  flagsCreated = [];
  final List<({int topicId, int postActionTypeId, String? message})>
  topicFlagsCreated = [];

  final Map<int, List<PostLiker>> likersById;

  final List<int> likersRequested = [];

  final Completer<void>? likerGate;

  final Map<int, PostRevision> postRevisions;
  final List<({int postId, int? revision})> postRevisionsRequested = [];

  /// Resolved appearances returned per site. Missing is the neutral optional
  /// capability answer used by tests unrelated to theming.
  final Map<String, SiteAppearance> siteAppearances;
  final Completer<void>? appearanceGate;
  final List<String> appearancesRequested = [];

  /// Missing config is the neutral, plain-core fixture default.
  final Map<String, SiteConfig> siteConfigs;
  final Completer<void>? siteConfigGate;

  final Map<String, List<GifCategory>> gifCategoriesBySite;
  final Map<String, GifSearchPage> gifSearchPages;
  final SiteLookupFailure? gifFailure;
  final List<String> gifCategoryRequests = [];
  final List<
    ({String siteUrl, String query, String fileDetail, String position})
  >
  gifSearchRequests = [];

  static String gifSearchKey(String query, {String position = '0'}) =>
      '$query::$position';

  final Map<String, SearchResults> searchResults;
  final List<({String siteUrl, String term, String? typeFilter, int? topicId})>
  searchesRequested = [];
  final List<({int searchLogId, Object resultId, SearchResultKind resultKind})>
  searchClicks = [];

  final List<String> siteConfigsRequested = [];

  final Map<String, Map<String, String>> customEmojisBySite;
  final Completer<void>? customEmojiGate;

  final List<String> customEmojisRequired = [];

  final Map<String, List<FoundUser>> userSearches;

  final List<({String term, int? topicId})> userSearchesRequested = [];

  final Map<String, List<TopicFilterLookupValue>> filterTagSearches;

  final Map<String, List<FoundHashtag>> hashtagSearches;
  final Completer<void>? hashtagSearchGate;

  final List<String> hashtagSearchesRequested = [];

  final List<List<String>> hashtagSearchOrdersRequested = [];

  final List<Set<String>> hashtagLookupsRequested = [];

  final List<List<String>> hashtagLookupOrdersRequested = [];

  final Set<String> realUsernames;

  final List<Set<String>> mentionChecksRequested = [];

  final Map<String, SiteEmojiCatalog> emojiCatalogsBySite;

  final Map<String, List<SiteEmoji>> emojisBySite;

  final List<String> emojisRequested = [];

  final Map<String, PostReactors> reactorsById;

  final List<({int postId, String? filter})> reactorsRequested = [];

  final Completer<void>? reactorGate;

  /// What [toggleReaction] answers with, keyed by post id. Nothing for a post
  /// means the route answered without one, which leaves the caller's own guess
  /// standing.
  final Map<int, Post> reactionResponses;

  final WriteException? reactionFailure;

  final Completer<void>? reactionGate;

  final List<({int postId, String reaction})> reacted = [];

  final Map<String, PollVoteResponse> pollVoteResponses;
  final Map<String, PollVoteResponse> pollRemovalResponses;

  final WriteException? pollVoteFailure;

  final Completer<void>? pollVoteGate;

  final List<({int postId, String pollName, List<String> options})> pollVotes =
      [];
  final List<({int postId, String pollName})> pollVotesRemoved = [];

  static String pollVoteKey(int postId, String pollName) =>
      '$postId::$pollName';

  /// Missing means Chat is disabled; totals must advertise it before lookup.
  final Map<String, ChatChannels> chatChannelsBySite;

  final Map<int, ChatChannel> chatChannelsById;
  final ChatChannel? chatChannelUpdateResponse;
  final Completer<void>? chatChannelUpdateGate;
  final WriteException? chatChannelUpdateFailure;
  final ChatChannel? chatChannelStatusResponse;
  final Completer<void>? chatChannelStatusGate;
  final WriteException? chatChannelStatusFailure;
  final List<({int channelId, String? name, String? slug, String? description})>
  chatChannelMetadataUpdates = [];
  final List<({int channelId, bool enabled})> chatChannelThreadingUpdates = [];
  final List<({int channelId, ChatChannelStatus status})>
  chatChannelStatusesUpdated = [];
  final List<int> chatChannelDetailsRequested = [];

  final Map<String, ChatChannel> directMessageChannelsByUsername;
  final ChatChannel? directMessageGroupChannel;

  final List<String> directMessageChannelsRequested = [];
  final List<
    ({List<String> usernames, List<String> groups, String? name, bool upsert})
  >
  directMessageChannelRequests = [];

  final Map<String, ChatDirectMessageSearchResults> chatDirectMessageSearches;
  final List<String> chatDirectMessageSearchesRequested = [];
  final List<
    ({String term, bool includeGroups, bool includeDirectMessageChannels})
  >
  chatDirectMessageSearchRequests = [];

  final List<String> chatChannelsRequested = [];

  final Completer<void>? chatChannelGate;

  final Completer<void>? chatChannelStarGate;
  final WriteException? chatChannelStarFailure;
  final List<({int channelId, bool starred})> chatChannelStarsUpdated = [];

  final ChatMembership chatChannelNotificationMembership;
  final Completer<void>? chatChannelNotificationGate;
  final WriteException? chatChannelNotificationFailure;
  final List<
    ({
      int channelId,
      bool? muted,
      ChatChannelNotificationLevel? notificationLevel,
    })
  >
  chatChannelNotificationsUpdated = [];

  final Map<String, ChatChannelMembersPage> chatChannelMemberPagesByKey;
  final Completer<void>? chatChannelMemberGate;
  final List<({int channelId, String username, int offset, int limit})>
  chatChannelMembersRequested = [];

  static String chatChannelMembersKey(
    int channelId, {
    String username = '',
    int offset = 0,
  }) => '$channelId~${username.trim()}~$offset';

  final Map<String, ChatChannelBrowsePage> chatBrowsePagesByKey;
  final Completer<void>? chatBrowseGate;
  final List<
    ({String filter, ChatChannelBrowseStatus status, int offset, int limit})
  >
  chatBrowseRequested = [];

  static String chatBrowseKey({
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
  }) => '${status.name}~${filter.trim()}~$offset';

  final ChatMembership chatChannelFollowMembership;
  final ChatMembership chatChannelUnfollowMembership;
  final Completer<void>? chatChannelFollowGate;
  final WriteException? chatChannelFollowFailure;
  final List<({int channelId, bool following})> chatChannelFollowsUpdated = [];

  final Map<String, ChatSearchPage> chatSearchPagesByKey;
  final Completer<void>? chatSearchGate;
  final List<
    ({
      String query,
      int? channelId,
      ChatSearchSort sort,
      int offset,
      int limit,
      bool excludeThreads,
    })
  >
  chatSearchesRequested = [];

  static String chatSearchKey(
    String query, {
    int? channelId,
    ChatSearchSort sort = ChatSearchSort.relevance,
    int offset = 0,
  }) => '$query~${channelId ?? 'all'}~${sort.name}~$offset';

  final Map<String, ChatMessagePage> chatMessagesByKey;

  final Map<int, ChatThreadPage> chatThreadPagesByOffset;
  final Map<String, ChatThreadPage> chatChannelThreadPagesByKey;
  final Map<String, ChatThread> chatThreadsByKey;
  final Map<String, ChatThread> createdChatThreadsByKey;

  static String chatThreadKey(int channelId, int threadId) =>
      '$channelId~$threadId';
  static String chatChannelThreadPageKey(int channelId, int offset) =>
      '$channelId~page~$offset';
  static String createdChatThreadKey(int channelId, int originalMessageId) =>
      '$channelId~original~$originalMessageId';

  static String chatMessagesKey(
    int channelId, {
    int? before,
    int? after,
    int? targetMessageId,
  }) => switch ((before, after, targetMessageId)) {
    (final int target, _, _) => '$channelId~past~$target',
    (_, final int target, _) => '$channelId~future~$target',
    (_, _, final int target) => '$channelId~target~$target',
    _ => '$channelId',
  };

  /// Falls back to [chatMessagesKey] unless a test names a newer window.
  static String chatMessagesLatestKey(int channelId) => '$channelId~latest';

  final List<
    ({
      int channelId,
      int? before,
      int? after,
      int? targetMessageId,
      bool fromLastRead,
      int pageSize,
    })
  >
  chatMessagesRequested = [];

  final List<({int channelId, int threadId})> chatThreadsRequested = [];
  final List<({int offset, int limit})> chatThreadPagesRequested = [];
  final List<({int channelId, int offset, int limit})>
  chatChannelThreadPagesRequested = [];
  final List<({int channelId, int originalMessageId, String? title})>
  chatThreadsCreated = [];
  final List<({int channelId, int threadId, String title})>
  chatThreadTitlesUpdated = [];
  final List<
    ({
      int channelId,
      int threadId,
      ChatThreadNotificationLevel notificationLevel,
    })
  >
  chatThreadNotificationLevelsUpdated = [];
  final List<
    ({
      int channelId,
      int threadId,
      int? before,
      int? after,
      int? targetMessageId,
      int pageSize,
    })
  >
  chatThreadMessagesRequested = [];

  final Completer<void>? chatMessageGate;

  final WriteException? chatReadFailure;

  final List<({int channelId, int messageId})> chatReadsMarked = [];

  final WriteException? chatSendFailure;
  final Completer<void>? chatSendGate;
  final int? chatSentMessageId;
  final ComposerUploadResult? composerUploadResult;
  final List<({String siteUrl, String filename, ComposerUploadType uploadType})>
  composerUploads = [];
  final List<
    ({
      String siteUrl,
      int channelId,
      String message,
      List<int> uploadIds,
      int? threadId,
      String? stagedId,
      DateTime? clientCreatedAt,
      int? contextTopicId,
      List<int> contextPostIds,
    })
  >
  chatMessagesSent = [];

  final WriteException? chatEditFailure;
  final Completer<void>? chatEditGate;
  final List<
    ({
      String siteUrl,
      int channelId,
      int messageId,
      String message,
      List<int> uploadIds,
    })
  >
  chatMessagesEdited = [];

  final WriteException? chatMessageMutationFailure;
  final Completer<void>? chatMessageMutationGate;
  final int chatMoveFirstMessageId;
  final WriteException? chatRebakeFailure;
  final Completer<void>? chatRebakeGate;
  final List<({int channelId, int messageId})> chatMessagesDeleted = [];
  final List<({int channelId, List<int> messageIds})>
  chatMessageBatchesDeleted = [];
  final List<({int channelId, int destinationChannelId, List<int> messageIds})>
  chatMessageMoves = [];
  final List<({int channelId, int messageId})> chatMessagesRestored = [];
  final List<({int channelId, int messageId})> chatMessagesRebaked = [];
  final String chatQuoteMarkdown;
  final WriteException? chatQuoteFailure;
  final Completer<void>? chatQuoteGate;
  final List<({int channelId, List<int> messageIds})> chatQuotesGenerated = [];

  final WriteException? chatPinFailure;
  final Completer<void>? chatPinGate;
  final List<({int channelId, int messageId, bool pinned})>
  chatMessagePinsUpdated = [];
  final Map<int, ChatPins> chatPinsByChannel;
  final List<int> chatPinsRead = [];

  final WriteException? chatFlagFailure;
  final Completer<void>? chatFlagGate;
  final List<({int channelId, int messageId, int flagTypeId, String? message})>
  chatMessagesFlagged = [];

  final WriteException? chatReactionFailure;
  final Completer<void>? chatReactionGate;
  final List<
    ({
      String siteUrl,
      int channelId,
      int messageId,
      String emoji,
      ChatReactionAction action,
    })
  >
  chatReactionsSet = [];

  final Map<String, ChatMessageReactors> chatReactorsById;
  final Completer<void>? chatReactorGate;
  final List<({int channelId, int messageId, String? filter})>
  chatReactorsRequested = [];

  final WriteException? draftFailure;

  final Completer<void>? draftGate;

  final WriteException? draftDeleteFailure;

  final Completer<void>? draftDeleteGate;

  final ({ComposerDraft? draft, int sequence}) draftToRestore;

  final Completer<void>? draftRestoreGate;

  WriteException? draftRestoreFailure;

  final List<Map<String, Object?>> draftsSaved = [];

  @override
  Duration get timeout => const Duration(seconds: 10);

  @override
  Future<DiscourseInstance> lookup(String term) async {
    lookups.add(term);
    final result = results[term];
    if (result != null) return result;
    throw SiteLookupException(failure ?? SiteLookupFailure.unreachable, term);
  }

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async =>
      user ?? const DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    topicTrackingRequests.add(siteUrl);
    final gate = trackingStateGate;
    if (gate != null) await gate.future;
    return trackingState ?? TopicTrackingState();
  }

  @override
  Future<UserPreferences> loadUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    userPreferenceLoads.add((
      siteUrl: siteUrl,
      username: username,
      clientId: clientId,
    ));
    final gate = userPreferencesGate;
    if (gate != null) await gate.future;
    return userPreferences ??
        UserPreferences(
          username: username,
          canEdit: true,
          canChangeTrackingPreferences: true,
        );
  }

  @override
  Future<UserPreferences> updateUserPreferences({
    required String siteUrl,
    required String apiKey,
    required String username,
    required UserPreferences fallback,
    required Map<String, Object?> values,
    String? clientId,
  }) async {
    userPreferenceUpdates.add((
      siteUrl: siteUrl,
      username: username,
      clientId: clientId,
      values: Map.unmodifiable(values),
    ));
    final gate = userPreferencesWriteGate;
    if (gate != null) await gate.future;
    final failure = writeFailure;
    if (failure != null) throw failure;
    final updated = UserPreferences.fromJson({
      'user_option': values,
    }, fallback: fallback);
    userPreferences = updated;
    return updated;
  }

  @override
  Future<List<SidebarSection>> customSidebarSections({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => customSidebarSectionsBySite[siteUrl] ?? const [];

  @override
  Future<NotificationTotals> notificationTotals({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    totalsCalls++;
    final result = totals;
    if (result == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return result;
  }

  @override
  Future<List<DiscourseNotification>> notifications({
    required String siteUrl,
    required String apiKey,
    int limit = 30,
    List<NotificationTypeName> filterByTypes = const [],
    String? clientId,
  }) async {
    notificationFilters.add(List.unmodifiable(filterByTypes));
    final replies = _sameKinds(filterByTypes, userMenuReplyNotificationTypes);
    final chat = _sameKinds(filterByTypes, chatNotificationFeed.filterByTypes);
    if (replies) {
      replyNotificationCalls++;
    } else if (chat) {
      chatNotificationCalls++;
    } else if (filterByTypes.isEmpty) {
      notificationCalls++;
    }
    final result = replies
        ? replyNotificationList
        : chat
        ? chatNotificationList
        : filterByTypes.isEmpty
        ? notificationList
        : null;
    if (result == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return result;
  }

  static bool _sameKinds(
    List<NotificationTypeName> actual,
    List<NotificationTypeName> expected,
  ) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  @override
  Future<BookmarkPayload> bookmarks({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    bookmarksRequested.add(username);
    final result = bookmarkList;
    if (result == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return (reminders: reminderList, bookmarks: result);
  }

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
  }) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    createdBookmarks.add((
      targetType: targetType,
      targetId: targetId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    ));
    return _nextBookmarkId++;
  }

  @override
  Future<void> updateBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
    String? clientId,
  }) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    updatedBookmarks.add((
      bookmarkId: bookmarkId,
      name: name,
      reminderAt: reminderAt,
      autoDeletePreference: autoDeletePreference,
    ));
  }

  @override
  Future<bool?> deleteBookmark({
    required String siteUrl,
    required String apiKey,
    required int bookmarkId,
    required BookmarkTargetType targetType,
    String? clientId,
  }) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
    deletedBookmarks.add(bookmarkId);
    return true;
  }

  @override
  Future<void> deleteTopicBookmarks({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> markNotificationRead({
    required String siteUrl,
    required String apiKey,
    required int id,
    String? clientId,
  }) async {
    markedRead.add(id);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> markNotificationsRead({
    required String siteUrl,
    required String apiKey,
    required List<NotificationTypeName> types,
    String? clientId,
  }) async {
    markedTypesRead.add(List.unmodifiable(types));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> revokeApiKey({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    revoked.add(siteUrl);
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    feedPaths.add(path);
    if (gate != null) await gate!.future;
    await feedGates[path]?.future;
    final topics = feeds[path];
    if (topics == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return TopicList(
      topics: topics,
      categories: feedCategoriesByPath[path] ?? const [],
      moreTopicsUrl: nextPages[path],
      canCreateTopic: creatableFeedPaths.contains(path),
      filterOptions: filterOptionsByPath[path] ?? const [],
    );
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
  }) async {
    topicsOpened.add(id);
    topicPostNumbersOpened.add(postNumber);
    if (summary) topicSummariesOpened.add(id);
    if (topicGate != null) await topicGate!.future;
    final detail = (summary ? summaryTopics[id] : null) ?? topics[id];
    if (detail == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return detail;
  }

  @override
  Future<void> recordTopicRead({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postNumber,
    int milliseconds = 500,
    String? clientId,
  }) async {
    topicReadsRecorded.add((topicId: topicId, postNumber: postNumber));
  }

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    topicNotificationLevelsUpdated.add((
      topicId: topicId,
      notificationLevel: notificationLevel,
    ));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> updateTopicPinForUser({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required bool pinned,
    String? clientId,
  }) async {
    topicPinPreferencesUpdated.add((topicId: topicId, pinned: pinned));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> setUserStatus({
    required String siteUrl,
    required String apiKey,
    required String description,
    required String emoji,
    DateTime? endsAt,
    String? clientId,
  }) async {
    userStatusesSet.add((
      description: description,
      emoji: emoji,
      endsAt: endsAt,
    ));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> clearUserStatus({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    userStatusesCleared.add(siteUrl);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<DateTime> enterDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    required DoNotDisturbDuration duration,
    String? clientId,
  }) async {
    doNotDisturbDurations.add(duration);
    final configured = doNotDisturbUntil;
    if (configured != null) return configured;
    throw StateError(
      'FakeDiscourseApi.enterDoNotDisturb requires doNotDisturbUntil.',
    );
  }

  @override
  Future<void> leaveDoNotDisturb({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    doNotDisturbResumes.add(siteUrl);
  }

  @override
  Future<void> updateHidePresence({
    required String siteUrl,
    required String apiKey,
    required String username,
    required bool hidePresence,
    String? clientId,
  }) async {
    presencePreferencesUpdated.add((
      siteUrl: siteUrl,
      username: username,
      hidePresence: hidePresence,
    ));
    await presenceGate?.future;
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> updateTopicStatus({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicStatusProperty status,
    required bool enabled,
    String? clientId,
  }) async {
    topicStatusesUpdated.add((
      topicId: topicId,
      status: status,
      enabled: enabled,
    ));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> deleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    topicsDeleted.add(topicId);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> permanentlyDeleteTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    topicsPermanentlyDeleted.add(topicId);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> recoverTopic({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    String? clientId,
  }) async {
    topicsRecovered.add(topicId);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) async {
    postFetches.add(ids);
    if (postGate != null) await postGate!.future;
    return ids.map((i) => postsById[i]).whereType<Post>().toList();
  }

  @override
  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    postFetches.add(ids);
    if (postGate != null) await postGate!.future;
    return (
      posts: ids.map((i) => postsById[i]).whereType<Post>().toList(),
      recommendations: postRecommendations[topicId],
    );
  }

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    cardsRequested.add(username);
    final card = cards[username];
    if (card == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return card;
  }

  @override
  Future<List<TopicCategory>> categories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    categoryRequests.add(siteUrl);
    categoryPagesRequested.add(page);
    return categoryPages[page] ?? (page == 1 ? categoryList : const []);
  }

  @override
  Future<CategoryLoadResult> loadCategories({
    required String siteUrl,
    String? apiKey,
    String? clientId,
    int page = 1,
  }) async {
    categoryRequests.add(siteUrl);
    categoryPagesRequested.add(page);
    final categories =
        categoryPages[page] ?? (page == 1 ? categoryList : const []);
    return CategoryLoadResult(
      categories,
      complete: categoryLoadComplete,
      canCreateTopic: false,
      postActionCatalog: categoryPostActionCatalog,
      siteTopTags: categorySiteTopTags,
      anonymousDefaultTags: categoryAnonymousDefaultTags,
    );
  }

  @override
  Future<List<SidebarTag>> tags({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    tagRequests.add(siteUrl);
    return tagList;
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) async {
    final requested = ids.toSet();
    categoryIdsRequested.add(List.unmodifiable(requested));
    return const [];
  }

  @override
  Future<List<TopicCategory>> searchCategories({
    required String siteUrl,
    required String term,
    required String apiKey,
    bool includeUncategorized = true,
    String? clientId,
  }) async {
    categorySearchTerms.add(term);
    return categorySearches[term] ?? const [];
  }

  @override
  Future<TopicComposerCapabilities> topicComposerCapabilities({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    topicComposerCapabilityRequests.add(siteUrl);
    return composerCapabilities;
  }

  @override
  Future<TopicTagSearch> searchTopicTags({
    required String siteUrl,
    required String apiKey,
    required String term,
    int? categoryId,
    Iterable<int> selectedTagIds = const [],
    int limit = SiteConfig.defaultMaxTagSearchResults,
    String? clientId,
  }) async {
    topicTagSearchLimits.add(limit);
    return topicTagSearches[term] ?? const TopicTagSearch();
  }

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    siteConfigsRequested.add(siteUrl);
    await siteConfigGate?.future;
    final config = siteConfigs[siteUrl];
    if (config == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return config;
  }

  @override
  Future<List<GifCategory>> gifCategories({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    gifCategoryRequests.add(siteUrl);
    if (gifFailure case final failure?) {
      throw SiteLookupException(failure, siteUrl);
    }
    return gifCategoriesBySite[siteUrl] ?? const [];
  }

  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async {
    gifSearchRequests.add((
      siteUrl: siteUrl,
      query: query,
      fileDetail: fileDetail,
      position: position,
    ));
    if (gifFailure case final failure?) {
      throw SiteLookupException(failure, siteUrl);
    }
    return gifSearchPages[gifSearchKey(query, position: position)] ??
        const GifSearchPage.empty();
  }

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
  }) async {
    searchesRequested.add((
      siteUrl: siteUrl,
      term: term,
      typeFilter: typeFilter,
      topicId: topicId,
    ));
    return searchResults[term] ?? const SearchResults();
  }

  @override
  Future<FoundUsersAndGroups> searchUsersAndGroups({
    required String siteUrl,
    required String term,
    int limit = 6,
    String? apiKey,
    String? clientId,
  }) async {
    userSearchesRequested.add((term: term, topicId: null));
    return FoundUsersAndGroups(
      users: (userSearches[term] ?? const []).take(limit).toList(),
    );
  }

  @override
  Future<List<String>> recentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => const [];

  @override
  Future<void> resetRecentSearches({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {}

  @override
  Future<void> logSearchClick({
    required String siteUrl,
    required String apiKey,
    required int searchLogId,
    required Object resultId,
    required SearchResultKind resultKind,
    String? clientId,
  }) async {
    searchClicks.add((
      searchLogId: searchLogId,
      resultId: resultId,
      resultKind: resultKind,
    ));
  }

  @override
  Future<SiteAppearance?> siteAppearance({
    required String siteUrl,
    String? username,
    String? apiKey,
    String? clientId,
  }) async {
    appearancesRequested.add(siteUrl);
    await appearanceGate?.future;
    return siteAppearances[siteUrl];
  }

  @override
  Future<List<FoundUser>> searchUsers({
    required String siteUrl,
    required String term,
    int? topicId,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    userSearchesRequested.add((term: term, topicId: topicId));
    return userSearches[term] ?? const [];
  }

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTags({
    required String siteUrl,
    required String term,
    int limit = 5,
    String? apiKey,
    String? clientId,
  }) async {
    return filterTagSearches[term] ?? const [];
  }

  @override
  Future<List<TopicFilterLookupValue>> searchFilterTagGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    return const [];
  }

  @override
  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    return const [];
  }

  @override
  Future<List<FoundHashtag>> searchHashtags({
    required String siteUrl,
    required String term,
    List<String> order = DiscourseApi.hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async {
    hashtagSearchesRequested.add(term);
    hashtagSearchOrdersRequested.add(List.of(order, growable: false));
    await hashtagSearchGate?.future;
    return hashtagSearches[term] ?? const [];
  }

  @override
  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    List<String> order = DiscourseApi.hashtagOrder,
    String? apiKey,
    String? clientId,
  }) async {
    final asked = refs.toSet();
    hashtagLookupsRequested.add(asked);
    hashtagLookupOrdersRequested.add(List.of(order, growable: false));
    return const [];
  }

  @override
  Future<Set<String>> checkMentions({
    required String siteUrl,
    required Iterable<String> names,
    int? topicId,
    String? apiKey,
    String? clientId,
  }) async {
    final asked = names.toSet();
    mentionChecksRequested.add(asked);
    return asked.intersection(realUsernames);
  }

  @override
  Future<SiteEmojiCatalog> emojiCatalog({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    emojisRequested.add(siteUrl);
    final catalog = emojiCatalogsBySite[siteUrl];
    if (catalog != null) return catalog;
    final flat = emojisBySite[siteUrl];
    if (flat == null) return SiteEmojiCatalog.empty;
    return SiteEmojiCatalog(
      groups: [SiteEmojiGroup(id: 'default', emojis: flat)],
    );
  }

  @override
  Future<Map<String, List<String>>> emojiSearchAliases({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    return const {};
  }

  @override
  Future<Map<String, String>> customEmojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    customEmojisRequired.add(siteUrl);
    if (customEmojiGate != null) await customEmojiGate!.future;
    return customEmojisBySite[siteUrl] ?? const {};
  }

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
  }) async {
    created.add({
      'siteUrl': siteUrl,
      'topicId': topicId,
      'raw': raw,
      'replyToPostNumber': replyToPostNumber,
      'whisper': whisper,
      'typingDurationMsecs': typingDuration.inMilliseconds,
      'composerOpenDurationMsecs': composerOpenDuration.inMilliseconds,
      'draftKey': draftKey,
    });

    final failure = writeFailure;
    if (failure != null) throw failure;

    return creation ??
        PostCreation(
          outcome: PostOutcome.created,
          post: Post(
            id: 9001,
            postNumber: 2,
            username: 'joffreyj',
            cooked: '<p>$raw</p>',
          ),
          draftSequence: 1,
        );
  }

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
  }) async {
    topicsCreated.add({
      'siteUrl': siteUrl,
      'title': title,
      'raw': raw,
      'categoryId': categoryId,
      'tags': tags.toList(),
      'targetRecipients': targetRecipients,
      'draftKey': draftKey,
    });
    final failure = writeFailure;
    if (failure != null) throw failure;
    return creation ??
        PostCreation(
          outcome: PostOutcome.created,
          post: Post(
            id: 9001,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>$raw</p>',
          ),
          topicId: 901,
          topicSlug: 'created-topic',
          topicTitle: title,
          draftSequence: 1,
        );
  }

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
  }) async {
    topicsUpdated.add({
      'topicId': topicId,
      'title': title,
      'originalTitle': originalTitle,
      'categoryId': categoryId,
      'tags': tags.toList(),
      'originalTags': originalTags.toList(),
    });
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> updateTopicTags({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required Iterable<TopicTag> tags,
    String? clientId,
  }) async {
    topicTagsUpdated.add({'topicId': topicId, 'tags': tags.toList()});
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? originalText,
    String? editReason,
    String? clientId,
  }) async {
    updated.add({
      'siteUrl': siteUrl,
      'postId': postId,
      'raw': raw,
      'originalText': originalText,
    });

    final failure = writeFailure;
    if (failure != null) throw failure;

    final existing = postsById[postId];
    return Post(
      id: postId,
      postNumber: existing?.postNumber ?? 1,
      username: existing?.username ?? 'joffreyj',
      cooked: '<p>$raw</p>',
      canEdit: true,
    );
  }

  @override
  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    deleted.add(postId);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<({bool allowed, String? reason})> checkPermanentPostDeletion({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    permanentDeletionChecks.add(postId);
    return (allowed: permanentDeletionAllowed, reason: permanentDeletionReason);
  }

  @override
  Future<void> permanentlyDeletePost({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postId,
    String? clientId,
  }) async {
    postsPermanentlyDeleted.add((topicId: topicId, postId: postId));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> deletePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    bulkDeleted.add(List.unmodifiable(postIds));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> mergePosts({
    required String siteUrl,
    required String apiKey,
    required List<int> postIds,
    String? clientId,
  }) async {
    merged.add(List.unmodifiable(postIds));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

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
  }) async {
    movedTopicPosts.add((
      topicId: topicId,
      postIds: List.unmodifiable(postIds),
      destinationTopicId: destinationTopicId,
      title: title,
      categoryId: categoryId,
      tagIds: List.unmodifiable(tagIds),
      chronologicalOrder: chronologicalOrder,
    ));
    final failure = writeFailure;
    if (failure != null) throw failure;
    return topicMoveUrl;
  }

  @override
  Future<void> changePostOwners({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required List<int> postIds,
    required String username,
    String? clientId,
  }) async {
    postOwnersChanged.add((
      topicId: topicId,
      postIds: List.unmodifiable(postIds),
      username: username,
    ));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  final List<({int postId, bool wiki})> postWikiUpdates = [];
  final List<({int postId, bool locked})> postLockUpdates = [];
  final List<int> postsUnhidden = [];
  final List<({int postId, int postType})> postTypeUpdates = [];
  final List<({int postId, String? notice})> postNoticeUpdates = [];

  @override
  Future<void> updatePostWiki({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool wiki,
    String? clientId,
  }) async {
    postWikiUpdates.add((postId: postId, wiki: wiki));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> updatePostLocked({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required bool locked,
    String? clientId,
  }) async {
    postLockUpdates.add((postId: postId, locked: locked));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> unhidePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    postsUnhidden.add(postId);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> updatePostType({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postType,
    String? clientId,
  }) async {
    postTypeUpdates.add((postId: postId, postType: postType));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> updatePostNotice({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? notice,
    String? clientId,
  }) async {
    postNoticeUpdates.add((postId: postId, notice: notice));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> recoverPost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    recovered.add(postId);
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    liked.add(postId);
    if (likeGate != null) await likeGate!.future;
    final failure = likeFailure ?? writeFailure;
    if (failure != null) throw failure;
    return likeResponses[postId];
  }

  @override
  Future<Post> createPostFlag({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    flagsCreated.add((
      postId: postId,
      postActionTypeId: postActionTypeId,
      message: message,
    ));
    await flagGate?.future;
    final failure = flagFailure ?? writeFailure;
    if (failure != null) throw failure;
    final response = flagResponses[postId];
    if (response == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return response;
  }

  @override
  Future<void> createTopicFlag({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required int postActionTypeId,
    String? message,
    String? clientId,
  }) async {
    topicFlagsCreated.add((
      topicId: topicId,
      postActionTypeId: postActionTypeId,
      message: message,
    ));
    final failure = writeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<Post?> unlikePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    unliked.add(postId);
    if (likeGate != null) await likeGate!.future;
    final failure = likeFailure ?? writeFailure;
    if (failure != null) throw failure;
    return likeResponses[postId];
  }

  @override
  Future<PostLikers> postLikers({
    required String siteUrl,
    required int postId,
    int limit = 25,
    String? apiKey,
    String? clientId,
  }) async {
    likersRequested.add(postId);
    if (likerGate != null) await likerGate!.future;
    final found = likersById[postId];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return PostLikers(postId: postId, likers: found);
  }

  @override
  Future<PostRevision> postRevision({
    required String siteUrl,
    required int postId,
    int? revision,
    String? apiKey,
    String? clientId,
  }) async {
    postRevisionsRequested.add((postId: postId, revision: revision));
    final found = postRevisions[postId];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<Post?> toggleReaction({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String reaction,
    String? clientId,
  }) async {
    reacted.add((postId: postId, reaction: reaction));
    if (reactionGate != null) await reactionGate!.future;
    if (reactionFailure != null) throw reactionFailure!;
    return reactionResponses[postId];
  }

  @override
  Future<PollVoteResponse> votePoll({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    required List<String> options,
    String? clientId,
  }) async {
    pollVotes.add((
      postId: postId,
      pollName: pollName,
      options: List.unmodifiable(options),
    ));
    if (pollVoteGate != null) await pollVoteGate!.future;
    if (pollVoteFailure != null) throw pollVoteFailure!;
    final response = pollVoteResponses[pollVoteKey(postId, pollName)];
    if (response == null) {
      throw StateError('No fake poll vote response for $postId/$pollName');
    }
    return response;
  }

  @override
  Future<PollVoteResponse> removePollVote({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String pollName,
    String? clientId,
  }) async {
    pollVotesRemoved.add((postId: postId, pollName: pollName));
    if (pollVoteGate != null) await pollVoteGate!.future;
    if (pollVoteFailure != null) throw pollVoteFailure!;
    final response = pollRemovalResponses[pollVoteKey(postId, pollName)];
    if (response == null) {
      throw StateError('No fake poll removal response for $postId/$pollName');
    }
    return response;
  }

  @override
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  }) async {
    reactorsRequested.add((postId: postId, filter: reaction));
    if (reactorGate != null) await reactorGate!.future;
    final found = reactorsById[PostReactors.key(postId, reaction)];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatChannel> createChatDirectMessageChannel({
    required String siteUrl,
    required String apiKey,
    required List<String> usernames,
    List<String> groups = const [],
    String? name,
    bool upsert = false,
    String? clientId,
  }) async {
    directMessageChannelRequests.add((
      usernames: List.unmodifiable(usernames),
      groups: List.unmodifiable(groups),
      name: name,
      upsert: upsert,
    ));
    final oneToOne =
        upsert &&
        usernames.length == 1 &&
        groups.isEmpty &&
        (name == null || name.isEmpty);
    if (oneToOne) directMessageChannelsRequested.add(usernames.single);
    final found = oneToOne
        ? directMessageChannelsByUsername[usernames.single]
        : directMessageGroupChannel;
    if (found == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return found;
  }

  @override
  Future<ChatDirectMessageSearchResults> searchChatDirectMessages({
    required String siteUrl,
    required String apiKey,
    required String term,
    bool includeGroups = false,
    bool includeDirectMessageChannels = true,
    String? clientId,
  }) async {
    chatDirectMessageSearchesRequested.add(term);
    chatDirectMessageSearchRequests.add((
      term: term,
      includeGroups: includeGroups,
      includeDirectMessageChannels: includeDirectMessageChannels,
    ));
    return chatDirectMessageSearches[term] ??
        ChatDirectMessageSearchResults(const []);
  }

  @override
  Future<ChatChannels> chatChannels({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    chatChannelsRequested.add(siteUrl);
    if (chatChannelGate != null) await chatChannelGate!.future;
    final found = chatChannelsBySite[siteUrl];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatChannel> chatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    chatChannelDetailsRequested.add(channelId);
    if (chatChannelGate != null) await chatChannelGate!.future;
    final found = chatChannelsById[channelId];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatChannel> updateChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? name,
    String? slug,
    String? description,
    bool? threadingEnabled,
    String? clientId,
  }) async {
    chatChannelMetadataUpdates.add((
      channelId: channelId,
      name: name,
      slug: slug,
      description: description,
    ));
    if (threadingEnabled case final enabled?) {
      chatChannelThreadingUpdates.add((channelId: channelId, enabled: enabled));
    }
    if (chatChannelUpdateGate case final gate?) await gate.future;
    if (chatChannelUpdateFailure case final failure?) throw failure;
    final failure = writeFailure;
    if (failure != null) throw failure;
    final response = chatChannelUpdateResponse ?? chatChannelsById[channelId];
    if (response == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return response;
  }

  @override
  Future<ChatChannel> updateChatChannelStatus({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required ChatChannelStatus status,
    String? clientId,
  }) async {
    chatChannelStatusesUpdated.add((channelId: channelId, status: status));
    if (chatChannelStatusGate case final gate?) await gate.future;
    if (chatChannelStatusFailure case final failure?) throw failure;
    final response = chatChannelStatusResponse ?? chatChannelsById[channelId];
    if (response == null) {
      throw SiteLookupException(SiteLookupFailure.notDiscourse, siteUrl);
    }
    return response;
  }

  @override
  Future<void> updateChatChannelStarred({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required bool starred,
    String? clientId,
  }) async {
    chatChannelStarsUpdated.add((channelId: channelId, starred: starred));
    await chatChannelStarGate?.future;
    final failure = chatChannelStarFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<ChatMembership> updateChatChannelNotifications({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    bool? muted,
    ChatChannelNotificationLevel? notificationLevel,
    String? clientId,
  }) async {
    chatChannelNotificationsUpdated.add((
      channelId: channelId,
      muted: muted,
      notificationLevel: notificationLevel,
    ));
    await chatChannelNotificationGate?.future;
    final failure = chatChannelNotificationFailure;
    if (failure != null) throw failure;
    return chatChannelNotificationMembership.withNotifications(
      muted: muted,
      notificationLevel: notificationLevel,
    );
  }

  @override
  Future<ChatChannelMembersPage> chatChannelMembers({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String username = '',
    int offset = 0,
    int limit = 20,
    String? clientId,
  }) async {
    chatChannelMembersRequested.add((
      channelId: channelId,
      username: username,
      offset: offset,
      limit: limit,
    ));
    await chatChannelMemberGate?.future;
    final found =
        chatChannelMemberPagesByKey[chatChannelMembersKey(
          channelId,
          username: username,
          offset: offset,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    chatBrowseRequested.add((
      filter: filter,
      status: status,
      offset: offset,
      limit: limit,
    ));
    await chatBrowseGate?.future;
    final found =
        chatBrowsePagesByKey[chatBrowseKey(
          filter: filter,
          status: status,
          offset: offset,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatMembership> followChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _updateChatChannelFollowing(channelId, true);

  @override
  Future<ChatMembership> unfollowChatChannel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) => _updateChatChannelFollowing(channelId, false);

  Future<ChatMembership> _updateChatChannelFollowing(
    int channelId,
    bool following,
  ) async {
    chatChannelFollowsUpdated.add((channelId: channelId, following: following));
    await chatChannelFollowGate?.future;
    final failure = chatChannelFollowFailure;
    if (failure != null) throw failure;
    return following
        ? chatChannelFollowMembership
        : chatChannelUnfollowMembership;
  }

  @override
  Future<ChatSearchPage> searchChatMessages({
    required String siteUrl,
    required String apiKey,
    required String query,
    int? channelId,
    ChatSearchSort sort = ChatSearchSort.relevance,
    int offset = 0,
    int limit = ChatSearchPage.defaultPageSize,
    bool excludeThreads = false,
    String? clientId,
  }) async {
    chatSearchesRequested.add((
      query: query,
      channelId: channelId,
      sort: sort,
      offset: offset,
      limit: limit,
      excludeThreads: excludeThreads,
    ));
    if (chatSearchGate != null) await chatSearchGate!.future;
    final found =
        chatSearchPagesByKey[chatSearchKey(
          query,
          channelId: channelId,
          sort: sort,
          offset: offset,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    int? targetMessageId,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    chatMessagesRequested.add((
      channelId: channelId,
      before: before,
      after: after,
      targetMessageId: targetMessageId,
      fromLastRead: fromLastRead,
      pageSize: pageSize,
    ));
    if (chatMessageGate != null) await chatMessageGate!.future;
    final asksForLatest =
        !fromLastRead &&
        before == null &&
        after == null &&
        targetMessageId == null;
    final found =
        (asksForLatest
            ? chatMessagesByKey[chatMessagesLatestKey(channelId)]
            : null) ??
        chatMessagesByKey[chatMessagesKey(
          channelId,
          before: before,
          after: after,
          targetMessageId: targetMessageId,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<void> markChatChannelRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatReadsMarked.add((channelId: channelId, messageId: messageId));
    if (chatReadFailure != null) throw chatReadFailure!;
  }

  @override
  Future<ChatMessagePage> chatThreadMessages({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? before,
    int? after,
    int? targetMessageId,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    final base = 'thread-$channelId-$threadId';
    chatThreadMessagesRequested.add((
      channelId: channelId,
      threadId: threadId,
      before: before,
      after: after,
      targetMessageId: targetMessageId,
      pageSize: pageSize,
    ));
    final directional = before != null
        ? '$base~past~$before'
        : after != null
        ? '$base~future~$after'
        : targetMessageId != null
        ? '$base~target~$targetMessageId'
        : base;
    final found = chatMessagesByKey[directional] ?? chatMessagesByKey[base];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatThread> chatThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    String? apiKey,
    String? clientId,
  }) async {
    chatThreadsRequested.add((channelId: channelId, threadId: threadId));
    final found = chatThreadsByKey[chatThreadKey(channelId, threadId)];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatThreadPage> chatThreads({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async {
    chatThreadPagesRequested.add((offset: offset, limit: limit));
    final found = chatThreadPagesByOffset[offset];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatThreadPage> chatChannelThreads({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    int offset = 0,
    int limit = ChatThreadPage.pageSize,
    String? clientId,
  }) async {
    chatChannelThreadPagesRequested.add((
      channelId: channelId,
      offset: offset,
      limit: limit,
    ));
    final found =
        chatChannelThreadPagesByKey[chatChannelThreadPageKey(
          channelId,
          offset,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<ChatThread> createChatThread({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int originalMessageId,
    String? title,
    String? clientId,
  }) async {
    chatThreadsCreated.add((
      channelId: channelId,
      originalMessageId: originalMessageId,
      title: title,
    ));
    final found =
        createdChatThreadsByKey[createdChatThreadKey(
          channelId,
          originalMessageId,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<void> updateChatThreadTitle({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required String title,
    String? clientId,
  }) async {
    chatThreadTitlesUpdated.add((
      channelId: channelId,
      threadId: threadId,
      title: title,
    ));
  }

  @override
  Future<ChatThreadMembership> updateChatThreadNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required ChatThreadNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    chatThreadNotificationLevelsUpdated.add((
      channelId: channelId,
      threadId: threadId,
      notificationLevel: notificationLevel,
    ));
    return ChatThreadMembership(
      threadId: threadId,
      notificationLevel: notificationLevel,
    );
  }

  @override
  Future<int?> sendChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required String message,
    List<int> uploadIds = const [],
    int? threadId,
    String? stagedId,
    DateTime? clientCreatedAt,
    int? contextTopicId,
    List<int> contextPostIds = const [],
    String? clientId,
  }) async {
    chatMessagesSent.add((
      siteUrl: siteUrl,
      channelId: channelId,
      message: message,
      uploadIds: List.unmodifiable(uploadIds),
      threadId: threadId,
      stagedId: stagedId,
      clientCreatedAt: clientCreatedAt,
      contextTopicId: contextTopicId,
      contextPostIds: List.unmodifiable(contextPostIds),
    ));
    if (chatSendGate != null) await chatSendGate!.future;
    if (chatSendFailure != null) throw chatSendFailure!;
    return chatSentMessageId;
  }

  @override
  Future<void> editChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String message,
    List<int> uploadIds = const [],
    String? clientId,
  }) async {
    chatMessagesEdited.add((
      siteUrl: siteUrl,
      channelId: channelId,
      messageId: messageId,
      message: message,
      uploadIds: List.unmodifiable(uploadIds),
    ));
    await chatEditGate?.future;
    final failure = chatEditFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> deleteChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatMessagesDeleted.add((channelId: channelId, messageId: messageId));
    await chatMessageMutationGate?.future;
    final failure = chatMessageMutationFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> deleteChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  }) async {
    chatMessageBatchesDeleted.add((
      channelId: channelId,
      messageIds: List.unmodifiable(messageIds),
    ));
    await chatMessageMutationGate?.future;
    final failure = chatMessageMutationFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<ChatMessageMove> moveChatMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int destinationChannelId,
    required List<int> messageIds,
    String? clientId,
  }) async {
    chatMessageMoves.add((
      channelId: channelId,
      destinationChannelId: destinationChannelId,
      messageIds: List.unmodifiable(messageIds),
    ));
    return (
      destinationChannelId: destinationChannelId,
      firstMovedMessageId: chatMoveFirstMessageId,
    );
  }

  @override
  Future<void> restoreChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatMessagesRestored.add((channelId: channelId, messageId: messageId));
    await chatMessageMutationGate?.future;
    final failure = chatMessageMutationFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> rebakeChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? clientId,
  }) async {
    chatMessagesRebaked.add((channelId: channelId, messageId: messageId));
    await chatRebakeGate?.future;
    final failure = chatRebakeFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<String> generateChatQuote({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required List<int> messageIds,
    String? clientId,
  }) async {
    chatQuotesGenerated.add((
      channelId: channelId,
      messageIds: List.unmodifiable(messageIds),
    ));
    await chatQuoteGate?.future;
    final failure = chatQuoteFailure;
    if (failure != null) throw failure;
    return chatQuoteMarkdown;
  }

  @override
  Future<void> updateChatMessagePinned({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required bool pinned,
    String? clientId,
  }) async {
    chatMessagePinsUpdated.add((
      channelId: channelId,
      messageId: messageId,
      pinned: pinned,
    ));
    await chatPinGate?.future;
    final failure = chatPinFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<ChatPins> chatPinnedMessages({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    return chatPinsByChannel[channelId] ??
        (pins: const <ChatPin>[], membership: null);
  }

  @override
  Future<void> markChatPinsRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    String? clientId,
  }) async {
    chatPinsRead.add(channelId);
  }

  @override
  Future<void> flagChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required int flagTypeId,
    String? message,
    String? clientId,
  }) async {
    chatMessagesFlagged.add((
      channelId: channelId,
      messageId: messageId,
      flagTypeId: flagTypeId,
      message: message,
    ));
    await chatFlagGate?.future;
    final failure = chatFlagFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> setChatMessageReaction({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    required String emoji,
    required ChatReactionAction action,
    String? clientId,
  }) async {
    chatReactionsSet.add((
      siteUrl: siteUrl,
      channelId: channelId,
      messageId: messageId,
      emoji: emoji,
      action: action,
    ));
    if (chatReactionGate != null) await chatReactionGate!.future;
    if (chatReactionFailure != null) throw chatReactionFailure!;
  }

  @override
  Future<ChatMessageReactors> chatMessageReactors({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int messageId,
    String? reaction,
    int limit = ChatMessageReactors.maximumPageSize,
    String? clientId,
  }) async {
    chatReactorsRequested.add((
      channelId: channelId,
      messageId: messageId,
      filter: reaction,
    ));
    if (chatReactorGate != null) await chatReactorGate!.future;
    final found =
        chatReactorsById[ChatMessageReactors.key(
          channelId,
          messageId,
          reaction,
        )];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<void> markChatThreadRead({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required int threadId,
    required int messageId,
    String? clientId,
  }) async {}

  @override
  Future<Map<String, dynamic>> pluginGetJson({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    final uri = Uri.parse(path);
    if (uri.path == '/gifs/categories.json') {
      final categories = await gifCategories(
        siteUrl: siteUrl,
        apiKey: apiKey!,
        clientId: clientId,
      );
      return {
        'tags': [
          for (final category in categories)
            {
              'name': category.title,
              'image': category.imageUrl,
              'searchterm': category.searchTerm,
            },
        ],
      };
    }
    if (uri.path == '/gifs/search.json') {
      final page = await searchGifs(
        siteUrl: siteUrl,
        apiKey: apiKey!,
        query: uri.queryParameters['q'] ?? '',
        fileDetail:
            siteConfigs[siteUrl]?.gifFileDetail ??
            GifsSettings.defaultFileDetail,
        position: uri.queryParameters['pos'] ?? '0',
        clientId: clientId,
      );
      return _gifPageJson(page);
    }
    final reactorsRoute = RegExp(
      r'^/discourse-reactions/posts/(\d+)/reactions-users-list\.json$',
    ).firstMatch(uri.path);
    if (reactorsRoute != null) {
      final page = await postReactors(
        siteUrl: siteUrl,
        postId: int.parse(reactorsRoute.group(1)!),
        reaction: uri.queryParameters['reaction_value'],
        limit: int.tryParse(uri.queryParameters['limit'] ?? '') ?? 30,
        apiKey: apiKey,
        clientId: clientId,
      );
      return {
        'users': [
          for (final reactor in page.reactors)
            {
              'id': reactor.id,
              'username': reactor.username,
              'name': reactor.name,
              'avatar_template': reactor.avatarUrl,
              'reaction': reactor.reaction,
            },
        ],
        'total_rows': page.total,
      };
    }
    pluginReadPaths.add(path);
    final response = pluginResponses['GET $path'];
    if (response == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return response;
  }

  @override
  Future<List<Map<String, dynamic>>> pluginGetJsonList({
    required String siteUrl,
    required String path,
    required String? apiKey,
    String? clientId,
  }) async {
    pluginReadPaths.add(path);
    throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
  }

  @override
  Future<Map<String, dynamic>> pluginWriteJson({
    required String siteUrl,
    required String path,
    required String method,
    required String apiKey,
    required Map<String, Object?> body,
    String? clientId,
  }) async {
    if (path == '/polls/vote.json') {
      final postId = body['post_id']! as int;
      final pollName = body['poll_name']! as String;
      final response = method == 'DELETE'
          ? await removePollVote(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: postId,
              pollName: pollName,
              clientId: clientId,
            )
          : await votePoll(
              siteUrl: siteUrl,
              apiKey: apiKey,
              postId: postId,
              pollName: pollName,
              options: (body['options']! as List).cast<String>(),
              clientId: clientId,
            );
      return _pollVoteJson(response, includeVote: method != 'DELETE');
    }
    final reactionRoute = RegExp(
      r'^/discourse-reactions/posts/(\d+)/custom-reactions/([^/]+)/toggle\.json$',
    ).firstMatch(path);
    if (reactionRoute != null) {
      final response = await toggleReaction(
        siteUrl: siteUrl,
        apiKey: apiKey,
        postId: int.parse(reactionRoute.group(1)!),
        reaction: Uri.decodeComponent(reactionRoute.group(2)!),
        clientId: clientId,
      );
      return response == null ? const {} : _reactionPostJson(response);
    }
    pluginWrites.add((
      siteUrl: siteUrl,
      method: method,
      path: path,
      body: body,
    ));
    final failure = pluginWriteFailures.remove('$method $path');
    if (failure != null) throw failure;
    final response = pluginResponses['$method $path'];
    if (response == null) {
      throw const WriteException(WriteFailure.unreachable);
    }
    return response;
  }

  @override
  Future<int?> saveDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    required String data,
    String? owner,
    String? clientId,
  }) async {
    draftsSaved.add({
      'siteUrl': siteUrl,
      'apiKey': apiKey,
      'draftKey': draftKey,
      'sequence': sequence,
      'data': data,
    });
    if (draftGate != null) await draftGate!.future;
    if (draftFailure != null) throw draftFailure!;
    return sequence + 1;
  }

  @override
  Future<({ComposerDraft? draft, int sequence})> draft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    String? clientId,
  }) async {
    await draftRestoreGate?.future;
    if (draftRestoreFailure != null) throw draftRestoreFailure!;
    return draftToRestore;
  }

  @override
  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    userDraftRequests.add((siteUrl: siteUrl, offset: offset, limit: limit));
    await userDraftGate?.future;
    return userDraftList.skip(offset).take(limit).toList(growable: false);
  }

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    userActivityRequests.add((
      siteUrl: siteUrl,
      username: username,
      offset: offset,
      limit: limit,
    ));
    await userActivityGate?.future;
    final items = userActivityItems
        .skip(offset)
        .take(limit)
        .toList(growable: false);
    return UserActivityPage(
      items: items,
      categories: userActivityCategories,
      rawItemCount: items.length,
    );
  }

  @override
  Future<void> deleteUserDraft({
    required String siteUrl,
    required String apiKey,
    required String draftKey,
    required int sequence,
    String? clientId,
  }) async {
    userDraftsDeleted.add((
      siteUrl: siteUrl,
      draftKey: draftKey,
      sequence: sequence,
    ));
    await draftDeleteGate?.future;
    if (draftDeleteFailure != null) throw draftDeleteFailure!;
  }

  @override
  Future<UserSummary> userSummary({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    userSummaryRequests.add((siteUrl: siteUrl, username: username));
    await userSummaryGate?.future;
    final value = summary;
    if (value == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return value;
  }

  @override
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    ComposerUploadType uploadType = ComposerUploadType.composer,
    String? clientId,
  }) async {
    composerUploads.add((
      siteUrl: siteUrl,
      filename: file.name,
      uploadType: uploadType,
    ));
    final result = composerUploadResult;
    if (result == null) {
      throw UnimplementedError('No uploads configured for this fake.');
    }
    onProgress(1);
    return result;
  }

  @override
  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  }) async => const {};

  @override
  void close() => closeCalls += 1;
}

Map<String, dynamic> _pollVoteJson(
  PollVoteResponse response, {
  required bool includeVote,
}) => {
  'poll': _pollJson(response.poll),
  if (includeVote)
    'vote': response.selection.rankedChoices.isEmpty
        ? response.selection.optionIds
        : [
            for (final choice in response.selection.rankedChoices)
              {'digest': choice.digest, 'rank': choice.rank},
          ],
};

Map<String, dynamic> _pollJson(Poll poll) => {
  'id': poll.id,
  'name': poll.name,
  'type': poll.type.value,
  'status': poll.status.value,
  'results': poll.results.value,
  'public': poll.isPublic,
  'dynamic': poll.isDynamic,
  'min': poll.min,
  'max': poll.max,
  'step': poll.step,
  'voters': poll.voters,
  'chart_type': poll.chartType.value,
  'title': poll.title,
  'options': [
    for (final option in poll.options)
      {'id': option.id, 'html': option.html, 'votes': option.votes},
  ],
};

Map<String, dynamic> _reactionPostJson(Post post) => {
  'id': post.id,
  'post_number': post.postNumber,
  'username': post.username,
  'cooked': post.cooked,
  'actions_summary': [
    {
      'id': Post.likeActionId,
      if (post.canLike) 'can_act': true,
      if (post.canUnlike) 'can_undo': true,
      if (post.liked) 'acted': true,
      'count': post.likeCount,
    },
  ],
  if (post.reactions case final reactions?) ...{
    'reactions': [
      for (final reaction in reactions.entries)
        {
          'id': reaction.id,
          'count': reaction.count,
          if (reaction.canUndo) 'can_undo': true,
        },
    ],
    'current_user_reaction': switch (reactions.mine) {
      final reaction? => {
        'id': reaction.id,
        if (reaction.canUndo) 'can_undo': true,
      },
      null => null,
    },
    'current_user_used_main_reaction': reactions.usedMainReaction,
    'reaction_users_count': reactions.userCount,
  },
};

Map<String, dynamic> _gifPageJson(GifSearchPage page) => {
  'results': [
    for (final result in page.results)
      {
        'title': result.title,
        'media_formats': {
          'gif': {
            'url': result.url,
            'dims': [result.width, result.height],
          },
          'webp': {
            'url': result.url,
            'dims': [result.width, result.height],
          },
        },
      },
  ],
  'next': page.nextPosition,
};

DiscourseInstance instance(String host, {String? title}) => DiscourseInstance(
  url: 'https://$host',
  title: title ?? host,
  apiVersion: 4,
);

class FakeApiCredentialReader implements ApiCredentialReader {
  FakeApiCredentialReader({this.clientIdValue = 'test-client'});

  final String clientIdValue;
  final Map<String, String> keys = {};

  @override
  Future<String?> apiKeyFor(String siteUrl) async => keys[siteUrl];

  @override
  Future<String> clientId() async => clientIdValue;
}

final class FakePluginRequestHost implements PluginRequestHost {
  FakePluginRequestHost({
    ApiCredentialReader? credentials,
    SiteLifecycle? lifecycle,
  }) : credentials = credentials ?? FakeApiCredentialReader(),
       lifecycle = lifecycle ?? SiteLifecycle();

  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;

  @override
  PluginSiteLease capture(String siteUrl) =>
      _FakePluginSiteLease(lifecycle.capture(siteUrl));

  @override
  Future<PluginRequestCredentials> credentialsFor(String siteUrl) async =>
      PluginRequestCredentials(
        apiKey: await credentials.apiKeyFor(siteUrl),
        clientId: await credentials.clientId(),
      );

  @override
  Future<PluginWriteCredential> writeCredentialFor(String siteUrl) async {
    final apiKey = await credentials.apiKeyFor(siteUrl);
    return (
      apiKey: apiKey,
      failure: apiKey == null
          ? const WriteException(WriteFailure.forbidden)
          : null,
    );
  }
}

final class _FakePluginSiteLease implements PluginSiteLease {
  const _FakePluginSiteLease(this.lease);

  final SiteLease lease;

  @override
  bool get isCurrent => lease.isCurrent;

  @override
  bool commit(void Function() mutation) => lease.commit(mutation);
}

class FakeAuthenticator implements Authenticator {
  FakeAuthenticator({
    this.credentials,
    this.failure,
    this.disconnectFailure,
    this.apiKeyFailure,
  });

  final UserApiCredentials? credentials;
  final UserApiAuthFailure? failure;

  /// Thrown by [disconnect] instead of answering. A keychain really can refuse
  /// — an unsigned macOS build answers `errSecMissingEntitlement` — and that
  /// must not be able to hold a site in the rail.
  final Object? disconnectFailure;

  Object? apiKeyFailure;

  final List<String> connected = [];
  final List<String> disconnected = [];
  final Map<String, String> keys = {};

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    final result = await authorize(siteUrl);
    await persistCredentials(siteUrl, result);
    return result;
  }

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    if (failure != null) throw UserApiAuthException(failure!);
    connected.add(siteUrl);
    return credentials ??
        const UserApiCredentials(key: 'api-key', apiVersion: 4, push: false);
  }

  @override
  Future<void> persistCredentials(
    String siteUrl,
    UserApiCredentials credentials,
  ) async {
    keys[siteUrl] = credentials.key;
  }

  @override
  Future<void> disconnect(String siteUrl) async {
    if (disconnectFailure != null) throw disconnectFailure!;
    disconnected.add(siteUrl);
    keys.remove(siteUrl);
  }

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (apiKeyFailure case final failure?) throw failure;
    return keys[siteUrl];
  }

  @override
  String get applicationName => 'Discourse Native';

  @override
  UserApiKeyProtocol get protocol => const UserApiKeyProtocol();

  @override
  Future<String> clientId() async => 'test-client';

  @override
  SecureStore get store => throw UnimplementedError();
}

TopicPayload topicPayload({
  required int id,
  String title = '',
  int? messageBusLastId,
  List<Post> posts = const [],
  List<int>? stream,
  Map<int, List<int>> gapsBefore = const {},
  Map<int, List<int>> gapsAfter = const {},
  int? postsCount,
  int replyCount = 0,
  int views = 0,
  int likeCount = 0,
  int participantCount = 0,
  int wordCount = 0,
  bool hasSummary = false,
  bool isNestedView = false,
  int? categoryId,
  List<TopicTag> tags = const [],
  bool canCreatePost = false,
  bool canReplyAsNewTopic = false,
  TopicNotificationLevel notificationLevel = TopicNotificationLevel.normal,
  bool pinned = false,
  bool unpinned = false,
  bool pinnedGlobally = false,
  bool closed = false,
  bool archived = false,
  bool visible = true,
  DateTime? deletedAt,
  bool canCloseTopic = false,
  bool canArchiveTopic = false,
  bool canToggleTopicVisibility = false,
  bool canDeleteTopic = false,
  bool canRecoverTopic = false,
  bool canPermanentlyDelete = false,
  bool canFlagTopic = false,
  bool canEditStaffNotes = false,
  bool canMovePosts = false,
  bool canSplitMergeTopic = false,
  List<PostActionSummary> topicActions = const [],
  ComposerDraft? draft,
  int draftSequence = 0,
  TopicRecommendations? recommendations,
  List<TopicParticipant> participants = const [],
  List<TopicMapLink> links = const [],
  List<Bookmark> bookmarks = const [],
  PluginData plugins = PluginData.none,
}) => (
  detail: TopicDetail(
    id: id,
    title: title,
    messageBusLastId: messageBusLastId,
    stream: stream ?? [for (final post in posts) post.id],
    gapsBefore: gapsBefore,
    gapsAfter: gapsAfter,
    postsCount: postsCount ?? posts.length,
    replyCount: replyCount,
    views: views,
    likeCount: likeCount,
    participantCount: participantCount,
    wordCount: wordCount,
    hasSummary: hasSummary,
    isNestedView: isNestedView,
    categoryId: categoryId,
    tags: tags,
    canCreatePost: canCreatePost,
    canReplyAsNewTopic: canReplyAsNewTopic,
    notificationLevel: notificationLevel,
    pinned: pinned,
    unpinned: unpinned,
    pinnedGlobally: pinnedGlobally,
    closed: closed,
    archived: archived,
    visible: visible,
    deletedAt: deletedAt,
    canCloseTopic: canCloseTopic,
    canArchiveTopic: canArchiveTopic,
    canToggleTopicVisibility: canToggleTopicVisibility,
    canDeleteTopic: canDeleteTopic,
    canRecoverTopic: canRecoverTopic,
    canPermanentlyDelete: canPermanentlyDelete,
    canFlagTopic: canFlagTopic,
    canEditStaffNotes: canEditStaffNotes,
    canMovePosts: canMovePosts,
    canSplitMergeTopic: canSplitMergeTopic,
    topicActions: topicActions,
    draft: draft,
    draftSequence: draftSequence,
    recommendations: recommendations,
    participants: participants,
    links: links,
    bookmarks: bookmarks,
    plugins: plugins,
  ),
  posts: posts,
);
