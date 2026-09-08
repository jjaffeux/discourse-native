import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _categories = [
  TopicCategory(id: 1, name: 'Muted', color: '111111'),
  TopicCategory(
    id: 2,
    name: 'Inherited mute',
    color: '222222',
    parentCategoryId: 1,
  ),
  TopicCategory(
    id: 3,
    name: 'Regular child',
    color: '333333',
    parentCategoryId: 1,
  ),
  TopicCategory(id: 4, name: 'Ordinary', color: '444444'),
];

DiscourseUser _user({
  int id = 7,
  List<int> muted = const [1],
  List<int> indirectlyMuted = const [2],
}) => const DiscourseModelCodec.core().currentUser({
  'id': id,
  'username': 'author$id',
  'muted_category_ids': muted,
  // Core resolves inherited muting, excluding an explicitly regular child.
  'indirectly_muted_category_ids': indirectlyMuted,
  'unified_new_enabled': true,
  'user_option': {'sidebar_show_count_of_new_items': true},
}, _site);

Map<String, Object?> _newTopic(int id, int categoryId) => {
  'topic_id': id,
  'message_type': 'new_topic',
  'payload': {
    'highest_post_number': 1,
    'last_read_post_number': null,
    'created_in_new_period': true,
    'category_id': categoryId,
  },
};

Future<ShellController> _loadShell(
  FakeDiscourseApi api, {
  DateTime Function()? clock,
}) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'api-key';
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user()),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    plugins: installedPlugins,
    clock: clock,
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  return shell;
}

final class _AccountApi extends FakeDiscourseApi {
  _AccountApi() : super(categoryList: _categories);

  DiscourseUser sessionUser = _user();

