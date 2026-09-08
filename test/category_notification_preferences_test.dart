import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/account_session_coordinator.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/site_message_bus_bootstrap.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _parent = TopicCategory(
  id: 1,
  name: 'Parent',
  slug: 'parent',
  color: '111111',
);
const _children = [
  TopicCategory(id: 2, name: 'Inherited', color: '222222', parentCategoryId: 1),
  TopicCategory(
    id: 3,
    name: 'Normal child',
    color: '333333',
    parentCategoryId: 1,
  ),
  TopicCategory(id: 4, name: 'Other', color: '444444'),
];

DiscourseUser _user({
  int id = 7,
  List<int> muted = const [],
  List<int> indirectlyMuted = const [],
}) => const DiscourseModelCodec.core().currentUser({
  'id': id,
  'username': 'reader',
  'muted_category_ids': muted,
  'indirectly_muted_category_ids': indirectlyMuted,
  'tracked_category_ids': <int>[],
  'watched_category_ids': <int>[],
  'watched_first_post_category_ids': <int>[],
  'unified_new_enabled': true,
  'user_option': {'sidebar_show_count_of_new_items': true},
}, _site);

Map<String, Object?> _row(int id, int categoryId, {int? level}) => {
  'topic_id': id,
  'category_id': categoryId,
  'notification_level': level,
  'highest_post_number': 1,
  'last_read_post_number': null,
  'created_in_new_period': true,
};

Map<String, Object?> _newTopic(int id, int categoryId) => {
  'topic_id': id,
  'message_type': 'new_topic',
  'payload': {
    'category_id': categoryId,
    'highest_post_number': 1,
    'last_read_post_number': null,
    'created_in_new_period': true,
  },
};

Future<ShellController> _openCategory(
  WidgetTester tester,
  _PreferenceApi api,
) async {
  await pumpShell(
    tester,
    laptop,
    instances: [instance('meta.discourse.org').copyWith(user: api.user)],
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
  );
  final shell = ShellScope.read(tester.element(find.byType(MainContent)));
  expect(shell.openListUrl('/c/parent/1'), isTrue);
  await tester.pumpAndSettle();
  return shell;
}

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(
    find.byKey(const ValueKey('category-notification-level-button')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<ShellController> _loadShell(
  _PreferenceApi api, {
  FakeInstanceStore? store,
}) async {
  final shell = ShellController(
    instanceStore:
        store ??
        FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: api.user),
        ]),
    api: api,
    authenticator: FakeAuthenticator()..keys[_site] = 'api-key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  return shell;
}

