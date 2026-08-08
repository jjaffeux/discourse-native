import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _PendingFeedRequest {
  _PendingFeedRequest(this.path);

  final String path;
  final Completer<TopicList> response = Completer<TopicList>();
}

final class _ControllableFeedApi extends FakeDiscourseApi {
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

TopicList _page(int id, {String? moreTopicsUrl}) => TopicList(
  topics: [Topic(id: id, title: 'Topic $id', slug: 'topic-$id')],
  moreTopicsUrl: moreTopicsUrl,
);

Future<void> _complete(_PendingFeedRequest request, TopicList response) async {
  request.response.complete(response);
  await pumpEventQueue();
}

Future<ShellController> _loadedShell(_ControllableFeedApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  await api.waitForRequests(1);
  await _complete(api.requests[0], _page(1, moreTopicsUrl: '/latest?page=1'));
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an older forced refresh cannot replace a newer response', () async {
    final api = _ControllableFeedApi();
    final shell = await _loadedShell(api);
    addTearDown(shell.dispose);

    final older = shell.loadFeed('latest', force: true);
    await api.waitForRequests(2);
    final newer = shell.loadFeed('latest', force: true);
    await api.waitForRequests(3);

    await _complete(api.requests[2], _page(3));
    await newer;
    expect(shell.currentFeed?.topicIds, [3]);

    await _complete(api.requests[1], _page(2));
    await older;

    expect(shell.currentFeed?.topicIds, [3]);
    expect(shell.store.read<Topic>(_siteUrl, 2), isNull);
    expect(shell.store.read<Topic>(_siteUrl, 3)?.title, 'Topic 3');
  });

  test(
    'pagination from the old snapshot cannot append after refresh',
    () async {
      final api = _ControllableFeedApi();
      final shell = await _loadedShell(api);
      addTearDown(shell.dispose);

      final oldPage = shell.loadMoreFeed('latest');
      await api.waitForRequests(2);
      expect(api.requests[1].path, '/latest.json?page=1');

      final refresh = shell.loadFeed('latest', force: true);
      await api.waitForRequests(3);
      await _complete(api.requests[2], _page(10));
      await refresh;

      await _complete(api.requests[1], _page(2));
      await oldPage;

      expect(shell.currentFeed?.topicIds, [10]);
      expect(shell.currentFeed?.loadingMore, isFalse);
      expect(shell.store.read<Topic>(_siteUrl, 2), isNull);
    },
  );

  test('an old page finalizer cannot release a newer page request', () async {
    final api = _ControllableFeedApi();
    final shell = await _loadedShell(api);
    addTearDown(shell.dispose);

    final oldPage = shell.loadMoreFeed('latest');
    await api.waitForRequests(2);

    final refresh = shell.loadFeed('latest', force: true);
    await api.waitForRequests(3);
    await _complete(
      api.requests[2],
      _page(10, moreTopicsUrl: '/latest?page=2'),
    );
    await refresh;

    final newPage = shell.loadMoreFeed('latest');
    await api.waitForRequests(4);
    expect(api.requests[3].path, '/latest.json?page=2');

    await _complete(api.requests[1], _page(2));
    await oldPage;

    expect(shell.currentFeed?.topicIds, [10]);
    expect(shell.currentFeed?.loadingMore, isTrue);

    await shell.loadMoreFeed('latest');
    expect(api.requests, hasLength(4));

    await _complete(api.requests[3], _page(11));
    await newPage;

    expect(shell.currentFeed?.topicIds, [10, 11]);
    expect(shell.currentFeed?.loadingMore, isFalse);
  });
}
