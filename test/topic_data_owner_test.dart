import 'dart:async';

import 'package:discourse_native/src/data/account_request_session.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/data/topic_tracking_reconciler.dart';

import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:discourse_native/src/shell/topic_feed_controller.dart';
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

final class _FeedApi extends FakeDiscourseApi {
  final reads = <Completer<TopicList>>[];

  @override
  Future<TopicList> topicList({
    required String siteUrl,
    required String path,
    String? apiKey,
    String? clientId,
  }) {
    final read = Completer<TopicList>();
    reads.add(read);
    return read.future;
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
      lastPostResolved: (siteUrl, topicId, postNumber) => resolvedLastPosts.add(
        (siteUrl: siteUrl, topicId: topicId, postNumber: postNumber),
      ),
      prepareCategories: (_, _) async {},

      loadTimeout: const Duration(seconds: 5),
      bookmarkReads: (siteUrl, lease) => bookmarks.forLease(siteUrl, lease)!,
      notificationReads: (siteUrl, lease, topicId) =>
          tracking.beginNotificationRead(topicId),
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
  TopicTrackingReconciler tracking = TopicTrackingReconciler();
  final api = _Api();
  final store = Store();
  final lifecycle = SiteLifecycle();
  final credentials = _Credentials();
  final resolvedLastPosts = <({String siteUrl, int topicId, int postNumber})>[];
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

Future<AccountRequestCredentials> _replyCredential(
  _Fixture f,
  TopicDataSession data,
) => AccountRequestSession(_site, data.lease).keyCredentials(f.credentials);

Future<ReplySendBoundary?> _captureReplyBoundary(
  _Fixture f,
  TopicDataSession data,
  AccountRequestCredentials credential, {
  TopicPayload? payload,
}) async {
  final count = f.api.topicReads.length;
  final capturing = data.captureReplySendBoundary(
    topicId: 7,
    slug: 'topic',
    credential: credential,
  );
  await f.api.waitTopics(count + 1);
  f.api.topicReads.last.result.complete(payload ?? _payload([], stream: [1]));
  return capturing;
}

Future<ReplyLookupResult> _lookupReply(
  _Fixture f,
  TopicDataSession data,
  AccountRequestCredentials credential,
  ReplySendBoundary boundary,
  List<Post> posts, {
  bool whisper = false,
  TopicDetail? detail,
}) async {
  final topics = f.api.topicReads.length;
  final reads = f.api.postReads.length;
  final matching = data.findReply(
    topicId: 7,
    slug: 'topic',
    username: 'author',
    raw: '  Same\u00a0reply  ',
    whisper: whisper,
    boundary: boundary,
    credential: credential,
  );
  await f.api.waitTopics(topics + 1);
  f.api.topicReads.last.result.complete(
    detail == null
        ? _payload([], stream: {1, ...posts.map((post) => post.id)}.toList())
        : (detail: detail, posts: const <Post>[]),
  );
  await f.api.waitPosts(reads + 1);
  f.api.postReads.last.result.complete(posts);
  return matching;
}

void main() {
  test(
    'canonical refresh reconciles category and tags into a retained row',
    () async {
      final f = _Fixture()..seed();
      f.store.put(
        _site,
        const Topic(id: 7, title: 'Old', slug: 'old', categoryId: 1),
      );
      final refreshing = f.data.refreshAfterMutation(7);
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete((
        detail: _payload(
          [],
        ).detail.copyWith(categoryId: 2, tags: const [TopicTag(name: 'new')]),
        posts: const <Post>[],
      ));

      expect(await refreshing, isTrue);
      expect(f.store.read<Topic>(_site, 7)?.categoryId, 2);
      expect(f.store.read<Topic>(_site, 7)?.tags, const [
        TopicTag(name: 'new'),
      ]);
    },
  );

  test(
    'older detail and feed reads preserve accepted metadata fields',
    () async {
      final f = _Fixture()..seed();
      f.store.put(
        _site,
        const Topic(id: 7, title: 'Old', slug: 'old', categoryId: 1),
      );
      final data = f.data;
      final stamp = data.actionEpoch;
      final reading = data.refresh(7);
      await f.api.waitTopics(1);
      data.projectAcceptedMetadata(
        7,
        title: 'Accepted title',
        categoryId: 3,
        tags: const [TopicTag(name: 'accepted')],
      );
      f.api.topicReads.single.result.complete(_payload([]));
      await reading;

      final detail = f.store.read<TopicDetail>(_site, 7)!;
      final row = f.store.read<Topic>(_site, 7)!;
      expect(detail.title, 'Accepted title');
      expect(detail.categoryId, 3);
      expect(detail.tags, const [TopicTag(name: 'accepted')]);
      expect(row.categoryId, 3);
      final incoming = data.actionRowFromRead(
        stamp,
        const Topic(id: 7, title: 'Stale', slug: 'old', categoryId: 1),
      );
      expect(incoming.title, 'Accepted title');
      expect(incoming.categoryId, 3);
      expect(incoming.tags, const [TopicTag(name: 'accepted')]);
    },
  );

  test('external refresh awaits a new read after an active old read', () async {
    final f = _Fixture()..seed();
    final oldRead = f.data.refresh(7);
    await f.api.waitTopics(1);
    var settled = false;
    final refreshing = f.data.refreshAfterMutation(7).then((value) {
      settled = true;
      return value;
    });
    await _drain();
    expect(settled, isFalse);
    expect(f.api.topicReads, hasLength(1));
    f.api.topicReads.first.result.complete(_payload([]));
    await oldRead;
    await f.api.waitTopics(2);
    expect(settled, isFalse);
    f.api.topicReads.last.result.complete(_payload([]));
    expect(await refreshing, isTrue);
  });

  test('external refresh reports failed reads and retired accounts', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    final failed = data.refreshAfterMutation(7);
    await f.api.waitTopics(1);
    f.api.topicReads.first.result.completeError(StateError('offline'));
    expect(await failed, isFalse);
    final oldRead = data.refresh(7);
    await f.api.waitTopics(2);
    final retired = data.refreshAfterMutation(7);
    f.lifecycle.invalidate(_site);
    expect(await retired, isFalse);
    f.api.topicReads.last.result.complete(_payload([]));
    await oldRead;
  });

  test(
    'last-post resolution excludes a post removed during the request',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final reading = data.open(
        7,
        slug: 'topic',
        postNumber: 99999999,
        opening: f.opening,
      );
      await f.api.waitTopics(1);
      data.removePost(7, 3);
      f.api.topicReads.single.result.complete(
        _payload(
          [_post(2, 'Visible'), _post(3, 'Removed')],
          stream: const [1, 2, 3],
        ),
      );
      await reading;
      expect(f.resolvedLastPosts, [
        (siteUrl: _site, topicId: 7, postNumber: 2),
      ]);
      expect(f.store.read<Post>(_site, 3), isNull);
    },
  );

