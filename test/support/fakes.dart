import 'dart:async';

import 'package:discourse_native/src/data/authenticator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/secure_store.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/data/instance_store.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
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

/// Keeps unsynced drafts in memory instead of shared_preferences.
class FakeDraftStore implements DraftStore {
  final Map<String, String> saved = {};

  static String _key(String siteUrl, String draftKey) =>
      '$siteUrl::$draftKey';

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

/// Answers lookups from a map of term to result, with no network involved.
class FakeDiscourseApi implements DiscourseApi {
  FakeDiscourseApi({
    this.results = const {},
    this.failure,
    this.user,
    this.totals,
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
  });

  final Map<String, DiscourseInstance> results;
  final SiteLookupFailure? failure;

  /// Returned by [currentUser]; defaults to a plausible account.
  final DiscourseUser? user;

  /// Returned by [notificationTotals]; null means the call fails.
  final NotificationTotals? totals;

  final List<String> revoked = [];
  int totalsCalls = 0;

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
  final Map<int, TopicDetail> topics;

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
      user ?? const DiscourseUser(username: 'joffreyj', name: 'Joffrey');

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
  Future<TopicDetail> topic({
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
  FakeAuthenticator({this.credentials, this.failure});

  final UserApiCredentials? credentials;
  final UserApiAuthFailure? failure;

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
