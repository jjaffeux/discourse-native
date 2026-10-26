import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://other.discourse.org';
const _reader = DiscourseUser(
  id: 7,
  username: 'reader',
  unifiedNewEnabled: true,
);
const _rows = [
  Topic(
    id: 1,
    title: 'First match',
    slug: 'first',
    categoryId: 21,
    seen: false,
    tags: [
      TopicTag(id: 4, name: 'Support'),
      TopicTag(id: 5, name: 'iOS'),
    ],
  ),
  Topic(
    id: 2,
    title: 'Second match',
    slug: 'second',
    categoryId: 21,
    seen: false,
    tags: [
      TopicTag(id: 4, name: 'Support'),
      TopicTag(id: 5, name: 'iOS'),
    ],
  ),
];

ContentRoute _route() => ContentRoute.filteredTopicList(
  TopicListMode.newActivity,
  categoryId: 21,
  tags: const ['support', 'iOS'],
  query: const {
    'search': ['matching words'],
    'order': ['created'],
    'ascending': ['true'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'enumerates the captured full list before writing and reloads it',
    () async {
      final (shell, api) = await _fixture();
      final source = shell.topicListContent!;
      final gate = api.holdPage('/page-2.json');
      final request = shell.dismissNewTopics();
      await gate.started.future;
      expect(api.dismissNewCalls, isEmpty);
      expect(shell.dismissingNewTopics, isTrue);
      await shell.dismissNewTopics();
      expect(api.reads, [(_site, source.feedPath!), (_site, '/page-2.json')]);

      await shell.selectTopicListMode(TopicListMode.latest);
      final destination = shell.topicListContent!;
      api.reads.clear();
      gate.release.complete();
      expect(await request, isNull);

      final call = api.dismissNewCalls.single;
      expect(call.topics, isTrue);
      expect(call.posts, isTrue);
      expect(call.categoryId, 21);
      expect(call.tagName, 'Support');
      expect(call.topicIds, [1, 2]);
      expect(api.reads, [(_site, source.feedPath!)]);
      expect(shell.topicListContent, same(destination));
      expect(shell.topicFeeds.feedFor(_site, source.id)!.topicIds, [1]);
      expect(shell.dismissingNewTopics, isFalse);
      expect(shell.store.read<Topic>(_site, 1)!.seen, isTrue);
    },
  );

  for (final failure in ['cycle', 'incomplete']) {
    test(
      '$failure enumeration refuses every bulk write and can retry',
      () async {
        final (shell, api) = await _fixture();
        final source = shell.topicListContent!;
        api.pages['/page-2.json'] = failure == 'cycle'
            ? TopicList(topics: [_rows.last], moreTopicsUrl: source.feedPath)
            : null;

        expect(await shell.dismissNewTopics(), contains('Could not dismiss'));
        expect(api.dismissNewCalls, isEmpty);
        expect(shell.store.read<Topic>(_site, 1)!.seen, isFalse);
        expect(shell.dismissingNewTopics, isFalse);
        expect(api.reads, [(_site, source.feedPath!), (_site, '/page-2.json')]);

        api.pages['/page-2.json'] = TopicList(topics: [_rows.last]);
        expect(await shell.dismissNewTopics(), isNull);
        expect(api.dismissNewCalls.single.topicIds, [1, 2]);
      },
    );
  }

  test(
    'retired enumeration cannot write or clear a replacement busy scope',
    () async {
      final (shell, api) = await _fixture();
      final oldPage = api.holdPage('/page-2.json');
      final old = shell.dismissNewTopics();
      await oldPage.started.future;
      shell.lifecycle.invalidate(_site);
      final replacementPage = api.holdPage('/page-2.json');
      final replacement = shell.dismissNewTopics();
      await replacementPage.started.future;

      oldPage.release.complete();
      expect(await old, isNull);
      expect(api.dismissNewCalls, isEmpty);
      expect(shell.dismissingNewTopics, isTrue);
      await shell.dismissNewTopics();
      expect(api.dismissNewCalls, isEmpty);

      replacementPage.release.complete();
      expect(await replacement, isNull);
      expect(api.dismissNewCalls, hasLength(1));
      expect(shell.dismissingNewTopics, isFalse);
    },
  );

  test('a searched list dismisses only the topics it matched', () async {
    final (shell, api) = await _fixture(
      route: () => ContentRoute.filteredTopicList(
        TopicListMode.newActivity,
        categoryId: 21,
        query: const {
          'search': ['matching words'],
        },
      ),
    );
    final source = shell.topicListContent!;

    expect(await shell.dismissNewTopics(), isNull);

    final call = api.dismissNewCalls.single;
    expect(call.categoryId, 21);
    expect(call.topicIds, [1, 2]);
    expect(api.reads, [
      (_site, source.feedPath!),
      (_site, '/page-2.json'),
      (_site, source.feedPath!),
    ]);
  });

  test(
    'a searched list with no category or tag offers no forum-wide dismiss',
    () async {
      final (shell, api) = await _fixture(
        route: () => ContentRoute.filteredTopicList(
          TopicListMode.newActivity,
          query: const {
            'search': ['matching words'],
          },
        ),
        dismissible: false,
      );

      expect(await shell.dismissNewTopics(), isNull);
      expect(api.dismissNewCalls, isEmpty);
    },
  );

  test('late write publishes and reloads only its original account', () async {
    final (shell, api) = await _fixture();
    final source = shell.topicListContent!;
    final write = Completer<void>();
    api.dismissNewGate = write;
    final request = shell.dismissNewTopics();
    await api.writeStarted.future;
    shell.selectInstance(1);
    shell.store.put(_otherSite, _rows.first);
    await pumpEventQueue();
    expect(shell.dismissingNewTopics, isFalse);
    api.reads.clear();

    write.complete();
    expect(await request, isNull);
    expect(shell.currentInstance!.url, _otherSite);
    expect(shell.store.read<Topic>(_site, 1)!.seen, isTrue);
    expect(shell.store.read<Topic>(_otherSite, 1)!.seen, isFalse);
    expect(api.reads, [(_site, source.feedPath!)]);
    expect(api.writeAccounts, [(_site, 'key-0')]);
  });

  test(
    'accepted write keeps reconciliation when the source reload fails',
    () async {
      final (shell, api) = await _fixture();
      final source = shell.topicListContent!;
      final write = Completer<void>();
      api.dismissNewGate = write;
      final request = shell.dismissNewTopics();
      await api.writeStarted.future;
      api.pages[source.feedPath!] = null;
      write.complete();
      expect(await request, isNull);
      expect(shell.store.read<Topic>(_site, 1)!.seen, isTrue);
      expect(shell.dismissingNewTopics, isFalse);
      expect(shell.topicFeeds.feedFor(_site, source.id)!.error, isNotNull);
    },
  );
}

Future<(ShellController, _Api)> _fixture({
  ContentRoute Function() route = _route,
  bool dismissible = true,
}) async {
  final source = route();
  final api = _Api(source.feedPath!);
  final sites = [
    instance('meta.discourse.org').copyWith(user: _reader),
    instance('other.discourse.org').copyWith(user: _reader),
  ];
  final auth = FakeAuthenticator();
  for (var index = 0; index < sites.length; index++) {
    auth.keys[sites[index].url] = 'key-$index';
  }
  final shell = ShellController(
    instanceStore: FakeInstanceStore(sites),
    api: api,
    authenticator: auth,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  addTearDown(shell.dispose);
  await shell.load();
  shell.pushContent(source);
  await shell.loadFeed(source.id);
  await pumpEventQueue();
  expect(shell.canDismissNewTopics, dismissible);
  api.reads.clear();
  return (shell, api);
}

final class _PageGate {
  final started = Completer<void>();
  final release = Completer<void>();
}

final class _Api extends FakeDiscourseApi {
  _Api(String path)
    : super(
        user: _reader,
        trackingState: TopicTrackingState([
          for (final row in _rows)
            TrackedTopicState(
              topicId: row.id,
              highestPostNumber: 1,
              createdInNewPeriod: true,
            ),
        ]),
      ) {
    pages[path] = TopicList(
      topics: [_rows.first],
      moreTopicsUrl: '/page-2.json',
    );
    pages['/page-2.json'] = TopicList(topics: [_rows.last]);
    dismissedNewIds = [1, 2];
  }

  final pages = <String, TopicList?>{};
  final pageGates = <String, _PageGate>{};
  final reads = <(String, String)>[];
  final writeAccounts = <(String, String)>[];
  final writeStarted = Completer<void>();

  _PageGate holdPage(String path) {
    final gate = _PageGate();
    pageGates[path] = gate;
    addTearDown(() {
      if (!gate.release.isCompleted) gate.release.complete();
    });
    return gate;
  }

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) async {
    reads.add((siteUrl, path));
    if (pageGates.remove(path) case final gate?) {
      gate.started.complete();
      await gate.release.future;
    }
    if (pages.containsKey(path)) {
      return pages[path] ?? (throw StateError('incomplete page'));
    }
    return const TopicList(topics: _rows);
  }

  @override
  Future<List<int>> dismissNewTopics({
    required String siteUrl,
    required String apiKey,
    required bool dismissTopics,
    required bool dismissPosts,
    int? categoryId,
    String? tagName,
    List<int>? topicIds,
    String? clientId,
  }) {
    writeAccounts.add((siteUrl, apiKey));
    if (!writeStarted.isCompleted) writeStarted.complete();
    return super.dismissNewTopics(
      siteUrl: siteUrl,
      apiKey: apiKey,
      dismissTopics: dismissTopics,
      dismissPosts: dismissPosts,
      categoryId: categoryId,
      tagName: tagName,
      topicIds: topicIds,
      clientId: clientId,
    );
  }
}
