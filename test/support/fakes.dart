import 'dart:async';

import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/data/update_store.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/incoming_topics.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';

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
  FakeUpdateStore({this.rawChannel, this.lastChecked});

  /// Raw, so a test can write a name that is no longer a channel.
  String? rawChannel;
  DateTime? lastChecked;
  int writeCount = 0;

  @override
  Future<UpdateChannel?> readChannel() async =>
      UpdateChannel.byName(rawChannel);

  @override
  Future<void> writeChannel(UpdateChannel channel) async {
    writeCount++;
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

  static String _key(String siteUrl, String draftKey) => '$siteUrl::$draftKey';

  @override
  Future<String?> read(String siteUrl, String draftKey) async =>
      saved[_key(siteUrl, draftKey)];

  @override
  Future<void> write(String siteUrl, String draftKey, String data) async {
    saved[_key(siteUrl, draftKey)] = data;
  }

  @override
  Future<void> clear(String siteUrl, String draftKey) async {
    saved.remove(_key(siteUrl, draftKey));
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

/// Answers lookups from a map of term to result, with no network involved.
class FakeDiscourseApi implements DiscourseApi {
  FakeDiscourseApi({
    this.results = const {},
    this.failure,
    this.user,
    this.totals,
    this.notificationList,
    this.bookmarkList,
    this.reminderList = const [],
    this.feeds = const {},
    this.categoryList = const [],
    this.nextPages = const {},
    this.gate,
    this.topics = const {},
    this.postsById = const {},
    this.cards = const {},
    this.creation,
    this.writeFailure,
    this.draftFailure,
    this.likeResponses = const {},
    this.likeFailure,
    this.likeGate,
    this.likersById = const {},
    this.likerGate,
  });

  final Map<String, DiscourseInstance> results;
  final SiteLookupFailure? failure;

  /// Returned by [currentUser]; defaults to a plausible account.
  final DiscourseUser? user;

  /// Returned by [notificationTotals]; null means the call fails.
  final NotificationTotals? totals;

  /// Returned by [notifications]; null means the call fails.
  final List<DiscourseNotification>? notificationList;

  /// Returned by [bookmarks]; null means the call fails.
  final List<Bookmark>? bookmarkList;

  /// The reminders [bookmarks] answers with, alongside [bookmarkList].
  final List<DiscourseNotification> reminderList;

  final List<String> revoked = [];
  int totalsCalls = 0;
  int notificationCalls = 0;

  /// Usernames passed to [bookmarks], in order.
  final List<String> bookmarksRequested = [];

  /// Ids passed to [markNotificationRead], in order.
  final List<int> markedRead = [];

  /// Returned by [topicList], keyed by path; a missing path fails.
  final Map<String, List<Topic>> feeds;

  /// Returned by [categories].
  final List<TopicCategory> categoryList;

  /// `more_topics_url` to report for a given path, driving pagination.
  final Map<String, String> nextPages;

  /// When set, [topicList] waits on it — lets a test control exactly when a
  /// response lands.
  final Completer<void>? gate;

  /// Returned by [topic], keyed by topic id.
  final Map<int, TopicPayload> topics;

  /// Returned by [posts], keyed by post id.
  final Map<int, Post> postsById;

  /// Returned by [userCard], keyed by username; a missing one fails.
  final Map<String, UserCard> cards;

  final List<String> cardsRequested = [];

  final List<int> topicsOpened = [];
  final List<List<int>> postFetches = [];

  final List<String> feedPaths = [];

  final List<String> lookups = [];

  /// Returned by [createPost]; defaults to a plausible published reply.
  final PostCreation? creation;

  /// Thrown by [createPost] instead of answering, so a test can drive the
  /// refusal paths without a server.
  final WriteException? writeFailure;

  /// Every [createPost] call, in order, as the arguments it was given.
  final List<Map<String, Object?>> created = [];

  /// Every [updatePost] call, in order.
  final List<Map<String, Object?>> updated = [];

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

  /// Thrown by [saveDraft] instead of answering.
  final WriteException? draftFailure;

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
    String? clientId,
  }) async {
    notificationCalls++;
    final result = notificationList;
    if (result == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return result;
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
    return TopicList(topics: topics, moreTopicsUrl: nextPages[path]);
  }

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    String? apiKey,
    String? clientId,
  }) async {
    topicsOpened.add(id);
    final detail = topics[id];
    if (detail == null) {
      throw SiteLookupException(SiteLookupFailure.unreachable, siteUrl);
    }
    return detail;
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
    return ids.map((i) => postsById[i]).whereType<Post>().toList();
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
  }) async => categoryList;

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
  Future<Post> updatePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    required String raw,
    String? editReason,
    String? clientId,
  }) async {
    updated.add({'siteUrl': siteUrl, 'postId': postId, 'raw': raw});

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
    if (draftFailure != null) throw draftFailure!;
    return sequence + 1;
  }

  @override
  void close() {}
}

DiscourseInstance instance(String host, {String? title}) => DiscourseInstance(
  url: 'https://$host',
  title: title ?? host,
  apiVersion: 4,
);

/// Runs the handshake without a browser or a keychain.
class FakeAuthenticator implements Authenticator {
  FakeAuthenticator({this.credentials, this.failure, this.disconnectFailure});

  final UserApiCredentials? credentials;
  final UserApiAuthFailure? failure;

  /// Thrown by [disconnect] instead of answering. A keychain really can refuse
  /// — an unsigned macOS build answers `errSecMissingEntitlement` — and that
  /// must not be able to hold a site in the rail.
  final Object? disconnectFailure;

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
  Future<String?> apiKeyFor(String siteUrl) async => keys[siteUrl];

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
  ),
  posts: posts,
);
