import 'dart:async';

import 'package:discourse_native/src/data/api_credentials.dart';
import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/forum_tab_store.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/data/update_store.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';

/// Keeps instances in memory instead of shared_preferences, which needs a
/// platform channel.
class FakeInstanceStore implements InstanceStore {
  FakeInstanceStore([this._instances = const []]);

  List<DiscourseInstance> _instances;
  int saveCount = 0;

  @override
  Future<List<DiscourseInstance>> load() async => _instances;

  @override
  Future<void> save(List<DiscourseInstance> instances) async {
    _instances = List.of(instances);
    saveCount++;
  }
}

/// Keeps forum workspaces in memory instead of shared_preferences.
class FakeForumTabStore implements ForumTabStore {
  FakeForumTabStore([Iterable<ForumWorkspace> workspaces = const []])
    : _workspaces = List.of(workspaces);

  List<ForumWorkspace> _workspaces;
  int saveCount = 0;

  List<ForumWorkspace> get workspaces => List.unmodifiable(_workspaces);

  @override
  Future<List<ForumWorkspace>> load() async => List.unmodifiable(_workspaces);

  @override
  Future<void> save(Iterable<ForumWorkspace> workspaces) async {
    _workspaces = List.of(workspaces);
    saveCount++;
  }
}

/// An updater with no network, no disk and no process behind it.
///
/// [isSupported] is false by default, and that default is load-bearing: the
/// hundred-odd tests that build a shell must not grow an update button just
/// because one exists.
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

  /// What each channel has to offer. A channel absent from the map, or mapped
  /// to null, is up to date.
  final Map<UpdateChannel, UpdateRelease?> releases;

  final UpdateException? checkFailure;
  final UpdateException? downloadFailure;
  final UpdateException? installFailure;

  /// Fractions handed to `onProgress`, in order.
  final List<double> progressSteps;

  /// Holds [check] open so a test can assert on the in-flight state. Mirrors
  /// [FakeDiscourseApi.gate].
  final Completer<void>? gate;

  final Map<UpdateChannel, Completer<void>> checkGates;

  /// Holds [download] open. Separate from [gate] so a test can let the check
  /// through and still catch the download mid-flight.
  final Completer<void>? downloadGate;

  int checkCount = 0;
  int downloadCount = 0;
  int installCount = 0;
  int discardCount = 0;
  UpdateChannel? lastCheckedChannel;
  UpdateRelease? lastDownloaded;

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
    downloadCount++;
    lastDownloaded = release;
    for (final step in progressSteps) {
      onProgress?.call(step);
    }
    if (downloadGate != null) await downloadGate!.future;
    if (downloadFailure != null) throw downloadFailure!;
  }

  @override
  Future<void> installAndRestart() async {
    installCount++;
    if (installFailure != null) throw installFailure!;
  }

  @override
  Future<void> discard() async {
    discardCount++;
  }
}

/// Keeps the channel and the last-checked stamp in memory instead of
/// shared_preferences, which needs a platform channel.
class FakeUpdateStore implements UpdateStore {
  FakeUpdateStore({
    this.rawChannel,
    this.lastChecked,
    this.channelWriteGates = const {},
  });

  /// Raw, so a test can write a name that is no longer a channel.
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

/// Keeps unsynced drafts in memory instead of shared_preferences.
class FakeDraftStore implements DraftStore {
  final Map<String, String> saved = {};
  final List<String> events = [];

  static String _key(String siteUrl, String draftKey) => '$siteUrl::$draftKey';

  @override
  Future<String?> read(String siteUrl, String draftKey) async =>
      saved[_key(siteUrl, draftKey)];

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
  Future<void> clearSite(String siteUrl, {bool Function()? ifCurrent}) async {
    if (ifCurrent != null && !ifCurrent()) return;
    saved.removeWhere((key, _) => key.startsWith('$siteUrl::'));
    events.add('clearSite:$siteUrl');
  }
}

/// A tracker with no connection behind it.
///
/// Tests publish to it by hand — `tracker.deliver(...)` stands in for a
/// message coming off the bus. Real ones hold a long poll open, which a widget
/// test must not, and which the test binding fails outright on: the poll's
/// backoff timer outlives the tree.
class FakeSiteTracker implements SiteTracker {
  FakeSiteTracker({
    required this.siteUrl,
    required this.onIncomingTopics,
    required this.onNotifications,
    required this.onReviewableCounts,
    this.userId,
    this.apiKey,
  });

