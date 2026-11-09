import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/site_tracker.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/bookmark_host.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/solved/solved_module.dart';
import 'package:discourse_native/src/plugins/solved/solved_post.dart';
import 'package:discourse_native/src/shell/bookmark_transactions.dart';
import 'package:discourse_native/src/shell/topic_channel_router.dart';
import 'package:discourse_native/src/shell/topic_data_owner.dart';
import 'package:discourse_native/src/shell/topic_tracking_directory.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://topic.example';

void main() {
  test('a core message reaches the reader for the watching account', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.watch();

    h.tracker.deliverTopicMessage('/topic/7', const {'type': 'noted'});

    final event = h.readerEvents.single;
    expect(event.siteUrl, _site);
    expect(event.topicId, 7);
    expect(event.data, const {'type': 'noted'});
    expect(
      identical(event.account, h.lifecycle.capture(_site).session),
      isTrue,
    );
    expect(h.observed, [7]);
  });

  test('a plugin channel reaches its hooks and no reader', () async {
    final h = _Harness()..plugin.channels = const ['/polls/7'];
    addTearDown(h.dispose);
    h.watch();

    h.tracker.deliverTopicMessage('/polls/7', const {'post_id': 1});
    await _drain();

    expect(h.plugin.staleTopicAsked, [7]);
    expect(h.readerEvents, isEmpty);
    expect(h.observed, isEmpty);
  });

  test('a message that changes the stream re-reads the topic', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.watch();

    h.tracker.deliverTopicMessage('/topic/7', const {'type': 'created'});
    await _drain();

    expect(h.api.topicsOpened, [7]);
  });

  test('a reply on a topic a plugin reader owns reads nothing here', () async {
    final h = _Harness(
      usesReader: true,
      api: FakeDiscourseApi(
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Topic',
            posts: const [
              Post(id: 1, postNumber: 1, username: 'sam', cooked: 'first'),
            ],
          ),
        },
      ),
    );
    addTearDown(h.dispose);
    h.watch();
    await h.topics.forSite(_site).refresh(7, slug: 'topic');
    h.api.topicsOpened.clear();

    h.tracker.deliverTopicMessage('/topic/7', const {
      'type': 'created',
      'id': 2,
    });
    await _drain();

    expect(h.readerEvents, hasLength(1));
    expect(h.api.topicsOpened, isEmpty);
    expect(h.api.postFetches, isEmpty);
  });

  test(
    'a reader listener retiring the account ends the message there',
    () async {
      final h = _Harness();
      h.onReaderEvent = () => h.lifecycle.invalidate(_site);
      addTearDown(h.dispose);
      h.watch();

      h.tracker.deliverTopicMessage('/topic/7', const {'type': 'created'});
      await _drain();

      expect(h.readerEvents, hasLength(1));
      expect(h.api.topicsOpened, isEmpty);
    },
  );

  test('stats apply to the account that watched', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.watch();

    h.tracker.deliverTopicMessage('/topic/7', const {
      'type': 'stats',
      'posts_count': 9,
    });

    expect(h.store.read<TopicDetail>(_site, 7)?.postsCount, 9);
  });

  test('a reader listener replacing the tracker applies no stats', () {
    final h = _Harness();
    h.onReaderEvent = () => h.heldTracker = null;
    addTearDown(h.dispose);
    h.watch();

    h.tracker.deliverTopicMessage('/topic/7', const {
      'type': 'stats',
      'posts_count': 9,
    });

    expect(h.store.read<TopicDetail>(_site, 7)?.postsCount, 1);
  });

  test(
    'a totals listener retiring the account ends the message there',
    () async {
      final h = _Harness();
      h.onTotalsChanged = () => h.lifecycle.invalidate(_site);
      addTearDown(h.dispose);
      h.watch();

      h.tracker.deliverTopicMessage('/topic/7', const {
        'type': 'stats',
        'posts_count': 9,
      });
      await _drain();

      expect(h.store.read<TopicDetail>(_site, 7)?.postsCount, 9);
      expect(h.plugin.staleTopicAsked, isEmpty);
    },
  );

  test(
    'a plugin hook retiring the account leaves later topics unrouted',
    () async {
      final h = _Harness()..plugin.channels = const ['/shared'];
      addTearDown(h.dispose);
      h.plugin.onStaleTopic = (_) => h.lifecycle.invalidate(_site);
      h.watch(const {7: 'seven', 8: 'eight'});

      h.tracker.deliverTopicMessage('/shared', const {'post_id': 1});
      await _drain();

      expect(h.plugin.staleTopicAsked, [7]);
    },
  );

  test('a topic sharing a plugin channel is routed with the others', () async {
    final h = _Harness()..plugin.channels = const ['/shared'];
    addTearDown(h.dispose);
    h.watch(const {7: 'seven', 8: 'eight'});

    h.tracker.deliverTopicMessage('/shared', const {'post_id': 1});
    await _drain();

    expect(h.plugin.staleTopicAsked, [7, 8]);
  });

  test('an account retired before delivery routes nothing', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.watch();
    h.lifecycle.invalidate(_site);

    h.tracker.deliverTopicMessage('/topic/7', const {'type': 'created'});
    await _drain();

    expect(h.readerEvents, isEmpty);
    expect(h.api.topicsOpened, isEmpty);
  });

  test('disposal ends routing', () async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.watch();
    h.disposed = true;

    h.tracker.deliverTopicMessage('/topic/7', const {'type': 'created'});
    await _drain();

    expect(h.readerEvents, isEmpty);
    expect(h.api.topicsOpened, isEmpty);
  });

  test(
    'a recovered post the reader no longer holds re-reads the stream',
    () async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.watch();

      h.tracker.deliverTopicMessage('/topic/7', const {
        'type': 'recovered',
        'id': 44,
      });
      await _drain();

      expect(h.api.topicsOpened, [7]);
    },
  );

  test('a watch resumes each topic from its snapshot cursor', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.store.put(
      _site,
      const TopicDetail(
        id: 7,
        title: 'Topic',
        stream: [1],
        postsCount: 1,
        messageBusLastId: 31,
      ),
    );

    h.watch();

    expect(h.tracker.watchedTopic, 7);
    expect(h.tracker.watchedChannelLastIds, {'/topic/7': 31});
  });

  group('a solution changed by someone else', () {
    Post answer(int id, {required bool accepted}) => Post(
      id: id,
      postNumber: id,
      username: 'sam',
      cooked: '<p>Answer</p>',
      plugins: PluginData.none.withValue(
        solvedPostKey,
        SolvedPost(accepted: accepted, canAccept: true, canUnaccept: accepted),
      ),
    );

    _Harness held({required Map<int, bool> before, required Set<int> after}) {
      final h = _Harness(
        extraPlugins: const [SolvedPlugin()],
        api: FakeDiscourseApi(
          postsById: {
            for (final id in before.keys)
              id: answer(id, accepted: after.contains(id)),
          },
        ),
      );
      h.store.put(
        _site,
        TopicDetail(
          id: 7,
          title: 'Topic',
          stream: before.keys.toList(),
          postsCount: before.length,
        ),
      );
      for (final entry in before.entries) {
        h.store.put(_site, answer(entry.key, accepted: entry.value));
      }
      return h;
    }

    bool accepted(_Harness h, int id) =>
        h.store.read<Post>(_site, id)!.plugins.get(solvedPostKey)!.accepted;

    // accept_answer.rb publishes AcceptedAnswersHelper.serialize, a
    // BasicPostSerializer row per remaining answer.
    test('moves the mark from the old answer to the new one', () async {
      final h = held(before: {2: true, 3: false, 4: false}, after: {3});
      addTearDown(h.dispose);
      h.watch();

      h.tracker.deliverTopicMessage('/topic/7', const {
        'type': 'accepted_solution',
        'accepted_answers': [
          {'id': 3, 'post_number': 3, 'topic_id': 7, 'username': 'sam'},
        ],
      });
      await _drain();

      expect(accepted(h, 3), isTrue);
      expect(accepted(h, 2), isFalse);
      expect(h.api.postFetches.expand((ids) => ids), isNot(contains(4)));
    });

    // AcceptedAnswersHelper.serialize returns nil once no answer remains.
    test('removes the mark from the only answer', () async {
      final h = held(before: {2: true, 3: false}, after: const {});
      addTearDown(h.dispose);
      h.watch();

      h.tracker.deliverTopicMessage('/topic/7', const {
        'type': 'unaccepted_solution',
        'accepted_answers': null,
      });
      await _drain();

      expect(accepted(h, 2), isFalse);
    });
  });
}

