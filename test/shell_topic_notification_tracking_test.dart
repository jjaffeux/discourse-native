import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _otherSite = 'https://team.discourse.org';
const _reader = DiscourseUser(
  id: 7,
  username: 'reader',
  unifiedNewEnabled: true,
  sidebarShowCountOfNewItems: true,
);
const _category = TopicCategory(id: 5, name: 'Support', color: '0088CC');
const _topicRow = Topic(
  id: 7,
  title: 'An unread topic',
  slug: 'unread-topic',
  lastReadPostNumber: 80,
  highestPostNumber: 100,
  categoryId: 5,
);
const _tracked = TrackedTopicState(
  topicId: 7,
  highestPostNumber: 100,
  lastReadPostNumber: 80,
  notificationLevel: 2,
  categoryId: 5,
  tagIds: {9},
);
const _detail = TopicDetail(
  id: 7,
  title: 'An unread topic',
  stream: [1],
  postsCount: 100,
  lastReadPostNumber: 80,
  categoryId: 5,
  notificationLevel: TopicNotificationLevel.tracking,
);
const _firstPost = Post(
  id: 1,
  postNumber: 1,
  username: 'author',
  cooked: '<p>First post of an unread topic</p>',
);

void main() {
  for (final level in [
    TopicNotificationLevel.normal,
    TopicNotificationLevel.muted,
  ]) {
    testWidgets(
      'successful ${level.name} menu choice reconciles unread badges',
      (tester) async {
        final tracking = TopicTrackingState([_tracked]);
        final api = _NotificationApi(trackingState: tracking);
        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: _reader)],
          api: api,
          authenticator: FakeAuthenticator()..keys[_site] = 'reader-key',
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        shell.openTopicPost(siteUrl: _site, topicId: 7, postNumber: 1);
        await tester.pumpAndSettle();
        expect(renderedText('First post of an unread topic'), findsOneWidget);
        expect(shell.currentContent?.postNumber, 1);
        expect(shell.newReplyCount, 1);
        expect(shell.sidebarBadgeFor('latest'), const SidebarBadge.count(1));
        expect(
          shell.sidebarBadgeFor('category-5'),
          const SidebarBadge.count(1),
        );
        expect(shell.sidebarBadgeFor('tag-9'), const SidebarBadge.count(1));

        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is DButton &&
                widget.tooltip?.startsWith('Topic notifications:') == true,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is DDropdownMenuRadioItem<TopicNotificationLevel> &&
                widget.value == level,
          ),
        );
        await tester.pumpAndSettle();
        expect(api.requests.single.level, level);
        api.requests.single.result.complete();
        await tester.pumpAndSettle();

        expect(shell.currentTopic?.notificationLevel, level);
        expect(shell.newReplyCount, 0);
        expect(shell.topicListNewCounts, (all: 0, topics: 0, replies: 0));
        expect(shell.sidebarBadgeFor('latest'), SidebarBadge.none);
        expect(shell.sidebarBadgeFor('category-5'), SidebarBadge.none);
        expect(shell.sidebarBadgeFor('tag-9'), SidebarBadge.none);
        expect(tracking.topics.single.lastReadPostNumber, 80);
        expect(tracking.topics.single.highestPostNumber, 100);
        expect(api.topicReadsRecorded, isEmpty);
        expect(api.topicTrackingRequests, [_site]);
        expect(api.topicsOpened, [7]);
      },
    );
  }

  for (final succeeds in [true, false]) {
    test(
      '${succeeds ? 'success' : 'rollback'} keeps interleaved tracking fields',
      () async {
        final fixture = await _Fixture.load();
        final write = fixture.select(TopicNotificationLevel.normal);
        expect(fixture.shell.newReplyCount, 0);
        await pumpEventQueue();
        fixture.tracker.deliverTopicTracking(const {
          'topic_id': 7,
          'message_type': 'read',
          'payload': {
            'last_read_post_number': 95,
            'highest_post_number': 110,
            'notification_level': 2,
            'category_id': 6,
            'tags': [
              {'id': 10},
            ],
            'is_seen': true,
          },
        });
        expect(fixture.shell.newReplyCount, 0);
        fixture.finish(succeeds: succeeds);
        expect(await write, succeeds);

        final topic = fixture.tracking.topics.single;
        expect(topic.lastReadPostNumber, 95);
        expect(topic.highestPostNumber, 110);
        expect(topic.categoryId, 6);
        expect(topic.tagIds, {10});
        expect(topic.isSeen, isTrue);
        expect(topic.notificationLevel, succeeds ? 1 : 2);
        expect(fixture.shell.newReplyCount, succeeds ? 0 : 1);
        expect(fixture.shell.sidebarBadgeFor('category-5'), SidebarBadge.none);
        expect(
          fixture.shell.sidebarBadgeFor('tag-10'),
          succeeds ? SidebarBadge.none : const SidebarBadge.count(1),
        );
      },
    );
  }

  test('rollback does not resurrect replies read during the write', () async {
    final fixture = await _Fixture.load();
    final write = fixture.select(TopicNotificationLevel.muted);
    await pumpEventQueue();
    fixture.tracker.deliverTopicTracking(const {
      'topic_id': 7,
      'message_type': 'read',
      'payload': {'last_read_post_number': 100},
    });
    fixture.finish(succeeds: false);
    expect(await write, isFalse);
    expect(
      fixture.shell.currentTopic?.notificationLevel,
      TopicNotificationLevel.tracking,
    );
    expect(fixture.tracking.topics.single.lastReadPostNumber, 100);
    expect(fixture.shell.newReplyCount, 0);
  });

  test(
    'superseded success and its echo preserve the newest selection',
    () async {
      final fixture = await _Fixture.load();
      final first = fixture.select(TopicNotificationLevel.muted);
      await pumpEventQueue();
      final skipped = fixture.select(TopicNotificationLevel.normal);
      final latest = fixture.select(TopicNotificationLevel.watching);
      fixture.bus(TopicNotificationLevel.muted);
      expect(fixture.tracking.topics.single.notificationLevel, 3);
      expect(fixture.shell.newReplyCount, 1);
      expect(
        fixture.shell.currentTopic?.notificationLevel,
        TopicNotificationLevel.watching,
      );
      fixture.finish();
      expect(await first, isTrue);
      expect(await skipped, isFalse);
      await pumpEventQueue();
      expect(fixture.api.requests.map((request) => request.level), [
        TopicNotificationLevel.muted,
        TopicNotificationLevel.watching,
      ]);
      fixture.bus(TopicNotificationLevel.muted);
      expect(fixture.tracking.topics.single.notificationLevel, 3);
      expect(fixture.shell.newReplyCount, 1);
      fixture.finish(succeeds: false);
      expect(await latest, isFalse);
      expect(fixture.tracking.topics.single.notificationLevel, 0);
      expect(
        fixture.shell.currentTopic?.notificationLevel,
        TopicNotificationLevel.muted,
      );
      expect(fixture.shell.newReplyCount, 0);
    },
  );

  test(
    'server topic events reconcile badges and the next rollback baseline',
    () async {
      final fixture = await _Fixture.load();
      fixture.bus(TopicNotificationLevel.normal);
      expect(fixture.shell.newReplyCount, 0);
      expect(
        fixture.shell.currentTopic?.notificationLevel,
        TopicNotificationLevel.normal,
      );
      fixture.bus(TopicNotificationLevel.watching);
      expect(fixture.shell.newReplyCount, 1);
      expect(
        fixture.shell.sidebarBadgeFor('tag-9'),
        const SidebarBadge.count(1),
      );
      final write = fixture.select(TopicNotificationLevel.muted);
      await pumpEventQueue();
      fixture.bus(TopicNotificationLevel.normal);
      expect(fixture.tracking.topics.single.notificationLevel, 0);
      fixture.finish(succeeds: false);
      expect(await write, isFalse);
      expect(fixture.tracking.topics.single.notificationLevel, 1);
      expect(
        fixture.shell.currentTopic?.notificationLevel,
        TopicNotificationLevel.normal,
      );
      expect(fixture.api.topicTrackingRequests, [_site]);
      expect(fixture.api.topicsOpened, isEmpty);
      expect(fixture.api.topicReadsRecorded, isEmpty);
    },
  );

  test('malformed or non-core topic events cannot change the level', () async {
    final fixture = await _Fixture.load();
    final revision = fixture.shell.topicTrackingRevisionFor(_site);
    for (final value in <Object?>[null, -1, 4, 1.5, '0', true, {}]) {
      fixture.tracker.deliverTopicMessage('/topic/7', {
        'notification_level_change': value,
      });
    }
    fixture.tracker.deliverTopicMessage('/plugin/7', {
      'notification_level_change': 0,
    });
    fixture.tracker.deliverTopicMessage('/topic/8', {
      'notification_level_change': 0,
    });
    expect(
      fixture.shell.currentTopic?.notificationLevel,
      TopicNotificationLevel.tracking,
    );
    expect(fixture.shell.newReplyCount, 1);
    expect(fixture.shell.topicTrackingRevisionFor(_site), revision);
  });

  for (final source in ['success', 'failure', 'bus', 'pending']) {
    test(
      'late initial snapshot retains $source notification reconciliation',
      () async {
        final gate = Completer<void>();
        final fixture = await _Fixture.load(snapshotGate: gate);
        expect(fixture.api.topicTrackingRequests, [_site]);
        expect(fixture.shell.sidebarBadgeFor('category-5'), SidebarBadge.none);
        Future<bool>? write;
        if (source == 'bus') {
          fixture.bus(TopicNotificationLevel.normal);
        } else {
          write = fixture.select(TopicNotificationLevel.normal);
          await pumpEventQueue();
          if (source != 'pending') {
            fixture.finish(succeeds: source == 'success');
            expect(await write, source == 'success');
            await pumpEventQueue();
          }
        }
        fixture.tracker.deliverTopicTracking({
          'topic_id': 7,
          'message_type': 'read',
          'payload': {
            'last_read_post_number': 90,
            'highest_post_number': 105,
            if (source == 'pending') 'notification_level': 2,
          },
        });
        gate.complete();
        await pumpEventQueue();
        expect(fixture.tracking.topics.single.lastReadPostNumber, 90);
        expect(fixture.tracking.topics.single.highestPostNumber, 105);
        expect(fixture.shell.newReplyCount, source == 'failure' ? 1 : 0);
        expect(
          fixture.tracking.topics.single.notificationLevel,
          source == 'failure' ? 2 : 1,
        );
        if (source == 'pending') {
          fixture.finish(succeeds: false);
          expect(await write!, isFalse);
          expect(fixture.shell.newReplyCount, 1);
          expect(fixture.tracking.topics.single.lastReadPostNumber, 90);
        }
        expect(fixture.api.topicTrackingRequests, [_site]);
      },
    );
  }

  test('a delayed bootstrap retains a completed native selection', () async {
    final gate = Completer<void>();
    final tracking = TopicTrackingState([_tracked]);
    final api = _NotificationApi(
      messageBusBootstrapGate: gate,
      messageBusBootstrapResult: SiteMessageBusBootstrap(
        currentUser: _reader,
        currentUserState: null,
        topicTrackingState: tracking,
        topicTrackingLastIds: const {
          '/latest': 1,
          '/new': 1,
          '/unread': 1,
          '/unread/7': 1,
          '/delete': 1,
          '/recover': 1,
          '/destroy': 1,
        },
        notificationChannelPosition: null,
      ),
    );
    final fixture = await _Fixture.load(api: api);
    final write = fixture.select(TopicNotificationLevel.normal);
    await pumpEventQueue();
    fixture.finish();
    expect(await write, isTrue);
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();
    expect(fixture.shell.newReplyCount, 0);
    expect(tracking.topics.single.notificationLevel, 1);
    expect(tracking.topics.single.lastReadPostNumber, 80);
    expect(api.topicTrackingRequests, isEmpty);
  });

  test(
    'retired account writes and topic callbacks cannot alter its replacement',
    () async {
      final fixture = await _Fixture.load();
      final oldTracker = fixture.tracker;
      final oldWrite = fixture.select(TopicNotificationLevel.normal);
      await pumpEventQueue();
      fixture.shell.lifecycle.invalidate(_site);
      oldTracker.deliverTopicMessage('/topic/7', {
        'notification_level_change': 3,
      });
      expect(fixture.tracking.topics.single.notificationLevel, 1);
      fixture.shell.clearAccountSessionState(_site);
      fixture.api.snapshots[_site] = TopicTrackingState([_tracked]);
      fixture.auth.keys[_site] = 'replacement-key';
      fixture.shell.applyAccountSessionInstance(
        fixture.shell.currentInstance!.copyWith(
          user: const DiscourseUser(
            id: 8,
            username: 'replacement',
            unifiedNewEnabled: true,
            sidebarShowCountOfNewItems: true,
          ),
        ),
        AccountSessionPhase.connected,
      );
      await pumpEventQueue();
      fixture.open();
      await pumpEventQueue();
      final replacement = fixture.select(TopicNotificationLevel.muted);
      await pumpEventQueue();
      fixture.api.requests.first.result.complete();
      expect(await oldWrite, isFalse);
      expect(fixture.tracking.topics.single.notificationLevel, 0);
      fixture.finish(succeeds: false);
      expect(await replacement, isFalse);
      expect(fixture.tracking.topics.single.notificationLevel, 2);
      expect(fixture.shell.newReplyCount, 1);
      expect(oldTracker.disposed, isTrue);
    },
  );

  test(
    'notification queues and counters remain scoped to each topic and site',
    () async {
      const otherTopic = TrackedTopicState(
        topicId: 8,
        highestPostNumber: 12,
        lastReadPostNumber: 10,
        notificationLevel: 2,
        categoryId: 5,
      );
      final api = _NotificationApi()
        ..snapshots.addAll({
          _site: TopicTrackingState([_tracked, otherTopic]),
          _otherSite: TopicTrackingState([_tracked]),
        });
      final fixture = await _Fixture.load(api: api, sites: [_site, _otherSite]);
      fixture.shell.store.put(
        _site,
        const TopicDetail(
          id: 8,
          title: 'Another topic',
          stream: [],
          notificationLevel: TopicNotificationLevel.tracking,
        ),
      );
      final first = fixture.select(TopicNotificationLevel.normal);
      final second = fixture.shell.updateTopicNotificationLevel(
        _site,
        8,
        TopicNotificationLevel.muted,
      );
      expect(fixture.shell.newReplyCount, 0);
      fixture.shell.selectInstance(1);
      fixture.open(siteUrl: _otherSite);
      expect(fixture.shell.newReplyCount, 1);
      final otherSite = fixture.select(
        TopicNotificationLevel.normal,
        siteUrl: _otherSite,
      );
      await pumpEventQueue();
      final requests = fixture.api.requests;
      expect(
        requests.map((request) => (request.siteUrl, request.topicId)).toSet(),
        {(_site, 7), (_site, 8), (_otherSite, 7)},
      );
      for (final request in requests) {
        if (request.siteUrl == _otherSite) {
          request.result.completeError(
            const WriteException(WriteFailure.forbidden),
          );
        } else {
          request.result.complete();
        }
      }
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(await otherSite, isFalse);
      expect(fixture.shell.newReplyCount, 1);
      fixture.shell.selectInstance(0);
      expect(fixture.shell.newReplyCount, 0);
      expect(fixture.tracking.topics.map((topic) => topic.notificationLevel), [
        1,
        0,
      ]);
    },
  );

  test(
    'an old account snapshot cannot replace the new account tracking state',
    () async {
      final gate = Completer<void>();
      final fixture = await _Fixture.load(snapshotGate: gate);
      fixture.bus(TopicNotificationLevel.normal);
      fixture.shell.lifecycle.invalidate(_site);
      fixture.shell.clearAccountSessionState(_site);
      fixture.api.trackingStateGate = null;
      fixture.api.snapshots[_site] = TopicTrackingState([_tracked]);
      fixture.shell.applyAccountSessionInstance(
        fixture.shell.currentInstance!.copyWith(user: _reader),
        AccountSessionPhase.connected,
      );
      await pumpEventQueue();
      expect(fixture.shell.newReplyCount, 1);
      gate.complete();
      await pumpEventQueue();
      expect(fixture.shell.newReplyCount, 1);
      expect(fixture.tracking.topics.single.notificationLevel, 2);
      expect(fixture.api.topicTrackingRequests, [_site, _site]);
    },
  );
}

