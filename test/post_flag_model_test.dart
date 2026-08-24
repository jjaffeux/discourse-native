import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:flutter_test/flutter_test.dart';

const _site = 'https://meta.discourse.org';

Post _post(Map<String, dynamic> json) => Post.fromJson({
  'id': 42,
  'post_number': 3,
  'username': 'sam',
  'cooked': '<p>Hello</p>',
  ...json,
}, _site);

void main() {
  group('site post-action catalog', () {
    test('retains ordered built-in and custom post flags', () {
      final catalog = SitePostActionCatalog.fromJson(const {
        'post_action_types': [
          {
            'id': 3,
            'name_key': 'off_topic',
            'name': 'Off-Topic',
            'description': '<p>Not relevant</p>',
            'short_description': '<p>Not relevant here</p>',
            'is_flag': true,
            'enabled': true,
            'applies_to': ['Post'],
            'system': true,
          },
          {
            'id': 91,
            'name_key': 'copyright',
            'name': 'Copyright concern',
            'description': '<p>Explain the concern</p>',
            'is_flag': true,
            'enabled': false,
            'require_message': true,
            'applies_to': ['Post', 'Topic'],
          },
          {
            'id': 7,
            'name_key': 'topic_only',
            'name': 'Topic reason',
            'description': '',
            'is_flag': true,
            'applies_to': ['Topic'],
          },
          {'id': 2, 'name_key': 'like', 'name': 'Like', 'is_flag': false},
        ],
      });

      expect(catalog.postFlags.map((type) => type.id), [3, 91, 7]);
      expect(catalog.postFlags.first.system, isTrue);
      expect(catalog.postFlags.first.shortDescription, contains('relevant'));
      expect(catalog.postFlags[1].enabled, isFalse);
      expect(catalog.postFlags[1].requireMessage, isTrue);
      expect(catalog.postFlags[1].appliesToPost, isTrue);
      expect(catalog.postFlags.last.appliesToPost, isFalse);
      expect(
        () => catalog.postFlags.add(catalog.postFlags.first),
        throwsUnsupportedError,
      );
    });

    test(
      'drops malformed and non-flag rows without losing an empty answer',
      () {
        final catalog = SitePostActionCatalog.fromJson(const {
          'post_action_types': [
            null,
            'flag',
            {'id': 3, 'name': 'Missing key', 'is_flag': true},
            {'id': -1, 'name_key': 'bad', 'name': 'Bad', 'is_flag': true},
            {'id': 2, 'name_key': 'like', 'name': 'Like'},
          ],
        });

        expect(catalog.postFlags, isEmpty);
        expect(catalog, const SitePostActionCatalog());
      },
    );
  });

  group('post flag action summaries', () {
    test('retains every non-like row while likes remain unchanged', () {
      final post = _post({
        'actions_summary': [
          {'id': 3, 'count': 2, 'can_act': true},
          {'id': 2, 'count': 5, 'acted': true, 'can_undo': true},
          {'id': 91, 'acted': true},
        ],
      });

      expect(post.likeCount, 5);
      expect(post.liked, isTrue);
      expect(post.postActions.map((summary) => summary.id), [3, 91]);
      expect(post.canFlagWith(3), isTrue);
      expect(post.actedFlagSummaries.single.id, 91);
      expect(post.actionSummary(3)?.count, 2);
    });

    test(
      'parses hidden state and includes it in copies and value identity',
      () {
        final hidden = _post({
          'hidden': true,
          'actions_summary': [
            {'id': 3, 'can_act': true},
          ],
        });
        final visible = hidden.copyWith(hidden: false);

        expect(hidden.hidden, isTrue);
        expect(visible.hidden, isFalse);
        expect(visible, isNot(hidden));
        expect(hidden.copyWith(), hidden);
        expect(hidden.copyWith().hashCode, hidden.hashCode);
      },
    );

    test('preserves personalized flags across an edit response', () {
      final held = _post({
        'actions_summary': [
          {'id': 3, 'acted': true},
          {'id': 2, 'count': 4, 'acted': true},
        ],
      });
      final edited = _post({'cooked': '<p>Edited</p>'});

      final merged = edited.withLikesOf(held).withPostActionsOf(held);
      expect(merged.liked, isTrue);
      expect(merged.likeCount, 4);
      expect(merged.actedFlagSummaries.single.id, 3);
    });

    test('an authoritative read replaces personalized flag state', () {
      final available = _post({
        'actions_summary': [
          {'id': 3, 'can_act': true},
        ],
      });
      final acted = _post({
        'actions_summary': [
          {'id': 3, 'acted': true},
        ],
      });

      expect(available.canFlagWith(3), isTrue);
      expect(acted.canFlagWith(3), isFalse);
      expect(acted.actedFlagSummaries, hasLength(1));
    });
  });
}
