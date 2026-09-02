import 'dart:async';

import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/models/user_status.dart';
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

Map<String, Object?> _created(int topicId) => {
  'topic_id': topicId,
  'message_type': 'new_topic',
  'payload': {'highest_post_number': 1, 'created_in_new_period': true},
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
    plugins: installedPlugins,
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
      );
      final api = FakeDiscourseApi(
        user: bootstrapUser,
        messageBusBootstrapResult: bootstrap,
      );

      final shell = await _loadShell(api);
      addTearDown(shell.dispose);
      final tracker = FakeSiteTracker.built.single;

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
      tracker.deliverTopicMessage('/topic/7/reactions', {'post_id': 1});
      await api.waitForPostRequests(1);
      await pumpEventQueue();
      expect(api.postRequests, hasLength(1));

      api.postRequests[0].response.complete([_post('older')]);
      await api.waitForPostRequests(2);
      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'initial');

      api.postRequests[1].response.complete([_post('newer')]);
      await pumpEventQueue();

      expect(shell.store.read<Post>(_siteUrl, 1)?.cooked, 'newer');
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
  });
}
