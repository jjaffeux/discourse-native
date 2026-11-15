import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/src/data/content_snapshot_store.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/discourse_topic_api.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_tracking_reconciler.dart';
import 'package:discourse_native/src/data/wire_body.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_model_codec.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/content_snapshots.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.example';
const _path = '/latest.json';
const _destination = 'latest';

final class _FeedApi extends FakeDiscourseApi {
  final requests = <Completer<TopicList>>[];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final request = Completer<TopicList>();
    requests.add(request);
    return request.future;
  }
}

final class _TopicApi extends FakeDiscourseApi {
  final requests = <Completer<TopicPayload>>[];

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
    final request = Completer<TopicPayload>();
    requests.add(request);
    return request.future;
  }
}

/// Answers each question when the test says so, which is what lets a test put
/// the disk on either side of the network.
final class _GatedSnapshots implements FeedSnapshots, TopicSnapshots {
  final feedReads = <Completer<TopicList?>>[];
  final topicReads = <Completer<TopicPayload?>>[];
  final rememberedFeeds = <TopicList>[];
  final rememberedTopics = <TopicPayload>[];

  @override
  Future<TopicList?> feed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
  ) {
    final read = Completer<TopicList?>();
    feedReads.add(read);
    return read.future;
  }

  @override
  void rememberFeed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
    TopicList list,
  ) => rememberedFeeds.add(list);

  @override
  Future<TopicPayload?> topic(String siteUrl, SiteLease lease, int topicId) {
    final read = Completer<TopicPayload?>();
    topicReads.add(read);
    return read.future;
  }

  @override
  void rememberTopic(String siteUrl, SiteLease lease, TopicPayload payload) =>
      rememberedTopics.add(payload);
}

TopicList _list(Map<int, String> titles) => TopicList(
  topics: [
    for (final MapEntry(key: id, value: title) in titles.entries)
      Topic(id: id, title: title, slug: 'topic-$id'),
  ],
);

Post _post(int id, String text) => Post(
  id: id,
  postNumber: id,
  username: 'author',
  cooked: '<p>$text</p>',
  version: 1,
);

TopicPayload _topic(String title, List<Post> posts) => (
  detail: TopicDetail(
    id: 7,
    title: title,
    stream: [for (final post in posts) post.id],
    postsCount: posts.length,
  ),
  posts: posts,
);

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Expected state did not arrive.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

final class _TopicFixture {
  _TopicFixture() {
    owner = TopicDataOwner(
      content: api,
      feeds: api,
      models: api.models,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      changed: () {},
      liveChanged: (_) {},
      published: (_, _) => false,
      prepareCategories: (_, _) async {},
      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (siteUrl, lease) => bookmarks.forLease(siteUrl, lease)!,
      notificationReads: (siteUrl, lease, topicId) =>
          tracking.beginNotificationRead(topicId),
      snapshots: snapshots,
    );
    addTearDown(owner.dispose);
    addTearDown(bookmarks.dispose);
    addTearDown(bookmarkChanges.dispose);
  }

  final api = _TopicApi();
  final store = Store();
  final lifecycle = SiteLifecycle();
  final credentials = FakeAuthenticator();
  final snapshots = _GatedSnapshots();
  final tracking = TopicTrackingReconciler();
  final bookmarkChanges = ChangeNotifier();
  late final TopicDataOwner owner;
  late final bookmarks = BookmarkTransactions(
    api: api,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    instanceAt: (_) => null,
    siteContextFor: (_) =>
        const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
    pluginStrategies: () => const [],
    topicData: (siteUrl, lease) => owner.forLease(siteUrl, lease),
    checklistWriting: (_, _) => false,
    topicSlug: (_, _) => 'topic',
    changes: bookmarkChanges,
    changed: () {},
    refreshMenu: (_) async {},
    refreshList: (_) async {},
  );

  TopicDataSession get data => owner.forSite(_siteUrl);

  Future<void> open() => data.open(
    7,
    slug: 'topic',
    opening: TopicOpening(
      received: (_) {},
      resume: (_) => null,
      canResume: () => false,
    ),
  );

  TopicDetail? get detail => store.read<TopicDetail>(_siteUrl, 7);
  String? cooked(int postId) => store.read<Post>(_siteUrl, postId)?.cooked;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a topic list', () {
    late _FeedApi api;
    late _GatedSnapshots snapshots;
    late SiteLifecycle lifecycle;
    late Store store;
    late TopicFeedController controller;
    final site = instance('meta.example');