final class _Fixture {
  _Fixture(this.shell, this.api, this.auth);

  final ShellController shell;
  final _NotificationApi api;
  final FakeAuthenticator auth;

  TopicTrackingState get tracking => api.snapshots[_site]!;
  FakeSiteTracker get tracker =>
      FakeSiteTracker.built.lastWhere((tracker) => tracker.siteUrl == _site);

  static Future<_Fixture> load({
    _NotificationApi? api,
    Completer<void>? snapshotGate,
    List<String> sites = const [_site],
  }) async {
    api ??= _NotificationApi(trackingStateGate: snapshotGate);
    api.snapshots.putIfAbsent(_site, () => TopicTrackingState([_tracked]));
    final auth = FakeAuthenticator()
      ..keys.addAll({for (final site in sites) site: 'reader-key'});
    final shell = ShellController(
      instanceStore: FakeInstanceStore([
        for (final site in sites)
          instance(Uri.parse(site).host).copyWith(user: _reader),
      ]),
      api: api,
      authenticator: auth,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
    );
    final fixture = _Fixture(shell, api, auth);
    addTearDown(() async {
      shell.dispose();
      for (final request in api!.requests) {
        if (!request.result.isCompleted) request.result.complete();
      }
      if (snapshotGate != null && !snapshotGate.isCompleted) {
        snapshotGate.complete();
      }
      await pumpEventQueue();
    });
    await shell.load();
    await pumpEventQueue();
    fixture.open();
    await pumpEventQueue();
    return fixture;
  }

