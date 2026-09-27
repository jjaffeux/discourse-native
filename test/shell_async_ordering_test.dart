import 'dart:async';

import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _PendingFeedRequest {
  _PendingFeedRequest(this.path);

  final String path;
  final Completer<TopicList> response = Completer<TopicList>();
}

final class _IncomingOrderingApi extends FakeDiscourseApi {
  final List<_PendingFeedRequest> requests = [];
  Completer<void> _requestsChanged = Completer<void>();

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final request = _PendingFeedRequest(path);
    requests.add(request);
    _requestsChanged.complete();
    _requestsChanged = Completer<void>();
    return request.response.future;
  }

  Future<void> waitForRequests(int count) async {
    while (requests.length < count) {
      await _requestsChanged.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TestFailure(
          'Expected $count feed requests, but received ${requests.length}.',
        ),
      );
    }
  }
}

final class _PendingPostRequest {
  _PendingPostRequest(this.ids);

  final List<int> ids;
  final Completer<List<Post>> response = Completer<List<Post>>();
}

final class _PostOrderingApi extends FakeDiscourseApi {
  _PostOrderingApi({this.deleteGate, super.likeGate})
    : super(
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A topic', slug: 'a-topic')],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A topic',
            posts: [_post('initial', canDelete: true)],
          ),
        },
      );

  final Completer<void>? deleteGate;
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> likeStarted = Completer<void>();
  final List<_PendingPostRequest> postRequests = [];
  Completer<void> _postRequestsChanged = Completer<void>();

  /// While set, each stream read waits for its entry in [topicRequests].
  bool holdTopics = false;
  final List<Completer<TopicPayload>> topicRequests = [];
  Completer<void> _topicRequestsChanged = Completer<void>();

  @override
  Future<TopicPayload> topic({
    required String siteUrl,
    required String slug,
    required int id,
    int? postNumber,
    bool summary = false,
    String? apiKey,
    String? clientId,
    Future<void>? abortTrigger,
  }) {
    if (!holdTopics) {
      return super.topic(
        siteUrl: siteUrl,
        slug: slug,
        id: id,
        postNumber: postNumber,
        summary: summary,
        apiKey: apiKey,
        clientId: clientId,
        abortTrigger: abortTrigger,
      );
    }
    final response = Completer<TopicPayload>();
    topicRequests.add(response);
    _topicRequestsChanged.complete();
    _topicRequestsChanged = Completer<void>();
    return response.future;
  }

  Future<void> waitForTopicRequests(int count) async {
    while (topicRequests.length < count) {
      await _topicRequestsChanged.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TestFailure(
          'Expected $count topic requests, '
          'but received ${topicRequests.length}.',
        ),
      );
    }
  }

  @override
  Future<List<Post>> posts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    bool includeRaw = false,
    String? apiKey,
    String? clientId,
  }) {
    final request = _PendingPostRequest(List.of(ids));
    postRequests.add(request);
    _postRequestsChanged.complete();
    _postRequestsChanged = Completer<void>();
    return request.response.future;
  }

  @override
  Future<void> deletePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    await deleteGate?.future;
  }

  @override
  Future<Post?> likePost({
    required String siteUrl,
    required String apiKey,
    required int postId,
    String? clientId,
  }) async {
    if (!likeStarted.isCompleted) likeStarted.complete();
    await likeGate?.future;
    return null;
  }

  Future<void> waitForPostRequests(int count) async {
    while (postRequests.length < count) {
      await _postRequestsChanged.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TestFailure(
          'Expected $count post requests, but received ${postRequests.length}.',
        ),
      );
    }
  }
}

final class _OneShotGatedAuthenticator extends FakeAuthenticator {
  bool gateNextRead = false;
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> readGate = Completer<void>();

  @override
  Future<String?> apiKeyFor(String siteUrl) async {
    if (!gateNextRead) return super.apiKeyFor(siteUrl);
    gateNextRead = false;
    readStarted.complete();
    await readGate.future;
    throw StateError('keychain unavailable');
  }
}

/// Answers each tracking snapshot read with a fresh report, or, while
/// [heldSnapshot] is set, with whatever the test completes it with.
final class _TrackingSnapshotApi extends FakeDiscourseApi {
  _TrackingSnapshotApi({super.categoryList, super.feeds})
    : super(user: const DiscourseUser(id: 1, username: 'author'));

  Completer<TopicTrackingState>? heldSnapshot;

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    topicTrackingRequests.add(siteUrl);
    final held = heldSnapshot;
    heldSnapshot = null;
    return held == null ? TopicTrackingState() : held.future;
  }
}

Post _post(
  String cooked, {
  bool canDelete = false,
  bool canLike = false,
  int likeCount = 0,
}) => Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: cooked,
  canDelete: canDelete,
  canLike: canLike,
  likeCount: likeCount,
);

const _reply = Post(id: 2, postNumber: 2, username: 'replier', cooked: 'reply');

const _laterReply = Post(
  id: 3,
  postNumber: 3,
  username: 'replier',
  cooked: 'later',
);

Post _streamPost(int id) =>
    Post(id: id, postNumber: id, username: 'replier', cooked: 'post $id');

const _closedAction = Post(
  id: 2,
  postNumber: 2,
  username: 'author',
  name: 'Author',
  cooked: '',
  postType: Post.smallActionPostType,
  actionCode: 'closed.enabled',
);

TopicList _page(int id) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
);

TopicList _pageOf(List<int> ids) => TopicList(
  topics: [
    for (final id in ids) Topic(id: id, title: 'Topic $id', slug: 'topic-$id'),
  ],
);

Map<String, Object?> _created(int topicId) => {
  'topic_id': topicId,
  'message_type': 'new_topic',
  'payload': {'highest_post_number': 1, 'created_in_new_period': true},
};

Map<String, Object?> _bumped(int topicId) => {
  'topic_id': topicId,
  'message_type': 'latest',
  'payload': {'bumped_at': '2026-09-27T10:00:00Z'},
};

Future<void> _completeFeed(
  _PendingFeedRequest request,
  TopicList response,
) async {
  request.response.complete(response);
  await pumpEventQueue();
}

Future<
  ({ShellController shell, _IncomingOrderingApi api, FakeSiteTracker tracker})
>
_loadIncomingShell() async {
  final api = _IncomingOrderingApi();
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
  );
  await shell.load();
  await api.waitForRequests(1);
  await _completeFeed(api.requests[0], _page(1));
  await pumpEventQueue();
  return (shell: shell, api: api, tracker: FakeSiteTracker.built.single);
}

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  FakeAuthenticator? authenticator,
  InstalledPlugins? plugins,
  DateTime Function()? clock,
}) async {
  final credentials = authenticator ?? FakeAuthenticator();
  credentials.keys[_siteUrl] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'meta.discourse.org',
      ).copyWith(user: const DiscourseUser(id: 1, username: 'author')),
    ]),
    api: api,
    authenticator: credentials,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: plugins ?? installedPlugins,
    clock: clock,
  );
  await shell.load();
  await pumpEventQueue();
  return shell;
}