    setUp(() {
      api = _FeedApi();
      snapshots = _GatedSnapshots();
      lifecycle = SiteLifecycle();
      store = Store();
      controller = TopicFeedController(
        api: api,
        credentials: FakeApiCredentialReader(),
        lifecycle: lifecycle,
        store: store,
        snapshots: snapshots,
      );
      addTearDown(controller.dispose);
    });

    Future<void> load({bool force = false}) => controller.load(
      instance: site,
      destinationId: _destination,
      path: _path,
      incoming: null,
      force: force,
    );

    List<String?> titles() => [
      for (final id
          in controller.feedFor(_siteUrl, _destination)?.topicIds ??
              const <int>[])
        store.read<Topic>(_siteUrl, id)?.title,
    ];

    test(
      'shows the snapshot as stale, then the response replaces it',
      () async {
        final loading = load();
        await _until(() => api.requests.length == 1);

        snapshots.feedReads.single.complete(
          _list({1: 'kept one', 2: 'kept two'}),
        );
        await pumpEventQueue();

        var feed = controller.feedFor(_siteUrl, _destination)!;
        expect(titles(), ['kept one', 'kept two']);
        expect(feed.stale, isTrue);
        expect(feed.loading, isTrue, reason: 'the request is still out');
        expect(feed.loaded, isTrue);

        final fresh = _list({2: 'fresh two', 3: 'fresh three'});
        api.requests.single.complete(fresh);
        await loading;

        feed = controller.feedFor(_siteUrl, _destination)!;
        expect(titles(), ['fresh two', 'fresh three']);
        expect(feed.stale, isFalse);
        expect(feed.loading, isFalse);
        expect(snapshots.rememberedFeeds, [same(fresh)]);
      },
    );

    test('a snapshot read after the response does not replace it', () async {
      final loading = load();
      await _until(() => api.requests.length == 1);

      api.requests.single.complete(_list({2: 'fresh two', 3: 'fresh three'}));
      await loading;
      snapshots.feedReads.single.complete(
        _list({1: 'kept one', 2: 'kept two'}),
      );
      await pumpEventQueue();

      final feed = controller.feedFor(_siteUrl, _destination)!;
      expect(titles(), ['fresh two', 'fresh three']);
      expect(feed.stale, isFalse);
      expect(
        store.read<Topic>(_siteUrl, 1),
        isNull,
        reason: 'a late snapshot must not reach the entity store either',
      );
    });

    test('the snapshot fills only records no request has put', () async {
      store.put(
        _siteUrl,
        const Topic(id: 2, title: 'live two', slug: 'topic-2'),
      );
      final loading = load();
      await _until(() => api.requests.length == 1);

      snapshots.feedReads.single.complete(
        _list({1: 'kept one', 2: 'kept two'}),
      );
      await pumpEventQueue();

      expect(titles(), ['kept one', 'live two']);
      api.requests.single.complete(_list({1: 'fresh one'}));
      await loading;
    });

    test('a failed request is drawn over the snapshot it waited for', () async {
      final loading = load();
      await _until(() => api.requests.length == 1);

      api.requests.single.completeError(
        const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
      );
      await pumpEventQueue();
      expect(
        controller.feedFor(_siteUrl, _destination)!.error,
        isNull,
        reason: 'the failure waits for what the disk has to say',
      );

      snapshots.feedReads.single.complete(_list({1: 'kept one'}));
      await loading;

      final feed = controller.feedFor(_siteUrl, _destination)!;
      expect(titles(), ['kept one']);
      expect(feed.stale, isTrue);
      expect(feed.error, isNotNull);
      expect(feed.loading, isFalse);
      expect(snapshots.rememberedFeeds, isEmpty);
    });

    test('a failed request with no snapshot is the plain failure', () async {
      final loading = load();
      await _until(() => api.requests.length == 1);
      snapshots.feedReads.single.complete(null);
      api.requests.single.completeError(
        const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
      );
      await loading;

      final feed = controller.feedFor(_siteUrl, _destination)!;
      expect(feed.topicIds, isEmpty);
      expect(feed.stale, isFalse);
      expect(feed.error, isNotNull);
    });

