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
      'combining sequence': ('${'a' * 511}e\u0301tail', '${'a' * 511}e'),
      'joined emoji': ('${'a' * 508}👩\u200d💻tail', '${'a' * 508}👩\u200d'),
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