  /// Every tracker built during a test, newest last, so a test can reach the
  /// one belonging to the site it is looking at.
  static final List<FakeSiteTracker> built = [];

  /// Hands [factory] out and empties [built]. Call from `setUp`.
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

  /// Null when the account id is not known, which is what decides whether a
  /// real tracker subscribes to the counter channels at all.
  @override
  final int? userId;

  /// Null when the site is not connected, which is what decides whether a real
  /// tracker subscribes to `/new`.
  final String? apiKey;

  @override
  final IncomingTopics incoming = IncomingTopics();

  bool polling = true;
  int pollNowCalls = 0;
  bool disposed = false;

  /// One `/latest` or `/new` message, exactly as it would arrive.
  void deliver(Object? message) {
    if (incoming.notify(message)) onIncomingTopics();
  }

  /// One `/notification/{id}` message.
  void deliverNotification(Object? message) => onNotifications(message);

  /// One `/reviewable_counts/{id}` message.
  void deliverReviewableCounts(Object? message) => onReviewableCounts(message);

  /// The channels a plugin asked to watch while a topic is open, in order.
  final List<String> watchedChannels = [];

  @override
  int? watchedTopic;

  void Function(String channel, Object? data)? _onTopicMessage;

  @override
  void watchTopic(
    int topicId,
    List<String> channels,
    void Function(String channel, Object? data) onMessage,
  ) {
    if (watchedTopic == topicId) return;
    unwatchTopic();
    watchedTopic = topicId;
    watchedChannels.addAll(channels);
    _onTopicMessage = onMessage;
  }

  @override
  void unwatchTopic() {
    watchedTopic = null;
    watchedChannels.clear();
    _onTopicMessage = null;
  }

  /// One message on a topic-scoped channel, exactly as it would arrive.
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

  void deliverPluginMessage(String channel, Object? data) {
    for (final callback in List.of(
      pluginChannelCallbacks[channel] ?? const [],
    )) {
      callback(data);
    }
  }

  @override
  void start() => polling = true;

  @override
  void stop() => polling = false;

