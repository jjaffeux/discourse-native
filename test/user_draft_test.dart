import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/draft_feed.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/plugins/voice/voice_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new-topic draft gets its title and excerpt from composer data', () {
    final draft = UserDraft.fromJson(const {
      'draft_key': 'new_topic',
      'sequence': 3,
      'data': {
        'reply': 'A topic in progress.\n\nWith another paragraph.',
        'action': 'createTopic',
        'title': 'A useful title',
        'categoryId': 5,
      },
    });

    expect(draft.displayTitle, 'A useful title');
    expect(draft.excerpt, 'A topic in progress. With another paragraph.');
    expect(draft.kindLabel, 'New topic draft');
    expect(draft.displayCategoryId, 5);
    expect(draft.canResume, isTrue);
  });

  test('wire parsing caches its whitespace-normalized excerpt', () {
    final draft = UserDraft.fromJson(const {
      'draft_key': 'topic_42',
      'sequence': 4,
      'topic_id': 42,
      'data': {'reply': '  First\tline\n\nSecond   line.  ', 'action': 'reply'},
    });

    final excerpt = draft.excerpt;
    expect(excerpt, 'First line Second line.');
    expect(draft.excerpt, same(excerpt));
  });

  test('a Live transcript draft from a current site is labeled', () {
    final draft = UserDraft.fromJson(const {
      'draft_key': 'new_topic_live_7_1792500000000',
      'sequence': 1,
      'data': {
        'reply': 'Transcript in progress',
        'action': 'createTopic',
        'title': 'Call transcript: Lounge',
      },
    });

    expect(
      const VoicePlugin().draftPresentation(draft)?.label,
      'Call transcript draft',
    );
  });

  test('a Voice transcript draft is labeled and resumable', () {
    final draft = UserDraft.fromJson(const {
      'draft_key': 'new_topic_voice_7_1788170000000',
      'sequence': 6,
      'data': {
        'reply': 'Transcript in progress',
        'action': 'createTopic',
        'title': 'Call transcript: Lounge',
      },
    });

    expect(draft.isNewTopic, isTrue);
    expect(const VoicePlugin().draftPresentation(draft), isNotNull);
    expect(
      const VoicePlugin().draftPresentation(draft)?.label,
      'Call transcript draft',
    );
    expect(draft.kindLabel, 'New topic draft');
    expect(draft.canResume, isTrue);
  });

  test('manual const drafts retain their derived excerpt', () {
    const draft = UserDraft(
      key: 'topic_42',
      sequence: 4,
      topicId: 42,
      data: ComposerDraft(reply: '  First\n\nSecond  '),
    );

    expect(draft.excerpt, 'First Second');
  });

  group('bounded excerpts', () {
    test('short Unicode whitespace retains trim and collapse semantics', () {
      for (final unit in [
        0x09,
        0x0a,
        0x0d,
        0x20,
        0x85,
        0xa0,
        0x1680,
        0x2000,
        0x2007,
        0x2028,
        0x2029,
        0x202f,
        0x205f,
        0x3000,
        0xfeff,
      ]) {
        final whitespace = String.fromCharCode(unit);
        final reply = '${whitespace}First${whitespace}line$whitespace';
        final draft = UserDraft(
          key: 'new_topic',
          sequence: 1,
          data: ComposerDraft(reply: reply),
        );

        expect(
          draft.excerpt,
          reply.trim().replaceAll(RegExp(r'\s+'), ' '),
          reason: 'U+${unit.toRadixString(16)}',
        );
      }
    });

    for (final entry in <String, (String, String)>{
      'long ASCII': ('a' * 100000, 'a' * 512),
      'surrogate pair at the boundary': (
        '${'a' * 510}😀tail',
        '${'a' * 510}😀',
      ),
      'surrogate pair across the boundary': ('${'a' * 511}😀tail', 'a' * 511),
      'combining sequence across the boundary': (
        '${'a' * 511}e\u0301tail',
        'a' * 511,
      ),
      'combining sequence at the boundary': (
        '${'a' * 510}e\u0301tail',
        '${'a' * 510}e\u0301',
      ),
      'joined emoji across the boundary': (
        '${'a' * 508}👩\u200d💻tail',
        'a' * 508,
      ),
      'joined emoji at the boundary': (
        '${'a' * 507}👩\u200d💻tail',
        '${'a' * 507}👩\u200d💻',
      ),
      'variation selector across the boundary': (
        '${'a' * 511}✈️tail',
        'a' * 511,
      ),
      'variation selector at the boundary': (
        '${'a' * 510}✈️tail',
        '${'a' * 510}✈️',
      ),
      'keycap across the boundary': ('${'a' * 510}1️⃣tail', 'a' * 510),
      'keycap at the boundary': ('${'a' * 509}1️⃣tail', '${'a' * 509}1️⃣'),
      'skin tone across the boundary': ('${'a' * 509}👍🏽tail', 'a' * 509),
      'skin tone at the boundary': ('${'a' * 508}👍🏽tail', '${'a' * 508}👍🏽'),
      'regional indicators across the boundary': (
        '${'a' * 509}🇫🇷tail',
        'a' * 509,
      ),
      'regional indicators at the boundary': (
        '${'a' * 508}🇫🇷tail',
        '${'a' * 508}🇫🇷',
      ),
      'cluster larger than the cap': ('e${'\u0301' * 100000}tail', ''),
      'oversized cluster after useful text': (
        'Text e${'\u0301' * 100000}tail',
        'Text',
      ),
      'collapsed whitespace joins a combining mark': (
        '${'a' * 510}\n\t \u0301tail',
        '${'a' * 510} \u0301',
      ),
      'collapsed whitespace cluster across the boundary': (
        '${'a' * 511}\n\t \u0301tail',
        'a' * 511,
      ),
      'trailing whitespace within a cluster at the boundary': (
        '${'a' * 510}\u0600 x',
        'a' * 510,
      ),
      'short trailing whitespace retains its prepend character': (
        'x\u0600 \u0085',
        'x\u0600',
      ),
      'trailing whitespace after a near-cap prepend is trimmed at EOF': (
        '${'a' * 511}\u0600 \u0085',
        '${'a' * 511}\u0600',
      ),
      'trailing whitespace after a near-cap prepend before text': (
        '${'a' * 511}\u0600 \u0085x',
        'a' * 511,
      ),
      'long trailing NEL whitespace before visible text': (
        '${'a' * 510}\u0600 ${'\u0085' * 100000}x',
        'a' * 510,
      ),
      'long trailing NEL whitespace at EOF': (
        '${'a' * 511}\u0600 ${'\u0085' * 100000}',
        '${'a' * 511}\u0600',
      ),
      'leading whitespace before a combining mark': (
        ' \n\u0301 x ',
        '\u0301 x',
      ),
      'short whitespace before a combining mark': ('x\n\u0301 y', 'x \u0301 y'),
      'long leading whitespace': (
        '${' \t\n' * 10000}Visible text',
        'Visible text',
      ),
      'collapsed whitespace at the boundary': (
        '${'a' * 510}\n\t btail',
        '${'a' * 510} b',
      ),
      'trailing whitespace': ('${'a' * 511}\n\t ', 'a' * 511),
    }.entries) {
      test('${entry.key} preserves the full resume body', () {
        final (reply, expected) = entry.value;
        final parsed = UserDraft.fromJson({
          'draft_key': 'topic_42',
          'sequence': 4,
          'topic_id': 42,
          'data': {'reply': reply},
        });
        final manual = UserDraft(
          key: 'topic_42',
          sequence: 4,
          topicId: 42,
          data: ComposerDraft(reply: reply),
        );

        for (final draft in [parsed, manual]) {
          expect(draft.excerpt, expected);
          expect(draft.excerpt.length, lessThanOrEqualTo(512));
          expect(draft.data?.reply, reply);
          expect(draft.canResume, isTrue);
        }
      });
    }

    test('feed reconciliation keeps the bounded fallback and full data', () {
      final reply = 'thought ' * 20000;
      final held = UserDraft.fromJson({
        'draft_key': 'topic_42',
        'sequence': 4,
        'topic_id': 42,
        'data': {'reply': reply},
      });
      final feed = DraftFeed(drafts: [held]).withPage(
        const UserDraftPage(
          drafts: [UserDraft(key: 'topic_42', sequence: 4, data: null)],
          rawItemCount: 1,
        ),
        limit: 30,
        reportedCount: 1,
      );

      expect(feed.drafts.single.excerpt, held.excerpt);
      expect(feed.drafts.single.excerpt.length, lessThanOrEqualTo(512));
      expect(feed.drafts.single.data, same(held.data));
      expect(feed.drafts.single.canResume, isTrue);
    });
  });

  test('an edit draft remains visible but is not resumed as a reply', () {
    final draft = UserDraft.fromJson(const {
      'draft_key': 'edit_topic_42',
      'sequence': 2,
      'data': '{"reply":"Changed text","action":"editPost"}',
      'topic_id': 42,
      'title': 'Original title',
    });

    expect(draft.displayTitle, 'Original title');
    expect(draft.kindLabel, 'Edit topic draft');
    expect(draft.canResume, isFalse);
  });
}
