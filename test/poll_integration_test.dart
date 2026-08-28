import 'dart:convert';

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/discourse_model_codec.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_card.dart';
import 'package:discourse_native/src/plugins/poll/poll_plugin.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/bundled_plugins.dart';

const _site = 'https://meta.discourse.org';

Map<String, Object?> _pollJson({
  required String name,
  String title = '',
  int voters = 0,
  int? votes = 0,
}) => {
  'id': name.hashCode,
  'name': name,
  'type': 'regular',
  'status': 'open',
  'results': 'always',
  'public': true,
  'dynamic': false,
  'voters': voters,
  'chart_type': 'bar',
  'title': title,
  'options': [
    {'id': '$name-a', 'html': 'A', 'votes': ?votes},
    {'id': '$name-b', 'html': 'B', 'votes': ?(votes == null ? null : 0)},
  ],
};

Map<String, Object?> _postJson({
  List<Map<String, Object?>>? polls,
  Map<String, Object?>? votes,
  bool reactions = false,
}) => {
  'id': 11,
  'post_number': 2,
  'username': 'sam',
  'cooked': '<p>Hello</p>',
  'polls': ?polls,
  'polls_votes': ?votes,
  if (reactions) ...{
    'reactions': [
      {'id': 'clap', 'type': 'emoji', 'count': 3},
    ],
    'current_user_reaction': {'id': 'clap', 'type': 'emoji', 'can_undo': true},
    'reaction_users_count': 3,
  },
};