Future<void> _drain() async {
  for (var index = 0; index < 8; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _Plugin
    implements SitePlugin, TopicLivePlugin, TopicLiveReloadPlugin {
  List<String> channels = const [];
  final staleTopicAsked = <int>[];
  void Function(int topicId)? onStaleTopic;

  @override
  String get name => 'router-probe';

  @override
  List<String> topicChannels(int topicId) => channels;

  @override
  List<int> stalePosts(String channel, Object? data) => const [];

  @override
  bool staleTopic(int topicId, String channel, Object? data) {
    staleTopicAsked.add(topicId);
    onStaleTopic?.call(topicId);
    return false;
  }
}

final class _Harness {
  _Harness({
    this.usesReader = false,
    FakeDiscourseApi? api,
    this.extraPlugins = const [],
  }) : api = api ?? FakeDiscourseApi() {
    store.put(
      _site,
      const TopicDetail(id: 7, title: 'Topic', stream: [1], postsCount: 1),
    );
    heldTracker = tracker;
  }

  final bool usesReader;
  final List<SitePlugin> extraPlugins;
  final FakeDiscourseApi api;
  final store = Store();
  final lifecycle = SiteLifecycle();
  final credentials = FakeAuthenticator();
  final plugin = _Plugin();
  final bookmarkChanges = ChangeNotifier();
  final readerEvents = <TopicReaderEvent>[];
  final observed = <int>[];
  final tracker = FakeSiteTracker(
    siteUrl: _site,
    onIncomingTopics: () {},
    onNotifications: (_) {},
    onReviewableCounts: (_) {},
  );
  SiteTracker? heldTracker;
  void Function()? onReaderEvent;
  void Function()? onTotalsChanged;
  bool disposed = false;

  late final BookmarkTransactions bookmarks = BookmarkTransactions(
    api: api,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    instanceAt: (_) => null,
    siteContextFor: (_) =>
        const BookmarkSiteContext(suggestWeekendsInDatePickers: true),
    pluginStrategies: () => const [],
    topicData: (siteUrl, lease) => topics.forLease(siteUrl, lease),
    checklistWriting: (_, _) => false,
    topicSlug: (_, _) => 'topic',
    changes: bookmarkChanges,
    changed: () {},
    refreshMenu: (_) async {},
    refreshList: (_) async {},
  );
  late final tracking = TopicTrackingDirectory(
    lifecycle: lifecycle,
    store: store,
    models: api.models,
    userFor: (_) => null,
    configFor: (_) => const SiteConfig(),
    changed: (_) {},
  );
  late final TopicDataOwner topics = TopicDataOwner(
    content: api,
    feeds: api,
    models: api.models,
    store: store,
    credentials: credentials,
    lifecycle: lifecycle,
    changed: () {},
    liveChanged: (_) => onTotalsChanged?.call(),
    published: (_, _) => false,
    prepareCategories: (_, _) async {},
    loadTimeout: const Duration(seconds: 5),
    bookmarkReads: (siteUrl, lease) => bookmarks.forLease(siteUrl, lease)!,
    usesReader: usesReader ? (_, _) => true : null,
  );
  late final router = TopicChannelRouter(
    trackerFor: (_) => heldTracker,
    tracking: tracking,
    observeTopicMessage: (_, topicId, _, _) => observed.add(topicId),
    topics: topics,
    store: store,
    lifecycle: lifecycle,
    plugins: PluginRegistry([plugin, ...extraPlugins]),
    publishReaderEvent: (event) {
      readerEvents.add(event);
      onReaderEvent?.call();
    },
    isDisposed: () => disposed,
  );

  void watch([Map<int, String> slugsByTopic = const {7: 'topic'}]) =>
      router.watch(_site, tracker, slugsByTopic);

  void dispose() {
    topics.dispose();
    tracking.dispose();
    bookmarks.dispose();
    bookmarkChanges.dispose();
  }
}
