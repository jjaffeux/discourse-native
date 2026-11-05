import 'package:discourse_native/src/models/topic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('server row statuses survive metadata and plugin projections', () {
    final topic = Topic.fromJson(
      const {
        'id': 7,
        'title': 'Topic',
        'slug': 'topic',
        'pinned': true,
        'closed': true,
        'archived': true,
        'visible': false,
        'deleted_at': '2026-11-05T12:00:00Z',
        'bookmarked': true,
        'notification_level': 0,
      },
      const {},
      'https://example.com',
    );
    for (final row in [
      topic,
      topic.copyWith(title: 'Edited'),
      topic.withPlugins(topic.plugins),
    ]) {
      expect(row.pinned, isTrue);
      expect(row.closed, isTrue);
      expect(row.archived, isTrue);
      expect(row.visible, isFalse);
      expect(row.deletedAt, DateTime.utc(2026, 11, 5, 12));
      expect(row.bookmarked, isTrue);
      expect(row.muted, isTrue);
    }
    expect(topic.copyWith(archived: false), isNot(topic));
    expect(topic.copyWith(visible: true), isNot(topic));
    expect(topic.copyWith(clearDeletedAt: true), isNot(topic));
    final restored = topic.copyWith(
      archived: false,
      visible: true,
      clearDeletedAt: true,
      muted: false,
    );
    expect(restored.archived, isFalse);
    expect(restored.visible, isTrue);
    expect(restored.deletedAt, isNull);
    expect(restored.muted, isFalse);
  });
}
