import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
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
      await _requestsChanged.future;
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
      await _postRequestsChanged.future;
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

Post _post(String cooked, {bool canDelete = false, bool canLike = false}) =>
    Post(
      id: 1,
      postNumber: 1,
      username: 'author',
      cooked: cooked,
      canDelete: canDelete,
      canLike: canLike,
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

  test('an incoming response cannot merge into a newer feed refresh', () async {
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
  });

  test('an old incoming finalizer cannot release a newer request', () async {
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

    api.requests[1].response.completeError(StateError('old request failed'));
    await older;

    expect(shell.currentFeed?.loadingIncoming, isTrue);
    await shell.showIncoming('latest');
    expect(api.requests, hasLength(4));

    await _completeFeed(api.requests[3], _page(100));
    await newer;
    expect(shell.currentFeed?.topicIds, [100, 3]);
  });

  test('the newest live post refresh owns the stored snapshot', () async {
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

  test('live invalidation waits for an active delete to settle', () async {
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

  test('an active write invalidates an older live post read', () async {
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
    api.postRequests.single.response.complete([_post('stale', canLike: true)]);
    await pumpEventQueue();

    expect(shell.store.read<Post>(_siteUrl, 1)?.liked, isTrue);

    likeGate.complete();
    expect(await liking, isNull);
    expect(shell.store.read<Post>(_siteUrl, 1)?.liked, isTrue);
  });

  test('a credential failure from an old session is discarded', () async {
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

  test(
    'a completed old-session delete does not read into a new session',
    () async {
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
    },
  );
}