  test(
    'last-post resolution excludes a post removed during publication',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      f.store.ref<Post>(_site, 3).addListener(() {
        if (f.store.read<Post>(_site, 3) != null) data.removePost(7, 3);
      });
      final reading = data.open(
        7,
        slug: 'topic',
        postNumber: 99999999,
        opening: f.opening,
      );
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete(
        _payload(
          [_post(2, 'Visible'), _post(3, 'Removed')],
          stream: const [1, 2, 3],
        ),
      );
      await reading;
      expect(f.resolvedLastPosts, [
        (siteUrl: _site, topicId: 7, postNumber: 2),
      ]);
      expect(f.store.read<Post>(_site, 3), isNull);
    },
  );

  for (final pinRemoved in [false, true]) {
    test(
      'delayed lists preserve the newest row reconciliation after pin ${pinRemoved ? 'removal' : 'preference'}',
      () async {
        final f = _Fixture()..seed();
        final data = f.data;
        f.store.put(
          _site,
          const Topic(id: 7, title: 'Topic', slug: 'topic', pinned: true),
        );
        f.store.put(
          _site,
          f.store.read<TopicDetail>(_site, 7)!.copyWith(pinned: true),
        );
        final api = _FeedApi();
        final feeds = TopicFeedController(
          api: api,
          credentials: f.credentials,
          lifecycle: f.lifecycle,
          store: f.store,
          readPersonalizationStamp: (site) => (
            bookmarks: f.bookmarks.forSite(site).epoch,
            actions: data.actionEpoch,
          ),
          prepareTopicForStore: (site, topic, stamp) => data.actionRowFromRead(
            stamp!.actions,
            f.bookmarks.forSite(site).prepareRow(topic, stamp.bookmarks),
          ),
        );
        addTearDown(feeds.dispose);
        Future<void> load(String destination) => feeds.load(
          instance: instance('topic.example'),
          destinationId: destination,
          path: '/$destination.json',
          incoming: null,
          force: true,
        );
        final oldList = load('latest');
        await _until(() => api.reads.length == 1);
        final oldDetail = data.refresh(7);
        await f.api.waitTopics(1);
        data.projectAcceptedStatus(7, TopicStatusProperty.closed, true);
        data.projectPinPreference(7, false);
        data.settlePinPreference(7);
        if (pinRemoved) {
          f.api.topicReads.single.result.complete(_payload([]));
          await oldDetail;
          expect(
            f.store.read<TopicDetail>(_site, 7)!.hasPinPreference,
            isFalse,
          );
          expect(f.store.read<Topic>(_site, 7)!.pinned, isFalse);
        }
        final nextList = load('new');
        await _until(() => api.reads.length == 2);
        api.reads[1].complete(
          const TopicList(
            topics: [
              Topic(
                id: 7,
                title: 'Newest',
                slug: 'topic',
                closed: false,
                pinned: true,
              ),
            ],
          ),
        );
        await nextList;
        expect(f.store.read<Topic>(_site, 7)!.closed, isFalse);
        expect(f.store.read<Topic>(_site, 7)!.pinned, isTrue);
        api.reads[0].complete(
          const TopicList(
            topics: [
              Topic(
                id: 7,
                title: 'Delayed',
                slug: 'topic',
                closed: true,
                pinned: false,
              ),
            ],
          ),
        );
        await oldList;
        expect(f.store.read<Topic>(_site, 7)!.closed, isFalse);
        expect(f.store.read<Topic>(_site, 7)!.pinned, isTrue);
        expect(f.store.read<Topic>(_site, 7)!.title, 'Delayed');
        if (!pinRemoved) {
          f.api.topicReads.single.result.complete((
            detail: _payload([]).detail.copyWith(pinned: true),
            posts: const <Post>[],
          ));
          await oldDetail;
        }
        expect(f.store.read<TopicDetail>(_site, 7)!.closed, isTrue);
        expect(f.store.read<TopicDetail>(_site, 7)!.pinned, isFalse);
        expect(f.store.read<Topic>(_site, 7)!.closed, isFalse);
        expect(f.store.read<Topic>(_site, 7)!.pinned, isTrue);
      },
    );
  }

  for (final deleted in [false, true]) {
    test(
      '${deleted ? 'withdrawal' : 'recovery'} fences its accepted closed state',
      () async {
        final f = _Fixture()..seed();
        final initial = f.store
            .read<TopicDetail>(_site, 7)!
            .copyWith(closed: !deleted, canRecoverTopic: !deleted);
        f.store.put(_site, initial);
        f.store.put(
          _site,
          Topic(id: 7, title: 'Topic', slug: 'topic', closed: !deleted),
        );
        final data = f.data;
        final reading = data.refresh(7);
        await f.api.waitTopics(1);
        expect(
          data.projectAcceptedDeletion(7, deleted, DateTime.utc(2026)),
          isTrue,
        );
        expect(f.store.read<TopicDetail>(_site, 7)!.canRecoverTopic, deleted);
        f.api.topicReads.single.result.complete((
          detail: initial,
          posts: const <Post>[],
        ));
        await reading;
        expect(f.store.read<TopicDetail>(_site, 7)!.closed, deleted);
        expect(f.store.read<Topic>(_site, 7)!.closed, deleted);
      },
    );
  }

  test('status and pin fencing preserve only the changed fields', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    f.store.put(
      _site,
      f.store.read<TopicDetail>(_site, 7)!.copyWith(pinned: true),
    );
    final reading = data.refresh(7);
    await f.api.waitTopics(1);
    data.projectAcceptedStatus(7, TopicStatusProperty.archived, true);
    data.projectPinPreference(7, false);
    data.settlePinPreference(7);
    final incoming = _payload([_post(1, 'incoming')]);
    f.api.topicReads.single.result.complete((
      detail: const TopicDetail(
        id: 7,
        title: 'Topic',
        stream: [1, 2],
        closed: true,
        visible: false,
        pinned: true,
        pinnedGlobally: true,
      ),
      posts: incoming.posts,
    ));
    await reading;
    final detail = f.store.read<TopicDetail>(_site, 7)!;
    expect(detail.archived, isTrue);
    expect(detail.closed, isTrue);
    expect(detail.visible, isFalse);
    expect(detail.pinned, isFalse);
    expect(detail.unpinned, isTrue);
    expect(detail.pinnedGlobally, isTrue);
    expect(f.store.read<Post>(_site, 1)!.cooked, '<p>incoming</p>');
  });

  test(
    'prefetch carries notification authority from dispatch through adoption',
    () async {
      final f = _Fixture();
      final data = f.data;
      final release = data.prefetch(
        const Topic(
          id: 7,
          title: 'Topic',
          slug: 'topic',
          highestPostNumber: 100,
          lastReadPostNumber: 89,
        ),
        intent: TopicPrefetchIntent.trajectory,
        isInterested: () => true,
      );
      addTearDown(release);
      await f.api.waitTopics(1);
      final choice = f.tracking.chooseNotificationLevel(
        7,
        TopicNotificationLevel.watching,
        confirmed: TopicNotificationLevel.tracking,
      );
      f.tracking.settleNotificationLevel(choice, succeeded: true);
      f.tracking.releaseNotificationChoice(choice);
      f.api.topicReads.single.result.complete(
        _payload([_post(90, 'prefetched')], stream: [1, 90]),
      );
      await _drain();
      await data.open(7, slug: 'topic', postNumber: 90, opening: f.opening);
      expect(f.api.topicReads, hasLength(1));
      expect(
        f.store.read<TopicDetail>(_site, 7)!.notificationLevel,
        TopicNotificationLevel.watching,
      );
      expect(f.tracking.notificationLevel(7), TopicNotificationLevel.watching);
    },
  );

  test(
    'retired tracking ticket blocks publication across same-lease replacement',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final session = data.lease.session;
      final reading = data.refresh(7);
      await f.api.waitTopics(1);
      f.tracking.retire();
      f.tracking = TopicTrackingReconciler();
      f.tracking.observeNotificationLevel(7, TopicNotificationLevel.watching);
      final held = f.store.read<TopicDetail>(_site, 7)!;
      f.api.topicReads.single.result.complete((
        detail: _payload([]).detail.copyWith(title: 'Retired account topic'),
        posts: [_post(99, 'Retired account post')],
      ));
      await reading;
      expect(data.lease.session, same(session));
      expect(data.isCurrent, isTrue);
      expect(f.store.read<TopicDetail>(_site, 7), same(held));
      expect(f.store.read<Post>(_site, 99), isNull);
      expect(f.tracking.notificationLevel(7), TopicNotificationLevel.watching);
      final fresh = data.refresh(7);
      await f.api.waitTopics(2);
      f.api.topicReads.last.result.complete(_payload([]));
      await fresh;
      expect(f.tracking.notificationLevel(7), TopicNotificationLevel.normal);
    },
  );

  test(
    'same-lease retirement during post publication stops remaining records',
    () async {
      final f = _Fixture()..seed();
      final held = f.store.read<TopicDetail>(_site, 7)!;
      final ref = f.store.ref<Post>(_site, 90);
      void replaceAccount() {
        f.tracking.retire();
        f.tracking = TopicTrackingReconciler();
      }

      ref.addListener(replaceAccount);
      addTearDown(() => ref.removeListener(replaceAccount));
      final reading = f.data.refresh(7);
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete(
        _payload([_post(90, 'first'), _post(91, 'second')], stream: [90, 91]),
      );
      await reading;
      expect(f.store.read<Post>(_site, 90), isNotNull);
      expect(f.store.read<Post>(_site, 91), isNull);
      expect(f.store.read<TopicDetail>(_site, 7), same(held));
    },
  );

  test(
    'same-lease retirement during detail publication stops row projection',
    () async {
      final f = _Fixture()..seed();
      final row = f.store.put(
        _site,
        const Topic(id: 7, title: 'Original row', slug: 'topic'),
      );
      final ref = f.store.ref<TopicDetail>(_site, 7);
      void replaceAccount() {
        f.tracking.retire();
        f.tracking = TopicTrackingReconciler();
      }

      ref.addListener(replaceAccount);
      addTearDown(() => ref.removeListener(replaceAccount));
      final reading = f.data.refresh(7);
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete((
        detail: _payload([]).detail.copyWith(title: 'Fresh detail'),
        posts: <Post>[],
      ));
      await reading;
      expect(f.store.read<Topic>(_site, 7), same(row));
    },
  );

  test(
    'prefetch carries the action stamp from launch through navigation',
    () async {
      final f = _Fixture();
      final data = f.data;
      final release = data.prefetch(
        const Topic(
          id: 7,
          title: 'Topic',
          slug: 'topic',
          highestPostNumber: 100,
          lastReadPostNumber: 89,
        ),
        intent: TopicPrefetchIntent.trajectory,
        isInterested: () => true,
      );
      addTearDown(release);
      await f.api.waitTopics(1);
      f.seed();
      f.store.put(_site, const Topic(id: 7, title: 'Topic', slug: 'topic'));
      data.projectAcceptedStatus(7, TopicStatusProperty.closed, true);
      f.api.topicReads.single.result.complete(
        _payload([_post(90, 'prefetched')], stream: [1, 90]),
      );
      await _drain();
      await data.open(7, slug: 'topic', postNumber: 90, opening: f.opening);
      expect(f.api.topicReads, hasLength(1));
      expect(f.store.read<TopicDetail>(_site, 7)!.closed, isTrue);
      expect(f.store.read<Topic>(_site, 7)!.closed, isTrue);
    },
  );

  test(
    'detail row projection reads canonical status after synchronous listeners',
    () async {
      final f = _Fixture()..seed();
      f.store.put(_site, const Topic(id: 7, title: 'Topic', slug: 'topic'));
      final data = f.data;
      var changed = false;
      final ref = f.store.ref<TopicDetail>(_site, 7);
      void acceptStatus() {
        if (changed) return;
        changed = true;
        data.projectAcceptedStatus(7, TopicStatusProperty.closed, true);
      }

      ref.addListener(acceptStatus);
      addTearDown(() => ref.removeListener(acceptStatus));
      final reading = data.refresh(7);
      await f.api.waitTopics(1);
      f.api.topicReads.single.result.complete((
        detail: _payload([]).detail.copyWith(title: 'Fresh topic'),
        posts: const <Post>[],
      ));
      await reading;
      expect(changed, isTrue);
      expect(f.store.read<TopicDetail>(_site, 7)!.closed, isTrue);
      expect(f.store.read<Topic>(_site, 7)!.closed, isTrue);
    },
  );

  test(
    'retired action fences and delayed reads cannot affect a successor',
    () async {
      final f = _Fixture()..seed();
      final old = f.data;
      final reading = old.refresh(7);
      await f.api.waitTopics(1);
      old.projectPinPreference(7, true);
      f.lifecycle.invalidate(_site);
      f.store.forget(_site);
      f.seed();
      final successor = f.data;
      old.projectAcceptedStatus(7, TopicStatusProperty.closed, true);
      old.settlePinPreference(7);
      f.api.topicReads.single.result.complete(_payload([]));
      await reading;
      expect(successor.actionEpoch, 0);
      expect(f.store.read<TopicDetail>(_site, 7)!.closed, isFalse);
      expect(f.store.read<TopicDetail>(_site, 7)!.pinned, isFalse);
      final fresh = successor.refresh(7);
      await f.api.waitTopics(2);
      f.api.topicReads.last.result.complete((
        detail: _payload([]).detail.copyWith(closed: true),
        posts: const <Post>[],
      ));
      await fresh;
      expect(f.store.read<TopicDetail>(_site, 7)!.closed, isTrue);
    },
  );

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
      final boundary = await _captureReplyBoundary(f, data, credential);
      final page = data.pageIds(7, ids: [2], newer: true);
      await f.api.waitPosts(1);
      final matching = data.findReply(
        topicId: 7,
        slug: 'topic',
        username: 'author',
        raw: 'landed reply',
        whisper: false,
        boundary: boundary,
        credential: credential,
      );
      await f.api.waitTopics(2);
      f.api.postReads[0].result.complete([]);
      await page;
      expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
      f.api.topicReads.last.result.complete(_payload([_post(1, 'one')]));
      await f.api.waitPosts(2);
      f.api.postReads[1].result.complete([
        _post(1, 'one'),
        _post(2, 'reply', raw: 'landed reply'),
      ]);
      expect((await matching as ReplyFound).post.id, 2);
      expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
    },
  );

  test(
    'reply boundary uses a fresh maximum without publishing its read',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await _replyCredential(f, data);
      final changes = f.changes;
      final boundary = await _captureReplyBoundary(
        f,
        data,
        credential,
        payload: _payload([], stream: [1, 120, 100]),
      );
      expect(f.store.read<TopicDetail>(_site, 7)?.stream, [1, 2]);
      expect(f.changes, changes);
      expect(
        await _lookupReply(f, data, credential, boundary!, [
          _post(110, 'Same reply', raw: 'Same reply'),
        ]),
        isA<ReplyIndeterminate>(),
      );
    },
  );

  test(
    'a new normalized reply is found beyond its original boundary',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await _replyCredential(f, data);
      final boundary = await _captureReplyBoundary(f, data, credential);
      final result = await _lookupReply(f, data, credential, boundary!, [
        _post(1, 'Same reply', raw: 'Same reply'),
        _post(2, 'Same reply', raw: 'Same reply'),
      ]);
      expect((result as ReplyFound).post.id, 2);
    },
  );

  for (final whisper in [false, true]) {
    for (final type in [Post.regularPostType, Post.whisperPostType, 3]) {
      test(
        'reply confirmation requires exact type $type for whisper $whisper',
        () async {
          final f = _Fixture()..seed();
          final data = f.data;
          final credential = await _replyCredential(f, data);
          final boundary = await _captureReplyBoundary(f, data, credential);
          final result = await _lookupReply(f, data, credential, boundary!, [
            Post(
              id: 2,
              postNumber: 2,
              username: 'author',
              cooked: '<p>Same reply</p>',
              raw: 'Same reply',
              postType: type,
            ),
          ], whisper: whisper);
          final expectedType = whisper
              ? Post.whisperPostType
              : Post.regularPostType;
          expect(
            result,
            type == expectedType
                ? isA<ReplyFound>()
                : isA<ReplyIndeterminate>(),
          );
        },
      );
    }
  }

  test(
    'a matching tail reply cannot confirm an unexamined new candidate',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await _replyCredential(f, data);
      final boundary = await _captureReplyBoundary(f, data, credential);
      final result = await _lookupReply(
        f,
        data,
        credential,
        boundary!,
        [
          for (var id = 3; id <= 6; id++)
            _post(id, 'Another reply', raw: 'Another reply'),
          _post(7, 'Same reply', raw: 'Same reply'),
        ],
        detail: const TopicDetail(
          id: 7,
          title: 'More new replies than the lookup window',
          stream: [1, 2, 3, 4, 5, 6, 7],
          postsCount: 7,
        ),
      );
      expect(result, isA<ReplyIndeterminate>());
    },
  );

  for (final detail in [
    const TopicDetail(
      id: 7,
      title: 'Mega',
      stream: [1, 2],
      postsCount: 2,
      isMegaTopic: true,
    ),
    const TopicDetail(id: 7, title: 'Partial', stream: [1, 2], postsCount: 3),
    const TopicDetail(
      id: 7,
      title: 'Gapped',
      stream: [1, 2],
      postsCount: 2,
      gapsBefore: {
        2: [3],
      },
    ),
  ]) {
    test(
      'a matching reply in ${detail.title} evidence is indeterminate',
      () async {
        final f = _Fixture()..seed();
        final data = f.data;
        final credential = await _replyCredential(f, data);
        final boundary = await _captureReplyBoundary(f, data, credential);
        expect(
          await _lookupReply(f, data, credential, boundary!, [
            _post(2, 'Same reply', raw: 'Same reply'),
          ], detail: detail),
          isA<ReplyIndeterminate>(),
        );
      },
    );
  }

  test(
    'another identified author needs no raw to exclude their reply',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await _replyCredential(f, data);
      final boundary = await _captureReplyBoundary(f, data, credential);
      final result = await _lookupReply(f, data, credential, boundary!, [
        const Post(
          id: 2,
          postNumber: 2,
          username: 'another',
          cooked: '<p>Another reply</p>',
        ),
        _post(3, 'Same reply', raw: 'Same reply'),
      ]);
      expect((result as ReplyFound).post.id, 3);
    },
  );

  for (final username in ['', 'author']) {
    test(
      'a new candidate with unavailable identity or raw remains indeterminate for $username',
      () async {
        final f = _Fixture()..seed();
        final data = f.data;
        final credential = await _replyCredential(f, data);
        final boundary = await _captureReplyBoundary(f, data, credential);
        expect(
          await _lookupReply(f, data, credential, boundary!, [
            Post(
              id: 2,
              postNumber: 2,
              username: username,
              cooked: '<p>A reply</p>',
            ),
            _post(3, 'Same reply', raw: 'Same reply'),
          ]),
          isA<ReplyIndeterminate>(),
        );
      },
    );
  }

  test('multiple new matching replies remain indeterminate', () async {
    final f = _Fixture()..seed();
    final data = f.data;
    final credential = await _replyCredential(f, data);
    final boundary = await _captureReplyBoundary(f, data, credential);
    expect(
      await _lookupReply(f, data, credential, boundary!, [
        _post(2, 'Same reply', raw: 'Same reply'),
        _post(3, 'Same reply', raw: 'Same reply'),
      ]),
      isA<ReplyIndeterminate>(),
    );
  });

  for (final username in <String?>[null, '', '   ']) {
    test(
      'reply confirmation requires a known nonblank author $username',
      () async {
        final f = _Fixture()..seed();
        final data = f.data;
        final credential = await _replyCredential(f, data);
        final boundary = await _captureReplyBoundary(f, data, credential);
        final reads = f.api.topicReads.length;
        expect(
          await data.findReply(
            topicId: 7,
            slug: 'topic',
            username: username,
            raw: 'Same reply',
            whisper: false,
            boundary: boundary,
            credential: credential,
          ),
          isA<ReplyIndeterminate>(),
        );
        expect(f.api.topicReads, hasLength(reads));
      },
    );
  }

  test(
    'reply confirmation cannot infer acceptance without a boundary',
    () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await _replyCredential(f, data);
      expect(
        await data.findReply(
          topicId: 7,
          slug: 'topic',
          username: 'author',
          raw: 'Same reply',
          whisper: false,
          boundary: null,
          credential: credential,
        ),
        isA<ReplyIndeterminate>(),
      );
      expect(f.api.topicReads, isEmpty);
    },
  );

  for (final detail in [
    const TopicDetail(id: 8, title: 'Wrong topic', stream: [1], postsCount: 1),
    const TopicDetail(id: 7, title: 'Empty', stream: [], postsCount: 0),
    const TopicDetail(id: 7, title: 'Invalid', stream: [0], postsCount: 1),
    const TopicDetail(id: 7, title: 'Partial', stream: [1], postsCount: 2),
    const TopicDetail(
      id: 7,
      title: 'Mega',
      stream: [1],
      postsCount: 1,
      isMegaTopic: true,
    ),
  ]) {
    test('reply boundary rejects ${detail.title} evidence', () async {
      final f = _Fixture()..seed();
      final data = f.data;
      final credential = await _replyCredential(f, data);
      expect(
        await _captureReplyBoundary(
          f,
          data,
          credential,
          payload: (detail: detail, posts: const []),
        ),
        isNull,
      );
    });
  }

  test('reply boundary cannot be reused by a replacement account', () async {
    final f = _Fixture()..seed();
    final original = f.data;
    final credential = await _replyCredential(f, original);
    final boundary = await _captureReplyBoundary(f, original, credential);
    f.lifecycle.invalidate(_site);
    final replacement = f.data;
    final replacementCredential = await _replyCredential(f, replacement);
    final reads = f.api.topicReads.length;
    expect(
      await replacement.findReply(
        topicId: 7,
        slug: 'topic',
        username: 'author',
        raw: 'Same reply',
        whisper: false,
        boundary: boundary,
        credential: replacementCredential,
      ),
      isA<ReplyIndeterminate>(),
    );
    expect(f.api.topicReads, hasLength(reads));
  });

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