  void open({String siteUrl = _site}) {
    shell.store.put(siteUrl, _topicRow);
    shell.store.put(siteUrl, _detail);
    shell.store.put(siteUrl, _firstPost);
    shell.openTopicPost(siteUrl: siteUrl, topicId: 7, postNumber: 1);
  }

  Future<bool> select(TopicNotificationLevel level, {String siteUrl = _site}) =>
      shell.updateTopicNotificationLevel(siteUrl, 7, level);

  void bus(TopicNotificationLevel level) => tracker.deliverTopicMessage(
    '/topic/7',
    {'notification_level_change': level.value},
  );

  void finish({bool succeeds = true}) {
    final result = api.requests.last.result;
    if (succeeds) {
      result.complete();
    } else {
      result.completeError(const WriteException(WriteFailure.forbidden));
    }
  }
}

final class _Request {
  _Request(this.siteUrl, this.topicId, this.level);

  final String siteUrl;
  final int topicId;
  final TopicNotificationLevel level;
  final result = Completer<void>();
}

final class _NotificationApi extends FakeDiscourseApi {
  _NotificationApi({
    super.trackingState,
    super.trackingStateGate,
    super.messageBusBootstrapGate,
    super.messageBusBootstrapResult,
  }) : super(
         user: _reader,
         feeds: const {
           '/latest.json': [_topicRow],
         },
         categoryList: const [_category],
         topics: {
           7: (detail: _detail, posts: const [_firstPost]),
         },
       );

  final requests = <_Request>[];
  final snapshots = <String, TopicTrackingState>{};

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    topicTrackingRequests.add(siteUrl);
    final snapshot =
        snapshots[siteUrl] ?? trackingState ?? TopicTrackingState();
    await trackingStateGate?.future;
    return snapshot;
  }

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) {
    final request = _Request(siteUrl, topicId, notificationLevel);
    requests.add(request);
    return request.result.future;
  }
}