Future<FakeSiteTracker> _openTopic(ShellController shell) async {
  final tracker = FakeSiteTracker.built.single;
  shell.pushContent(
    ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
  );
  await shell.loadTopic(7, 'a-topic');
  expect(tracker.watchedTopic, 7);
  expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'initial');
  return tracker;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('topic tracking snapshot authority', () {
    const category = TopicCategory(id: 1, name: 'Support', color: '0088CC');
    const unreadInCategory = {
      'topic_id': 7,
      'message_type': 'unread',
      'payload': {
        'highest_post_number': 3,
        'category_id': 1,
        'notification_level': 2,
      },
    };

    test(
      'a live message after a failed snapshot load shows no badge',
      () async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: const DiscourseUser(id: 1, username: 'author'),
          categoryList: const [category],
          trackingStateGate: gate,
        );
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        expect(api.topicTrackingRequests, [_siteUrl]);

        gate.completeError(StateError('tracking unavailable'));
        await pumpEventQueue();
        FakeSiteTracker.built.single.deliverTopicTracking(unreadInCategory);
        await pumpEventQueue();

        expect(shell.sidebarBadgeFor('category-1'), SidebarBadge.none);
      },
    );

    test('the same message after a loaded snapshot shows the badge', () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        user: const DiscourseUser(id: 1, username: 'author'),
        categoryList: const [category],
        trackingStateGate: gate,
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);

      expect(api.topicTrackingRequests, [_siteUrl]);
      gate.complete();
      await pumpEventQueue();
      expect(shell.topicTrackingRevisionFor(_siteUrl), 1);
      FakeSiteTracker.built.single.deliverTopicTracking(unreadInCategory);
      await pumpEventQueue();
      expect(shell.topicTrackingRevisionFor(_siteUrl), 2);

      expect(shell.sidebarBadgeFor('category-1'), isNot(SidebarBadge.none));
    });

    test(
      'a failed snapshot load is retried by the next tracking message',
      () async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: const DiscourseUser(id: 1, username: 'author'),
          categoryList: const [category],
          trackingStateGate: gate,
        );
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        gate.completeError(StateError('tracking unavailable'));
        await pumpEventQueue();
        expect(api.topicTrackingRequests, [_siteUrl]);

        api.trackingStateGate = null;
        FakeSiteTracker.built.single.deliverTopicTracking(unreadInCategory);
        await pumpEventQueue();

        // The message that proved the site reachable is replayed onto the
        // snapshot it triggered, so the badge it describes is not lost to it.
        expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);
        expect(shell.sidebarBadgeFor('category-1'), isNot(SidebarBadge.none));
      },
    );

    test(
      'a failed snapshot load is retried on return to the foreground',
      () async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: const DiscourseUser(id: 1, username: 'author'),
          categoryList: const [category],
          trackingStateGate: gate,
        );
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        gate.completeError(StateError('tracking unavailable'));
        await pumpEventQueue();
        expect(api.topicTrackingRequests, [_siteUrl]);

        api.trackingStateGate = null;
        shell.setForeground(false);
        shell.setForeground(true);
        await pumpEventQueue();
        expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);

        FakeSiteTracker.built.single.deliverTopicTracking(unreadInCategory);
        await pumpEventQueue();
        expect(shell.sidebarBadgeFor('category-1'), isNot(SidebarBadge.none));
      },
    );

    test('a retry that fails again waits for the next trigger', () async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        user: const DiscourseUser(id: 1, username: 'author'),
        categoryList: const [category],
        trackingStateGate: gate,
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      gate.completeError(StateError('tracking unavailable'));
      await pumpEventQueue();

      shell.setForeground(false);
      shell.setForeground(true);
      await pumpEventQueue();
      expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);
      expect(shell.sidebarBadgeFor('category-1'), SidebarBadge.none);

      shell.setForeground(false);
      shell.setForeground(true);
      await pumpEventQueue();
      expect(api.topicTrackingRequests, [_siteUrl, _siteUrl, _siteUrl]);
    });

    test('a run of tracking messages notifies the shell once', () async {
      final api = FakeDiscourseApi(
        user: const DiscourseUser(id: 1, username: 'author'),
        categoryList: const [category],
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      expect(shell.topicTrackingRevisionFor(_siteUrl), 1);

      var notifications = 0;
      shell.addListener(() => notifications++);
      final tracker = FakeSiteTracker.built.single;
      for (var topicId = 7; topicId < 12; topicId++) {
        tracker.deliverTopicTracking({
          ...unreadInCategory,
          'topic_id': topicId,
        });
      }

      // The state is current before the run ends; only the redraw waits.
      expect(shell.topicTrackingRevisionFor(_siteUrl), 6);
      expect(notifications, 0);
      await pumpEventQueue();
      expect(notifications, 1);
    });

    Map<String, Object?> tracked(
      int topicId,
      String type,
      Map<String, Object?> payload,
    ) => {
      'topic_id': topicId,
      'message_type': type,
      'payload': {'category_id': 1, ...payload},
    };

    test('resuming after a long absence re-reads the snapshot', () async {
      var now = DateTime.utc(2026, 9, 26, 23);
      final api = _TrackingSnapshotApi(categoryList: const [category]);
      final shell = await _loadShell(api, clock: () => now);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;
      expect(api.topicTrackingRequests, [_siteUrl]);

      shell.setForeground(false);
      now = now.add(const Duration(hours: 8));
      shell.setForeground(true);
      await pumpEventQueue();

      // Overnight the site kept only each channel's last 100 messages, so the
      // resume poll cannot replay everything the stopped tracker missed.
      expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);
      expect(shell.topicTrackingRevisionFor(_siteUrl), 2);
      expect(tracker.pollNowCalls, 1);
    });

    test('a short app switch leaves tracking to the resume poll', () async {
      var now = DateTime.utc(2026, 9, 27, 9);
      final api = _TrackingSnapshotApi(categoryList: const [category]);
      final shell = await _loadShell(api, clock: () => now);
      addTearDown(shell.dispose);

      for (var switches = 0; switches < 3; switches++) {
        shell.setForeground(false);
        now = now.add(const Duration(seconds: 50));
        shell.setForeground(true);
        await pumpEventQueue();
      }

      // Each absence is judged alone, however many add up.
      expect(api.topicTrackingRequests, [_siteUrl]);
      expect(FakeSiteTracker.built.single.pollNowCalls, 3);
    });

    test('messages replayed during the re-read cannot take it back', () async {
      var now = DateTime.utc(2026, 9, 26, 23);
      final api = _TrackingSnapshotApi(categoryList: const [category]);
      final shell = await _loadShell(api, clock: () => now);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;

      final snapshot = Completer<TopicTrackingState>();
      api.heldSnapshot = snapshot;
      shell.setForeground(false);
      now = now.add(const Duration(hours: 8));
      shell.setForeground(true);
      await pumpEventQueue();
      expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);

      // The resume poll's backlog lands while the report is in flight.
      // These reads were published before the report was taken: replayed
      // onto it, they would lower topic 7's read position and settle
      // topic 8, whose last two replies are still unread.
      tracker
        ..deliverTopicTracking(
          tracked(7, 'read', {
            'last_read_post_number': 4,
            'highest_post_number': 5,
            'notification_level': 2,
          }),
        )
        ..deliverTopicTracking(
          tracked(8, 'read', {
            'last_read_post_number': 6,
            'highest_post_number': 6,
            'notification_level': 2,
          }),
        )
        // Published after the report was taken.
        ..deliverTopicTracking(
          tracked(7, 'unread', {'highest_post_number': 13}),
        )
        ..deliverTopicTracking(
          tracked(9, 'new_topic', {
            'last_read_post_number': null,
            'highest_post_number': 1,
            'created_in_new_period': true,
          }),
        );
      final report = TopicTrackingState([
        const TrackedTopicState(
          topicId: 7,
          highestPostNumber: 12,
          lastReadPostNumber: 10,
          categoryId: 1,
          notificationLevel: 2,
        ),
        const TrackedTopicState(
          topicId: 8,
          highestPostNumber: 8,
          lastReadPostNumber: 6,
          categoryId: 1,
          notificationLevel: 2,
        ),
      ]);
      final revision = shell.topicTrackingRevisionFor(_siteUrl);
      snapshot.complete(report);
      await pumpEventQueue();

      expect(shell.topicTrackingRevisionFor(_siteUrl), revision + 1);
      expect(report.topic(7)?.lastReadPostNumber, 10);
      expect(report.topic(7)?.highestPostNumber, 13);
      expect(report.topic(8)?.lastReadPostNumber, 6);
      expect(report.topic(8)?.highestPostNumber, 8);
      expect(report.topic(9)?.isNew, isTrue);
      expect(shell.categoryActivityCountFor(_siteUrl, 1), 2);
    });

    test('a forum removed during the re-read drops its answer', () async {
      var now = DateTime.utc(2026, 9, 26, 23);
      final api = _TrackingSnapshotApi(categoryList: const [category]);
      final shell = await _loadShell(api, clock: () => now);
      addTearDown(shell.dispose);

      final snapshot = Completer<TopicTrackingState>();
      api.heldSnapshot = snapshot;
      shell.setForeground(false);
      now = now.add(const Duration(hours: 8));
      shell.setForeground(true);
      await pumpEventQueue();
      expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);

      expect(await shell.removeInstance(shell.currentInstance!), isTrue);
      snapshot.complete(
        TopicTrackingState([
          const TrackedTopicState(
            topicId: 7,
            highestPostNumber: 12,
            lastReadPostNumber: 10,
            categoryId: 1,
            notificationLevel: 2,
          ),
        ]),
      );
      await pumpEventQueue();

      expect(shell.instanceFor(_siteUrl), isNull);
      expect(shell.topicTrackingRevisionFor(_siteUrl), 0);
    });

    test('a re-read keeps what it omits out of a loaded unread list', () async {
      var now = DateTime.utc(2026, 9, 26, 23);
      final rows = [
        for (var id = 1; id <= 3; id++)
          Topic(
            id: id,
            title: 'Topic $id',
            slug: 'topic-$id',
            postsCount: 10,
            highestPostNumber: 10,
            lastReadPostNumber: 4,
            unreadPosts: 6,
            newPosts: 6,
            seen: true,
          ),
      ];
      TrackedTopicState unread(int topicId) => TrackedTopicState(
        topicId: topicId,
        highestPostNumber: 10,
        lastReadPostNumber: 4,
        categoryId: 1,
        notificationLevel: 2,
      );
      final api = _TrackingSnapshotApi(
        categoryList: const [category],
        feeds: {'/latest.json': rows, '/unread.json': rows},
      );
      api.heldSnapshot = Completer()
        ..complete(TopicTrackingState([unread(1), unread(2), unread(3)]));
      final shell = await _loadShell(api, clock: () => now);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;
      await shell.selectTopicListMode(TopicListMode.unread);
      expect(shell.currentFeed?.topicIds, [1, 2, 3]);

      tracker.deliverTopicTracking(
        tracked(1, 'read', {
          'last_read_post_number': 10,
          'highest_post_number': 10,
          'notification_level': 2,
        }),
      );
      await pumpEventQueue();
      expect(shell.currentFeed?.topicIds, [2, 3]);

      // Overnight topic 2 was read elsewhere too, and its message fell out of
      // the backlog: the report no longer names either topic.
      api.heldSnapshot = Completer()..complete(TopicTrackingState([unread(3)]));
      shell.setForeground(false);
      now = now.add(const Duration(hours: 8));
      shell.setForeground(true);
      await pumpEventQueue();

      expect(api.topicTrackingRequests, [_siteUrl, _siteUrl]);
      expect(shell.currentFeed?.topicIds, [3]);
      expect(shell.categoryActivityCountFor(_siteUrl, 1), 1);

      tracker.deliverTopicTracking(
        tracked(2, 'unread', {'highest_post_number': 11}),
      );
      await pumpEventQueue();
      expect(shell.currentFeed?.topicIds, [2, 3]);
      expect(shell.categoryActivityCountFor(_siteUrl, 1), 2);
    });
  });

  group('MessageBus bootstrap ordering', () {
    test('installs snapshots before subscribing at their positions', () async {
      const bootstrapUser = DiscourseUser(
        id: 2,
        username: 'author',
        status: UserStatus(
          description: 'Heads down',
          emoji: 'hammer_and_wrench',
          messageBusLastId: 301,
        ),
        doNotDisturbChannelPosition: 302,
      );
      final bootstrap = SiteMessageBusBootstrap(
        currentUser: bootstrapUser,
        currentUserState: const {
          'id': 2,
          'username': 'author',
          'all_unread_notifications_count': 5,
          'new_personal_messages_notifications_count': 2,
          'unseen_reviewable_count': 4,
        },
        topicTrackingState: TopicTrackingState.fromJson(const [
          {
            'topic_id': 7,
            'highest_post_number': 3,
            'last_read_post_number': 1,
            'notification_level': 2,
          },
        ]),
        topicTrackingLastIds: const {
          '/latest': 303,
          '/new': 304,
          '/unread': 305,
          '/unread/2': 306,
          '/delete': 307,
          '/recover': 308,
          '/destroy': 309,
        },
        notificationChannelPosition: 310,
        serverPluginNames: const {'discourse-bbcode-color'},
      );
      final api = FakeDiscourseApi(
        user: bootstrapUser,
        messageBusBootstrapResult: bootstrap,
      );

      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;

      expect(shell.supportsComposerColors(_siteUrl), isTrue);
      expect(shell.supportsComposerColors('https://another.example'), isFalse);

      expect(tracker.initialLastIds, {
        '/latest': 303,
        '/new': 304,
        '/unread': 305,
        '/unread/2': 306,
        '/delete': 307,
        '/recover': 308,
        '/destroy': 309,
        '/notification/2': 310,
        '/user-status': 301,
        '/do-not-disturb/2': 302,
      });
      expect(tracker.topicTrackingLastIds, tracker.initialLastIds);
      expect(api.messageBusBootstrapRequests, [_siteUrl]);
      expect(api.currentUserRequests, isEmpty);
      expect(api.topicTrackingRequests, isEmpty);
      expect(shell.currentInstance?.user?.id, 2);
      expect(shell.freshCurrentUserFor(_siteUrl)?.id, 2);
      expect(shell.topicTrackingRevisionFor(_siteUrl), 1);
      expect(shell.currentTotals?.unreadNotifications, 3);
      expect(shell.currentTotals?.unreadPersonalMessages, 2);
      expect(shell.currentTotals?.unseenReviewables, 4);
    });

    test(
      'falls back when the application document has no current user',
      () async {
        const currentUser = DiscourseUser(id: 1, username: 'author');
        final api = FakeDiscourseApi(user: currentUser);

        final shell = await _loadShell(api);
        addTearDown(shell.dispose);

        expect(api.messageBusBootstrapRequests, [_siteUrl]);
        expect(api.currentUserRequests, [_siteUrl]);
        expect(shell.freshCurrentUserFor(_siteUrl), currentUser);
      },
    );
  });

  group('incoming feed ordering', () {
    test(
      'keeps a newer refresh when an incoming response completes last',
      () async {
        final (:shell, :api, :tracker) = await _loadIncomingShell();
        addTearDown(shell.dispose);

        tracker.deliver(_created(99));
        final incoming = shell.showIncoming('latest');
        await api.waitForRequests(2);
        expect(api.requests[1].path, '/latest.json?topic_ids=99');

        final refresh = shell.loadFeed('latest', force: true);
        await api.waitForRequests(3);
        await _completeFeed(api.requests[2], _page(3));
        await refresh;

        await _completeFeed(api.requests[1], _page(99));
        await incoming;

        expect(shell.currentFeed?.topicIds, [3]);
        expect(shell.store.read<Topic>(_siteUrl, 99), isNull);
      },
    );

    test(
      'keeps a newer request guarded when an older finalizer runs',
      () async {
        final (:shell, :api, :tracker) = await _loadIncomingShell();
        addTearDown(shell.dispose);

        tracker.deliver(_created(99));
        final older = shell.showIncoming('latest');
        await api.waitForRequests(2);

        final refresh = shell.loadFeed('latest', force: true);
        await api.waitForRequests(3);
        await _completeFeed(api.requests[2], _page(3));
        await refresh;

        tracker.deliver(_created(100));
        final newer = shell.showIncoming('latest');
        await api.waitForRequests(4);
        expect(shell.currentFeed?.loadingIncoming, isTrue);

        api.requests[1].response.completeError(
          StateError('old request failed'),
        );
        await older;

        expect(shell.currentFeed?.loadingIncoming, isTrue);
        await shell.showIncoming('latest');
        expect(api.requests, hasLength(4));

        await _completeFeed(api.requests[3], _page(100));
        await newer;
        expect(shell.currentFeed?.topicIds, [100, 3]);
      },
    );

    test('a refresh stops announcing the arrivals its answer lists', () async {
      final (:shell, :api, :tracker) = await _loadIncomingShell();
      addTearDown(shell.dispose);

      // The site answers after topic 3 is created and topic 1 is bumped, but
      // before topic 4 is created, so only topic 4 is still missing.
      final refresh = shell.loadFeed('latest', force: true);
      await api.waitForRequests(2);
      tracker
        ..deliver(_created(3))
        ..deliver(_bumped(1))
        ..deliver(_created(4));
      expect(shell.incomingCount('latest'), 3);
      await _completeFeed(api.requests[1], _pageOf([3, 1]));
      await refresh;

      expect(shell.currentFeed?.topicIds, [3, 1]);
      expect(shell.incomingCount('latest'), 1);

      final incoming = shell.showIncoming('latest');
      await api.waitForRequests(3);
      expect(api.requests[2].path, '/latest.json?topic_ids=4');
      await _completeFeed(api.requests[2], _page(4));
      await incoming;
      expect(shell.currentFeed?.topicIds, [4, 3, 1]);
      expect(shell.incomingCount('latest'), 0);
    });

    test(
      'a failed refresh announces what it withdrew and what arrived meanwhile',
      () async {
        final (:shell, :api, :tracker) = await _loadIncomingShell();
        addTearDown(shell.dispose);

        tracker.deliver(_created(3));
        final refresh = shell.loadFeed('latest', force: true);
        await api.waitForRequests(2);
        expect(shell.incomingCount('latest'), 0);
        tracker.deliver(_created(4));
        api.requests[1].response.completeError(StateError('offline'));
        await refresh;

        expect(shell.currentFeed?.topicIds, [1]);
        expect(shell.currentFeed?.error, isNotNull);
        expect(shell.incomingCount('latest'), 2);
      },
    );

    test('a run of arrivals notifies the shell once', () async {
      final (:shell, api: _, :tracker) = await _loadIncomingShell();
      addTearDown(shell.dispose);

      var notifications = 0;
      shell.addListener(() => notifications++);
      for (var topicId = 20; topicId < 25; topicId++) {
        tracker.deliver(_created(topicId));
      }
      tracker.deliverDelete(const {'topic_id': 20});

      // The count is current before the run ends; only the redraw waits.
      expect(shell.incomingCount('latest'), 4);
      expect(notifications, 0);
      await pumpEventQueue();
      expect(notifications, 1);
    });

    test('a shell disposed during a run of arrivals stays quiet', () async {
      final (:shell, api: _, :tracker) = await _loadIncomingShell();
      var notifications = 0;
      shell.addListener(() => notifications++);

      tracker.deliver(_created(20));
      shell.dispose();
      await pumpEventQueue();

      expect(notifications, 0);
    });
  });

  group('live topic updates', () {
    test('watches a cached topic from its server snapshot', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;
      shell.store.put(
        _siteUrl,
        topicPayload(
          id: 7,
          title: 'A topic',
          posts: [_post('initial')],
          messageBusLastId: 144,
        ).detail,
      );

      shell.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
      );

      expect(tracker.watchedChannelLastIds['/topic/7'], 144);
    });

    test('commits only the newest post refresh', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);

      tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 1});
      await api.waitForPostRequests(1);
      tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 1});
      await pumpEventQueue();
      expect(api.postRequests, hasLength(1));

      api.postRequests[0].response.complete([_post('older')]);
      await api.waitForPostRequests(2);
      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'initial');

      api.postRequests[1].response.complete([_post('newer')]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'newer');
    });

    Future<
      ({ShellController shell, _PostOrderingApi api, FakeSiteTracker tracker})
    >
    openWithHeldPosts(int count, {Completer<void>? likeGate}) async {
      final api = _PostOrderingApi(likeGate: likeGate);
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [
          _post('initial', canLike: true),
          for (var id = 2; id <= count; id++) _streamPost(id),
        ],
      );
      final tracker = await _openTopic(shell);
      for (var id = 1; id <= count; id++) {
        expect(shell.store.read<Post>(_siteUrl, id), isNotNull);
      }
      return (shell: shell, api: api, tracker: tracker);
    }

    Post reread(int id) =>
        Post(id: id, postNumber: id, username: 'replier', cooked: 'read $id');

    test('reads the posts one poll answer names in one request', () async {
      final (:shell, :api, :tracker) = await openWithHeldPosts(5);

      // Core's own post messages beside a feature's, in one delivered run.
      tracker
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 3})
        ..deliverTopicMessage('/topic/7', const {'type': 'revised', 'id': 1})
        ..deliverTopicMessage('/topic/7/reactions', {'post_id': 5})
        ..deliverTopicMessage('/topic/7', const {'type': 'acted', 'id': 2});
      await api.waitForPostRequests(1);
      await pumpEventQueue();

      expect(api.postRequests.single.ids, [3, 1, 5, 2]);
      api.postRequests.single.response.complete([
        for (final id in const [1, 2, 3, 5]) reread(id),
      ]);
      await pumpEventQueue();

      for (final id in const [1, 2, 3, 5]) {
        expect(shell.store.read<Post>(_siteUrl, id)?.cooked, 'read $id');
      }
      expect(shell.store.read<Post>(_siteUrl, 4)?.cooked, 'post 4');
      expect(api.postRequests, hasLength(1));
    });

    test('reads a post one poll answer names twice once', () async {
      final (:shell, :api, :tracker) = await openWithHeldPosts(1);

      tracker
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'revised', 'id': 1})
        ..deliverTopicMessage('/topic/7/reactions', {'post_id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 1});
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete([reread(1)]);
      await pumpEventQueue();

      expect(api.postRequests.single.ids, [1]);
      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'read 1');
    });

    test("reads a long answer's posts twenty at a time", () async {
      final (:shell, :api, :tracker) = await openWithHeldPosts(25);

      for (var id = 1; id <= 25; id++) {
        tracker.deliverTopicMessage('/topic/7', {'type': 'liked', 'id': id});
      }
      await api.waitForPostRequests(2);
      await pumpEventQueue();

      expect(
        [for (final request in api.postRequests) request.ids],
        [
          [for (var id = 1; id <= 20; id++) id],
          [21, 22, 23, 24, 25],
        ],
      );
      for (final request in api.postRequests) {
        request.response.complete([for (final id in request.ids) reread(id)]);
      }
      await pumpEventQueue();

      for (var id = 1; id <= 25; id++) {
        expect(shell.store.read<Post>(_siteUrl, id)?.cooked, 'read $id');
      }
      expect(api.postRequests, hasLength(2));
    });

    test('reads a post named while its read is out once more', () async {
      final (:shell, :api, :tracker) = await openWithHeldPosts(2);

      tracker
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 2});
      await api.waitForPostRequests(1);
      expect(api.postRequests.single.ids, [1, 2]);

      // The read that is out may have been answered before any of these.
      tracker
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'revised', 'id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 1});
      await pumpEventQueue();
      expect(api.postRequests, hasLength(1));

      api.postRequests[0].response.complete([_post('older'), reread(2)]);
      await api.waitForPostRequests(2);
      await pumpEventQueue();
      expect(api.postRequests[1].ids, [1]);
      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'initial');
      expect(shell.store.read<Post>(_siteUrl, 2)?.cooked, 'read 2');

      api.postRequests[1].response.complete([_post('newer')]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'newer');
      expect(api.postRequests, hasLength(2));
    });

    test('leaves a queued post a write takes to the write', () async {
      final likeGate = Completer<void>();
      final (:shell, :api, :tracker) = await openWithHeldPosts(
        2,
        likeGate: likeGate,
      );
      final post = shell.store.read<Post>(_siteUrl, 1)!;

      // The reader likes the first post before the run's read leaves.
      tracker
        ..deliverTopicMessage('/topic/7', const {'type': 'revised', 'id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'revised', 'id': 2});
      final liking = shell.toggleLike(post);
      await api.waitForPostRequests(1);
      await pumpEventQueue();
      expect(api.postRequests.single.ids, [2]);

      api.postRequests.single.response.complete([reread(2)]);
      await pumpEventQueue();
      expect(shell.store.read<Post>(_siteUrl, 1)?.liked, isTrue);

      likeGate.complete();
      expect(await liking, isNull);
      await api.waitForPostRequests(2);
      expect(api.postRequests[1].ids, [1]);
      api.postRequests[1].response.complete([
        _post('edited', canLike: true, likeCount: 1),
      ]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'edited');
      expect(shell.store.read<Post>(_siteUrl, 2)?.cooked, 'read 2');
      expect(api.postRequests, hasLength(2));
    });

    test('a deletion read beside other posts drops only its post', () async {
      final api = _PostOrderingApi();
      // Core's own handling only: the Topic Calendar also reads the stream
      // again after a deletion.
      final plugins = PluginInstaller.install(const PluginManifest([]));
      addTearDown(plugins.close);
      final shell = await _loadShell(api, plugins: plugins);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), _reply],
      );
      final tracker = await _openTopic(shell);

      tracker
        ..deliverTopicMessage('/topic/7', const {'type': 'revised', 'id': 1})
        ..deliverTopicMessage('/topic/7', const {'type': 'deleted', 'id': 2});
      await api.waitForPostRequests(1);
      await pumpEventQueue();
      expect(api.postRequests.single.ids, [1, 2]);

      api.postRequests.single.response.complete([_post('edited')]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'edited');
      expect(shell.store.read<Post>(_siteUrl, 2), isNull);
      expect(shell.currentTopic?.stream, [1]);
      expect(api.topicsOpened, [7]);
      expect(api.postRequests, hasLength(1));
    });

    test('reveals a closed-topic small action from a created event', () async {
      final topics = <int, TopicPayload>{
        7: topicPayload(id: 7, title: 'A topic', posts: [_post('initial')]),
      };
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [Topic(id: 7, title: 'A topic', slug: 'a-topic')],
        },
        topics: topics,
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      expect(tracker.watchedChannels.first, '/topic/7');

      topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), _closedAction],
        closed: true,
      );
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'created',
        'id': 2,
      });
      await pumpEventQueue();

      expect(api.topicsOpened, [7, 7]);
      expect(shell.currentTopic?.stream, [1, 2]);
      expect(shell.store.read<Post>(_siteUrl, 2), _closedAction);
      expect(shell.store.read<Post>(_siteUrl, 2)?.isSmallAction, isTrue);
      expect(shell.store.read<Post>(_siteUrl, 2)?.actionCode, 'closed.enabled');
    });

    test('waits for an active delete before refreshing', () async {
      final deleteGate = Completer<void>();
      final api = _PostOrderingApi(deleteGate: deleteGate);
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      final post = shell.store.read<Post>(_siteUrl, 1)!;

      final deleting = shell.deletePost(post);
      await api.deleteStarted.future;
      tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 1});
      await pumpEventQueue();

      expect(api.postRequests, isEmpty);

      deleteGate.complete();
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete([_post('deleted')]);
      await deleting;

      expect(api.postRequests.single.ids, [1]);
    });

    test('does not overwrite an active write with an older read', () async {
      final likeGate = Completer<void>();
      final api = _PostOrderingApi(likeGate: likeGate);
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      final post = shell.store.read<Post>(_siteUrl, 1)!.copyWith(canLike: true);
      shell.store.put(_siteUrl, post);

      tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 1});
      await api.waitForPostRequests(1);

      final liking = shell.toggleLike(post);
      await api.likeStarted.future;
      api.postRequests.single.response.complete([
        _post('stale', canLike: true),
      ]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.liked, isTrue);

      likeGate.complete();
      expect(await liking, isNull);
      expect(shell.store.read<Post>(_siteUrl, 1)?.liked, isTrue);
    });

    test('a failed like keeps the count a refetch brought', () async {
      final likeGate = Completer<void>();
      final api = _PostOrderingApi(likeGate: likeGate);
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      final post = shell.store.read<Post>(_siteUrl, 1)!.copyWith(canLike: true);
      shell.store.put(_siteUrl, post);

      final liking = shell.toggleLike(post);
      await api.likeStarted.future;
      expect(shell.store.read<Post>(_siteUrl, 1)?.likeCount, 1);

      // Other readers liked the post while the request was out, and a new
      // reply's refetch brought their count before the site answered.
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial', canLike: true, likeCount: 5)],
      );
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'created',
        'id': 2,
      });
      await pumpEventQueue();
      expect(shell.store.read<Post>(_siteUrl, 1)?.likeCount, 5);

      likeGate.completeError(StateError('like lost'));
      expect(await liking, isNotNull);

      expect(shell.store.read<Post>(_siteUrl, 1)?.likeCount, 5);
      expect(shell.store.read<Post>(_siteUrl, 1)?.liked, isFalse);
    });

    test(
      'does not overwrite a bookmark bulk delete with an older read',
      () async {
        final api = _PostOrderingApi();
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        final tracker = await _openTopic(shell);
        final bookmark = Bookmark(
          id: 5,
          bookmarkableId: 1,
          bookmarkableType: BookmarkTargetType.post.wireName,
        );
        shell.store.put(
          _siteUrl,
          shell.store.read<Post>(_siteUrl, 1)!.withBookmark(bookmark),
        );
        shell.store.put(
          _siteUrl,
          shell.store.read<TopicDetail>(_siteUrl, 7)!.withBookmark(bookmark),
        );

        tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 1});
        await api.waitForPostRequests(1);

        final deleting = shell.deleteAllTopicBookmarks(
          siteUrl: _siteUrl,
          topicId: 7,
        );
        expect((await deleting).saved, isTrue);
        expect(shell.store.read<Post>(_siteUrl, 1)?.bookmark, isNull);

        // The read that was already out is disowned by the write and replayed
        // once it ends; its pre-delete answer must not bring the ribbon back.
        await api.waitForPostRequests(2);
        api.postRequests[0].response.complete([
          _post('stale').withBookmark(bookmark),
        ]);
        await pumpEventQueue();
        expect(shell.store.read<Post>(_siteUrl, 1)?.bookmark, isNull);

        api.postRequests[1].response.complete([_post('fresh')]);
        await pumpEventQueue();
        expect(shell.store.read<Post>(_siteUrl, 1)?.bookmark, isNull);
      },
    );

    test('re-reads a post core says changed', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);

      const types = ['revised', 'rebaked', 'acted', 'liked', 'unliked'];
      for (final (index, type) in types.indexed) {
        tracker.deliverTopicMessage('/topic/7', {'type': type, 'id': 1});
        await api.waitForPostRequests(index + 1);
        expect(api.postRequests[index].ids, [1], reason: type);
        api.postRequests[index].response.complete([_post(type)]);
        await pumpEventQueue();
        expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, type);
      }

      expect(api.postRequests, hasLength(types.length));
      expect(api.topicsOpened, [7]);
    });

    test('replays a revision a cached topic missed', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;
      final cached = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial')],
        messageBusLastId: 144,
      );
      shell.store.put(_siteUrl, cached.detail);
      shell.store.putAll(_siteUrl, cached.posts);

      shell.pushContent(
        ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
      );
      await shell.loadTopic(7, 'a-topic');
      expect(api.topicsOpened, isEmpty);
      expect(tracker.watchedChannelLastIds['/topic/7'], 144);

      // Resuming after 144 brings back the edit made while it was closed.
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'revised',
        'id': 1,
      });
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete([_post('edited')]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'edited');
      expect(api.topicsOpened, isEmpty);
    });

    test('waits for an active like before re-reading a liked post', () async {
      final likeGate = Completer<void>();
      final api = _PostOrderingApi(likeGate: likeGate);
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      final post = shell.store.read<Post>(_siteUrl, 1)!.copyWith(canLike: true);
      shell.store.put(_siteUrl, post);

      final liking = shell.toggleLike(post);
      await api.likeStarted.future;
      tracker.deliverTopicMessage('/topic/7', const {'type': 'liked', 'id': 1});
      await pumpEventQueue();

      expect(api.postRequests, isEmpty);
      expect(shell.store.read<Post>(_siteUrl, 1)?.likeCount, 1);

      likeGate.complete();
      expect(await liking, isNull);
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete([
        _post('initial', likeCount: 2),
      ]);
      await pumpEventQueue();

      expect(api.postRequests.single.ids, [1]);
      expect(shell.store.read<Post>(_siteUrl, 1)?.likeCount, 2);
    });

    test('does not read a post it does not hold', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);

      for (final message in const <Map<String, Object?>>[
        {'type': 'revised', 'id': 99},
        {'type': 'revised', 'id': '1'},
        {'type': 'revised', 'id': -1},
        {'type': 'revised'},
        {'type': 'read', 'id': 1},
      ]) {
        tracker.deliverTopicMessage('/topic/7', message);
      }
      await pumpEventQueue();

      expect(api.postRequests, isEmpty);
      expect(api.topicsOpened, [7]);
    });

    test('leaves a post named by a topic reload to that reload', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);

      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'revised',
        'id': 1,
        'reload_topic': true,
      });
      await pumpEventQueue();

      expect(api.topicsOpened, [7, 7]);
      expect(api.postRequests, isEmpty);
    });

    test('a topic reload carries a rename to the open route', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);

      api.topics[7] = topicPayload(
        id: 7,
        title: 'A renamed topic',
        posts: [_post('initial')],
      );
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'revised',
        'id': 1,
        'reload_topic': true,
      });
      await pumpEventQueue();

      expect(api.topicsOpened, [7, 7]);
      expect(shell.currentTopic?.title, 'A renamed topic');
      expect(shell.currentContent?.title, 'A renamed topic');
    });

    test('keeps a deleted post the reader can still see', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), _reply],
      );
      final tracker = await _openTopic(shell);
      final deletedAt = DateTime.utc(2026, 9, 27);

      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'deleted',
        'id': 2,
      });
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete([
        Post(
          id: 2,
          postNumber: 2,
          username: 'replier',
          cooked: 'reply',
          deletedAt: deletedAt,
        ),
      ]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 2)?.deletedAt, deletedAt);
      expect(shell.currentTopic?.stream, [1, 2]);

      // Only a deletion's own re-read takes an omission as removal.
      tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 2});
      await api.waitForPostRequests(2);
      api.postRequests[1].response.complete(const []);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 2)?.deletedAt, deletedAt);
      expect(shell.currentTopic?.stream, [1, 2]);
    });

    test('drops a post deleted while an earlier re-read was out', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), _reply],
      );
      final tracker = await _openTopic(shell);

      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'revised',
        'id': 2,
      });
      await api.waitForPostRequests(1);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial')],
      );
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'deleted',
        'id': 2,
      });
      await pumpEventQueue();

      // The edit's read left before the deletion, so its answer cannot stand.
      api.postRequests[0].response.complete([_reply]);
      await api.waitForPostRequests(2);
      expect(shell.currentTopic?.stream, [1, 2]);

      api.postRequests[1].response.complete(const []);
      await pumpEventQueue();

      expect(api.postRequests[1].ids, [2]);
      expect(shell.store.read<Post>(_siteUrl, 2), isNull);
      expect(shell.currentTopic?.stream, [1]);
    });

    for (final type in const ['deleted', 'destroyed']) {
      test('drops a $type post the site no longer returns', () async {
        final api = _PostOrderingApi();
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        api.topics[7] = topicPayload(
          id: 7,
          title: 'A topic',
          posts: [_post('initial'), _reply],
        );
        final tracker = await _openTopic(shell);
        expect(shell.currentTopic?.stream, [1, 2]);

        // A reader who cannot see deleted posts is answered without it, both
        // by id and in any stream read after the deletion.
        api.topics[7] = topicPayload(
          id: 7,
          title: 'A topic',
          posts: [_post('initial')],
        );
        tracker.deliverTopicMessage('/topic/7', {'type': type, 'id': 2});
        await api.waitForPostRequests(1);
        await pumpEventQueue();
        api.postRequests.single.response.complete(const []);
        await pumpEventQueue();

        expect(api.postRequests.single.ids, [2]);
        expect(shell.store.read<Post>(_siteUrl, 2), isNull);
        expect(shell.currentTopic?.stream, [1]);
      });
    }

    test('re-reads a recovered post it still holds', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [
          _post('initial'),
          Post(
            id: 2,
            postNumber: 2,
            username: 'replier',
            cooked: 'reply',
            deletedAt: DateTime.utc(2026, 9, 27),
          ),
        ],
      );
      final tracker = await _openTopic(shell);

      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'recovered',
        'id': 2,
      });
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete([_reply]);
      await pumpEventQueue();

      expect(api.postRequests.single.ids, [2]);
      expect(shell.store.read<Post>(_siteUrl, 2)?.deletedAt, isNull);
      expect(shell.currentTopic?.stream, [1, 2]);
    });

    test('reads the stream again for a recovered post it dropped', () async {
      final api = _PostOrderingApi();
      // Core owns this without any bundled feature asking for the topic.
      final plugins = PluginInstaller.install(const PluginManifest([]));
      addTearDown(plugins.close);
      final shell = await _loadShell(api, plugins: plugins);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);

      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), _reply],
      );
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'recovered',
        'id': 2,
      });
      await pumpEventQueue();

      expect(api.topicsOpened, [7, 7]);
      expect(api.postRequests, isEmpty);
      expect(shell.currentTopic?.stream, [1, 2]);
      expect(shell.store.read<Post>(_siteUrl, 2), _reply);
    });

    Future<
      ({ShellController shell, _PostOrderingApi api, FakeSiteTracker tracker})
    >
    openWithHeldStreamRead(Post reply, {bool forced = false}) async {
      final api = _PostOrderingApi();
      // Core's own handling only: the Topic Calendar also reads the stream
      // again after a deletion, and that later read is not the race.
      final plugins = PluginInstaller.install(const PluginManifest([]));
      addTearDown(plugins.close);
      final shell = await _loadShell(api, plugins: plugins);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), reply],
      );
      final tracker = await _openTopic(shell);
      expect(shell.currentTopic?.stream, [1, 2]);

      api.holdTopics = true;
      if (forced) {
        unawaited(shell.loadTopic(7, 'a-topic', force: true));
      } else {
        tracker.deliverTopicMessage('/topic/7', const {
          'type': 'created',
          'id': 3,
        });
      }
      await api.waitForTopicRequests(1);
      return (shell: shell, api: api, tracker: tracker);
    }

    // What a stream read that left before the deletion answers with.
    TopicPayload beforeDeletion(Post reply) => topicPayload(
      id: 7,
      title: 'A topic',
      posts: [_post('refetched'), reply, _laterReply],
    );

    Future<void> deliverDeletion(
      _PostOrderingApi api,
      FakeSiteTracker tracker,
    ) async {
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'deleted',
        'id': 2,
      });
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete(const []);
      await pumpEventQueue();
    }

    for (final forced in const [false, true]) {
      final read = forced ? 'a forced reload' : 'a live refetch';
      test('$read from before a deletion does not restore the post', () async {
        final (:shell, :api, :tracker) = await openWithHeldStreamRead(
          _reply,
          forced: forced,
        );
        await deliverDeletion(api, tracker);
        expect(shell.store.read<Post>(_siteUrl, 2), isNull);
        expect(shell.currentTopic?.stream, [1]);

        api.topicRequests.single.complete(beforeDeletion(_reply));
        await pumpEventQueue();

        expect(shell.store.read<Post>(_siteUrl, 2), isNull);
        expect(shell.currentTopic?.stream, [1, 3]);
        expect(shell.currentTopic?.postsCount, 2);
        // The rest of that answer still stands.
        expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'refetched');
        expect(shell.store.read<Post>(_siteUrl, 3), _laterReply);
      });
    }

    test(
      'a stream read from before the reader deleted a post does not restore it',
      () async {
        const reply = Post(
          id: 2,
          postNumber: 2,
          username: 'author',
          cooked: 'reply',
          canDelete: true,
        );
        final (:shell, :api, tracker: _) = await openWithHeldStreamRead(reply);

        final deleting = shell.deletePost(reply);
        await api.waitForPostRequests(1);
        api.postRequests.single.response.complete(const []);
        expect(await deleting, isNull);
        expect(shell.store.read<Post>(_siteUrl, 2), isNull);
        expect(shell.currentTopic?.stream, [1]);

        api.topicRequests.single.complete(beforeDeletion(reply));
        await pumpEventQueue();

        expect(shell.store.read<Post>(_siteUrl, 2), isNull);
        expect(shell.currentTopic?.stream, [1, 3]);
      },
    );

    test('a read after the deletion restores a recovered post', () async {
      final (:shell, :api, :tracker) = await openWithHeldStreamRead(_reply);
      await deliverDeletion(api, tracker);

      // The recovery's own stream read waits behind the one already out.
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'recovered',
        'id': 2,
      });
      await pumpEventQueue();
      expect(api.topicRequests, hasLength(1));

      api.topicRequests[0].complete(beforeDeletion(_reply));
      await api.waitForTopicRequests(2);
      expect(shell.currentTopic?.stream, [1, 3]);

      api.topicRequests[1].complete(
        topicPayload(
          id: 7,
          title: 'A topic',
          posts: [_post('initial'), _reply, _laterReply],
        ),
      );
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 2), _reply);
      expect(shell.currentTopic?.stream, [1, 2, 3]);
      expect(shell.currentTopic?.postsCount, 3);
    });

    test('takes the totals core publishes without reading again', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), _reply],
      );
      final tracker = await _openTopic(shell);
      expect(shell.store.read<Topic>(_siteUrl, 7)?.postsCount, 2);

      // What core sends after a like, then after a reply.
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'stats',
        'id': 7,
        'like_count': 4,
      });
      expect(shell.currentTopic?.likeCount, 4);
      expect(shell.currentTopic?.postsCount, 2);
      expect(shell.store.read<Topic>(_siteUrl, 7)?.likeCount, 4);

      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'stats',
        'id': 7,
        'posts_count': 3,
        'last_posted_at': '2026-09-27T12:00:00.000Z',
        'last_poster': {'id': 2, 'username': 'replier'},
      });
      await pumpEventQueue();

      expect(shell.currentTopic?.postsCount, 3);
      expect(shell.currentTopic?.replyCount, 2);
      expect(shell.currentTopic?.likeCount, 4);
      final row = shell.store.read<Topic>(_siteUrl, 7);
      expect(row?.postsCount, 3);
      expect(row?.likeCount, 4);
      expect(api.topicsOpened, [7]);
      expect(api.postRequests, isEmpty);
    });

    test('a run of stats messages notifies the shell once', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      await pumpEventQueue();

      var notifications = 0;
      shell.addListener(() => notifications++);
      for (var likes = 1; likes <= 5; likes++) {
        tracker.deliverTopicMessage('/topic/7', {
          'type': 'stats',
          'id': 7,
          'like_count': likes,
        });
      }

      // The totals are current before the run ends; only the redraw waits.
      expect(shell.currentTopic?.likeCount, 5);
      expect(shell.store.read<Topic>(_siteUrl, 7)?.likeCount, 5);
      expect(notifications, 0);
      await pumpEventQueue();
      expect(notifications, 1);
    });

    test('ignores stats totals that are not counts', () async {
      final api = _PostOrderingApi();
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      final topic = shell.currentTopic;
      final row = shell.store.read<Topic>(_siteUrl, 7);
      expect(row, isNotNull);

      for (final value in const <Object?>[
        '4',
        4.5,
        -1,
        true,
        null,
        {'count': 4},
      ]) {
        tracker.deliverTopicMessage('/topic/7', {
          'type': 'stats',
          'like_count': value,
          'posts_count': value,
        });
      }
      tracker.deliverTopicMessage('/topic/7', const {'type': 'stats'});
      tracker.deliverTopicMessage('/topic/7', const {
        'like_count': 4,
        'posts_count': 4,
      });
      await pumpEventQueue();

      expect(shell.currentTopic, same(topic));
      expect(shell.store.read<Topic>(_siteUrl, 7), same(row));
      expect(api.topicsOpened, [7]);
      expect(api.postRequests, isEmpty);
    });

    for (final visible in const [false, true]) {
      final reader = visible ? 'still sees' : 'no longer sees';
      test('a deletion the reader $reader lowers the total once', () async {
        final api = _PostOrderingApi();
        // Core's own handling only: the Topic Calendar also reads the stream
        // again after a deletion.
        final plugins = PluginInstaller.install(const PluginManifest([]));
        addTearDown(plugins.close);
        final shell = await _loadShell(api, plugins: plugins);
        addTearDown(shell.dispose);
        api.topics[7] = topicPayload(
          id: 7,
          title: 'A topic',
          posts: [_post('initial'), _reply],
        );
        final tracker = await _openTopic(shell);
        expect(shell.currentTopic?.postsCount, 2);

        // Core announces the deletion, then the totals that already omit it.
        tracker.deliverTopicMessage('/topic/7', const {
          'type': 'deleted',
          'id': 2,
        });
        tracker.deliverTopicMessage('/topic/7', const {
          'type': 'stats',
          'id': 7,
          'posts_count': 1,
        });
        await api.waitForPostRequests(1);
        api.postRequests.single.response.complete([
          if (visible)
            Post(
              id: 2,
              postNumber: 2,
              username: 'replier',
              cooked: 'reply',
              deletedAt: DateTime.utc(2026, 9, 27),
            ),
        ]);
        await pumpEventQueue();

        expect(shell.currentTopic?.stream, visible ? [1, 2] : [1]);
        expect(shell.currentTopic?.postsCount, 1);
        expect(shell.store.read<Topic>(_siteUrl, 7)?.postsCount, 1);
        expect(api.topicsOpened, [7]);
      });
    }

    test('a permanent deletion keeps the total core sends for it', () async {
      final deletedReply = Post(
        id: 2,
        postNumber: 2,
        username: 'replier',
        cooked: 'reply',
        deletedAt: DateTime.utc(2026, 9, 27),
        canPermanentlyDelete: true,
      );
      final api = _PostOrderingApi();
      final plugins = PluginInstaller.install(const PluginManifest([]));
      addTearDown(plugins.close);
      final shell = await _loadShell(api, plugins: plugins);
      addTearDown(shell.dispose);
      // Core stopped counting the post when it was deleted; staff still see it.
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A topic',
        posts: [_post('initial'), deletedReply],
        postsCount: 1,
      );
      final tracker = await _openTopic(shell);

      final deleting = shell.permanentlyDeletePost(
        shell.capturePostPermanentDeleteTarget(
          siteUrl: _siteUrl,
          topicId: 7,
          post: deletedReply,
        ),
      );
      // Core tells every reader while the deleting one's own re-read, which is
      // what takes the post out, is still out.
      await api.waitForPostRequests(1);
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'destroyed',
        'id': 2,
      });
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'stats',
        'id': 7,
        'posts_count': 1,
      });
      api.postRequests.single.response.complete(const []);
      expect(await deleting, isNull);
      await pumpEventQueue();

      expect(shell.currentTopic?.stream, [1]);
      expect(shell.currentTopic?.postsCount, 1);
      expect(shell.store.read<Topic>(_siteUrl, 7)?.postsCount, 1);
      expect(api.postRequests, hasLength(1));
    });
  });

  group('posts the site no longer serves', () {
    // The stream was read before a moderator deleted one of its posts, and
    // this reader cannot see deleted posts: reading it by id leaves it out.
    final stream = [for (var id = 1; id <= 45; id++) id];
    List<int> without(int omitted) => [
      for (final id in stream)
        if (id != omitted) id,
    ];

    Future<
      ({ShellController shell, FakeDiscourseApi api, FakeSiteTracker tracker})
    >
    openPartly(
      Iterable<int> loaded, {
      required int omitted,
      int? postNumber,
    }) async {
      final api = FakeDiscourseApi(
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A topic',
            posts: [for (final id in loaded) _streamPost(id)],
            stream: stream,
            postsCount: stream.length,
          ),
        },
        postsById: {for (final id in without(omitted)) id: _streamPost(id)},
      );
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      shell.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'a-topic',
          title: 'A topic',
          postNumber: postNumber,
        ),
      );
      await shell.loadTopic(7, 'a-topic', postNumber: postNumber);
      return (shell: shell, api: api, tracker: FakeSiteTracker.built.single);
    }

    test('pages forward past a post the site leaves out', () async {
      final (:shell, :api, tracker: _) = await openPartly([
        for (var id = 1; id <= 20; id++) id,
      ], omitted: 25);
      expect(shell.currentTopicHasMore, isTrue);

      await shell.loadMorePosts();
      await shell.loadMorePosts();
      await shell.loadMorePosts();

      expect(api.postFetches, [
        [for (var id = 21; id <= 40; id++) id],
        [41, 42, 43, 44, 45],
      ]);
      expect(shell.currentTopic?.stream, without(25));
      expect(shell.currentTopic?.postsCount, 44);
      expect(shell.currentPostIds, without(25));
      expect(shell.currentTopicHasMore, isFalse);
    });

    test('pages back past a post the site leaves out', () async {
      final (:shell, :api, tracker: _) = await openPartly(
        [for (var id = 26; id <= 45; id++) id],
        omitted: 22,
        postNumber: 40,
      );
      expect(shell.currentTopicHasEarlier, isTrue);

      await shell.loadEarlierPosts();
      await shell.loadEarlierPosts();
      await shell.loadEarlierPosts();

      expect(api.postFetches, [
        [for (var id = 6; id <= 25; id++) id],
        [1, 2, 3, 4, 5],
      ]);
      expect(shell.currentTopic?.stream, without(22));
      expect(shell.currentTopic?.postsCount, 44);
      expect(shell.currentPostIds, without(22));
      expect(shell.currentTopicHasEarlier, isFalse);
    });

    for (final pagedPast in const [true, false]) {
      final when = pagedPast ? 'after paging past' : 'before paging reaches';
      test('a refetch $when the post keeps it out of the stream', () async {
        final (:shell, :api, :tracker) = await openPartly([
          for (var id = 1; id <= 20; id++) id,
        ], omitted: 25);
        if (pagedPast) {
          await shell.loadMorePosts();
          await shell.loadMorePosts();
        }

        // A reply arrives, and the site's stream no longer has the post.
        final current = [...without(25), 46];
        api.topics[7] = topicPayload(
          id: 7,
          title: 'A topic',
          posts: [for (var id = 1; id <= 20; id++) _streamPost(id)],
          stream: current,
          postsCount: current.length,
        );
        api.postsById[46] = _streamPost(46);
        tracker.deliverTopicMessage('/topic/7', const {
          'type': 'created',
          'id': 46,
        });
        await pumpEventQueue();

        expect(shell.currentTopic?.stream, current);
        expect(shell.currentTopic?.postsCount, current.length);

        await shell.loadMorePosts();
        await shell.loadMorePosts();

        expect(shell.currentPostIds, current);
        expect(shell.currentTopicHasMore, isFalse);
      });
    }

    for (final stored in const [true, false]) {
      final read = stored ? 'stored' : 'still out';
      test(
        'a page does not drop a post a recovery read $read restores',
        () async {
          final api = _PostOrderingApi();
          // Core's own handling only, so the recovery starts one stream read.
          final plugins = PluginInstaller.install(const PluginManifest([]));
          addTearDown(plugins.close);
          final shell = await _loadShell(api, plugins: plugins);
          addTearDown(shell.dispose);
          final recovered = [for (var id = 1; id <= 30; id++) id];
          TopicPayload snapshot() => topicPayload(
            id: 7,
            title: 'A topic',
            posts: [_post('initial'), _reply],
            stream: recovered,
            postsCount: recovered.length,
          );
          api.topics[7] = snapshot();
          final tracker = await _openTopic(shell);

          final paging = shell.loadMorePosts();
          await api.waitForPostRequests(1);
          expect(api.postRequests.single.ids, [
            for (var id = 3; id <= 22; id++) id,
          ]);

          // The page is served while post 10 is deleted, and answers only after
          // the post's recovery started a stream read.
          api.holdTopics = !stored;
          tracker.deliverTopicMessage('/topic/7', const {
            'type': 'recovered',
            'id': 10,
          });
          if (stored) {
            await pumpEventQueue();
            expect(api.topicsOpened, [7, 7]);
          } else {
            await api.waitForTopicRequests(1);
          }
          api.postRequests.single.response.complete([
            for (var id = 3; id <= 22; id++)
              if (id != 10) _streamPost(id),
          ]);
          await paging;
          if (!stored) {
            api.topicRequests.single.complete(snapshot());
            await pumpEventQueue();
          }

          expect(shell.currentTopic?.stream, recovered);
          expect(shell.currentPostIds, [for (var id = 1; id <= 9; id++) id]);
          expect(shell.currentTopicHasMore, isTrue);
        },
      );
    }
  });

  group('top replies', () {
    final replies = [for (var id = 1; id <= 10; id++) id];
    const summarized = [1, 3, 5, 7, 9];

    Future<({ShellController shell, FakeSiteTracker tracker})> openSummarized(
      FakeDiscourseApi api,
    ) async {
      // Core's own handling only, so a deletion starts no stream read.
      final plugins = PluginInstaller.install(const PluginManifest([]));
      addTearDown(plugins.close);
      final shell = await _loadShell(api, plugins: plugins);
      addTearDown(shell.dispose);
      final tracker = await _openTopic(shell);
      return (shell: shell, tracker: tracker);
    }

    TopicPayload topic(Iterable<int> ids) => topicPayload(
      id: 7,
      title: 'A topic',
      posts: [
        for (final id in ids) id == 1 ? _post('initial') : _streamPost(id),
      ],
      hasSummary: true,
    );

    test('a removed post leaves the top replies stream', () async {
      final api = FakeDiscourseApi(
        topics: {7: topic(replies)},
        summaryTopics: {7: topic(summarized)},
        // This reader cannot see post 5 once it is deleted.
        postsById: {
          for (final id in replies)
            if (id != 5) id: _streamPost(id),
        },
      );
      final (:shell, :tracker) = await openSummarized(api);
      await shell.toggleTopicSummary();
      expect(shell.currentPostIds, summarized);

      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'deleted',
        'id': 5,
      });
      await pumpEventQueue();

      expect(shell.currentPostIds, [1, 3, 7, 9]);
      expect(shell.currentTopicHasMore, isFalse);

      await shell.toggleTopicSummary();
      expect(shell.currentTopicSummary, isFalse);
      expect(shell.currentPostIds, [1, 2, 3, 4, 6, 7, 8, 9, 10]);
    });

    test('a top replies read from before a removal does not restore '
        'the post', () async {
      final api = _PostOrderingApi();
      api.topics[7] = topic(replies);
      final (:shell, :tracker) = await openSummarized(api);

      api.holdTopics = true;
      final summarizing = shell.toggleTopicSummary();
      await api.waitForTopicRequests(1);
      tracker.deliverTopicMessage('/topic/7', const {
        'type': 'deleted',
        'id': 5,
      });
      await api.waitForPostRequests(1);
      api.postRequests.single.response.complete(const []);
      await pumpEventQueue();
      expect(shell.currentTopic?.stream, isNot(contains(5)));

      api.topicRequests.single.complete(topic(summarized));
      expect(await summarizing, isNull);

      expect(shell.currentTopicSummary, isTrue);
      expect(shell.currentPostIds, [1, 3, 7, 9]);
      expect(shell.store.read<Post>(_siteUrl, 5), isNull);
    });
  });

  group('session replacement', () {
    test('discards a credential failure from the old session', () async {
      final authenticator = _OneShotGatedAuthenticator();
      final api = _PostOrderingApi();
      final shell = await _loadShell(api, authenticator: authenticator);
      addTearDown(shell.dispose);
      await _openTopic(shell);
      final post = shell.store.read<Post>(_siteUrl, 1)!.copyWith(canLike: true);
      shell.store.put(_siteUrl, post);

      authenticator.gateNextRead = true;
      final liking = shell.toggleLike(post);
      await authenticator.readStarted.future;
      await shell.disconnectCurrentInstance();

      authenticator.readGate.complete();
      expect(await liking, isNull);
      expect(api.liked, isEmpty);
    });

    test('does not read after an old-session delete completes', () async {
      final deleteGate = Completer<void>();
      final api = _PostOrderingApi(deleteGate: deleteGate);
      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      await _openTopic(shell);
      final post = shell.store.read<Post>(_siteUrl, 1)!;

      final deleting = shell.deletePost(post);
      await api.deleteStarted.future;
      await shell.disconnectCurrentInstance();

      deleteGate.complete();
      await deleting;

      expect(api.postRequests, isEmpty);
    });

    test(
      'lets the next account expand a gap the old one left loading',
      () async {
        final api = _PostOrderingApi();
        final shell = await _loadShell(api);
        addTearDown(shell.dispose);
        void openGap() {
          shell.pushContent(
            ContentRoute.topic(topicId: 7, slug: 'a-topic', title: 'A topic'),
          );
          shell.store.put(
            _siteUrl,
            const TopicDetail(
              id: 7,
              title: 'A topic',
              stream: [1, 2],
              gapsAfter: {
                1: [2],
              },
              postsCount: 2,
            ),
          );
        }

        openGap();
        final retired = shell.expandPostGap(anchorPostId: 1, before: false);
        await api.waitForPostRequests(1);
        await shell.disconnectCurrentInstance();
        await shell.connectCurrentInstance();
        api.postRequests[0].response.complete([_reply]);
        await retired;

        openGap();
        final expanding = shell.expandPostGap(anchorPostId: 1, before: false);
        await pumpEventQueue();
        expect(api.postRequests, hasLength(2));
        api.postRequests[1].response.complete([_reply]);
        await expanding;

        expect(shell.store.read<Post>(_siteUrl, 2)?.cooked, 'reply');
      },
    );
  });
}
