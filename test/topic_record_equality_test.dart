import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/src/plugins/bundled_plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://records.example';

Map<String, dynamic> _topic([Map<String, dynamic> extra = const {}]) => {
  'id': 7,
  'title': 'Hello',
  'fancy_title': 'Hello',
  'slug': 'hello',
  'posts_count': 3,
  'reply_count': 2,
  'views': 10,
  'like_count': 1,
  'category_id': 2,
  'bumped_at': '2026-09-01T00:00:00Z',
  'last_posted_at': '2026-09-01T00:00:00Z',
  'pinned': false,
  'closed': false,
  'archived': false,
  'visible': true,
  'tags': ['ux'],
  'posters': <Object?>[],
  'excerpt': 'An excerpt',
  'unseen': false,
  'last_read_post_number': 3,
  'highest_post_number': 3,
  ...extra,
};

// Payloads that switch on the bundled plugins' topic records.
final _payloads = <String, Map<String, dynamic> Function()>{
  'plain': _topic,
  'post voting': () => _topic({
    'is_post_voting': true,
    'answer_count': 2,
    'last_answered_at': '2026-09-02T00:00:00Z',
    'last_commented_on': '2026-09-03T00:00:00Z',
    'last_answer_post_number': 4,
    'last_answerer': {
      'id': 5,
      'username': 'ada',
      'name': 'Ada',
      'avatar_template': '/user_avatar/ada/{size}/1.png',
    },
  }),
  'board': () => _topic({
    'board_memberships': [
      {
        'board_id': 3,
        'board_name': 'Roadmap',
        'board_slug': 'roadmap',
        'cards': [
          {'card_id': 9, 'column_title': 'Next'},
        ],
      },
    ],
  }),
  'assigned': () => _topic({
    'assigned_to_user': {
      'id': 8,
      'username': 'joffrey',
      'avatar_template': '/user_avatar/joffrey/{size}/1.png',
    },
  }),
  'event': () => _topic({
    'event_starts_at': '2026-10-14T20:00:00+02:00',
    'event_ends_at': '2026-10-14T21:00:00+02:00',
    'event_timezone': 'Europe/Paris',
  }),
};

void main() {
  final registry = PluginInstaller.install(bundledPluginManifest).registry;

  // A refresh, a page reload or a live update decodes topics the store
  // already holds. Topic.merge keeps the held topic only when the fresh one
  // is equal; otherwise the store notifies and every row showing it rebuilds.
  for (final MapEntry(key: name, value: payload) in _payloads.entries) {
    test('a $name topic decoded again keeps the held topic', () {
      final held = Topic.fromJson(
        payload(),
        const {},
        _site,
        extensions: registry,
      );
      final again = Topic.fromJson(
        payload(),
        const {},
        _site,
        extensions: registry,
      );
      expect(again, held);
      expect(again.hashCode, held.hashCode);
      expect(identical(held.merge(again), held), isTrue);
    });
  }

  group('a topic as its post tiles compare it', () {
    const held = TopicDetail(id: 7, title: 'Hello', stream: [1, 2]);

    test('ignores the figures a like or a reply moves', () {
      final moved = held.copyWith(
        stream: const [1, 2, 3],
        lastPostId: 3,
        postsCount: 3,
        likeCount: 9,
        gapsAfter: const {
          2: [3],
        },
        messageBusLastId: 12,
      );

      expect(moved == held, isFalse);
      expect(moved.hasSameFieldsBesidesFigures(held), isTrue);
    });

    test('notices every field a post can read', () {
      for (final changed in [
        held.copyWith(title: 'Renamed'),
        held.copyWith(closed: true),
        held.copyWith(archived: true),
        held.copyWith(canEdit: true),
        held.copyWith(privateMessage: true),
        held.copyWith(visible: false),
        held.copyWith(categoryId: 3),
      ]) {
        expect(changed.hasSameFieldsBesidesFigures(held), isFalse);
      }
    });
  });

  test('every bundled topic record compares by value', () {
    final plugins = [
      for (final plugin in registry.plugins)
        if (plugin is TopicRecordPlugin<Object>) plugin,
    ];
    expect(plugins, isNotEmpty);
    final reached = <String>{};
    for (final plugin in plugins) {
      final reader = plugin as TopicRecordPlugin<Object>;
      for (final MapEntry(key: name, value: payload) in _payloads.entries) {
        final first = reader.readTopic(payload(), _site);
        final second = reader.readTopic(payload(), _site);
        if (first == null && second == null) continue;
        reached.add('${plugin.name} $name');
        expect(second, first, reason: '${plugin.name} on a $name topic');
        expect(
          second.hashCode,
          first.hashCode,
          reason: '${plugin.name} on a $name topic',
        );
      }
    }
    // Each payload must keep reaching the record it was written for.
    expect(
      reached,
      containsAll([
        'discourse-post-voting plain',
        'discourse-post-voting post voting',
        'boards board',
        'discourse-assign assigned',
        'discourse-events event',
      ]),
    );
  });
}
