import 'package:discourse_native/src/models/post.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads and preserves a server-rendered custom post notice', () {
    final post = Post.fromJson(const {
      'id': 42,
      'post_number': 2,
      'username': 'sam',
      'cooked': '<p>Post body</p>',
      'notice': {
        'type': 'custom',
        'raw': 'Please read this carefully.',
        'cooked': '<p>Please <strong>read</strong> this carefully.</p>',
      },
    }, 'https://example.com');

    expect(post.notice?.type, 'custom');
    expect(post.notice?.raw, 'Please read this carefully.');
    expect(
      post.notice?.cooked,
      '<p>Please <strong>read</strong> this carefully.</p>',
    );
    expect(post.copyWith(hidden: true).notice, post.notice);
    expect(post.copyWith(clearNotice: true).notice, isNull);
  });

  test('reads and preserves the topic-level staff-note capability', () {
    final payload = TopicDetail.parse(const {
      'id': 7,
      'title': 'A topic',
      'post_stream': {'stream': <int>[], 'posts': <Object>[]},
      'details': {'can_edit_staff_notes': true},
    }, 'https://example.com');

    expect(payload.detail.canEditStaffNotes, isTrue);
    expect(payload.detail.copyWith(closed: true).canEditStaffNotes, isTrue);
    expect(
      payload.detail.withPlugins(payload.detail.plugins).canEditStaffNotes,
      isTrue,
    );
  });
}