void main() {
  group('poll session state', () {
    test(
      'current user reads fresh poll capability, staff, and group names',
      () async {
        final api = DiscourseApi(
          models: DiscourseModelCodec(extensions: pluginRegistry),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {
                  'id': 7,
                  'username': 'sam',
                  'can_create_poll': true,
                  'moderator': true,
                  'groups': [
                    {'id': 1, 'name': 'team'},
                    {'id': 2, 'name': 'Poll Builders'},
                    {'id': 3, 'name': 42},
                  ],
                },
              }),
              200,
            ),
          ),
        );

        final user = await api.currentUser(siteUrl: _site, apiKey: 'key');

        expect(user.canCreatePoll, isTrue);
        expect(user.staff, isTrue);
        expect(user.groups, ['team', 'Poll Builders']);
        expect(() => user.groups.add('another'), throwsUnsupportedError);
      },
    );

    test(
      'an absent plugin capability remains unknown, including in old storage',
      () async {
        final api = DiscourseApi(
          models: DiscourseModelCodec(extensions: pluginRegistry),
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'current_user': {'id': 7, 'username': 'sam'},
              }),
              200,
            ),
          ),
        );

        final live = await api.currentUser(siteUrl: _site, apiKey: 'key');
        final stored = DiscourseUser.fromJson(const {
          'username': 'sam',
        }, extensions: pluginRegistry);

        expect(live.canCreatePoll, isNull);
        expect(stored.canCreatePoll, isNull);
        expect(stored.staff, isFalse);
        expect(stored.groups, isEmpty);
      },
    );
  });

  group('poll site settings', () {
    test('uses upstream defaults when settings are absent or unusable', () {
      final absent = SiteConfig.fromSettings(
        const {},
        extensions: pluginRegistry,
      );
      final invalid = SiteConfig.fromSettings(const {
        'poll_maximum_options': 1,
      }, extensions: pluginRegistry);

      expect(absent.pollMaximumOptions, 20);
      expect(absent.pollDefaultPublic, isTrue);
      expect(invalid.pollMaximumOptions, 20);
    });

    test('reads and persists the poll builder settings', () {
      final configured = SiteConfig.fromSettings(const {
        'poll_maximum_options': 37,
        'poll_default_public': false,
      }, extensions: pluginRegistry);
      final restored = SiteConfig.fromJson(
        jsonDecode(jsonEncode(configured.toJson(extensions: pluginRegistry)))
            as Map<String, dynamic>,
        extensions: pluginRegistry,
      );

      expect(configured.pollMaximumOptions, 37);
      expect(configured.pollDefaultPublic, isFalse);
      expect(restored, configured);
    });

    test('stored site settings predating Poll remain readable', () {
      final restored = SiteConfig.fromJson(
        const {},
        extensions: pluginRegistry,
      );

      expect(restored.pollMaximumOptions, 20);
      expect(restored.pollDefaultPublic, isTrue);
    });

    test('legacy storage preserves a previously accepted Poll limit', () {
      final restored = SiteConfig.fromJson(const {
        'pollMaximumOptions': 1,
        'pollDefaultPublic': false,
      }, extensions: pluginRegistry);

      expect(restored.pollMaximumOptions, 1);
      expect(restored.pollDefaultPublic, isFalse);
    });
  });

  group('topic archived state', () {
    test('retains the top-level archived flag used to block poll writes', () {
      final archived = TopicDetail.parse(const {
        'id': 7,
        'title': 'Closed for writes',
        'archived': true,
      }, _site).detail;
      final ordinary = TopicDetail.parse(const {
        'id': 8,
        'title': 'Open',
      }, _site).detail;

      expect(archived.archived, isTrue);
      expect(ordinary.archived, isFalse);
      expect(ordinary.merge(archived.copyWith(title: 'New')).archived, isTrue);
    });
  });

  group('PollPlugin integration', () {
    const plugin = PollPlugin();

    test('payload presence gates the feature and preserves named polls', () {
      expect(plugin.readPost(_postJson(), _site), isNull);

      final polls = plugin.readPost(
        _postJson(
          polls: [
            _pollJson(name: 'first'),
            _pollJson(name: 'second'),
          ],
          votes: const {
            'second': ['second-b'],
          },
        ),
        _site,
      );

      expect(polls?.byName.keys, ['first', 'second']);
      expect(polls?['second']?.selection.optionIds, ['second-b']);
    });

    testWidgets('matches cooked poll elements to structured data by name', (
      tester,
    ) async {
      final post = Post.fromJson(
        _postJson(
          polls: [
            _pollJson(name: 'first', title: 'First title'),
            _pollJson(name: 'second', title: 'Second title'),
          ],
        ),
        _site,
        extensions: pluginRegistry,
      );
      final element = html
          .parseFragment(
            '<div class="poll" data-poll-name="second">cooked skeleton</div>',
          )
          .querySelector('.poll')!;
      final body = plugin.postBodyElement(_site, post, element)!;

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));

      final card = tester.widget<PollCard>(find.byType(PollCard));
      expect(card.poll.name, 'second');
      expect(card.poll.title, 'Second title');
    });

    test('unmatched cooked polls fall back instead of inventing state', () {
      final post = Post.fromJson(
        _postJson(polls: [_pollJson(name: 'known')]),
        _site,
        extensions: pluginRegistry,
      );
      final element = html
          .parseFragment('''
            <div class="poll" data-poll-name="missing">
              <div class="poll-title">Cooked title</div>
              <ul><li data-poll-option-id="a">A</li></ul>
              <span class="info-number">0</span>
            </div>
          ''')
          .querySelector('.poll')!;

      expect(
        plugin.postBodyElement(_site, post, element),
        isA<PollFallbackCard>(),
      );
    });

    test(
      'subscribes to poll invalidations and extracts only valid post ids',
      () {
        expect(plugin.topicChannels(42), ['/polls/42']);
        expect(plugin.stalePosts('/polls/42', const {'post_id': 9}), [9]);
        expect(plugin.stalePosts('/polls/42', const {'post_id': '9'}), isEmpty);
        expect(plugin.stalePosts('/polls/42', const []), isEmpty);
      },
    );
  });

  group('post-edit plugin merge policy', () {
    test('incoming Poll data wins while the held reaction record survives', () {
      final held = Post.fromJson(
        _postJson(
          reactions: true,
          polls: [_pollJson(name: 'poll', voters: 1, votes: 1)],
        ),
        _site,
        extensions: pluginRegistry,
      ).plugins;
      final incoming = Post.fromJson(
        _postJson(polls: [_pollJson(name: 'poll', voters: 8, votes: 6)]),
        _site,
        extensions: pluginRegistry,
      ).plugins;

      final merged = pluginRegistry.mergeAfterPostEdit(
        held: held,
        incoming: incoming,
      );

      expect(merged.get(reactionsDataKey), held.get(reactionsDataKey));
      expect(merged.get(pollsDataKey)?['poll']?.voters, 8);
      expect(merged.get(pollsDataKey)?['poll']?.options.first.votes, 6);
    });

    test('absence in an edit removes Poll without removing Reactions', () {
      final held = Post.fromJson(
        _postJson(reactions: true, polls: [_pollJson(name: 'poll', voters: 3)]),
        _site,
        extensions: pluginRegistry,
      ).plugins;
      final incoming = pluginRegistry.readPost(_postJson(), _site);

      final merged = pluginRegistry.mergeAfterPostEdit(
        held: held,
        incoming: incoming,
      );

      expect(merged.get(pollsDataKey), isNull);
      expect(merged.get(reactionsDataKey), held.get(reactionsDataKey));
    });
  });
}