void main() {
  testWidgets('native Normal choice admits subsequent public new topics', (
    tester,
  ) async {
    final api = _PreferenceApi(
      _user(muted: [1], indirectlyMuted: [2]),
      level: CategoryNotificationLevel.muted,
    );
    final shell = await _openCategory(tester, api);

    await _choose(tester, 'Normal');
    expect(api.writes.single.url.path, '/category/1/notifications');
    expect(jsonDecode(api.writes.single.body), {'notification_level': 1});
    final tracker = FakeSiteTracker.built.single;
    tracker.deliver(_newTopic(10, 1));
    tracker.deliver(_newTopic(11, 2));
    await tester.pumpAndSettle();

    expect(shell.newTopicCount, 2);
    expect(shell.currentInstance!.user!.mutedCategoryIds, isEmpty);
    expect(shell.currentInstance!.user!.indirectlyMutedCategoryIds, isEmpty);
    expect(shell.sidebarBadgeFor('category-1'), const SidebarBadge.count(2));
  });

  testWidgets(
    'native Muted choice settles loaded badges and keeps explicit overrides',
    (tester) async {
      final api = _PreferenceApi(_user())
        ..indirectlyMuted = [2]
        ..rows = [
          _row(10, 1),
          _row(11, 2),
          _row(12, 3),
          _row(13, 4),
          _row(14, 1, level: 3),
        ];
      final shell = await _openCategory(tester, api);
      expect(shell.newTopicCount, 5);
      expect(shell.sidebarBadgeFor('category-1'), const SidebarBadge.count(4));
      // Core's personalized report excludes muted categories while retaining
      // the explicit Normal child and individually watched topic in the parent.
      api.rows = [_row(12, 3), _row(13, 4), _row(14, 1, level: 3)];

      await _choose(tester, 'Muted');

      expect(shell.newTopicCount, 3);
      expect(shell.currentInstance!.user!.mutedCategoryIds, [1]);
      expect(shell.currentInstance!.user!.indirectlyMutedCategoryIds, [2]);
      expect(shell.sidebarBadgeFor('category-1'), const SidebarBadge.count(2));
      final tracker = FakeSiteTracker.built.single;
      tracker.deliver(_newTopic(15, 1));
      tracker.deliver(_newTopic(16, 2));
      tracker.deliver(_newTopic(17, 3));
      await tester.pumpAndSettle();
      expect(shell.newTopicCount, 4);
      expect(shell.sidebarBadgeFor('category-2'), SidebarBadge.none);
      expect(shell.sidebarBadgeFor('category-3'), const SidebarBadge.count(2));
    },
  );

  test(
    'committed choices move preference memberships and persist other categories',
    () async {
      final user = _user().withCategoryNotificationPreferences(
        trackedCategoryIds: const [1, 40],
        watchedCategoryIds: const [41],
        watchedFirstPostCategoryIds: const [42],
        mutedCategoryIds: const [43],
        indirectlyMutedCategoryIds: const [],
      );
      final api = _PreferenceApi(
        user,
        level: CategoryNotificationLevel.tracking,
      );
      final store = FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: user),
      ]);
      final shell = await _loadShell(api, store: store);
      for (final level in [
        CategoryNotificationLevel.watching,
        CategoryNotificationLevel.watchingFirstPost,
        CategoryNotificationLevel.normal,
        CategoryNotificationLevel.muted,
        CategoryNotificationLevel.tracking,
      ]) {
        expect(
          await shell.updateCategoryNotificationLevel(_site, 1, level),
          isTrue,
        );
        await pumpEventQueue();
        final updated = shell.currentInstance!.user!;
        expect(updated.trackedCategoryIds, [
          40,
          if (level == CategoryNotificationLevel.tracking) 1,
        ]);
        expect(updated.watchedCategoryIds, [
          41,
          if (level == CategoryNotificationLevel.watching) 1,
        ]);
        expect(updated.watchedFirstPostCategoryIds, [
          42,
          if (level == CategoryNotificationLevel.watchingFirstPost) 1,
        ]);
        expect(updated.mutedCategoryIds, [
          43,
          if (level == CategoryNotificationLevel.muted) 1,
        ]);
        expect((await store.load()).single.user, updated);
      }
    },
  );

  test(
    'a category preference read keeps live status, counters and other account fields',
    () async {
      final original = DiscourseUser.fromJson({
        ..._user().toJson(),
        'name': 'Reader name',
        'canCreateTopic': true,
        'groups': const ['helpers'],
        'sidebarCategoryIds': const [4],
        'hidePresence': true,
        'timezone': 'Europe/Paris',
        'groupedUnreadNotifications': const {'1': 2},
      });
      final api = _PreferenceApi(original);
      final shell = await _loadShell(api);
      api.indirectlyMuted = null;
      final gate = Completer<DiscourseUser>();
      api.userResponse = gate;
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      await pumpEventQueue();
      final tracker = FakeSiteTracker.built.single;
      tracker.deliverPluginMessage('/user-status', const {
        '7': {'description': 'Writing', 'emoji': 'pencil'},
      });
      tracker.deliverPluginMessage('/user-drafts/7', const {'draft_count': 5});
      tracker.onNotifications(const {
        'all_unread_notifications_count': 6,
        'grouped_unread_notifications': {'1': 4},
      });
      final held = shell.currentInstance!.user!.toJson();
      final totals = shell.currentTotals;
      gate.complete(_user(muted: [1], indirectlyMuted: [2]));
      await pumpEventQueue();
      expect(shell.currentInstance!.user!.toJson(), {
        ...held,
        'indirectlyMutedCategoryIds': [2],
      });
      expect(shell.currentInstance!.user!.draftCount, 5);
      expect(shell.currentInstance!.user!.status!.description, 'Writing');
      expect(shell.currentTotals, totals);
      expect(shell.currentInstance!.user!.canCreateTopic, isTrue);
    },
  );

  test(
    'an explicit Normal child stays unmuted inside a muted parent',
    () async {
      final api = _PreferenceApi(_user(muted: [1, 2]));
      final shell = await _loadShell(api);
      shell.store.put(
        _site,
        _children.first.withNotificationLevel(CategoryNotificationLevel.muted),
      );
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          2,
          CategoryNotificationLevel.normal,
        ),
        isTrue,
      );
      await pumpEventQueue();
      final tracker = FakeSiteTracker.built.single;
      tracker.deliver(_newTopic(10, 1));
      tracker.deliver(_newTopic(11, 2));
      expect(shell.currentInstance!.user!.mutedCategoryIds, [1]);
      expect(shell.currentInstance!.user!.indirectlyMutedCategoryIds, isEmpty);
      expect(shell.newTopicCount, 1);
      expect(shell.sidebarBadgeFor('category-2'), const SidebarBadge.count(1));
    },
  );

  test(
    'a rejected later choice retains the last committed preferences',
    () async {
      final api = _PreferenceApi(_user())..indirectlyMuted = [2];
      final shell = await _loadShell(api);
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      await pumpEventQueue();
      final loaded = api.topicTrackingRequests.length;
      final gate = Completer<void>();
      api.writeGate = gate;
      final rejected = shell.updateCategoryNotificationLevel(
        _site,
        1,
        CategoryNotificationLevel.watching,
      );
      await pumpEventQueue();
      expect(
        shell.categoryFor(1)!.notificationLevel,
        CategoryNotificationLevel.watching,
      );
      expect(shell.currentInstance!.user!.mutedCategoryIds, [1]);
      gate.completeError(StateError('rejected'));
      expect(await rejected, isFalse);
      await pumpEventQueue();
      expect(
        shell.categoryFor(1)!.notificationLevel,
        CategoryNotificationLevel.muted,
      );
      expect(shell.currentInstance!.user!.watchedCategoryIds, isEmpty);
      expect(shell.currentInstance!.user!.indirectlyMutedCategoryIds, [2]);
      expect(api.topicTrackingRequests, hasLength(loaded));
    },
  );

  for (final fails in ['snapshot', 'preferences']) {
    test(
      'a failed $fails refresh preserves the successful setting and retries',
      () async {
        final api = _PreferenceApi(_user())..rows = [_row(10, 1)];
        final shell = await _loadShell(api);
        final gate = Completer<void>();
        final userGate = Completer<DiscourseUser>();
        if (fails == 'snapshot') {
          api.snapshotGate = gate;
          api.indirectlyMuted = [2];
        } else {
          api.indirectlyMuted = null;
          api.userResponse = userGate;
        }
        expect(
          await shell.updateCategoryNotificationLevel(
            _site,
            1,
            CategoryNotificationLevel.muted,
          ),
          isTrue,
        );
        await pumpEventQueue();
        if (fails == 'snapshot') {
          gate.completeError(StateError('offline'));
        } else {
          userGate.completeError(StateError('offline'));
        }
        await pumpEventQueue();
        expect(
          shell.categoryFor(1)!.notificationLevel,
          CategoryNotificationLevel.muted,
        );
        expect(shell.currentInstance!.user!.mutedCategoryIds, [1]);
        expect(shell.newTopicCount, 1);
        api.snapshotGate = null;
        api.userResponse = null;
        api.sessionUser = _user(muted: [1], indirectlyMuted: [2]);
        api.rows = [];
        final tracker = FakeSiteTracker.built.single;
        tracker.deliverTopicTracking(const {
          'message_type': 'latest',
          'topic_id': 99,
        });
        await pumpEventQueue();
        expect(shell.newTopicCount, 0);
        expect(shell.currentInstance!.user!.indirectlyMutedCategoryIds, [2]);
        tracker.deliver(_newTopic(11, 1));
        tracker.deliver(_newTopic(12, 2));
        tracker.deliver(_newTopic(13, 3));
        expect(shell.newTopicCount, 1);
        expect(api.writes, hasLength(1));
      },
    );
  }

  test(
    'refresh replays live reads and topic choices while keeping a pending choice',
    () async {
      final api = _PreferenceApi(_user())
        ..rows = [
          {
            ..._row(20, 4, level: 2),
            'highest_post_number': 3,
            'last_read_post_number': 1,
          },
          {
            ..._row(21, 4, level: 3),
            'highest_post_number': 3,
            'last_read_post_number': 1,
          },
        ];
      final shell = await _loadShell(api);
      final tracker = FakeSiteTracker.built.single;
      shell.store.put(
        _site,
        const TopicDetail(
          id: 20,
          title: 'Pending',
          stream: [],
          notificationLevel: TopicNotificationLevel.tracking,
        ),
      );
      shell.store.put(
        _site,
        const TopicDetail(
          id: 21,
          title: 'Settled',
          stream: [],
          notificationLevel: TopicNotificationLevel.watching,
        ),
      );
      final notificationGate = Completer<void>();
      api.notificationGate = notificationGate;
      final topicWrite = shell.updateTopicNotificationLevel(
        _site,
        20,
        TopicNotificationLevel.normal,
      );
      await pumpEventQueue();
      final snapshotGate = Completer<void>();
      api.snapshotGate = snapshotGate;
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      await pumpEventQueue();
      api.notificationGate = null;
      expect(
        await shell.updateTopicNotificationLevel(
          _site,
          21,
          TopicNotificationLevel.normal,
        ),
        isTrue,
      );
      tracker.deliverTopicTracking(const {
        'topic_id': 20,
        'message_type': 'read',
        'payload': {'last_read_post_number': 3},
      });
      tracker.deliver(_newTopic(22, 4));
      tracker.deliver(_newTopic(23, 1));
      snapshotGate.complete();
      await pumpEventQueue();
      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
      expect(shell.sidebarBadgeFor('category-4'), const SidebarBadge.count(1));
      notificationGate.completeError(
        const WriteException(WriteFailure.forbidden),
      );
      expect(await topicWrite, isFalse);
      expect(
        shell.newReplyCount,
        0,
        reason: 'the read cursor survived the refresh and rollback',
      );
      tracker.deliverTopicTracking(const {
        'topic_id': 20,
        'message_type': 'unread',
        'payload': {'highest_post_number': 4},
      });
      expect(shell.newReplyCount, 1);
    },
  );

  for (final staleFails in [false, true]) {
    test(
      'superseded ${staleFails ? 'failed' : 'successful'} refresh leaves the newest replay buffer owned',
      () async {
        final initial = Completer<void>();
        final api = _PreferenceApi(_user())
          ..rows = [_row(10, 1)]
          ..snapshotGate = initial;
        final shell = await _loadShell(api);
        final muted = Completer<void>();
        api.snapshotGate = muted;
        api.rows = [];
        api.indirectlyMuted = [2];
        expect(
          await shell.updateCategoryNotificationLevel(
            _site,
            1,
            CategoryNotificationLevel.muted,
          ),
          isTrue,
        );
        final normal = Completer<void>();
        api.snapshotGate = normal;
        api.rows = [_row(10, 1)];
        api.indirectlyMuted = [];
        expect(
          await shell.updateCategoryNotificationLevel(
            _site,
            1,
            CategoryNotificationLevel.normal,
          ),
          isTrue,
        );
        initial.complete();
        if (staleFails) {
          muted.completeError(StateError('stale failure'));
        } else {
          muted.complete();
        }
        await pumpEventQueue();
        FakeSiteTracker.built.single.deliver(_newTopic(11, 2));
        normal.complete();
        await pumpEventQueue();
        expect(shell.newTopicCount, 2);
        expect(shell.currentInstance!.user!.mutedCategoryIds, isEmpty);
        expect(
          shell.currentInstance!.user!.indirectlyMutedCategoryIds,
          isEmpty,
        );
        expect(api.topicTrackingRequests, hasLength(3));
      },
    );
  }

  test(
    'category writes are ordered across categories without delaying optimistic choices',
    () async {
      final api = _PreferenceApi(_user());
      final shell = await _loadShell(api);
      final gate = Completer<void>();
      api.writeGate = gate;
      api.indirectlyMuted = [2];
      final parent = shell.updateCategoryNotificationLevel(
        _site,
        1,
        CategoryNotificationLevel.muted,
      );
      await pumpEventQueue();
      api.writeGate = null;
      api.indirectlyMuted = [];
      final child = shell.updateCategoryNotificationLevel(
        _site,
        2,
        CategoryNotificationLevel.tracking,
      );
      expect(
        shell.categoryFor(2)!.notificationLevel,
        CategoryNotificationLevel.tracking,
      );
      await pumpEventQueue();
      expect(api.writes, hasLength(1));
      gate.complete();
      expect(await parent, isTrue);
      expect(await child, isTrue);
      await pumpEventQueue();
      expect(shell.currentInstance!.user!.mutedCategoryIds, [1]);
      expect(shell.currentInstance!.user!.trackedCategoryIds, [2]);
      expect(shell.currentInstance!.user!.indirectlyMutedCategoryIds, isEmpty);
    },
  );

  test(
    'stale account preference and tracking responses cannot overwrite a replacement',
    () async {
      final api = _PreferenceApi(_user());
      final shell = await _loadShell(api);
      final userGate = Completer<DiscourseUser>();
      api.indirectlyMuted = null;
      api.userResponse = userGate;
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      await pumpEventQueue();
      shell.lifecycle.invalidate(_site);
      shell.clearAccountSessionState(_site);
      final replacement = _user(id: 8, muted: [4]);
      shell.applyAccountSessionInstance(
        shell.currentInstance!.copyWith(user: replacement),
        AccountSessionPhase.connecting,
      );
      shell.store.put(_site, _parent);
      api.sessionUser = replacement;
      api.userResponse = null;
      api.indirectlyMuted = [];
      final freshGate = Completer<void>();
      api.snapshotGate = freshGate;
      api.rows = [_row(30, 1)];
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          1,
          CategoryNotificationLevel.watching,
        ),
        isTrue,
      );
      userGate.complete(_user(muted: [1], indirectlyMuted: [2]));
      await pumpEventQueue();
      freshGate.complete();
      await pumpEventQueue();
      expect(shell.currentInstance!.user!.id, 8);
      expect(shell.currentInstance!.user!.mutedCategoryIds, [4]);
      expect(shell.currentInstance!.user!.watchedCategoryIds, [1]);
      expect(shell.newTopicCount, 1);
    },
  );

  test(
    'a bootstrap started before the edit cannot restore its old preferences or report',
    () async {
      final gate = Completer<void>();
      final oldUser = _user();
      final api = _PreferenceApi(
        oldUser,
        messageBusBootstrapGate: gate,
        messageBusBootstrapResult: SiteMessageBusBootstrap(
          currentUser: oldUser,
          currentUserState: null,
          topicTrackingState: TopicTrackingState.fromJson([_row(10, 1)]),
          topicTrackingLastIds: const {
            '/latest': 1,
            '/new': 2,
            '/unread': 3,
            '/unread/7': 4,
            '/delete': 5,
            '/recover': 6,
            '/destroy': 7,
          },
          notificationChannelPosition: null,
        ),
      );
      final shell = await _loadShell(api);
      expect(
        await shell.updateCategoryNotificationLevel(
          _site,
          1,
          CategoryNotificationLevel.muted,
        ),
        isTrue,
      );
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      expect(shell.currentInstance!.user!.mutedCategoryIds, [1]);
      expect(shell.newTopicCount, 0);
      FakeSiteTracker.built.single.deliver(_newTopic(11, 1));
      expect(shell.newTopicCount, 0);
    },
  );
}