  @override
  void pollNow() => pollNowCalls++;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class _FakeSiteMessageBusSubscription
    implements SiteMessageBusSubscription {
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

/// Answers lookups from a map of term to result, with no network involved.
class FakeDiscourseApi implements DiscourseApi {
  FakeDiscourseApi({
    this.results = const {},
    this.failure,
    this.user,
    this.totals,
    this.notificationList,
    this.replyNotificationList,
    this.chatNotificationList,
    this.bookmarkList,
    this.reminderList = const [],
    this.feeds = const {},
    this.filterOptionsByPath = const {},
    this.creatableFeedPaths = const {},
    this.categoryList = const [],
    this.categoryPages = const {},
    this.categoryLoadComplete = true,
    this.categoryCanCreateTopic = false,
    this.composerCapabilities = const TopicComposerCapabilities(),
    this.topicTagSearches = const {},
    this.serverDrafts = const {},
    this.userDraftList = const [],
    this.nextPages = const {},
    this.gate,
    this.topics = const {},
    this.postsById = const {},
    this.postRecommendations = const {},
    this.postGate,
    this.cards = const {},
    this.creation,
    this.writeFailure,
    this.draftFailure,
    this.draftGate,
    this.likeResponses = const {},
    this.likeFailure,
    this.likeGate,
    this.likersById = const {},
    this.likerGate,
    this.siteAppearances = const {},
    this.appearanceGate,
    this.siteConfigs = const {},
    this.searchResults = const {},
    this.searchGate,
    this.searchFailure,
    this.customEmojisBySite = const {},
    this.customEmojiGate,
    this.userSearches = const {},
    this.userSearchGate,
    this.filterTagSearches = const {},
    this.filterTagGroupSearches = const {},
    this.filterGroupSearches = const {},
    this.filterSuggestionGate,
    this.hashtagSearches = const {},
    this.hashtagSearchGate,
    this.hashtagsByRef = const {},
    this.hashtagLookupGate,
    this.realUsernames = const {},
    this.mentionCheckGate,
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
    this.chatChannelsBySite = const {},
    this.chatChannelGate,
    this.chatMessagesByKey = const {},
    this.chatMessageGate,
    this.chatReadFailure,
    this.chatSendFailure,
    this.chatSendGate,
    this.chatSentMessageId = 1,
    this.customSidebarSectionsBySite = const {},
    this.pluginResponses = const {},
    Map<String, WriteException>? pluginWriteFailures,
  }) : pluginWriteFailures = pluginWriteFailures ?? {};

  final Map<String, DiscourseInstance> results;
  final Map<String, List<SidebarSection>> customSidebarSectionsBySite;
  final Map<String, Map<String, dynamic>> pluginResponses;
  final Map<String, WriteException> pluginWriteFailures;
  final List<
    ({String siteUrl, String method, String path, Map<String, Object?> body})
  >
  pluginWrites = [];
  final SiteLookupFailure? failure;

  /// Returned by [currentUser]; defaults to a plausible account.
  final DiscourseUser? user;

  /// Returned by [notificationTotals]; null means the call fails.
  final NotificationTotals? totals;

  /// Returned by [notifications]; null means the call fails.
  final List<DiscourseNotification>? notificationList;

  /// Returned by filtered [notifications] calls; null means the call fails.
  final List<DiscourseNotification>? replyNotificationList;

  /// Returned by Chat-filtered [notifications] calls; null means the call fails.
  final List<DiscourseNotification>? chatNotificationList;

  /// Returned by [bookmarks]; null means the call fails.
  final List<Bookmark>? bookmarkList;

  /// The reminders [bookmarks] answers with, alongside [bookmarkList].
  final List<DiscourseNotification> reminderList;

  final List<String> revoked = [];
  int totalsCalls = 0;
  int notificationCalls = 0;
  int replyNotificationCalls = 0;
  int chatNotificationCalls = 0;

  /// The type filters passed to [notifications], one immutable list per call.
  final List<List<NotificationKind>> notificationFilters = [];

  /// Usernames passed to [bookmarks], in order.
  final List<String> bookmarksRequested = [];

  /// Ids passed to [markNotificationRead], in order.
  final List<int> markedRead = [];

  /// Returned by [topicList], keyed by path; a missing path fails.
  final Map<String, List<Topic>> feeds;
  final Map<String, List<TopicFilterOption>> filterOptionsByPath;
  final Set<String> creatableFeedPaths;

  /// Returned by [categories].
  final List<TopicCategory> categoryList;
  final Map<int, List<TopicCategory>> categoryPages;
  final bool categoryLoadComplete;
  final bool categoryCanCreateTopic;
  final TopicComposerCapabilities composerCapabilities;
  final List<String> categoryRequests = [];
  final List<int> categoryPagesRequested = [];
  final List<String> topicComposerCapabilityRequests = [];
  final Map<String, TopicTagSearch> topicTagSearches;
  final Map<String, ComposerDraft> serverDrafts;
  final List<UserDraft> userDraftList;
  final List<({String siteUrl, int offset, int limit})> userDraftRequests = [];
  final List<({String siteUrl, String draftKey, int sequence})>
  userDraftsDeleted = [];

  /// `more_topics_url` to report for a given path, driving pagination.
  final Map<String, String> nextPages;

  /// When set, [topicList] waits on it — lets a test control exactly when a
  /// response lands.
  final Completer<void>? gate;

  /// Returned by [topic], keyed by topic id.
  final Map<int, TopicPayload> topics;

  /// Returned by [posts], keyed by post id.
  final Map<int, Post> postsById;

  /// More-topics data returned with the final [topicPosts] window.
  final Map<int, TopicRecommendations> postRecommendations;

  /// When set, post refreshes wait on it so a write can supersede one already
  /// in flight and a test can observe the queued replay.
  final Completer<void>? postGate;

  /// Returned by [userCard], keyed by username; a missing one fails.
  final Map<String, UserCard> cards;

  final List<String> cardsRequested = [];

  final List<int> topicsOpened = [];
  final List<int?> topicPostNumbersOpened = [];
  final List<({int topicId, int postNumber})> topicReadsRecorded = [];
  final List<List<int>> postFetches = [];

  final List<String> feedPaths = [];

  final List<String> lookups = [];

  int closeCalls = 0;

  /// Returned by [createPost]; defaults to a plausible published reply.
  final PostCreation? creation;

  /// Thrown by [createPost] instead of answering, so a test can drive the
  /// refusal paths without a server.
  final WriteException? writeFailure;

  /// Every [createPost] call, in order, as the arguments it was given.
  final List<Map<String, Object?>> created = [];
  final List<Map<String, Object?>> topicsCreated = [];

  /// Every [updatePost] call, in order.
  final List<Map<String, Object?>> updated = [];
  final List<Map<String, Object?>> topicsUpdated = [];
  final List<Map<String, Object?>> topicTagsUpdated = [];

  /// Post ids passed to [deletePost] and [recoverPost], in order.
  final List<int> deleted = [];
  final List<int> recovered = [];

  /// Post ids passed to [likePost] and [unlikePost], in order.
  final List<int> liked = [];
  final List<int> unliked = [];

  /// What a like route answers with, keyed by post id. Nothing for a post
  /// means the route answered without one — which real ones do, and which
  /// leaves the caller's own guess at the count standing.
  final Map<int, Post> likeResponses;

  /// Thrown by [likePost] and [unlikePost] instead of answering.
  final WriteException? likeFailure;

  /// When set, both like routes wait on it — lets a test press the heart twice
  /// before either write has come back.
  final Completer<void>? likeGate;

  /// Returned by [postLikers], keyed by post id; a missing one fails.
  final Map<int, List<PostLiker>> likersById;

  /// Post ids passed to [postLikers], in order.
  final List<int> likersRequested = [];

  /// When set, [postLikers] waits on it, so a test can hold the list in flight.
  final Completer<void>? likerGate;

  /// Resolved appearances returned per site. Missing is the neutral optional
  /// capability answer used by tests unrelated to theming.
  final Map<String, SiteAppearance> siteAppearances;
  final Completer<void>? appearanceGate;
  final List<String> appearancesRequested = [];

  /// Returned by [siteConfig], keyed by site url. A missing one fails, which
  /// is the default and is deliberate: a test that has not said what a site's
  /// settings are gets a site drawn as plain core, which is what every test
  /// that is not about an optional feature wants to see.
  final Map<String, SiteConfig> siteConfigs;
  final Map<String, SearchResults> searchResults;
  final Completer<void>? searchGate;
  final SiteLookupFailure? searchFailure;
  final List<({String siteUrl, String term, String? typeFilter})>
  searchesRequested = [];

  /// Site urls passed to [siteConfig], in order.
  final List<String> siteConfigsRequested = [];

  /// Returned by [customEmojis], keyed by site url. Empty by default: a site
  /// with no custom emoji is the neutral answer here, not a failure. Named
  /// apart from the method, which a field of the same name would collide with.
  final Map<String, Map<String, String>> customEmojisBySite;
  final Completer<void>? customEmojiGate;

  /// Site urls passed to [customEmojis], in order.
  final List<String> customEmojisRequired = [];

  /// Returned by [searchUsers], keyed by term. A term nobody listed answers
  /// with nothing, which is what a real site does for a name it does not have.
  final Map<String, List<FoundUser>> userSearches;

  /// The searches asked for, in order.
  final List<({String term, int? topicId})> userSearchesRequested = [];

  /// When set, [searchUsers] waits on it, so a test can hold an answer in
  /// flight while the query moves on.
  final Completer<void>? userSearchGate;

  final Map<String, List<TopicFilterLookupValue>> filterTagSearches;
  final Map<String, List<TopicFilterLookupValue>> filterTagGroupSearches;
  final Map<String, List<TopicFilterLookupValue>> filterGroupSearches;
  final Completer<void>? filterSuggestionGate;
  final List<String> filterTagSearchesRequested = [];
  final List<String> filterTagGroupSearchesRequested = [];
  final List<String> filterGroupSearchesRequested = [];

  /// Returned by [searchHashtags], keyed by term. A term nobody listed answers
  /// with nothing, the way a real site does for a slug it does not have.
  final Map<String, List<FoundHashtag>> hashtagSearches;

  /// The terms asked for, in order.
  final List<String> hashtagSearchesRequested = [];

  /// When set, [searchHashtags] waits on it, so a test can hold an answer in
  /// flight while the query moves on.
  final Completer<void>? hashtagSearchGate;

  /// What [lookupHashtags] resolves, keyed by ref. A ref nobody listed is
  /// absent from the reply, which is how a real site says "not one of mine".
  final Map<String, FoundHashtag> hashtagsByRef;

  /// The batches of refs looked up, in order — so a test can show that typing
  /// a ref asks nothing and finishing it asks once.
  final List<Set<String>> hashtagLookupsRequested = [];

  final Completer<void>? hashtagLookupGate;

  /// The usernames [checkMentions] confirms. Anything else is somebody who
  /// does not exist, and must stay text.
  final Set<String> realUsernames;

  final List<Set<String>> mentionChecksRequested = [];

  final Completer<void>? mentionCheckGate;

  /// Returned by [emojis], keyed by site url.
  final Map<String, List<SiteEmoji>> emojisBySite;

  /// Site urls passed to [emojis], in order — so a test can show the list is
  /// fetched once and not per keystroke.
  final List<String> emojisRequested = [];

  /// Returned by [postReactors], keyed by `PostReactors.key(postId, filter)`;
  /// a missing one fails.
  final Map<String, PostReactors> reactorsById;

  /// The `(postId, filter)` pairs passed to [postReactors], in order.
  final List<({int postId, String? filter})> reactorsRequested = [];

  /// When set, [postReactors] waits on it, so a test can hold the list in
  /// flight.
  final Completer<void>? reactorGate;

  /// What [toggleReaction] answers with, keyed by post id. Nothing for a post
  /// means the route answered without one, which leaves the caller's own guess
  /// standing.
  final Map<int, Post> reactionResponses;

  /// Thrown by [toggleReaction] instead of answering.
  final WriteException? reactionFailure;

  /// When set, [toggleReaction] waits on it, so a test can press twice before
  /// either write has come back.
  final Completer<void>? reactionGate;

  /// Every [toggleReaction] call, in order.
  final List<({int postId, String reaction})> reacted = [];

  /// Personalized answers for poll writes, keyed by [pollVoteKey].
  final Map<String, PollVoteResponse> pollVoteResponses;
  final Map<String, PollVoteResponse> pollRemovalResponses;

  /// Thrown by either poll vote route instead of answering.
  final WriteException? pollVoteFailure;

  /// Holds either poll route open so controller tests can exercise concurrent
  /// invalidation and per-post write serialization.
  final Completer<void>? pollVoteGate;

  /// Poll writes in call order, with an immutable copy of the sent digests.
  final List<({int postId, String pollName, List<String> options})> pollVotes =
      [];
  final List<({int postId, String pollName})> pollVotesRemoved = [];

  static String pollVoteKey(int postId, String pollName) =>
      '$postId::$pollName';

  /// Returned by [chatChannels], keyed by site url; a missing site fails.
  ///
  /// Missing is the default, and deliberately: a test that has not said a site
  /// has chat sees a site drawn as plain core, which is what every test that is
  /// not about chat wants. Nothing asks in the first place unless
  /// [totals] reports `hasChatEnabled`, which itself defaults to off.
  final Map<String, ChatChannels> chatChannelsBySite;

  /// Site urls passed to [chatChannels], in order.
  final List<String> chatChannelsRequested = [];

  /// When set, [chatChannels] waits on it, so a test can hold the sidebar in
  /// the moment before the sections exist.
  final Completer<void>? chatChannelGate;

  /// Returned by [chatMessages], keyed by [chatMessagesKey]; a missing key
  /// fails, so a test only has to name the pages it expects to be asked for.
  final Map<String, ChatMessagePage> chatMessagesByKey;

  /// The window a channel opens on is keyed by the channel alone; a page by
  /// the message and the direction it was asked to page from.
  static String chatMessagesKey(int channelId, {int? before, int? after}) =>
      switch ((before, after)) {
        (final int target, _) => '$channelId~past~$target',
        (_, final int target) => '$channelId~future~$target',
        _ => '$channelId',
      };

  /// What a jump to the present is answered with, when a test names it.
  ///
  /// Falls back to [chatMessagesKey], because most of the time the two are the
  /// same window and saying so twice would only be noise. A test that wants
  /// the anchored window to differ from the newest page — the whole point of
  /// jumping — names this one as well.
  static String chatMessagesLatestKey(int channelId) => '$channelId~latest';

  /// Every ask passed to [chatMessages], in order and in the shape it was made.
  final List<({int channelId, int? before, int? after, bool fromLastRead})>
  chatMessagesRequested = [];

  /// When set, [chatMessages] waits on it, so a test can look at a channel
  /// while its first page is still on the way.
  final Completer<void>? chatMessageGate;

  /// Thrown by [markChatChannelRead] instead of answering.
  final WriteException? chatReadFailure;

  /// Every [markChatChannelRead] call, in order.
  final List<({int channelId, int messageId})> chatReadsMarked = [];

  /// Chat-message writes, their optional gate, and the id returned by a
  /// successful fake send.
  final WriteException? chatSendFailure;
  final Completer<void>? chatSendGate;
  final int? chatSentMessageId;
  final List<({String siteUrl, int channelId, String message, int? threadId})>
  chatMessagesSent = [];

  /// Thrown by [saveDraft] instead of answering.
  final WriteException? draftFailure;

  /// Holds draft saves open so tests can type a newer revision while one is
  /// still in flight.
  final Completer<void>? draftGate;

  /// Every [saveDraft] call, in order.
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
      user ??
      // With an id, because that is what names the account's message_bus
      // channels — a user without one gets no live counters.
      const DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');

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
    List<NotificationKind> filterByTypes = const [],
    String? clientId,
  }) async {
    notificationFilters.add(List.unmodifiable(filterByTypes));
    final replies = _sameKinds(filterByTypes, userMenuReplyNotificationKinds);
    final chat = _sameKinds(filterByTypes, userMenuChatNotificationKinds);
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
    List<NotificationKind> actual,
    List<NotificationKind> expected,
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
    final topics = feeds[path];
    if (topics == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return TopicList(
      topics: topics,
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
    String? apiKey,
    String? clientId,
  }) async {
    topicsOpened.add(id);
    topicPostNumbersOpened.add(postNumber);
    final detail = topics[id];
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
      canCreateTopic: categoryCanCreateTopic,
    );
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
    int limit = 20,
    String? clientId,
  }) async => topicTagSearches[term] ?? const TopicTagSearch();

