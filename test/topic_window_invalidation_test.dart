import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_viewport_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://window.example';

final class _CountingStore extends Store {
  _CountingStore({super.policy});

  int postReads = 0;

  @override
  T? read<T extends Storable<T>>(String siteUrl, Object id) {
    if (T == Post) postReads++;
    return super.read<T>(siteUrl, id);
  }
}

Post _post(int id, {int? number, String? cooked}) => Post(
  id: id,
  postNumber: number ?? id,
  username: 'reader',
  cooked: cooked ?? '<p>Post $id</p>',
);

Future<ShellController> _open({
  required List<int> stream,
  required List<int> loaded,
  int? target,
  Store? store,
  bool mega = false,
  int? lastPostId,
}) async {
  final site = instance('window.example');
  final controller = ShellController(
    store: store,
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  controller.store
    ..put(
      site.url,
      TopicDetail(
        id: 7,
        title: 'Window',
        stream: stream,
        postsCount: 100,
        isMegaTopic: mega,
        lastPostId: lastPostId,
      ),
    )
    ..putAll(site.url, loaded.map(_post));
  controller.pushContent(
    ContentRoute.topic(
      topicId: 7,
      slug: 'window',
      title: 'Window',
      postNumber: target,
    ),
  );
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'content and topic metadata retain the window with fresh records',
    () async {
      final store = _CountingStore();
      final controller = await _open(
        stream: [1, 2, 3],
        loaded: [1, 2, 3, 99],
        target: 2,
        store: store,
      );
      final ids = controller.currentPostIds;
      final ref = store.ref<Post>(_siteUrl, 2);
      store.postReads = 0;
      store.put(_siteUrl, _post(2, cooked: '<p>Edited</p>'));
      store.put(_siteUrl, _post(99, cooked: '<p>Other topic</p>'));
      store.update<TopicDetail>(
        _siteUrl,
        7,
        (topic) => topic.copyWith(title: 'Renamed', closed: true),
      );
      expect(controller.currentPostIds, same(ids));
      expect(store.postReads, 0);
      expect(ref.value?.cooked, '<p>Edited</p>');
      final snapshot = TopicViewportSnapshot.from(controller);
      expect(snapshot.topic?.title, 'Renamed');
      expect(snapshot.topic?.closed, isTrue);
      expect(snapshot.postIds, same(ids));
    },
  );

  test(
    'arrivals fill gaps and late targets replace the fallback window',
    () async {
      final controller = await _open(
        stream: [1, 2, 3, 4, 5, 6],
        loaded: [1, 2],
        target: 5,
      );
      expect(controller.currentPostIds, [1, 2]);
      expect(controller.currentTopicHasEarlier, isFalse);
      expect(controller.currentTopicHasMore, isTrue);
      controller.store.put(_siteUrl, _post(5));
      expect(controller.currentPostIds, [5]);
      expect(controller.currentTopicHasEarlier, isTrue);
      controller.store.putAll(_siteUrl, [_post(3), _post(4), _post(6)]);
      expect(controller.currentPostIds, [1, 2, 3, 4, 5, 6]);
      expect(controller.currentTopicHasMore, isFalse);
      controller.store.remove<Post>(_siteUrl, 4);
      expect(controller.currentPostIds, [5, 6]);
      expect(controller.currentTopicHasEarlier, isTrue);
      controller.store.remove<Post>(_siteUrl, 5);
      expect(controller.currentPostIds, [6]);
    },
  );

  test('an empty window resolves when the first loaded post arrives', () async {
    final controller = await _open(stream: [1, 2, 3], loaded: [], target: 2);
    expect(controller.currentPostIds, isEmpty);
    controller.store.put(_siteUrl, _post(3));
    expect(controller.currentPostIds, [3]);
    expect(controller.currentTopicHasEarlier, isTrue);
    expect(controller.currentTopicHasMore, isFalse);
  });

  test('post number replacement refreshes the initial index', () async {
    final controller = await _open(
      stream: [1, 2, 3],
      loaded: [1, 2, 3],
      target: 3,
    );
    final before = TopicViewportSnapshot.from(controller);
    expect(before.initialPostIndex, 2);
    controller.store.put(_siteUrl, _post(2, number: 3));
    final after = TopicViewportSnapshot.from(controller);
    expect(after.postIds, [1, 2, 3]);
    expect(after.postIds, isNot(same(before.postIds)));
    expect(after.initialPostIndex, 1);
  });

  test('route targets and stream replacements select the new window', () async {
    final controller = await _open(
      stream: [1, 2, 3, 4, 5, 6],
      loaded: [1, 2, 5, 6],
      target: 2,
    );
    expect(controller.currentPostIds, [1, 2]);
    controller.pushContent(
      ContentRoute.topic(
        topicId: 7,
        slug: 'window',
        title: 'Window',
        postNumber: 5,
      ),
    );
    expect(controller.currentPostIds, [5, 6]);
    controller.store.update<TopicDetail>(
      _siteUrl,
      7,
      (topic) => topic.copyWith(
        stream: [1, 2, 5, 6],
        gapsAfter: {
          2: [3, 4],
        },
      ),
    );
    expect(controller.currentPostIds, [1, 2, 5, 6]);
    expect(TopicViewportSnapshot.from(controller).topic?.gapsAfter, {
      2: [3, 4],
    });
  });

  test('mega topic edge flags stay fresh when metadata changes', () async {
    final controller = await _open(
      stream: [20, 21, 22],
      loaded: [20, 21, 22],
      target: 21,
      mega: true,
      lastPostId: 23,
    );
    final ids = controller.currentPostIds;
    expect(ids, [20, 21, 22]);
    expect(controller.currentTopicHasEarlier, isTrue);
    expect(controller.currentTopicHasMore, isTrue);
    controller.store.update<TopicDetail>(
      _siteUrl,
      7,
      (topic) => topic.copyWith(lastPostId: 22),
    );
    expect(controller.currentPostIds, same(ids));
    expect(controller.currentTopicHasMore, isFalse);
    controller.store.put(_siteUrl, _post(20, number: 1));
    expect(controller.currentTopicHasEarlier, isFalse);
  });

  test(
    'bounded stores invalidate evicted windows and keep observed refs',
    () async {
      const policy = StorePolicy(
        maxEntries: 8,
        maxEntriesPerSite: 8,
        maxEntriesPerSiteAndType: 3,
      );
      final store = _CountingStore(policy: policy);
      final controller = await _open(
        stream: [1, 2, 3],
        loaded: [1, 2, 3],
        store: store,
      );
      final ids = controller.currentPostIds;
      expect(ids, [1, 2, 3]);
      final observed = store.ref<Post>(_siteUrl, 2);
      var updates = 0;
      void listener() => updates++;
      observed.addListener(listener);
      addTearDown(() => observed.removeListener(listener));
      store.put(_siteUrl, _post(1, cooked: '<p>Edited</p>'));
      expect(controller.currentPostIds, same(ids));
      store.put(_siteUrl, _post(4));
      expect(store.containsRecord<Post>(_siteUrl, 3), isFalse);
      expect(controller.currentPostIds, [1, 2]);
      expect(store.ref<Post>(_siteUrl, 2), same(observed));
      store.put(_siteUrl, _post(2, cooked: '<p>Observed edit</p>'));
      expect(observed.value?.cooked, '<p>Observed edit</p>');
      expect(updates, 1);
      final statistics = store.statisticsForTesting;
      expect(statistics.entriesFor<Post>(_siteUrl), 3);
      expect(statistics.entries, lessThanOrEqualTo(policy.maxEntries));
      expect(statistics.observedEntries, greaterThanOrEqualTo(1));
      expect(statistics.overCapacity, 0);
    },
  );
}
