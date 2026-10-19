import 'dart:async';

import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _root = TopicCategory(id: 1, name: 'Directory', color: '111111');
const _child = TopicCategory(
  id: 10,
  name: 'Child',
  color: '222222',
  parentCategoryId: 20,
  readRestricted: true,
);
const _parent = TopicCategory(id: 20, name: 'Parent', color: '333333');
const _other = TopicCategory(id: 11, name: 'Other', color: '444444');
const _first = Topic(id: 41, title: 'First', slug: 'first', categoryId: 10);
const _second = Topic(id: 42, title: 'Second', slug: 'second', categoryId: 11);
const _warm = Topic(id: 43, title: 'Warm', slug: 'warm', categoryId: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'publishes usable rows before child and parent category lookup',
    () async {
      final api = _MetadataApi();
      final shell = await _loadShell(api);
      final loading = _loadFeed(shell);
      await api.lookupStarted(10);
      await loading;

      expect(_rows(shell), [41]);
      expect(shell.topicFeeds.feedFor(_site, 'metadata')?.loading, isFalse);
      expect(shell.topicRef(_site, 41).value, _first);
      expect(shell.categoryFor(10), isNull);

      api.answer(10, [_child]);
      await api.lookupStarted(20);
      expect(_rows(shell), [41]);
      expect(shell.categoryFor(10), _child);
      expect(shell.categoryFor(20), isNull);

      api.answer(20, [_parent]);
      await pumpEventQueue();
      expect(shell.topicCategoryPathLabel(_child), 'Parent › Child');
      expect(shell.categoryFor(10)?.readRestricted, isTrue);
      expect(api.categoryIdsRequested, [
        [10],
        [20],
      ]);
    },
  );

  for (final failureId in [10, 20]) {
    test(
      'metadata failure at $failureId leaves published rows usable',
      () async {
        final api = _MetadataApi();
        final shell = await _loadShell(api);
        final loading = _loadFeed(shell);
        await api.lookupStarted(10);
        await loading;
        if (failureId == 20) {
          api.answer(10, [_child]);
          await api.lookupStarted(20);
        }
        api.fail(failureId);
        await pumpEventQueue();

        expect(_rows(shell), [41]);
        expect(shell.topicFeeds.feedFor(_site, 'metadata')?.error, isNull);
        expect(shell.topicRef(_site, 41).value, _first);
        expect(shell.categoryFor(failureId), isNull);
        if (failureId == 20) {
          expect(shell.categoryFor(10), _child);
          expect(shell.topicCategoryPathLabel(_child), 'Child');
        }
      },
    );
  }

  test('cached and inline categories need no lookup', () async {
    final api = _MetadataApi();
    final shell = await _loadShell(api);
    api.feeds['/metadata.json'] = [_warm];
    await _loadFeed(shell);
    expect(_rows(shell), [43]);
    expect(shell.categoryFor(1), _root);
    expect(api.categoryIdsRequested, isEmpty);

    api.feeds['/metadata.json'] = [_first];
    api.feedCategoriesByPath['/metadata.json'] = [_child, _parent];
    await _loadFeed(shell, force: true);
    expect(_rows(shell), [41]);
    expect(shell.topicCategoryPathLabel(_child), 'Parent › Child');
    expect(api.categoryIdsRequested, isEmpty);
  });

  test(
    'next page enrichment survives completion of its page request',
    () async {
      final api = _MetadataApi();
      final shell = await _loadShell(api);
      api.feeds['/metadata.json'] = [_warm];
      api.nextPages['/metadata.json'] = '/next.json';
      await _loadFeed(shell);

      final next = shell.topicFeeds.loadMore(
        instance: shell.currentInstance!,
        destinationId: 'metadata',
      );
      await api.lookupStarted(10);
      await next;
      expect(_rows(shell), [43, 41]);
      expect(shell.topicFeeds.feedFor(_site, 'metadata')?.loadingMore, isFalse);

      api.answer(10, [_child]);
      await api.lookupStarted(20);
      api.answer(20, [_parent]);
      await pumpEventQueue();
      expect(shell.topicCategoryPathLabel(_child), 'Parent › Child');
      expect(_rows(shell), [43, 41]);
    },
  );

  test('superseded feed cannot commit its pending missing category', () async {
    final api = _MetadataApi();
    final shell = await _loadShell(api);
    await _loadFeed(shell);
    await api.lookupStarted(10);

    api.feeds['/metadata.json'] = [_second];
    await _loadFeed(shell, force: true);
    await api.lookupStarted(11);
    api.answer(10, [_child]);
    await pumpEventQueue();
    expect(shell.categoryFor(10), isNull);
    expect(api.categoryIdsRequested, [
      [10],
      [11],
    ]);
    expect(_rows(shell), [42]);

    api.answer(11, [_other]);
    await pumpEventQueue();
    expect(shell.categoryFor(11), _other);
    expect(_rows(shell), [42]);
  });

  test('superseded feed cannot commit a pending ancestor', () async {
    final api = _MetadataApi();
    final shell = await _loadShell(api);
    await _loadFeed(shell);
    await api.lookupStarted(10);
    api.answer(10, [_child]);
    await api.lookupStarted(20);

    api.feeds['/metadata.json'] = [_warm];
    await _loadFeed(shell, force: true);
    api.answer(20, [_parent]);
    await pumpEventQueue();
    expect(shell.categoryFor(20), isNull);
    expect(_rows(shell), [43]);
  });

  test(
    'current feed can consume a lookup started by a superseded feed',
    () async {
      final api = _MetadataApi();
      final shell = await _loadShell(api);
      await _loadFeed(shell);
      await api.lookupStarted(10);
      await _loadFeed(shell, force: true);
      expect(api.categoryIdsRequested, [
        [10],
      ]);

      api.answer(10, [_child]);
      await api.lookupStarted(20);
      api.answer(20, [_parent]);
      await pumpEventQueue();
      expect(shell.topicCategoryPathLabel(_child), 'Parent › Child');
      expect(api.categoryIdsRequested, [
        [10],
        [20],
      ]);
      expect(_rows(shell), [41]);
    },
  );

  test(
    'successful overlapping lookup publishes before another lookup finishes',
    () async {
      final api = _MetadataApi();
      final shell = await _loadShell(api);
      await _loadFeed(shell);
      await api.lookupStarted(10);

      api.feeds['/mixed.json'] = [_first, _second];
      await shell.topicFeeds.load(
        instance: shell.currentInstance!,
        destinationId: 'mixed',
        path: '/mixed.json',
        incoming: null,
      );
      await api.lookupStarted(11);
      api.answer(11, [_other]);
      await pumpEventQueue();
      expect(shell.categoryFor(11), _other);
      expect(shell.categoryFor(10), isNull);

      api.feeds['/other.json'] = [_second];
      await shell.topicFeeds.load(
        instance: shell.currentInstance!,
        destinationId: 'other',
        path: '/other.json',
        incoming: null,
      );
      await pumpEventQueue();
      expect(api.categoryIdsRequested, [
        [10],
        [11],
      ]);

      api.answer(10, [_child]);
      await api.lookupStarted(20);
      api.answer(20, [_parent]);
      await pumpEventQueue();
      expect(shell.topicCategoryPathLabel(_child), 'Parent › Child');
    },
  );

  test(
    'failed overlapping lookup retains another successful category',
    () async {
      final api = _MetadataApi();
      final shell = await _loadShell(api);
      await _loadFeed(shell);
      await api.lookupStarted(10);

      api.feeds['/mixed.json'] = [_first, _second];
      await shell.topicFeeds.load(
        instance: shell.currentInstance!,
        destinationId: 'mixed',
        path: '/mixed.json',
        incoming: null,
      );
      await api.lookupStarted(11);
      api.fail(10);
      api.answer(11, [_other]);
      await pumpEventQueue();
      expect(shell.categoryFor(10), isNull);
      expect(shell.categoryFor(11), _other);
      expect(shell.topicFeeds.feedFor(_site, 'mixed')?.topicIds, [41, 42]);
      expect(api.categoryIdsRequested, [
        [10],
        [11],
      ]);
    },
  );

  for (final retireAccount in [false, true]) {
    test(
      'retired ${retireAccount ? 'account' : 'feed'} rejects enrichment',
      () async {
        final api = _MetadataApi();
        final shell = await _loadShell(api);
        await _loadFeed(shell);
        await api.lookupStarted(10);
        if (retireAccount) {
          shell.lifecycle.invalidate(_site);
          shell.clearAccountSessionState(_site);
        } else {
          shell.topicFeeds.forget(_site);
        }
        api.answer(10, [_child]);
        await pumpEventQueue();
        expect(shell.categoryFor(10), isNull);
        expect(shell.topicFeeds.feedFor(_site, 'metadata'), isNull);
        expect(api.categoryIdsRequested, [
          [10],
        ]);
      },
    );
  }

  test(
    'synchronous account retirement stops remaining category writes',
    () async {
      final api = _MetadataApi();
      final shell = await _loadShell(api);
      api.feeds['/metadata.json'] = [_first, _second];
      await _loadFeed(shell);
      await api.lookupStarted(10);
      final ref = shell.categoryRef(_site, 10);
      var retired = false;
      void retire() {
        if (retired || ref.value == null) return;
        retired = true;
        shell.lifecycle.invalidate(_site);
        shell.clearAccountSessionState(_site);
      }

      ref.addListener(retire);
      addTearDown(() => ref.removeListener(retire));
      api.answer(10, [_child, _other]);
      await pumpEventQueue();
      expect(retired, isTrue);
      expect(shell.categoryFor(10), isNull);
      expect(shell.categoryFor(11), isNull);
      expect(shell.topicFeeds.feedFor(_site, 'metadata'), isNull);
      expect(api.categoryIdsRequested, [
        [10, 11],
      ]);
    },
  );
}