  @override
  Future<SiteConfig> siteConfig({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    siteConfigsRequested.add(siteUrl);
    final config = siteConfigs[siteUrl];
    if (config == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return config;
  }

  @override
  Future<SearchResults> searchPosts({
    required String siteUrl,
    required String term,
    String? typeFilter,
    String? apiKey,
    String? clientId,
  }) async {
    searchesRequested.add((
      siteUrl: siteUrl,
      term: term,
      typeFilter: typeFilter,
    ));
    await searchGate?.future;
    if (searchFailure case final failure?) {
      throw SiteLookupException(failure, siteUrl);
    }
    return searchResults[term] ?? const SearchResults();
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
    if (userSearchGate != null) await userSearchGate!.future;
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
    filterTagSearchesRequested.add(term);
    await filterSuggestionGate?.future;
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
    filterTagGroupSearchesRequested.add(term);
    await filterSuggestionGate?.future;
    return filterTagGroupSearches[term] ?? const [];
  }

  @override
  Future<List<TopicFilterLookupValue>> searchFilterGroups({
    required String siteUrl,
    required String term,
    int limit = 10,
    String? apiKey,
    String? clientId,
  }) async {
    filterGroupSearchesRequested.add(term);
    await filterSuggestionGate?.future;
    return filterGroupSearches[term] ?? const [];
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
    if (hashtagSearchGate != null) await hashtagSearchGate!.future;
    return hashtagSearches[term] ?? const [];
  }

  @override
  Future<List<FoundHashtag>> lookupHashtags({
    required String siteUrl,
    required Iterable<String> refs,
    String? apiKey,
    String? clientId,
  }) async {
    final asked = refs.toSet();
    hashtagLookupsRequested.add(asked);
    if (hashtagLookupGate != null) await hashtagLookupGate!.future;
    return [for (final ref in asked) ?hashtagsByRef[ref]];
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
    if (mentionCheckGate != null) await mentionCheckGate!.future;
    return asked.intersection(realUsernames);
  }

  @override
  Future<List<SiteEmoji>> emojis({
    required String siteUrl,
    String? apiKey,
    String? clientId,
  }) async {
    emojisRequested.add(siteUrl);
    return emojisBySite[siteUrl] ?? const [];
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
    String? draftKey,
    String? clientId,
  }) async {
    created.add({
      'siteUrl': siteUrl,
      'topicId': topicId,
      'raw': raw,
      'replyToPostNumber': replyToPostNumber,
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
    String draftKey = ComposerDraft.newTopicDraftKey,
    String? clientId,
  }) async {
    topicsCreated.add({
      'siteUrl': siteUrl,
      'title': title,
      'raw': raw,
      'categoryId': categoryId,
      'tags': tags.toList(),
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
  Future<ChatMessagePage> chatMessages({
    required String siteUrl,
    required int channelId,
    int? before,
    int? after,
    bool fromLastRead = false,
    int pageSize = 50,
    String? apiKey,
    String? clientId,
  }) async {
    chatMessagesRequested.add((
      channelId: channelId,
      before: before,
      after: after,
      fromLastRead: fromLastRead,
    ));
    if (chatMessageGate != null) await chatMessageGate!.future;
    final asksForLatest = !fromLastRead && before == null && after == null;
    final found =
        (asksForLatest
            ? chatMessagesByKey[chatMessagesLatestKey(channelId)]
            : null) ??
        chatMessagesByKey[chatMessagesKey(
          channelId,
          before: before,
          after: after,
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
    String? apiKey,
    String? clientId,
  }) async {
    final base = 'thread-$channelId-$threadId';
    final directional = before != null
        ? '$base~past~$before'
        : after != null
        ? '$base~future~$after'
        : base;
    final found = chatMessagesByKey[directional] ?? chatMessagesByKey[base];
    if (found == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return found;
  }

  @override
  Future<int?> sendChatMessage({
    required String siteUrl,
    required String apiKey,
    required int channelId,
    required String message,
    int? threadId,
    String? clientId,
  }) async {
    chatMessagesSent.add((
      siteUrl: siteUrl,
      channelId: channelId,
      message: message,
      threadId: threadId,
    ));
    if (chatSendGate != null) await chatSendGate!.future;
    if (chatSendFailure != null) throw chatSendFailure!;
    return chatSentMessageId;
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
    required String apiKey,
    String? clientId,
  }) async {
    final response = pluginResponses['GET $path'];
    if (response == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return response;
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
  }) async => (draft: serverDrafts[draftKey], sequence: 0);

  @override
  Future<List<UserDraft>> userDrafts({
    required String siteUrl,
    required String apiKey,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    userDraftRequests.add((siteUrl: siteUrl, offset: offset, limit: limit));
    return userDraftList.skip(offset).take(limit).toList(growable: false);
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
  }

  @override
  Future<ComposerUploadResult> uploadComposerImage({
    required String siteUrl,
    required String apiKey,
    required ComposerUploadFile file,
    required void Function(double progress) onProgress,
    required Future<void> abortTrigger,
    String? clientId,
  }) => throw UnimplementedError('No uploads configured for this fake.');

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

/// Runs the handshake without a browser or a keychain.
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

  /// Thrown by [apiKeyFor] when a test needs the platform credential store to
  /// fail after the rest of the shell has already loaded.
  Object? apiKeyFailure;

  final List<String> connected = [];
  final List<String> disconnected = [];
  final Map<String, String> keys = {};

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    if (failure != null) throw UserApiAuthException(failure!);
    connected.add(siteUrl);
    final result =
        credentials ??
        const UserApiCredentials(key: 'api-key', apiVersion: 4, push: false);
    keys[siteUrl] = result.key;
    return result;
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

/// A topic payload, in the shape a fetch answers with: the topic, and the
/// posts that came down with it.
///
/// [stream] and [postsCount] default to exactly the posts given, which is what
/// a short topic looks like. Pass them to describe a topic with more to fetch.
TopicPayload topicPayload({
  required int id,
  String title = '',
  List<Post> posts = const [],
  List<int>? stream,
  int? postsCount,
  int? categoryId,
  bool canCreatePost = false,
  ComposerDraft? draft,
  int draftSequence = 0,
  TopicRecommendations? recommendations,
}) => (
  detail: TopicDetail(
    id: id,
    title: title,
    stream: stream ?? [for (final post in posts) post.id],
    postsCount: postsCount ?? posts.length,
    categoryId: categoryId,
    canCreatePost: canCreatePost,
    draft: draft,
    draftSequence: draftSequence,
    recommendations: recommendations,
  ),
  posts: posts,
);