    test(
      'a retry after that failure keeps the stale rows and revalidates',
      () async {
        final first = load();
        await _until(() => api.requests.length == 1);
        snapshots.feedReads.single.complete(_list({1: 'kept one'}));
        api.requests.single.completeError(
          const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
        );
        await first;

        final retry = load();
        await _until(() => api.requests.length == 2);
        expect(titles(), ['kept one']);
        expect(
          snapshots.feedReads,
          hasLength(1),
          reason: 'rows already shown are not read from disk again',
        );
        api.requests.last.complete(_list({9: 'fresh nine'}));
        await retry;

        expect(titles(), ['fresh nine']);
        expect(controller.feedFor(_siteUrl, _destination)!.stale, isFalse);
      },
    );

    test('a snapshot read for a retired account publishes nothing', () async {
      final loading = load();
      await _until(() => api.requests.length == 1);

      lifecycle.invalidate(_siteUrl);
      controller.forget(_siteUrl);
      snapshots.feedReads.single.complete(_list({1: 'kept one'}));
      api.requests.single.complete(_list({2: 'fresh two'}));
      await loading;
      await pumpEventQueue();

      expect(controller.feedFor(_siteUrl, _destination), isNull);
      expect(store.read<Topic>(_siteUrl, 1), isNull);
      expect(snapshots.rememberedFeeds, isEmpty);
    });

