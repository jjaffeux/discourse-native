import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';

import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:discourse_native/src/shell/topic_prefetch_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://topic.example';

Post _post(int id, String text, {String? raw}) => Post(
  id: id,
  postNumber: id,
  username: 'author',
  cooked: '<p>$text</p>',
  raw: raw,
  version: 1,
);

TopicPayload _payload(
  List<Post> posts, {
  List<int> stream = const [1, 2],
  int? lastRead,
  TopicRecommendations? recommendations,
}) => (
  detail: TopicDetail(
    id: 7,
    title: 'Topic',
    stream: stream,
    postsCount: stream.length,
    lastReadPostNumber: lastRead,
    recommendations: recommendations,
  ),
  posts: posts,
);

final class _PostRead {
  _PostRead(this.ids, this.apiKey);
  final List<int> ids;
  final String? apiKey;
  final result = Completer<List<Post>>();
}

final class _TopicRead {
  _TopicRead(this.postNumber, this.summary);
  final int? postNumber;
  final bool summary;
  final result = Completer<TopicPayload>();
}

final class _Api extends FakeDiscourseApi {
  final postReads = <_PostRead>[];
  final topicReads = <_TopicRead>[];
  TopicRecommendations? recommendations;

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
    final read = _TopicRead(postNumber, summary);
    topicReads.add(read);
    return read.result.future;
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
    final read = _PostRead(List.of(ids), apiKey);
    postReads.add(read);
    return read.result.future;
  }

  @override
  Future<TopicPostsPayload> topicPosts({
    required String siteUrl,
    required int topicId,
    required List<int> ids,
    String? apiKey,
    String? clientId,
  }) async => (
    posts: await posts(
      siteUrl: siteUrl,
      topicId: topicId,
      ids: ids,
      apiKey: apiKey,
    ),
    recommendations: recommendations,
  );

  @override
  Future<List<Post>> postsFromNumber({
    required String siteUrl,
    required int topicId,
    required int postNumber,
    required bool ascending,
    String? apiKey,
    String? clientId,
  }) => posts(siteUrl: siteUrl, topicId: topicId, ids: [], apiKey: apiKey);

  Future<void> waitPosts(int count) => _until(() => postReads.length >= count);
  Future<void> waitTopics(int count) =>
      _until(() => topicReads.length >= count);
}

Future<void> _until(bool Function() ready) async {
  final timeout = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(timeout)) {
      fail('Expected request did not arrive.');
    }
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _drain() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Credentials extends FakeAuthenticator {
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads++;
    return super.apiKeyFor(siteUrl);
  }
}

final class _Fixture {
  _Fixture() {
    owner = TopicDataOwner(
      content: api,
      feeds: api,
      models: api.models,
      store: store,
      credentials: credentials,
      lifecycle: lifecycle,
      changed: () {
        changes++;
        onChange?.call();
      },
      liveChanged: (_) => changes++,
      published: (_, _) => false,
      prepareCategories: (_, _) async {},

      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (siteUrl, lease) => bookmarks.forLease(siteUrl, lease)!,
    );
    addTearDown(owner.dispose);
    addTearDown(bookmarks.dispose);
    addTearDown(bookmarkChanges.dispose);
  }

