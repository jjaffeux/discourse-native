import 'dart:async';

import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';

DiscourseUser _user() => const DiscourseModelCodec.core().currentUser(const {
  'id': 7,
  'username': 'reader',
  'muted_tags': [
    {'id': 44, 'name': 'muted-tag', 'slug': 'muted-tag'},
  ],
  'unified_new_enabled': true,
  'user_option': {'sidebar_show_count_of_new_items': true},
}, _site);

Map<String, Object?> _arrival(int id, List<int>? tags, {bool bump = false}) => {
  'topic_id': id,
  'message_type': bump ? 'latest' : 'new_topic',
  'payload': {
    'category_id': 4,
    if (!bump) ...{
      'highest_post_number': 1,
      'last_read_post_number': null,
      'created_in_new_period': true,
    },
    if (tags != null)
      'tags': [
        for (final id in tags) {'id': id},
      ],
  },
};

Future<ShellController> _loadShell(
  Map<String, dynamic> settings, {
  Completer<void>? trackingGate,
}) async {
  final config = SiteConfig.fromSettings(settings);
  final user = _user();
  final shell = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: user, config: config),
    ]),
    api: FakeDiscourseApi(
      user: user,
      siteConfigs: {_site: config},
      trackingStateGate: trackingGate,
    ),
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(shell.dispose);
  await shell.load();
  await pumpEventQueue();
  return shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final duringLoad in [false, true]) {
    test(
      'always hides muted-tag creations and bumps '
      '${duringLoad ? 'during snapshot replay' : 'after snapshot load'}',
      () async {
        final gate = Completer<void>();
        final shell = await _loadShell({
          'remove_muted_tags_from_latest': 'always',
        }, trackingGate: gate);
        final tracker = FakeSiteTracker.built.single;
        if (!duringLoad) {
          gate.complete();
          await pumpEventQueue();
        }
        // A category/topic unmute exempts category policy, not tag policy.
        tracker.deliver(const {'topic_id': 10, 'message_type': 'unmuted'});
        tracker.deliver(_arrival(10, [44, 45]));
        tracker.deliver(_arrival(11, [44], bump: true));
        tracker.deliver(_arrival(12, [45]));
        if (duringLoad) gate.complete();
        await pumpEventQueue();

        expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
        expect(tracker.incoming.topicIds('new'), [12]);
        expect(tracker.incoming.topicIds('latest'), [12]);
      },
    );
  }

  test('only_muted keeps mixed and untagged arrivals', () async {
    final shell = await _loadShell({
      'remove_muted_tags_from_latest': 'only_muted',
    });
    final tracker = FakeSiteTracker.built.single;
    tracker.deliver(_arrival(10, [44]));
    tracker.deliver(_arrival(11, [44], bump: true));
    tracker.deliver(_arrival(12, [44, 45]));
    tracker.deliver(_arrival(13, []));
    tracker.deliver(_arrival(14, null));
    tracker.deliver(_arrival(15, [44, 45], bump: true));

    expect(shell.topicListNewCounts, (all: 3, topics: 3, replies: 0));
    expect(tracker.incoming.topicIds('new'), [12, 13, 14]);
    expect(tracker.incoming.topicIds('latest'), [12, 13, 14, 15]);
  });

  test('default category muting requires an unmuted topic hint', () async {
    final shell = await _loadShell({'mute_all_categories_by_default': true});
    final tracker = FakeSiteTracker.built.single;
    tracker.deliver(_arrival(10, [45]));
    tracker.deliver(_arrival(11, [45], bump: true));
    tracker.deliver(const {'topic_id': 12, 'message_type': 'unmuted'});
    tracker.deliver(_arrival(12, [45]));
    tracker.deliver(const {'topic_id': 13, 'message_type': 'unmuted'});
    tracker.deliver(_arrival(13, [45], bump: true));

    expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
    expect(tracker.incoming.topicIds('new'), [12]);
    expect(tracker.incoming.topicIds('latest'), [12, 13]);
  });

  test('a muted hint holds a public new topic out of counters', () async {
    final shell = await _loadShell({});
    final tracker = FakeSiteTracker.built.single;
    for (final type in ['muted', 'unmuted']) {
      tracker.deliver({'topic_id': 10, 'message_type': type});
    }
    tracker.deliver(_arrival(10, null));

    expect(shell.topicListNewCounts, (all: 0, topics: 0, replies: 0));
    expect(tracker.incoming.topicIds('new'), isEmpty);
  });

  test(
    'personalized unread and read updates bypass public mute policy',
    () async {
      final shell = await _loadShell({
        'remove_muted_tags_from_latest': 'always',
        'mute_all_categories_by_default': true,
      });
      final tracker = FakeSiteTracker.built.single;
      tracker.deliver(const {'topic_id': 10, 'message_type': 'muted'});
      tracker.deliver(_arrival(10, [44]));
      expect(shell.newTopicCount, 0);

      tracker.deliverTopicTracking(const {
        'topic_id': 10,
        'message_type': 'unread',
        'payload': {
          'category_id': 4,
          'highest_post_number': 3,
          'tags': [
            {'id': 44},
          ],
        },
      });
      expect(shell.topicListNewCounts, (all: 1, topics: 0, replies: 1));
      tracker.deliverTopicTracking(const {
        'topic_id': 10,
        'message_type': 'read',
        'payload': {'category_id': 4, 'last_read_post_number': 3},
      });
      expect(shell.topicListNewCounts, (all: 0, topics: 0, replies: 0));
      expect(tracker.incoming.topicIds('new'), isEmpty);
    },
  );

  test('unknown and never tag policies retain existing admission', () async {
    for (final policy in [null, 'never', 'future-policy']) {
      final shell = await _loadShell({
        'remove_muted_tags_from_latest': ?policy,
      });
      final tracker = FakeSiteTracker.built.single;
      tracker.deliver(_arrival(10, [44]));
      tracker.deliver(_arrival(11, [44], bump: true));

      expect(shell.topicListNewCounts, (all: 1, topics: 1, replies: 0));
      expect(tracker.incoming.topicIds('new'), [10]);
      expect(tracker.incoming.topicIds('latest'), [10, 11]);
    }
  });
}