    test('a list that already has rows is not read from disk', () async {
      final first = load();
      await _until(() => api.requests.length == 1);
      snapshots.feedReads.single.complete(null);
      api.requests.single.complete(_list({1: 'fresh one'}));
      await first;

      final refresh = load(force: true);
      await _until(() => api.requests.length == 2);
      expect(snapshots.feedReads, hasLength(1));
      api.requests.last.complete(_list({1: 'fresher one'}));
      await refresh;
    });
  });

  group('a topic', () {
    test('shows the snapshot, then the response replaces it', () async {
      final f = _TopicFixture();
      final opening = f.open();
      await _until(() => f.snapshots.topicReads.length == 1);
      expect(f.api.requests, isEmpty);

      f.snapshots.topicReads.single.complete(
        _topic('Kept', [_post(1, 'kept')]),
      );
      await _until(() => f.api.requests.length == 1);

      expect(f.detail?.title, 'Kept');
      expect(f.cooked(1), '<p>kept</p>');
      expect(f.data.loading(7), isTrue, reason: 'the snapshot is revalidated');

      final fresh = _topic('Fresh', [_post(1, 'fresh'), _post(2, 'reply')]);
      f.api.requests.single.complete(fresh);
      await opening;

      expect(f.detail?.title, 'Fresh');
      expect(f.cooked(1), '<p>fresh</p>');
      expect(f.cooked(2), '<p>reply</p>');
      expect(f.snapshots.rememberedTopics, [fresh]);
    });

    test('stays readable when the request fails', () async {
      final f = _TopicFixture();
      final opening = f.open();
      await _until(() => f.snapshots.topicReads.length == 1);
      f.snapshots.topicReads.single.complete(
        _topic('Kept', [_post(1, 'kept')]),
      );
      await _until(() => f.api.requests.length == 1);
      f.api.requests.single.completeError(
        const SiteLookupException(SiteLookupFailure.unreachable, _siteUrl),
      );
      await opening;

      expect(f.detail?.title, 'Kept');
      expect(f.cooked(1), '<p>kept</p>');
      expect(f.snapshots.rememberedTopics, isEmpty);

      // Still stale: the next open asks the site rather than trusting it.
      final again = f.open();
      await _until(() => f.api.requests.length == 2);
      expect(f.snapshots.topicReads, hasLength(1));
      f.api.requests.last.complete(_topic('Fresh', [_post(1, 'fresh')]));
      await again;
      expect(f.detail?.title, 'Fresh');
    });

    test('a snapshot read after a response does not replace it', () async {
      final f = _TopicFixture();
      final opening = f.open();
      await _until(() => f.snapshots.topicReads.length == 1);

      // Another reader of the same topic lands while the file is being read.
      final refreshing = f.data.refresh(7);
      await _until(() => f.api.requests.length == 1);
      f.api.requests.single.complete(_topic('Fresh', [_post(1, 'fresh')]));
      await refreshing;
      expect(f.detail?.title, 'Fresh');

      f.snapshots.topicReads.single.complete(
        _topic('Kept', [_post(1, 'kept'), _post(2, 'kept reply')]),
      );
      await opening;

      expect(f.detail?.title, 'Fresh');
      expect(f.cooked(1), '<p>fresh</p>');
      expect(f.cooked(2), isNull);
    });

    test(
      'a snapshot read while a request is out leaves it to the request',
      () async {
        final f = _TopicFixture();
        final opening = f.open();
        await _until(() => f.snapshots.topicReads.length == 1);
        final refreshing = f.data.refresh(7);
        await _until(() => f.api.requests.length == 1);

        f.snapshots.topicReads.single.complete(
          _topic('Kept', [_post(1, 'kept')]),
        );
        await pumpEventQueue();
        expect(f.detail, isNull);

        f.api.requests.single.complete(_topic('Fresh', [_post(1, 'fresh')]));
        await Future.wait([refreshing, opening]);
        expect(f.detail?.title, 'Fresh');
      },
    );

    test('a snapshot read for a retired account publishes nothing', () async {
      final f = _TopicFixture();
      final opening = f.open();
      await _until(() => f.snapshots.topicReads.length == 1);

      f.lifecycle.invalidate(_siteUrl);
      f.snapshots.topicReads.single.complete(
        _topic('Kept', [_post(1, 'kept')]),
      );
      await opening;

      expect(f.detail, isNull);
      expect(f.cooked(1), isNull);
      expect(f.api.requests, isEmpty);
    });
  });

  group('the account a snapshot belongs to', () {
    late Directory directory;
    late ContentSnapshotStore files;
    late SiteLifecycle lifecycle;
    late DiscourseInstance? current;
    late ContentSnapshots snapshots;

    const alice = DiscourseInstance(
      url: _siteUrl,
      title: 'Meta',
      user: DiscourseUser(id: 1, username: 'alice', name: 'Alice'),
    );
    const bob = DiscourseInstance(
      url: _siteUrl,
      title: 'Meta',
      user: DiscourseUser(id: 2, username: 'bob', name: 'Bob'),
    );
    final wire = jsonEncode({
      'topic_list': {
        'topics': [
          {'id': 11, 'title': 'A private message', 'slug': 'pm'},
        ],
      },
    });

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'discourse-native-content-snapshots-test-',
      );
      files = ContentSnapshotStore(
        directory: () => directory,
        writeDelay: const Duration(hours: 1),
      );
      lifecycle = SiteLifecycle();
      current = alice;
      snapshots = ContentSnapshots(
        store: files,
        models: const DiscourseModelCodec.core(),
        lifecycle: lifecycle,
        instanceAt: (_) => current,
      );
    });

    tearDown(() async {
      await files.flush();
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    File fileFor(String siteUrl) =>
        File('${directory.path}/${Uri.encodeComponent(siteUrl)}.json');

    TopicList received() {
      final list = const DiscourseModelCodec.core().topicList(
        jsonDecode(wire) as Map<String, dynamic>,
        _siteUrl,
      );
      WireBody.attach(list, WireBody.text(wire));
      return list;
    }

    Future<TopicList?> read() => snapshots.feed(
      _siteUrl,
      lifecycle.capture(_siteUrl),
      'messages',
      _path,
    );

    void remember() => snapshots.rememberFeed(
      _siteUrl,
      lifecycle.capture(_siteUrl),
      'messages',
      _path,
      received(),
    );

    test('reads back the list the same account received', () async {
      remember();
      await files.flush();

      expect((await read())?.topics.single.title, 'A private message');
    });

    test('a model with no response behind it is not saved', () async {
      snapshots.rememberFeed(
        _siteUrl,
        lifecycle.capture(_siteUrl),
        'messages',
        _path,
        _list({1: 'built by hand'}),
      );
      await files.flush();

      expect(await read(), isNull);
      expect(await fileFor(_siteUrl).exists(), isFalse);
    });

    test('another account on the same forum reads nothing', () async {
      remember();
      await files.flush();

      current = bob;
      expect(await read(), isNull);
      current = const DiscourseInstance(url: _siteUrl, title: 'Meta');
      expect(await read(), isNull);
    });

    test('a signed-out reader of a login-required forum has no scope', () {
      expect(
        ContentSnapshots.accountOf(
          const DiscourseInstance(
            url: _siteUrl,
            title: 'Meta',
            loginRequired: true,
          ),
        ),
        isNull,
      );
      expect(ContentSnapshots.accountOf(null), isNull);
      expect(ContentSnapshots.accountOf(alice), 'id:1');
    });

    test('a read that outlives its account answers nothing', () async {
      remember();
      await files.flush();
      final lease = lifecycle.capture(_siteUrl);
      final reading = snapshots.feed(_siteUrl, lease, 'messages', _path);
      lifecycle.invalidate(_siteUrl);

      expect(await reading, isNull);
    });

    test('a response that outlives its account is not written down', () async {
      final lease = lifecycle.capture(_siteUrl);
      lifecycle.invalidate(_siteUrl);
      snapshots.rememberFeed(_siteUrl, lease, 'messages', _path, received());
      await files.flush();

      expect(await fileFor(_siteUrl).exists(), isFalse);
    });

    test('a kept body that no longer parses is no snapshot', () async {
      files.saveFeed(
        _siteUrl,
        'id:1',
        'messages',
        _path,
        wire: '<html>gateway timeout</html>',
        bytes: 28,
      );

      expect(await read(), isNull);
    });
  });

  group('the transport', () {
    test('hands the body of a topic list and a topic to a snapshot', () async {
      final listBody = jsonEncode({
        'topic_list': {
          'topics': [
            {'id': 3, 'title': 'Ünïcode title', 'slug': 'unicode'},
          ],
        },
      });
      final topicBody = jsonEncode({
        'id': 3,
        'title': 'Ünïcode title',
        'post_stream': {
          'posts': [
            {'id': 30, 'post_number': 1, 'username': 'a', 'cooked': '<p>é</p>'},
          ],
          'stream': [30],
        },
      });
      final api = DiscourseApi(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(request.url.path == _path ? listBody : topicBody),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.close);

      final list = await api.topicList(siteUrl: _siteUrl, path: _path);
      final kept = WireBody.from(list)!;
      expect(kept.text, listBody);
      expect(kept.byteLength, utf8.encode(listBody).length);
      final restored = await decodeTopicListWire(
        api.models,
        kept.text,
        _siteUrl,
      );
      expect(restored.topics.single.title, 'Ünïcode title');

      final topic = await api.topic(siteUrl: _siteUrl, slug: 'unicode', id: 3);
      final keptTopic = WireBody.from(topic.detail)!;
      final restoredTopic = await decodeTopicWire(
        api.models,
        keptTopic.text,
        _siteUrl,
      );
      expect(restoredTopic.detail.title, 'Ünïcode title');
      expect(restoredTopic.posts.single.cooked, topic.posts.single.cooked);
    });
  });

  group('the shell', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp(
        'discourse-native-content-snapshot-shell-test-',
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    File fileFor(String siteUrl) =>
        File('${directory.path}/${Uri.encodeComponent(siteUrl)}.json');

    Future<(ShellController, ContentSnapshotStore)> shellWith(
      DiscourseInstance signedIn,
    ) async {
      final files = ContentSnapshotStore(
        directory: () => directory,
        writeDelay: const Duration(hours: 1),
      );
      files.saveFeed(
        signedIn.url,
        ContentSnapshots.accountOf(signedIn)!,
        'messages',
        _path,
        wire: '{"private":true}',
        bytes: 16,
      );
      await files.flush();
      expect(await fileFor(signedIn.url).exists(), isTrue);
      final shell = ShellController(
        instanceStore: FakeInstanceStore([signedIn]),
        api: FakeDiscourseApi(user: signedIn.user),
        authenticator: FakeAuthenticator()..keys[signedIn.url] = 'key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        contentSnapshots: files,
      );
      addTearDown(shell.dispose);
      await shell.load();
      return (shell, files);
    }

    const signedIn = DiscourseInstance(
      url: _siteUrl,
      title: 'Meta',
      user: DiscourseUser(id: 1, username: 'alice', name: 'Alice'),
    );

    test('signing out deletes the forum snapshot', () async {
      final (shell, files) = await shellWith(signedIn);

      expect(await shell.disconnectInstance(_siteUrl), isTrue);
      await files.flush();

      expect(await fileFor(_siteUrl).exists(), isFalse);
    });

    test('removing the forum deletes its snapshot', () async {
      final (shell, files) = await shellWith(signedIn);

      expect(await shell.removeInstance(shell.instanceFor(_siteUrl)!), isTrue);
      await files.flush();

      expect(await fileFor(_siteUrl).exists(), isFalse);
    });
  });
}