final class _PreferenceApi extends FakeDiscourseApi {
  _PreferenceApi(
    DiscourseUser user, {
    CategoryNotificationLevel level = CategoryNotificationLevel.normal,
    super.messageBusBootstrapGate,
    super.messageBusBootstrapResult,
  }) : sessionUser = user,
       super(
         user: user,
         feeds: const {'/latest.json': [], '/c/parent/1.json': []},
         categoryList: [_parent.withNotificationLevel(level), ..._children],
       );

  List<int>? indirectlyMuted = [];
  List<Map<String, Object?>> rows = [];
  final writes = <http.Request>[];
  Completer<void>? snapshotGate;
  Completer<void>? writeGate;
  Completer<void>? notificationGate;
  Completer<DiscourseUser>? userResponse;
  DiscourseUser sessionUser;

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async {
    currentUserRequests.add(siteUrl);
    return userResponse == null ? sessionUser : await userResponse!.future;
  }

  @override
  Future<void> updateTopicNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int topicId,
    required TopicNotificationLevel notificationLevel,
    String? clientId,
  }) async {
    await notificationGate?.future;
  }

  @override
  Future<List<int>?> updateCategoryNotificationLevel({
    required String siteUrl,
    required String apiKey,
    required int categoryId,
    required CategoryNotificationLevel notificationLevel,
    String? clientId,
  }) =>
      DiscourseApi(
        client: MockClient((request) async {
          writes.add(request);
          final ids = indirectlyMuted;
          await writeGate?.future;
          return http.Response(
            jsonEncode({
              'success': 'OK',
              'indirectly_muted_category_ids': ?ids,
            }),
            200,
          );
        }),
      ).updateCategoryNotificationLevel(
        siteUrl: siteUrl,
        apiKey: apiKey,
        categoryId: categoryId,
        notificationLevel: notificationLevel,
        clientId: clientId,
      );

  @override
  Future<TopicTrackingState> topicTrackingState({
    required String siteUrl,
    required String apiKey,
    required String username,
    String? clientId,
  }) async {
    topicTrackingRequests.add(siteUrl);
    final snapshot = TopicTrackingState.fromJson(rows);
    await snapshotGate?.future;
    return snapshot;
  }
}
