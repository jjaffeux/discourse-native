import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic_tracking_message_filter.dart';
import 'package:flutter_test/flutter_test.dart';

const _user = DiscourseUser(
  username: 'author',
  mutedCategoryIds: [1],
  indirectlyMutedCategoryIds: [2],
);

Map<String, Object?> _newTopic(int id, {int categoryId = 1}) => {
  'topic_id': id,
  'message_type': 'new_topic',
  'payload': {'category_id': categoryId},
};

Map<String, Object?> _hint(int id, [String type = 'unmuted']) => {
  'topic_id': id,
  'message_type': type,
};

void main() {
  test('server hints expire at 60 seconds and only exempt their topic', () {
    var now = DateTime.utc(2026);
    final filter = TopicTrackingMessageFilter(clock: () => now);
    expect(filter.accepts(_hint(10), user: _user), isFalse);
    expect(filter.accepts(_newTopic(10), user: _user), isTrue);
    expect(filter.accepts(_newTopic(11), user: _user), isFalse);
    expect(filter.accepts(_newTopic(12, categoryId: 2), user: _user), isFalse);
    expect(filter.accepts(_newTopic(13, categoryId: 3), user: _user), isTrue);

    now = now.add(const Duration(seconds: 59));
    expect(filter.accepts(_newTopic(10), user: _user), isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(filter.accepts(_newTopic(10), user: _user), isFalse);
    filter.accepts(_hint(10));
    expect(filter.accepts(_newTopic(10, categoryId: 2), user: _user), isTrue);
  });

  test('muting or destroying a topic retires its unmuted hint', () {
    final filter = TopicTrackingMessageFilter();
    for (final type in ['muted', 'destroy']) {
      filter.accepts(_hint(10));
      filter.accepts(_hint(10, type));
      expect(filter.accepts(_newTopic(10), user: _user), isFalse);
    }
  });

  test('hint retention is bounded and repeated hints refresh their entry', () {
    final filter = TopicTrackingMessageFilter(clock: () => DateTime.utc(2026));
    for (var id = 1; id <= 5000; id++) {
      filter.accepts(_hint(id));
    }
    filter.accepts(_hint(1));
    filter.accepts(_hint(5001));

    expect(filter.accepts(_newTopic(1), user: _user), isTrue);
    expect(filter.accepts(_newTopic(2), user: _user), isFalse);
    expect(filter.accepts(_newTopic(5001), user: _user), isTrue);
  });

  test('targeted read and unread events bypass category admission', () {
    final filter = TopicTrackingMessageFilter();
    for (final type in ['read', 'unread']) {
      expect(
        filter.accepts({..._newTopic(10), 'message_type': type}, user: _user),
        isTrue,
      );
    }
    expect(filter.accepts(_newTopic(10)), isTrue);
    expect(filter.accepts(null, user: _user), isFalse);
    filter.accepts(_hint(-1));
    expect(filter.accepts(_newTopic(-1), user: _user), isFalse);
  });
}
