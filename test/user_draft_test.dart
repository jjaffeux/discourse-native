import 'package:discourse_native/src/models/user_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new-topic draft gets its title and excerpt from composer data', () {
    final draft = UserDraft.fromJson({
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

  test('an edit draft remains visible but is not resumed as a reply', () {
    final draft = UserDraft.fromJson({
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