  final bookmarkChanges = ChangeNotifier();
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
    changed: () {
      changes++;
      onChange?.call();
    },
    refreshMenu: (_) async {},
    refreshList: (_) async {},
  );
  final api = _Api();
  final store = Store();
  final lifecycle = SiteLifecycle();
  final credentials = _Credentials();
  int changes = 0;
  void Function()? onChange;
  late final TopicDataOwner owner;
  TopicDataSession get data => owner.forSite(_site);
  TopicOpening get opening => TopicOpening(
    received: (_) {},
    resume: (_) => null,
    canResume: () => false,
  );

  void seed() {
    store.put(_site, _payload([_post(1, 'initial')]).detail);
    store.put(_site, _post(1, 'initial'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'late ID hydration preserves an accepted unchanged-version edit',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final paging = data.pageIds(7, ids: [2], newer: true);
      await f.api.waitPosts(1);
      data.acceptEditedPost(_post(2, 'new', raw: 'new'), raw: 'new');
      f.api.postReads.single.result.complete([_post(2, 'old', raw: 'old')]);
      await paging;
      expect(f.store.read<Post>(_site, 2)?.cooked, '<p>new</p>');
      expect(f.store.read<Post>(_site, 2)?.raw, 'new');
    },
  );

  test(
    'an active stream recovery owns membership over an omitted page',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final paging = data.pageIds(7, ids: [2], newer: true);
      await f.api.waitPosts(1);
      final refreshing = data.refresh(7);
      await f.api.waitTopics(1);
      f.api.postReads.single.result.complete([]);
      await paging;
      expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
      f.api.topicReads.single.result.complete(
        _payload([_post(1, 'one'), _post(2, 'recovered')]),
      );
      await refreshing;
      expect(f.store.read<Post>(_site, 2)?.cooked, '<p>recovered</p>');
    },
  );

  test('a retired page cannot publish or clear successor loading', () async {
    final f = _Fixture()..seed();
    final old = f.data;
    final oldPage = old.pageIds(7, ids: [2], newer: true);
    await f.api.waitPosts(1);
    f.lifecycle.invalidate(_site);
    f.store.forget(_site);
    f.seed();
    final successor = f.data;
    final newPage = successor.pageIds(7, ids: [2], newer: true);
    await f.api.waitPosts(2);
    f.api.postReads[0].result.complete([_post(2, 'old account')]);
    await oldPage;
    expect(successor.paging(7, newer: true), isTrue);
    expect(f.store.read<Post>(_site, 2), isNull);
    f.api.postReads[1].result.complete([_post(2, 'successor')]);
    await newPage;
    expect(f.store.read<Post>(_site, 2)?.cooked, '<p>successor</p>');
    expect(successor.paging(7, newer: true), isFalse);
  });

  test(
    'reentrant account retirement stops a multi-record publication',
    () async {
      final f = _Fixture();
      final old = f.data;
      var replaced = false;
      f.store.ref<Post>(_site, 1).addListener(() {
        if (replaced || f.store.read<Post>(_site, 1) == null) return;
        replaced = true;
        f.lifecycle.invalidate(_site);
        f.store.forget(_site);
        f.store.put(_site, _post(1, 'successor'));
        f.data;
      });
      final opening = old.open(7, slug: 'topic', opening: f.opening);
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete(
        _payload([_post(1, 'old one'), _post(2, 'old two')]),
      );
      await opening;
      expect(replaced, isTrue);
      expect(f.store.read<Post>(_site, 1)?.cooked, '<p>successor</p>');
      expect(f.store.read<Post>(_site, 2), isNull);
      expect(f.store.read<TopicDetail>(_site, 7), isNull);
      expect(old.isCurrent, isFalse);
    },
  );

  test('overlapping holds defer live replay until the final release', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    data.invalidatePosts(7, {1});
    await f.api.waitPosts(1);
    final releaseBookmark = data.holdPostWrite(1);
    final releaseChecklist = data.holdPostWrite(1);
    f.api.postReads[0].result.complete([_post(1, 'stale')]);
    await _drain();
    expect(f.store.read<Post>(_site, 1)?.cooked, '<p>initial</p>');
    releaseBookmark();
    releaseBookmark();
    await _drain();
    expect(data.postWriting(1), isTrue);
    expect(f.api.postReads, hasLength(1));
    releaseChecklist();
    await f.api.waitPosts(2);
    f.api.postReads[1].result.complete([_post(1, 'fresh')]);
    await _drain();
    expect(f.store.read<Post>(_site, 1)?.cooked, '<p>fresh</p>');
    expect(data.postWriting(1), isFalse);
  });

  test(
    'selected repair keeps its key and publishes no partial batch',
    () async {
      final f = _Fixture();
      final ids = [for (var id = 1; id <= 41; id++) id];
      f.store.put(_site, _payload([], stream: ids).detail);
      f.store.putAll(_site, [for (final id in ids) _post(id, 'initial')]);
      final data = f.data;
      final repairing = data.repairSelectedPosts(
        7,
        ids,
        'captured-write-key',
        data.lease,
      );
      await f.api.waitPosts(1);
      f.api.postReads[0].result.complete([
        for (final id in ids.take(20)) _post(id, 'fresh'),
      ]);
      await f.api.waitPosts(2);
      f.api.postReads[1].result.complete([
        for (final id in ids.skip(20).take(20)) _post(id, 'fresh'),
      ]);
      await f.api.waitPosts(3);
      expect(f.api.postReads.map((read) => read.ids.length), [20, 20, 1]);
      expect(
        f.api.postReads.map((read) => read.apiKey),
        everyElement('captured-write-key'),
      );
      expect(f.credentials.reads, 0);
      f.api.postReads[2].result.completeError(
        StateError('last batch unavailable'),
      );
      await repairing;
      for (final id in ids) {
        expect(f.store.read<Post>(_site, id)?.cooked, '<p>initial</p>');
      }
    },
  );

  test('bookmark repair preserves accepted content', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    final refresh = f.bookmarks.forSite(_site).refreshBookmarks(7, 'topic');
    await f.api.waitTopics(1);
    data.acceptEditedPost(
      _post(1, 'new content', raw: 'new content'),
      raw: 'new content',
    );
    const bookmark = Bookmark(
      id: 12,
      bookmarkableId: 1,
      bookmarkableType: 'Post',
    );
    f.api.topicReads.single.result.complete((
      detail: _payload([]).detail.withBookmark(bookmark),
      posts: [_post(1, 'stale content').withBookmark(bookmark)],
    ));
    await refresh;
    expect(f.store.read<Post>(_site, 1)?.cooked, '<p>new content</p>');
    expect(f.store.read<Post>(_site, 1)?.bookmark?.id, 12);
  });

  test('a final page preserves newer resolved-empty recommendations', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    f.api.recommendations = TopicRecommendations(
      sources: [
        TopicRecommendationSource(
          definition: coreSuggestedTopicRecommendationSource,
          topics: const [Topic(id: 99, title: 'Old', slug: 'old')],
        ),
      ],
    );
    final page = data.pageIds(7, ids: [2], newer: true, reachesEnd: true);
    await f.api.waitPosts(1);
    final refresh = data.refresh(7);
    await f.api.waitTopics(1);
    const empty = TopicRecommendations(sources: []);
    f.api.topicReads.single.result.complete(
      _payload([_post(1, 'fresh')], recommendations: empty),
    );
    await refresh;
    f.api.postReads.single.result.complete([_post(2, 'page')]);
    await page;
    expect(f.store.read<TopicDetail>(_site, 7)?.recommendations, same(empty));
  });

  for (final explicit in [false, true]) {
    test(
      'queued refresh honors explicit priority when explicit is $explicit',
      () async {
        final f = _Fixture();
        final data = f.data;
        final resumes = <int>[];
        final opening = TopicOpening(
          received: (_) {},
          canResume: () => true,
          resume: (number) {
            resumes.add(number);
            return (slug: 'topic', postNumber: number);
          },
        );
        final initial = data.open(7, slug: 'topic', opening: opening);
        await f.api.waitTopics(1);
        await data.open(
          7,
          slug: 'topic',
          force: true,
          postNumber: explicit ? 75 : null,
          opening: opening,
        );
        f.api.topicReads[0].result.complete(
          _payload([_post(1, 'one')], stream: [1, 50, 75], lastRead: 50),
        );
        await initial;
        await f.api.waitTopics(2);
        expect(f.api.topicReads[1].postNumber, explicit ? 75 : 50);
        expect(resumes, explicit ? isEmpty : [50]);
        f.api.topicReads[1].result.complete(
          _payload(
            [_post(explicit ? 75 : 50, 'target')],
            stream: [1, 50, 75],
            lastRead: 50,
          ),
        );
        await _drain();
        expect(data.loading(7), isFalse);
      },
    );
  }

  test('normal server resume stays awaited by the original open', () async {
    final f = _Fixture();
    final data = f.data;
    var completed = false;
    final opening = TopicOpening(
      received: (_) {},
      canResume: () => true,
      resume: (number) => (slug: 'topic', postNumber: number),
    );
    final initial = data.open(7, slug: 'topic', opening: opening);
    unawaited(
      initial.then<void>((_) {
        completed = true;
      }),
    );
    await f.api.waitTopics(1);
    f.api.topicReads[0].result.complete(
      _payload([_post(1, 'one')], stream: [1, 50], lastRead: 50),
    );
    await f.api.waitTopics(2);
    expect(completed, isFalse);
    f.api.topicReads[1].result.complete(
      _payload([_post(50, 'resume')], stream: [1, 50], lastRead: 50),
    );
    await initial;
    expect(completed, isTrue);
  });
  test(
    'composer lookup protects stream membership while its full read is active',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await AccountRequestSession(
        _site,
        data.lease,
      ).keyCredentials(f.credentials);
      final page = data.pageIds(7, ids: [2], newer: true);
      await f.api.waitPosts(1);
      final matching = data.findReply(
        topicId: 7,
        slug: 'topic',
        username: 'author',
        raw: 'landed reply',
        credential: credential,
      );
      await f.api.waitTopics(1);
      f.api.postReads[0].result.complete([]);
      await page;
      expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
      f.api.topicReads.single.result.complete(_payload([_post(1, 'one')]));
      await f.api.waitPosts(2);
      f.api.postReads[1].result.complete([
        _post(1, 'one'),
        _post(2, 'reply', raw: 'landed reply'),
      ]);
      expect((await matching)?.id, 2);
      expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
    },
  );

  test('summary publication does not advance full-stream authority', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    final page = data.pageIds(7, ids: [2], newer: true);
    await f.api.waitPosts(1);
    final summary = data.toggleSummary(7, slug: 'topic');
    await f.api.waitTopics(1);
    final payload = _payload([_post(1, 'top reply')], stream: [1]);
    f.api.topicReads.single.result.complete((
      detail: payload.detail.copyWith(title: 'Summary view'),
      posts: payload.posts,
    ));
    expect(await summary, isTrue);
    expect(f.store.read<TopicDetail>(_site, 7)?.title, 'Topic');
    expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
    f.api.postReads.single.result.complete([]);
    await page;
    expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1]);
    expect(data.streamFor(f.store.read<TopicDetail>(_site, 7)!), [1]);
  });

  test(
    'a bookmark accepted during detail publication also owns the list row',
    () async {
      final f = _Fixture()..seed();
      f.store.put(_site, const Topic(id: 7, title: 'Topic', slug: 'topic'));
      final data = f.data;
      var accepted = false;
      f.store.ref<TopicDetail>(_site, 7).addListener(() {
        if (accepted) return;
        accepted = true;
        f.bookmarks
            .forSite(_site)
            .acceptBookmark(
              7,
              const Bookmark(
                id: 12,
                bookmarkableId: 1,
                bookmarkableType: 'Post',
              ),
              isPost: true,
            );
      });
      final refresh = data.refresh(7);
      await f.api.waitTopics(1);
      final payload = _payload([_post(1, 'fresh')]);
      f.api.topicReads.single.result.complete((
        detail: payload.detail.copyWith(title: 'Refreshed topic'),
        posts: payload.posts,
      ));
      await refresh;
      expect(accepted, isTrue);
      expect(f.store.read<TopicDetail>(_site, 7)!.hasBookmarks, isTrue);
      expect(f.store.read<Topic>(_site, 7)!.bookmarked, isTrue);
    },
  );

  for (final kind in ['summary', 'gap', 'mega']) {
    test(
      '$kind publication preserves removal by a synchronous post listener',
      () async {
        final f = _Fixture()..seed();
        final data = f.data;
        f.store.put(
          _site,
          TopicDetail(
            id: 7,
            title: 'Topic',
            stream: const [1],
            postsCount: 3,
            isMegaTopic: kind == 'mega',
            lastPostId: 3,
            gapsAfter: kind == 'gap'
                ? const {
                    1: [2],
                  }
                : const {},
          ),
        );
        var removed = false;
        f.store.ref<Post>(_site, 2).addListener(() {
          if (removed || f.store.read<Post>(_site, 2) == null) return;
          removed = true;
          data.removePost(7, 2);
        });
        if (kind == 'summary') {
          final reading = data.toggleSummary(7, slug: 'topic');
          await f.api.waitTopics(1);
          f.api.topicReads.single.result.complete(
            _payload([_post(2, 'fresh')]),
          );
          await reading;
        } else {
          final reading = kind == 'gap'
              ? data.expandGap(7, anchorPostId: 1, before: false)
              : data.pageMega(
                  f.store.read<TopicDetail>(_site, 7)!,
                  _post(1, 'edge'),
                  newer: true,
                );
          await f.api.waitPosts(1);
          f.api.postReads.single.result.complete([_post(2, 'fresh')]);
          await reading;
        }
        expect(removed, isTrue);
        expect(f.store.read<Post>(_site, 2), isNull);
        expect(
          data.streamFor(f.store.read<TopicDetail>(_site, 7)!),
          isNot(contains(2)),
        );
      },
    );
  }
  test(
    'forced opening reserves its reader before pending moderation recovery',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final uncertain = data.reconcileUncertainMutation(
        7,
        [1],
        'key',
        alreadyHeld: false,
      );
      await f.api.waitPosts(1);
      f.api.postReads.single.result.completeError(StateError('Offline'));
      await uncertain;
      final first = data.open(
        7,
        slug: 'topic',
        postNumber: 75,
        force: true,
        opening: f.opening,
      );
      expect(data.loading(7), isTrue);
      await f.api.waitPosts(2);
      await data.open(
        7,
        slug: 'topic',
        postNumber: 90,
        force: true,
        opening: f.opening,
      );
      expect(f.api.topicReads, isEmpty);
      f.api.postReads[1].result.complete([_post(1, 'recovered')]);
      await f.api.waitTopics(1);
      expect(f.api.topicReads.single.postNumber, 75);
      f.api.topicReads.single.result.complete(
        _payload([_post(75, 'first')], stream: [1, 75, 90]),
      );
      await first;
      await f.api.waitTopics(2);
      expect(f.api.topicReads[1].postNumber, 90);
      f.api.topicReads[1].result.complete(
        _payload([_post(90, 'newest')], stream: [1, 75, 90]),
      );
      await _drain();
      expect([for (final read in f.api.topicReads) read.postNumber], [75, 90]);
      expect(f.api.postReads, hasLength(2));
      expect(data.loading(7), isFalse);
    },
  );

  for (final initialOpen in [true, false]) {
    test(
      'a settlement listener position wins over queued replay after ${initialOpen ? 'open' : 'refresh'}',
      () async {
        final f = _Fixture();
        final data = f.data;
        final first = initialOpen
            ? data.open(7, slug: 'topic', opening: f.opening)
            : data.refresh(7);
        await f.api.waitTopics(1);
        await data.open(
          7,
          slug: 'topic',
          postNumber: 75,
          force: true,
          opening: f.opening,
        );
        Future<void>? newest;
        f.onChange = () {
          if (newest != null || data.loading(7)) return;
          newest = data.open(
            7,
            slug: 'topic',
            postNumber: 90,
            force: true,
            opening: f.opening,
          );
        };
        f.api.topicReads[0].result.complete(
          _payload([_post(1, 'first')], stream: [1, 75, 90]),
        );
        await first;
        await f.api.waitTopics(2);
        expect(f.api.topicReads[1].postNumber, 90);
        f.api.topicReads[1].result.complete(
          _payload([_post(90, 'newest')], stream: [1, 75, 90]),
        );
        await newest;
        await _drain();
        final numbers = [for (final read in f.api.topicReads) read.postNumber];
        for (final read in f.api.topicReads.skip(2)) {
          read.result.complete(_payload([]));
        }
        expect(numbers, [null, 90]);
      },
    );
  }

  test(
    'each omitted ID rechecks full-read authority after observable removal',
    () async {
      final f = _Fixture();
      f.store.put(_site, _payload([], stream: [1, 2, 3]).detail);
      final data = f.data;
      Future<void>? recovery;
      f.store.ref<TopicDetail>(_site, 7).addListener(() {
        if (recovery != null ||
            f.store.read<TopicDetail>(_site, 7)!.stream.contains(2)) {
          return;
        }
        recovery = data.refresh(7);
      });
      final page = data.pageIds(7, ids: [2, 3], newer: true);
      await f.api.waitPosts(1);
      f.api.postReads.single.result.complete([]);
      await page;
      final streamBeforeRecovery = f.store.read<TopicDetail>(_site, 7)!.stream;
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete(
        _payload([_post(3, 'recovered')], stream: [1, 3]),
      );
      await recovery;
      expect(streamBeforeRecovery, [1, 3]);
    },
  );
  for (final repairing in [false, true]) {
    test(
      '${repairing ? 'repair' : 'accepted reply'} cannot restore a post removed during its publication',
      () async {
        final f = _Fixture()..seed();
        final data = f.data;
        var removed = false;
        f.store.ref<Post>(_site, 2).addListener(() {
          if (removed || f.store.read<Post>(_site, 2) == null) return;
          removed = true;
          data.removePost(7, 2);
        });
        if (repairing) {
          final repair = data.repairPost(7, 2, 'original', data.lease);
          await f.api.waitPosts(1);
          f.api.postReads.single.result.complete([_post(2, 'accepted')]);
          await repair;
        } else {
          data.acceptReply(7, _post(2, 'accepted'));
        }
        expect(removed, isTrue);
        expect(f.store.read<Post>(_site, 2), isNull);
        expect(f.store.read<TopicDetail>(_site, 7)!.stream, isNot(contains(2)));
      },
    );
  }
  test(
    'a cached resume callback cannot supersede newer explicit navigation',
    () async {
      final f = _Fixture()..seed();
      f.store.put(
        _site,
        _payload([_post(1, 'held')], stream: [1, 50, 90], lastRead: 50).detail,
      );
      final data = f.data;
      Future<void>? newest;
      final initial = data.open(
        7,
        slug: 'topic',
        opening: TopicOpening(
          received: (_) {},
          canResume: () => true,
          resume: (number) {
            newest = data.open(
              7,
              slug: 'topic',
              postNumber: 90,
              force: true,
              opening: f.opening,
            );
            return (slug: 'topic', postNumber: number);
          },
        ),
      );
      await f.api.waitTopics(1);
      f.api.topicReads[0].result.complete(
        _payload([_post(90, 'newest')], stream: [1, 50, 90]),
      );
      await newest;
      await initial;
      await _drain();
      final numbers = [for (final read in f.api.topicReads) read.postNumber];
      for (final read in f.api.topicReads.skip(1)) {
        read.result.complete(_payload([]));
      }
      expect(numbers, [90]);
    },
  );
  test(
    'a positioned mega run preserves removal during detail publication',
    () async {
      final f = _Fixture();
      f.store.put(
        _site,
        const TopicDetail(
          id: 7,
          title: 'Held',
          stream: [10],
          isMegaTopic: true,
          lastPostId: 99,
          postsCount: 10000,
        ),
      );
      f.store.put(_site, _post(10, 'held'));
      final data = f.data;
      var removed = false;
      f.store.ref<TopicDetail>(_site, 7).addListener(() {
        if (removed) return;
        removed = true;
        data.removePost(7, 2);
      });
      final opening = data.open(
        7,
        slug: 'topic',
        postNumber: 2,
        force: true,
        opening: f.opening,
      );
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete((
        detail: const TopicDetail(
          id: 7,
          title: 'Incoming',
          stream: [2, 3],
          isMegaTopic: true,
          lastPostId: 99,
          postsCount: 10000,
        ),
        posts: [_post(2, 'two'), _post(3, 'three')],
      ));
      await opening;
      expect(removed, isTrue);
      expect(f.store.read<Post>(_site, 2), isNull);
      expect(f.store.read<TopicDetail>(_site, 7)!.stream, [3]);
    },
  );

  for (final initialOpen in [true, false]) {
    test(
      'a cached position keeps queued invalidation after ${initialOpen ? 'open' : 'refresh'} settlement',
      () async {
        final f = _Fixture();
        final data = f.data;
        final first = initialOpen
            ? data.open(7, slug: 'topic', opening: f.opening)
            : data.refresh(7);
        await f.api.waitTopics(1);
        await data.open(
          7,
          slug: 'topic',
          postNumber: 75,
          force: true,
          opening: f.opening,
        );
        Future<void>? navigation;
        f.onChange = () {
          if (navigation != null || data.loading(7)) return;
          navigation = data.open(
            7,
            slug: 'topic',
            postNumber: 90,
            opening: f.opening,
          );
        };
        f.api.topicReads[0].result.complete(
          _payload([_post(1, 'first'), _post(90, 'held')], stream: [1, 75, 90]),
        );
        await first;
        await _drain();
        final numbers = [for (final read in f.api.topicReads) read.postNumber];
        for (final read in f.api.topicReads.skip(1)) {
          read.result.complete(
            _payload([_post(90, 'fresh')], stream: [1, 75, 90]),
          );
        }
        await navigation;
        expect(numbers, [null, 90]);
        expect(f.store.read<Post>(_site, 90)!.cooked, '<p>fresh</p>');
      },
    );
  }
  test(
    'a speculative successor cannot satisfy queued forced invalidation',
    () async {
      final f = _Fixture();
      final data = f.data;
      final release = data.prefetch(
        const Topic(
          id: 7,
          title: 'Topic',
          slug: 'topic',
          lastReadPostNumber: 89,
          highestPostNumber: 100,
        ),
        intent: TopicPrefetchIntent.trajectory,
        isInterested: () => true,
      );
      addTearDown(release);
      await f.api.waitTopics(1);
      f.api.topicReads[0].result.complete(
        _payload([_post(90, 'speculative')], stream: [1, 75, 90]),
      );
      await _drain();
      final initial = data.open(7, slug: 'topic', opening: f.opening);
      await f.api.waitTopics(2);
      await data.open(
        7,
        slug: 'topic',
        postNumber: 75,
        force: true,
        opening: f.opening,
      );
      Future<void>? navigation;
      f.onChange = () {
        if (navigation != null || data.loading(7)) return;
        navigation = data.open(
          7,
          slug: 'topic',
          postNumber: 90,
          opening: f.opening,
        );
      };
      f.api.topicReads[1].result.complete(
        _payload([_post(1, 'first')], stream: [1, 75, 90]),
      );
      await initial;
      await _drain();
      final numbers = [for (final read in f.api.topicReads) read.postNumber];
      for (final read in f.api.topicReads.skip(2)) {
        read.result.complete(
          _payload([_post(90, 'fresh')], stream: [1, 75, 90]),
        );
      }
      await navigation;
      expect(numbers, [90, null, 90]);
      expect(f.store.read<Post>(_site, 90)!.cooked, '<p>fresh</p>');
    },
  );
}