  @override
  Future<DiscourseUser> currentUser({
    required String siteUrl,
    required String apiKey,
    String? clientId,
  }) async => sessionUser;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final duringLoad in [false, true]) {
    test(
      'muted public new topics stay out of counters ${duringLoad ? 'during snapshot replay' : 'after snapshot load'}',
      () async {
        final gate = Completer<void>();
        final api = FakeDiscourseApi(
          user: _user(),
          categoryList: _categories,
          trackingStateGate: gate,
        );
        final shell = await _loadShell(api);
        final tracker = FakeSiteTracker.built.single;
        expect(api.topicTrackingRequests, [_site]);
        if (!duringLoad) {
          gate.complete();
          await pumpEventQueue();
        }

        tracker.deliver(_newTopic(10, 1));
        tracker.deliver(_newTopic(11, 2));
        if (duringLoad) gate.complete();
        await pumpEventQueue();

        expect(shell.topicListNewCounts, (all: 0, topics: 0, replies: 0));
        expect(shell.sidebarBadgeFor('latest'), SidebarBadge.none);
        expect(shell.sidebarBadgeFor('category-1'), SidebarBadge.none);
        expect(shell.sidebarBadgeFor('category-2'), SidebarBadge.none);
        // The feed-arrival path keeps receiving the public messages.
        expect(tracker.incoming.topicIds('new'), [10, 11]);

        tracker.deliver(_newTopic(12, 3));
        tracker.deliver(_newTopic(13, 4));
        tracker.deliverTopicTracking(const {
          'topic_id': 14,
          'message_type': 'unread',
          'payload': {'highest_post_number': 3, 'category_id': 2},
        });
        await pumpEventQueue();

        expect(shell.topicListNewCounts, (all: 3, topics: 2, replies: 1));
        expect(shell.sidebarBadgeFor('latest'), const SidebarBadge.count(3));
        expect(
          shell.sidebarBadgeFor('category-1'),
          const SidebarBadge.count(2),
        );
        expect(
          shell.sidebarBadgeFor('category-2'),
          const SidebarBadge.count(1),
        );
        expect(
          shell.sidebarBadgeFor('category-3'),
          const SidebarBadge.count(1),
        );
        expect(
          shell.sidebarBadgeFor('category-4'),
          const SidebarBadge.count(1),
        );
      },
    );
  }

  test(
    'personalized tracked and watched topics survive muted public duplicates',
    () async {
      final api = FakeDiscourseApi(
        user: _user(),
        categoryList: _categories,
        trackingState: TopicTrackingState.fromJson(const [
          {
            'topic_id': 20,
            'category_id': 1,
            'notification_level': 2,
            'highest_post_number': 1,
            'last_read_post_number': null,
            'created_in_new_period': true,
          },
          {
            'topic_id': 21,
            'category_id': 2,
            'notification_level': 3,
            'highest_post_number': 3,
            'last_read_post_number': 1,
          },
        ]),
      );
      final shell = await _loadShell(api);
      final tracker = FakeSiteTracker.built.single;
      expect(shell.topicListNewCounts, (all: 2, topics: 1, replies: 1));

      tracker.deliver(_newTopic(20, 1));
      tracker.deliver(_newTopic(21, 2));
      expect(shell.topicListNewCounts, (all: 2, topics: 1, replies: 1));
      expect(shell.sidebarBadgeFor('category-1'), const SidebarBadge.count(2));

      tracker.deliverTopicTracking(const {
        'topic_id': 21,
        'message_type': 'read',
        'payload': {'last_read_post_number': 3, 'category_id': 2},
      });
      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
      expect(shell.sidebarBadgeFor('category-2'), SidebarBadge.none);
      tracker.deliverTopicTracking(const {
        'topic_id': 21,
        'message_type': 'unread',
        'payload': {'highest_post_number': 4, 'category_id': 2},
      });
      expect(shell.topicListNewCounts, (all: 2, topics: 1, replies: 1));
    },
  );

  test(
    'snapshot replay preserves arrival-time admission without renewing hints',
    () async {
      var now = DateTime.utc(2026);
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        user: _user(),
        categoryList: _categories,
        trackingStateGate: gate,
      );
      final shell = await _loadShell(api, clock: () => now);
      final tracker = FakeSiteTracker.built.single;

      tracker.deliver(_newTopic(10, 1));
      tracker.deliver(const {'topic_id': 10, 'message_type': 'unmuted'});
      tracker.deliver(const {'topic_id': 11, 'message_type': 'unmuted'});
      tracker.deliver(_newTopic(11, 2));
      tracker.deliver(const {'topic_id': 12, 'message_type': 'unmuted'});
      tracker.deliver(_newTopic(13, 4));
      tracker.deliverTopicTracking(const {
        'topic_id': 14,
        'message_type': 'unread',
        'payload': {'highest_post_number': 3, 'category_id': 1},
      });
      now = now.add(const Duration(seconds: 61));
      gate.complete();
      await pumpEventQueue();

      // A later hint cannot resurrect 10, and 11 was admitted before expiry.
      expect(shell.topicListNewCounts, (all: 3, topics: 2, replies: 1));
      tracker.deliver(_newTopic(10, 1));
      tracker.deliver(_newTopic(12, 1));
      expect(shell.topicListNewCounts, (all: 3, topics: 2, replies: 1));
    },
  );

  test(
    'an unexpired hint survives replacing the provisional snapshot',
    () async {
      var now = DateTime.utc(2026);
      final gate = Completer<void>();
      final api = FakeDiscourseApi(user: _user(), trackingStateGate: gate);
      final shell = await _loadShell(api, clock: () => now);
      final tracker = FakeSiteTracker.built.single;
      tracker.deliver(const {'topic_id': 10, 'message_type': 'unmuted'});
      gate.complete();
      await pumpEventQueue();

      now = now.add(const Duration(seconds: 59));
      tracker.deliver(_newTopic(10, 2));
      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
    },
  );

  test(
    'snapshot retry retains a preceding hint and replays admitted events',
    () async {
      var now = DateTime.utc(2026);
      final failed = Completer<void>();
      final retry = Completer<void>();
      final api = FakeDiscourseApi(user: _user(), trackingStateGate: failed);
      final shell = await _loadShell(api, clock: () => now);
      final tracker = FakeSiteTracker.built.single;
      tracker.deliver(const {'topic_id': 10, 'message_type': 'unmuted'});
      failed.completeError(StateError('unavailable'));
      await pumpEventQueue();

      api.trackingStateGate = retry;
      tracker.deliver(_newTopic(10, 1));
      tracker.deliver(_newTopic(11, 2));
      now = now.add(const Duration(seconds: 61));
      retry.complete();
      await pumpEventQueue();

      expect(api.topicTrackingRequests, [_site, _site]);
      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
    },
  );

  test(
    'account replacement clears hints and uses the new mute preferences',
    () async {
      final api = _AccountApi();
      final shell = await _loadShell(api);
      final oldTracker = FakeSiteTracker.built.single;
      oldTracker.deliver(const {'topic_id': 10, 'message_type': 'unmuted'});
      oldTracker.deliver(_newTopic(11, 4));
      expect(shell.newTopicCount, 1);

      await shell.disconnectCurrentInstance();
      api.sessionUser = _user(id: 8, muted: [2], indirectlyMuted: []);
      await shell.connectCurrentInstance();
      await pumpEventQueue();
      final tracker = FakeSiteTracker.built.last;
      expect(tracker.userId, 8);
      expect(shell.newTopicCount, 0);

      oldTracker.deliver(const {'topic_id': 10, 'message_type': 'unmuted'});
      tracker.deliver(_newTopic(10, 2));
      expect(shell.newTopicCount, 0);
      tracker.deliver(_newTopic(12, 1));
      expect(shell.newTopicCount, 1);
      expect(shell.sidebarBadgeFor('category-2'), SidebarBadge.none);
    },
  );
}