List<int>? _rows(ShellController shell) =>
    shell.topicFeeds.feedFor(_site, 'metadata')?.topicIds;

Future<void> _loadFeed(ShellController shell, {bool force = false}) =>
    shell.topicFeeds.load(
      instance: shell.currentInstance!,
      destinationId: 'metadata',
      path: '/metadata.json',
      incoming: null,
      force: force,
    );

Future<ShellController> _loadShell(_MetadataApi api) async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore([instance('meta.discourse.org')]),
    api: api,
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    ownsApi: false,
  );
  addTearDown(() async {
    shell.dispose();
    api.releasePending();
    await pumpEventQueue();
  });
  await shell.load();
  await pumpEventQueue();
  await shell.loadCategories(_site);
  return shell;
}

final class _MetadataApi extends FakeDiscourseApi {
  _MetadataApi()
    : super(
        feeds: {
          '/latest.json': [],
          '/metadata.json': [_first],
          '/next.json': [_first],
        },
        nextPages: {},
        feedCategoriesByPath: {},
        categoryList: [_root],
      );

  final _started = <int, Completer<void>>{};
  final _responses = <int, Completer<List<TopicCategory>>>{};

  Future<void> lookupStarted(int id) =>
      _started.putIfAbsent(id, Completer<void>.new).future;

  void answer(int id, List<TopicCategory> categories) =>
      _responses[id]!.complete(categories);

  void fail(int id) =>
      _responses[id]!.completeError(StateError('Category $id unavailable'));

  void releasePending() {
    for (final response in _responses.values) {
      if (!response.isCompleted) response.complete(const []);
    }
  }

  @override
  Future<List<TopicCategory>> findCategories({
    required String siteUrl,
    required Iterable<int> ids,
    String? apiKey,
    String? clientId,
  }) {
    final requested = ids.toList();
    categoryIdsRequested.add(requested);
    final response = Completer<List<TopicCategory>>();
    for (final id in requested) {
      _responses[id] = response;
      final started = _started.putIfAbsent(id, Completer<void>.new);
      if (!started.isCompleted) started.complete();
    }
    return response.future;
  }
}
